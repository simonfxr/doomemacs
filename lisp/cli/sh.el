;;; lisp/cli/sh.el -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Syntax sugar for quickly executing shell commands from your Doom CLIs.
;;
;; TODO: Intercept and handle pipes/redirects in elisp (to stay platform
;;   agnostic). E.g.
;;
;;     (sh! cat file | grep "test")
;;     (sh! cat file > /some/file)
;;     (sh! cat file < /some/file)
;;
;;   And allow redirecting to/from elisp buffers
;;
;;     (sh! cat file > ,(current-buffer))
;;     (sh! cat file < ,(current-buffer))
;;
;;; Code:

(defun doom-sh--process-args (args)
  (cl-loop for arg in (delq nil args)
           if (symbolp arg)
           collect (symbol-name arg)
           else collect arg))

;;;###autoload
(defmacro sh! (&rest args)
  "Execute ARGS as a shell command and return t if successful.

Emits its output to `standard-output'. Does not support pipes (yet)."
  `(zerop (apply #'doom-exec-process
                 (doom-sh--process-args (backquote ,args)))))

;;;###autoload
(defmacro sh< (&rest args)
  "Execute ARGS as a shell command and return its output.

Returns nil if command exits with a non-zero exit code."
  `(let ((result (apply #'doom-call-process
                        (doom-sh--process-args (backquote ,args)))))
     (when (zerop (car result))
       (cdr result))))

;;;###autoload
(defmacro sh? (&rest args)
  "Execute ARGS as a shell command and return t if successful.

Unlike `sh!', this does not emit the output to `standard-output'."
  `(if (with-no-warnings (sh< ,@args)) t))

;; TODO: Implement sh&
;; ;;;###autoload
;; (defmacro sh& (&rest args)
;;   "Execute ARGS as a shell command in the background.")

(provide 'doom-cli '(sh))
;;; sh.el ends here
