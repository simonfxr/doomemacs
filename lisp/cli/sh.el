;;; lisp/cli/sh.el -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; A miniature DSL for quickly executing shell commands from your Doom CLIs.
;; Includes rudimentary support for a few shell-isms like pipes and redirects
;; (|, <, >, >>, 2>, 2>>), implemented in elisp so they may be used on any
;; platform. See `sh!' for details and examples.
;;
;;; Code:

;;
;;; * Helpers

(defun doom-sh--parse (tokens)
  (let (stages argv ins outs errs)
    (letf! ((defun flush ()
              (prog1 (list :argv (delq nil (nreverse argv))
                           :in   (delq nil (nreverse ins))
                           :out  (seq-filter #'car (nreverse outs))
                           :err  (seq-filter #'car (nreverse errs)))
                (setq argv nil
                      ins nil
                      outs nil
                      errs nil)))
            (defun stringify (arg)
              (if (and arg
                       (or (numberp arg)
                           (symbolp arg)))
                  (format "%s" arg)
                arg)))
      (while tokens
        (pcase (pop tokens)
          (`|    (push (flush) stages))
          (`<    (push (stringify (pop tokens)) ins))
          (`>    (push (cons (stringify (pop tokens)) nil) outs))
          (`>>   (push (cons (stringify (pop tokens)) t) outs))
          ('2>   (push (cons (stringify (pop tokens)) nil) errs))
          ('2>>  (push (cons (stringify (pop tokens)) t) errs))
          (token (push (stringify token) argv))))
      (push (flush) stages))
    (nreverse stages)))

(defun doom-sh--write-to-sink (sink output append?)
  "Write STRING to redirect SINK (a buffer or filename)."
  (if (bufferp sink)
      (with-current-buffer sink
        (unless append? (erase-buffer))
        (goto-char (point-max))
        (insert output))
    (write-region output nil sink append? 'silent)))

(defun doom-sh--read-sources (sources)
  "Read SOURCES and return their concatenated contents in order."
  (mapconcat (lambda (source)
               (if (bufferp source)
                   (with-current-buffer source (buffer-string))
                 (with-temp-buffer
                   (insert-file-contents (format "%s" source))
                   (buffer-string))))
             sources
             ""))

(defun doom-sh--write-to-sinks (sinks string)
  "Write or append STRING to all SINKS.

Each sink is a (TARGET . APPEND) cons cell. nil sinks are skipped."
  (dolist (sink sinks)
    (doom-sh--write-to-sink (car sink) string (cdr sink))))

(defun doom-sh--run (argv &optional stdin errs stream?)
  "Run one command (ARGV, a list of program + string args) synchronously.

STDIN, if non-nil, is a string fed to the process on standard input, which is
then closed (so the process never blocks waiting for a prompt). When STREAM? is
non-nil, stdout is echoed to `standard-output' as it arrives; otherwise it is
captured silently. ERRS, if non-nil, is a list of (SINK . APPEND) stderr sinks;
stderr is peeled off to them instead of being mixed into stdout.

Returns (STATUS . OUTPUT)."
  (let ((buffer
         ;; REVIEW: Use `generate-new-buffer's INHIBIT-BUFFER-HOOKS arg once 27
         ;;   support is dropped.
         (let (kill-buffer-hook
               kill-buffer-query-functions
               buffer-list-update-hook)
           (generate-new-buffer " *doom-sh*"))))
    (unwind-protect
        (cons (if stream?
                  (let* (;; A dedicated pipe process lets stderr flow through
                         ;; the same sink-fanning filter as everything else. nil
                         ;; means "mix with stdout".
                         (errproc (and errs
                                       (make-pipe-process
                                        :name "doom-sh-err" :noquery t
                                        :filter (doom-sh--async-filter errs nil))))
                         (process (make-process :name "doom-sh"
                                                :buffer buffer
                                                :command argv
                                                :connection-type 'pipe
                                                :stderr errproc)))
                    (set-process-filter
                     process (lambda (_process output)
                               (with-current-buffer buffer (insert output))
                               (princ (doom-print--format output))))
                    ;; A no-op sentinel keeps the default one from injecting
                    ;; "Process finished" into our captured output.
                    (set-process-sentinel process #'ignore)
                    ;; A process with no stdin needs (like `echo') may already
                    ;; be dead by the time we get here, so guard the writes.
                    (when (and stdin (process-live-p process))
                      (ignore-errors
                        (process-send-string process stdin)
                        (process-send-eof process)))
                    (while (process-live-p process)
                      (accept-process-output process 0.1))
                    (while (accept-process-output process 0))  ; drain tail
                    (when errproc  ; drain + close stderr
                      (while (accept-process-output errproc 0))
                      (when (process-live-p errproc) (delete-process errproc)))
                    (process-exit-status process))
                ;; `call-process-region' can only split stderr to a file, so
                ;; when the caller wants stderr routed capture it to a temp file
                ;; and then fan it out to the real sinks.
                (let ((errfile (and errs (make-temp-file "doom-sh-err"))))
                  (unwind-protect
                      (prog1 (apply #'call-process-region (or stdin "") nil (car argv)
                                    nil (if errfile (list buffer errfile) buffer) nil
                                    (cdr argv))
                        (when errfile
                          (doom-sh--write-to-sinks errs (doom-file-read errfile))))
                    (if errfile (ignore-errors (delete-file errfile))))))
              (with-current-buffer buffer
                (buffer-string)))
      (kill-buffer buffer))))

(defun doom-sh--pipeline (stages &optional stream)
  "Execute STAGES (from `doom-sh--parse') synchronously.

Output is threaded through each pipe and redirects are honored. When STREAM is
non-nil, the final stage's stdout is mirrored to `standard-output' as produced
\(unless that stage was redirected).

Returns (STATUS . OUTPUT), where STATUS is the last stage's exit code and OUTPUT
is the pipeline's trailing output (empty when the last stage was redirected)."
  (let ((pipe "")
        (status 0)
        (i 0)
        (n (length stages)))
    (dolist (stage stages)
      (setq i (1+ i))
      (cl-destructuring-bind (&key argv in out err) stage
        (unless argv
          (error "sh: empty command in pipeline"))
        (let ((result
               (doom-sh--run
                argv (if in (doom-sh--read-sources in) pipe)
                err (and stream (= i n) (not out)))))
          (setq status (car result)
                pipe (if (not out)
                         (cdr result)
                       (doom-sh--write-to-sinks out (cdr result))
                       "")))))
    (cons status (if (string-suffix-p "\n" pipe)
                     (substring pipe 0 -1)
                   pipe))))

(defun doom-sh--async-filter (outs &optional down)
  "Build a process filter for one asynchronous pipeline stage.

OUTS is a list of (TARGET . APPEND) sinks, DOWN the downstream process."
  (let (seen)
    (lambda (_process chunk)
      (cond (outs
             (dolist (sink outs)
               (doom-sh--write-to-sink (car sink) chunk
                                       (or (memq sink seen)
                                           (cdr sink)))
               ;; First chunk to a sink obeys its truncate/append flag; later
               ;; chunks must append or it will clobber.
               (push sink seen)))
            ;; Consumer may have exited early (e.g. `... | head`); don't error
            ;; feeding a dead pipe.
            (down
             (when (process-live-p down)
               (ignore-errors (process-send-string down chunk))))))))

(defun doom-sh--async-sentinel (down errproc)
  (lambda (process _event)
    (when (memq (process-status process) '(exit signal))
      (when (and down (process-live-p down))
        ;; So the rest of the pipeline can drain and terminate
        (process-send-eof down))
      (when errproc
        ;; Drain/close ERRPROC so it doesn't linger.
        (while (accept-process-output errproc 0))
        (when (process-live-p errproc)
          (delete-process errproc))))))

(defun doom-sh--pipeline-async (stages)
  "Execute STAGES (from `doom-sh--parse') asynchronously, without blocking.

Stages run concurrently, wired stdout->stdin. Redirects are honored. Output from
an unredirected final stage is discarded."
  (let* ((n (length stages))
         (procs (make-vector n nil)))
    ;; Build back-to-front so each stage's filter can reference its downstream
    ;; process, and so no stage can emit output before its target exists.
    (cl-loop for i from (1- n) downto 0
             for stage = (nth i stages)
             for argv = (plist-get stage :argv)
             for errs = (plist-get stage :err)
             for down = (and (< (1+ i) n) (aref procs (1+ i)))
             for errproc = (and errs
                                (make-pipe-process
                                 :name (format "doom-sh&-err[%d]" i) :noquery t
                                 :filter (doom-sh--async-filter errs)))
             do (unless argv (error "sh: empty command in pipeline"))
             do (aset procs i
                      (make-process
                       :name (format "doom-sh&[%d]" i)
                       :command argv
                       :connection-type 'pipe
                       :noquery t
                       :stderr errproc
                       :filter (doom-sh--async-filter (plist-get stage :out) down)
                       :sentinel (doom-sh--async-sentinel down errproc))))
    ;; Prime the head of the pipeline's stdin, then close it. Read the sources
    ;; outside `ignore-errors' so a missing input file still signals.
    (let* ((head (aref procs 0))
           (ins (plist-get (nth 0 stages) :in))
           (input (and ins (doom-sh--read-sources ins))))
      (ignore-errors
        (if input (process-send-string head input))
        (process-send-eof head)))
    ;; Mirrors the shell's $! for a pipeline
    (process-id (aref procs (1- n)))))


;;
;;; * DSL

;;;###autoload
(defmacro sh! (&rest args)
  "Execute ARGS as a shell command, emitting output to `standard-output'.

Returns t if successful.

Supports pipes and redirects (|, <, >, >>, 2>, 2>>). E.g.

  \\=(sh! cat file | grep \"test\")        ; pipe between two programs
  \\=(sh! cat file > /some/file)         ; truncate stdout to a file
  \\=(sh! echo \"done\" >> /some/file)     ; append stdout to a file
  \\=(sh! sort < /some/file)             ; read stdin from a file
  \\=(sh! cat file > ,(current-buffer))  ; write stdout into a buffer
  \\=(sh! grep foo < ,(get-buffer \"x\"))  ; read stdin from a buffer
  \\=(sh! make 2> errors.log)            ; send stderr to its own file
  \\=(sh! make 2>> errors.log)           ; append stderr to a file

stdout and stderr are mixed together by default (so `> f' captures both). Use
`2>'/`2>>' to peel stderr off into its own file or buffer. There is no `2>&1';
it is the default behavior.

Values can be spliced into commands using backquote and `,' / `,@' syntax:

  \\=(sh< ls ,@flags ,(expand-file-name dir))"
  `(let ((result (doom-sh--pipeline (doom-sh--parse (backquote ,args)) 'stream)))
     (with-no-warnings (zerop (car result)))))

;;;###autoload
(defmacro sh< (&rest args)
  "Execute ARGS as a shell command and return its output.

Returns nil if the command exits with a non-zero exit code. Supports pipes and
redirects (see `sh!' for details)."
  `(let ((result (doom-sh--pipeline (doom-sh--parse (backquote ,args)))))
     (when (zerop (car result))
       (with-no-warnings (cdr result)))))

;;;###autoload
(defmacro sh? (&rest args)
  "Execute ARGS as a shell command and return t if successful.

Unlike `sh!', does not emit the output to `standard-output'. Supports pipes and
redirects (see `sh!' for details)."
  `(let ((result (doom-sh--pipeline (doom-sh--parse (backquote ,args)))))
     (with-no-warnings (zerop (car result)))))

;;;###autoload
(defmacro sh& (&rest args)
  "Execute ARGS as a shell command asynchronously and return its process id.

Does not block. For pipelines, returns the pid of the final stage. The final
stage's output is discarded unless redirected. Supports pipes and redirects (see
`sh!' for details)."
  `(doom-sh--pipeline-async (doom-sh--parse (backquote ,args))))

(provide 'doom-cli '(sh))
;;; sh.el ends here
