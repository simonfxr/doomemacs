;;; doom/cli/+commit-linter.el -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;;
;;; * Variables

(defvar doom-commit-linter-styles
  `((default   ; conventional commits (default)
     (types "fix" "feat"))
    (cc        ; conventional commits (angular)
     (url "https://www.conventionalcommits.org/")
     (trailers ("^Fix[: ]" ref hash url)
               ("^Refs?[: ]" ref hash url)
               ("^Close[: ]" ref)
               ("^Revert[: ]" ref hash)
               ("^Amend[: ]" ref hash)
               ("^Co-authored-by[: ]" user)
               ("^Signed-off-by[: ]" user))
     (types "ci" "chore" "docs" "feat" "fix" "refactor" "style" "revert" "test")
     (scopeless-types))
    (doom      ; doom-style conventional commits
     (url "https://docs.doomemacs.org/conventions")
     (trailers ("^Fix: " ref hash url)
               ("^Ref\\(\\[[0-9]+\\]\\)?: " ref hash url)
               ("^Close: " ref)
               ("^Revert: " ref hash)
               ("^Amend: " ref hash)
               ("^Co-authored-by: " user)
               ("^Signed-off-by: " user))
     (types "bump" "dev" "docs" "feat" "fix" "merge" "nit" "perf" "refactor"
            "release" "revert" "test" "tweak" "module")
     (scopes "ci" doom-commit-has-valid-module-scope)
     (scopeless-types "bump" "merge" "release" "revert"))))

(defvar doom-commit-linter-trailer-types
  '((ref      . "^\\(https?://[^ ]+\\|[^/]+/[^/]+\\)?#[0-9]+$")
    (hash     . "^\\(https?://[^ ]+\\|[^/]+/[^/]+@\\)?[a-z0-9]\\{12\\}$")
    (url      . "^https?://")
    (user     . "^[a-zA-Z0-9-_ \\.']+<[^@]+@[^.]+\\.[^>]+>$")
    (username . "^@[^a-zA-Z0-9_-]+$"))
  "An alist of valid trailer keys and their accepted value types.

Accapted value types can be one or more of ref, hash, url, username, or name.")

(defvar doom-commit-linter-functions
  '(;; General checkers
    doom-commit-has-valid-subject-length

    ;; Conventional commit checkers
    doom-commit-has-valid-cc-type
    doom-commit-has-valid-cc-scope
    doom-commit-has-valid-cc-summary
    doom-commit-has-valid-cc-body
    doom-commit-has-valid-cc-bang
    doom-commit-has-valid-cc-bumps
    doom-commit-has-valid-cc-trailers

    ;; TODO: Validate bump/revert SUBJECT list
    ;; TODO: Ensure diff corraborates your SCOPE
    )
  "A list of validator functions to run against a commit.

Each function takes two arguments, the first is an configuration alist which is
merged from the project's .doom and any defaults specified in
`doom-commit-linter-styles'. The second is a plist containing parsed data about
the commit being linted; this plist contains the following:

  :preset
    Which of the presets in `doom-commit-linter-styles' is active. Nil of none.
  :root
    The root directory of the current git repository.
  :bang
    (Boolean) If `t', the commit is declared to contain a breaking change.
    e.g. \\='refactor!: this commit breaks everything'
  :body
    (String) Contains the whole BODY of a commit message, excluding the
    TRAILERS.
  :scopes
    (List<Symbol>) Contains a list of scopes, as symbols. e.g. with
    \\='feat(org,lsp): so on and so forth', this contains \\='(org lsp).
  :subject
    (String) Contains the whole first line of a commit message.
  :summary
    (String) Contains the summary following the type and scopes. e.g. In
    \\='feat(org): fix X, Y, and Z' the summary is \\='fix X, Y, and Z'.
  :trailers
    (Map<String, String>) Contains an alist of KEY: VALUE trailers, i.e. All
    Fix, Ref, Close, Revert, etc lines with a valid value. This will be empty if
    the formatting of a commit's trailers is invalid.
  :type
    (Symbol) The type of commit this is. E.g. `feat', `fix', `bump', etc.

Each function should return a list of cons cells (RESULT . MESSAGE) where RESULT
is one of `fail' or `warn' and MESSAGE is a string message to explain the
failure or warning. Otherwise, it should throw a `skip' tag (with a string
message) to signal that this commit should be skipped over by all validator
functions and all previous results be ignored.

Note: warnings are not considered failures.")


;;
;;; * Commands

(defun doom-commit-linter--hook-path ()
  (or (sh< git config core.hooksPath)
      (sh< git rev-parse --git-path hooks)
      (doom-path (sh< git rev-parse --show-toplevel)
                 ".git/hooks")))

(defcli! (run git-hook install) (&context context &rest hooks)
  "Install Doom's git-hooks to the current git repository."
  :benchmark t
  (unless (sh? git rev-parse --show-toplevel)
    (user-error "Not in a git repository"))
  (let ((hooks-dir (doom-commit-linter--hook-path)))
    (print! (start "Installing git hooks to %S" hooks-dir))
    (print-group!
     (make-directory hooks-dir 'parents)
     (dolist (hook (or hooks '("commit-msg" "pre-push")) t)
       (or (if (not (member hook '("install" "uninstall")))
               (doom-cli-get
                `(,(doom-cli-context-prefix context) run git-hook ,hook)))
           (user-error "Invalid hook: %s" hook))
       (let* ((hook (doom-path hooks-dir hook))
              (overwrite-p (file-exists-p hook)))
         (with-file-modes #o700
           (with-temp-file hook
             (insert "#!/usr/bin/env sh\n"
                     (doom-emacs-dir "bin/doom")
                     " --no-color run git-hook " (file-name-base hook)
                     " \"$@\"")))
         (print! (success "%s %s")
                 (if overwrite-p "Overwrote" "Created")
                 (path hook)))))))

(defcli! (run git-hook uninstall) (&rest hooks)
  "Delete Doom's git-hooks from the current git repository.

Be warned! This will delete pre-existing and non-Doom git-hooks!"
  :benchmark t
  (let ((hooks-dir (doom-commit-linter--hook-path)))
    (print! (start "Uninstalling git hooks from %s" hooks-dir))
    (print-group!
     (unless (file-directory-p hooks-dir)
       (user-error "Hooks directory does not exist: %S" hooks-dir))
     (dolist (hook (or hooks '("commit-msg" "pre-push")) t)
       (if (not (file-exists-p (doom-path hooks-dir hook)))
           (print! (warn "No %S hook" hook))
         (delete-file (doom-path hooks-dir hook))
         (print! (success "Hook uninstalled: %s" hook)))))))

(defcli! (run git-hook commit-msg) (file)
  "Run git commit-msg hook.

Lints the current commit message."
  (with-temp-buffer
    (insert-file-contents file)
    (or (doom-commit-linter
         `(("CURRENT" .
            ,(buffer-substring
              (point-min)
              (if (re-search-forward "^# Please enter the commit message" nil t)
                  (match-beginning 0)
                (point-max)))))
         t)
        (exit! 1))))

(defcli! (run git-hook pre-push) (remote url)
  "Run git pre-push hook.

Prevents pushing if there are unrebased or WIP commits."
  (with-temp-buffer
    (let ((z40 (make-string 40 ?0))
          line error)
      (while (setq line (ignore-errors (read-from-minibuffer "")))
        (catch 'continue
          (seq-let (_local-ref local-sha remote-ref remote-sha)
              (split-string line " ")
            ;; TODO: Extract this branch detection to a variable
            (unless (or (string-match-p "^refs/heads/\\(master\\|main\\)$" remote-ref)
                        (equal local-sha z40))
              (throw 'continue t))
            (print-group!
              (mapc (lambda (commit)
                      (seq-let (hash msg) (split-string commit "\t")
                        (setq error t)
                        (print! (item "%S commit in %s"
                                      (car (split-string msg " "))
                                      (substring hash 0 12)))))
                    (split-string
                     (sh< git rev-list
                          --grep ,(concat "^" (regexp-opt '("WIP" "squash!" "fixup!" "FIXUP") t) " ")
                          --format=%H\t%s
                          ,(if (equal remote-sha z40)
                               local-sha
                             (format "%s..%s" remote-sha local-sha)))
                     "\n" t))
              (when error
                (print! (error "Aborting push due to unrebased WIP, squash!, or fixup! commits"))
                (exit! 1)))))))))

(defcli! (run commit-linter) (from &optional to)
  "TODO"
  (with-temp-buffer
    (insert
     (sh< git log ,(format "%s...%s" from (or to (concat from "~1")))))
    (or (doom-commit-linter
         (let (commits)
           (while (re-search-backward "^commit \\([a-z0-9]\\{40\\}\\)" nil t)
             (push (cons (match-string 1)
                         (replace-regexp-in-string
                          "^    " ""
                          (save-excursion
                            (buffer-substring-no-properties
                             (search-forward "\n\n")
                             (if (re-search-forward "\ncommit \\([a-z0-9]\\{40\\}\\)" nil t)
                                 (match-beginning 0)
                               (point-max))))))
                   commits))
           commits))
        (exit! 1))))


;;
;;; * Helpers

(defun doom-commit-linter--parse (commit-msg &optional _config)
  (with-temp-buffer
    (save-excursion (insert commit-msg))
    `(,@(let ((end
               (save-excursion
                 (if (re-search-forward "\n\\(\n[a-zA-Z-]+: [^ ][^\n]+\\)+\n*\\'" nil t)
                     (1+ (match-beginning 0))
                   (point-max)))))
          `(:preset   nil
            :root     ,(sh< git rev-parse --show-toplevel)
            :subject  ,(buffer-substring
                        (point-min) (save-excursion (goto-char (point-min))
                                                    (pos-eol)))
            :body     ,(string-trim-right (buffer-substring (line-beginning-position 3) end))
            :trailers ,(save-match-data
                         (cl-loop with footer = (buffer-substring end (point-max))
                                  for line in (split-string footer "\n" t)
                                  if (string-match "^\\([a-zA-Z-]+\\): \\(.+\\)$" line)
                                  collect (cons (match-string 1 line) (match-string 2 line))))))
      ,@(save-match-data
          (when (looking-at "^\\([a-zA-Z0-9_-]+\\)\\(!?\\(?:(\\([^)]+\\))\\)?!?\\): \\([^\n]+\\)")
            `(:type    ,(intern (match-string 1))
              :bang    ,(or (string-prefix-p "!" (match-string 2))
                            (string-suffix-p "!" (match-string 2)))
              :summary ,(match-string 4)
              :scopes  ,(ignore-errors (split-string (match-string 3) ",")))))
      ,@(save-excursion
          (let ((bump-re "\\(\\(?:https?://.+\\|[^/ \n]+\\)/[^/ \n]+@[a-f0-9]\\{12\\}\\)\\( ([^)]+)\\)?")
                bumps)
            (while (re-search-forward (format "^\\s-*\\<%s -> %s\\>" bump-re bump-re) nil t)
              (cond ((rassoc (match-string 1) bumps)
                     (setcdr (rassoc (match-string 1) bumps) (match-string 2)))
                    ((assoc (match-string 2) bumps)
                     (setcar (assoc (match-string 2) bumps) (match-string 1)))
                    ((setf (alist-get (match-string 1) bumps nil nil #'equal)
                           (match-string 2)))))
            `(:bumps ,(cl-sort (delete-dups bumps) #'string-lessp :key #'car)))))))

(defun doom-commit-linter--parse-bumps (from end)
  (with-temp-buffer
    (save-excursion
      (insert
       (sh< git log --format=full "--grep=\\(bump\\|revert\\):"
            ,(format "%s...%s" from end))))
    (save-match-data
      (let (packages)
        (while (let ((bump-re "\\(\\(?:https?://.+\\|[^/ ]+\\)/[^/ ]+@[a-f0-9]\\{12\\}\\(?: ([^)]+)\\)?\\)"))
                 (re-search-forward (format "^\\s-*\\<%s -> %s\\>" bump-re bump-re) nil t))
          (cond ((rassoc (match-string 1) packages)
                 (setcdr (rassoc (match-string 1) packages) (match-string 2)))
                ((assoc (match-string 2) packages)
                 (setcar (assoc (match-string 2) packages) (match-string 1)))
                ((setf (alist-get (match-string 1) packages nil nil #'equal)
                       (match-string 2)))))
        (cl-sort (delete-dups packages) #'string-lessp :key #'car)))))

(defun doom-commit-linter (commits &optional echo-msg)
  "lint commit messages in the given COMMITS alist (mapping ref -> message).

print the original message again when ECHO-MSG is non-nil."
  (let* ((root (sh< git rev-parse --show-toplevel))
         (config (doom-config `(,root project commits)))
         (warnings 0)
         (failures 0)
         case-fold-search)  ; case sensitive regexp matching
    (when-let* ((style (car (alist-get 'style config)))
                (defaults (alist-get style doom-commit-linter-styles)))
      (setq config (map-merge 'alist defaults config)))
    (print! (start "Linting %d commit%s..." (length commits) (if (cdr commits) "s" "")))
    (print-group!
      (pcase-dolist (`(,ref . ,commitmsg) commits)
        (let* ((commit   (doom-commit-linter--parse commitmsg config))
               (shortref (substring ref 0 7))
               (subject  (plist-get commit :subject)))
          (print! (start "%s %s") shortref subject)
          (print-group!
            (if (string-match "^\\(\\(?:fixup\\|squash\\)!\\|FIXUP\\|WIP\\) " subject)
                (print! (info "Found %S commit, skipping...") (match-string 1 subject))
              (dolist (fn doom-commit-linter-functions)
                (dolist (result (remq nil (funcall fn config commit)))
                  (pcase (car result)
                    (`fail
                     (print! (error "%s") (cdr result))
                     (cl-incf failures))
                    (`warn
                     (print! (warn "%s") (cdr result))
                     (cl-incf warnings))))))))))
    (let ((issues (+ warnings failures)))
      (if (= issues 0)
          (always (print! (success "There were no issues!")))
        (if warnings (print! (warn "Warnings: %d" warnings)))
        (if failures (print! (warn "Failures: %d" failures)))
        (when-let* ((url (car (alist-get 'url config))))
          (print! "\nSee %s" url))
        (if (not failures)
            t
          (when echo-msg
            (print! "\nPlease adjust your previous attempt:")
            (pcase-dolist (`(,ref . ,commitmsg) commits)
              (unless (string= ref "CURRENT")
                (print! "\n%s\n" ref))
              (print! "%s" commitmsg)))
          nil)))))


;;
;;; * Rule checkers

;;; ** General checkers

(cl-defun doom-commit-has-valid-subject-length (_config (&key type subject &allow-other-keys))
  "Test SUBJECT length"
  (let ((len (length subject)))
    (cond
     ((memq type '(bump revert release)) nil)
     ((<= len 10)
      `((fail . "Subject is too short (<10) and should be more descriptive")))
     ((<= len 20)
      `((warn . "Subject is short (<20); are you sure it's descriptive enough?")))
     ((> len 72)
      `((fail . ,(format "Subject is %d characters, above the 72 maximum" len))))
     ((> len 50)
      `((warn . ,(format "Subject is %d characters; <=50 is ideal" len)))))))


;;; ** Conventional-commit checkers

(cl-defun doom-commit-has-valid-cc-type (config (&key type &allow-other-keys))
  "Ensure commit has valid type"
  (let ((types (alist-get 'types config)))
    (unless (or (member (symbol-name type) types)
                (cl-loop for tp in types
                         if (if (functionp tp)
                                (funcall tp type))
                         return t))
      `((fail
         . ,(if type
                (format "Invalid commit type: %s" type)
              "Commit has no detectable type"))))))

(cl-defun doom-commit-has-valid-cc-summary (_config (&key summary &allow-other-keys))
  "Ensure summary isn't needlessly capitalized"
  `(,@(and (or (not (stringp summary))
               (string-blank-p summary))
           '((fail . "Commit has no summary")))
    ,@(and (stringp summary)
           (string-match-p "^[A-Z][^-A-Z.]" summary)
           `((fail . ,(format "%S in summary should not be capitalized"
                              (car (split-string summary " "))))))))

(cl-defun doom-commit-has-valid-cc-scope (config (&rest plist &key type scopes &allow-other-keys))
  (let-alist config
    `(,@(let (results)
          (dolist (scope scopes (nreverse results))
            (condition-case e
                (letf! (defun* check-rule (rule)
                         (or (and (stringp rule)
                                  (string= rule scope))
                             (and (functionp rule)
                                  (funcall rule config plist))
                             (and (listp rule)
                                  (eq type (car rule))
                                  (seq-find #'check-rule (cdr rule)))))
                  (or (seq-find #'check-rule .scopes)
                      (push `(fail . ,(format "Invalid scope: %s" scope)) results)))
              (user-error
               (push `(fail . ,(format "%s" (error-message-string e))) results)))))
      ;; Ensure scopeless commits are respected
      ,@(if (memq type .scopeless-types)
            `((fail
               . ,(format "Scopes for %s commits go after the colon, not before"
                          type)))
          ;; Ensure is sorted correctly
          (unless (equal scopes (sort (copy-sequence scopes) #'string-lessp))
            `((fail . "Scopes are not in lexicographical order")))))))

(cl-defun doom-commit-has-valid-cc-body (_config (&rest plist &key _type _scopes body &allow-other-keys))
  "Enforce 72 character line width for BODY"
  (catch 'result
    (with-temp-buffer
      (save-excursion (insert body))
      (while (re-search-forward "^[^\n]\\{73,\\}" nil t)
        (save-excursion
          (let ((bol (match-beginning 0)))
            (or
             ;; Long bump lines are acceptable
             (let ((bump-re "\\(https?://.+\\|[^/]+\\)/[^/]+@[a-f0-9]\\{12\\}\\( ([^)]+)\\)?"))
               (re-search-backward (format "^%s -> %s$" bump-re bump-re) bol t))
             ;; Long URLs are acceptable
             (re-search-backward "https?://[^ \n]+" bol t)
             ;; Lines that start with # or whitespace are comment or
             ;; code blocks.
             (re-search-backward "^\\(?:#\\| +\\)" bol t)
             (throw
              'result `((fail
                         . "Line(s) in commit body exceeds 72 characters"))))))))))

(cl-defun doom-commit-has-valid-cc-bang (_config (&key bang body type &allow-other-keys))
  "Ensure ! is accompanied by a `BREAKING CHANGE:' in BODY."
  (if bang
      (cond ((not (string-match-p "^BREAKING CHANGE:" body))
             '((fail
                . "'!' present in commit type, but missing 'BREAKING CHANGE:' in body")))
            ((not (string-match-p "^BREAKING CHANGE: .+" body))
             '((fail
                . "'BREAKING CHANGE:' present in commit body without explanation"))))
    (when (string-match-p "^BREAKING CHANGE:" body)
      `((fail
         . ,(format "'BREAKING CHANGE:' present in body, but missing '!' after %S"
                    type))))))

(cl-defun doom-commit-has-valid-cc-bumps (_config (&key type body &allow-other-keys))
  "Ensure bump commits have package ref lines"
  `(,@(and (eq type 'bump)
           (let ((re "\\(?:https?://.+\\|[^/]+\\)/[^/]+@\\([a-f0-9]+\\)\\( ([^)]+)\\)?"))
             (not (string-match-p (concat "^" re " -> " re "$") body)))
           `((fail . "Bump commit is missing commit hash diffs")))

    ;; Ensure commit hashes in bump lines are 12 characters long
    ,@(with-temp-buffer
        (insert body)
        (let ((bump-re "\\<\\(?:https?://[^@]+\\|[^/]+\\)/[^/]+@\\([a-f0-9]+\\)")
              refs)
          (while (re-search-backward bump-re nil t)
            (when (/= (length (match-string 1)) 12)
              (push (match-string 0) refs)))
          (when refs
            `((fail
               . ,(format "%d commit hash(s) not 12 characters long: %s"
                          (length refs) (string-join (nreverse refs) ", ")))))))))

(cl-defun doom-commit-has-valid-cc-trailers (config (&key body trailers &allow-other-keys))
  ;; TODO: Add bump validations for revert: type.
  (let-alist config
    (let* ((keys   (mapcar #'car .trailers))
           (key-re (regexp-opt keys t))
           (lines
            ;; Scan BODY because invalid trailers won't be in TRAILERS.
            (save-match-data
              (and (string-match "\n\\(\n[a-zA-Z][a-zA-Z-]*:? [^ ][^\n]+\\)+\n+\\'" body)
                   (split-string (match-string 0 body) "\n" t))))
           fails)
      (dolist (line lines)
        (unless (string-match-p (concat "^" key-re ":? [^ ]") line)
          (push (format "Found %S, expected one of: %s"
                        (truncate-string-to-width (string-trim line) 16 nil nil "…")
                        (string-join keys ", "))
                fails))
        (when (and (string-match "^[^a-zA-Z-]+:? \\(.+\\)$" line)
                   (string-match-p " " (match-string 1 line)))
          (push (format "%S has multiple references, but should only have one per line"
                        (truncate-string-to-width (string-trim line) 20 nil nil "…"))
                fails))
        (when (or (string-match (concat "^" key-re "\\(?:e?[sd]\\|ing\\)? [^ ]") line)
                  (string-match (concat "^\\([a-zA-Z-]+\\) [^ \n]+$") line))
          (push (format "%S missing colon after %S"
                        (truncate-string-to-width (string-trim line) 16 nil nil "…")
                        (match-string 1 line))
                fails)))
      (pcase-dolist (`(,key . ,value) trailers)
        (if (and (not (memq 'name (cdr (assoc key .trailers))))
                 (string-match-p " " value))
            (push (format "Found %S, but only one value allowed per trailer"
                          (truncate-string-to-width (concat key ": " value) 20
                                                    nil nil "…"))
                  fails)
          (when-let* ((allowed-types (cdr (assoc key .trailers))))
            (or (cl-loop for type in allowed-types
                         if (cdr (assq type doom-cli-commit-trailer-types))
                         if (string-match-p it value)
                         return t)
                (push (format "%S expects one of %s, but got %S"
                              key allowed-types value)
                      fails)))))
      (mapcar (fn! (cons 'fail %)) (nreverse fails)))))


;;; ** Doom-specific checkers

(cl-defun doom-commit-has-valid-module-scope (_config (&key root scopes &allow-other-keys))
  "Checks if SCOPE is a valid module scope."
  (cl-loop for scope in scopes
           if (doom-glob
               root "modules" (if (string-prefix-p ":" scope)
                                  (format "%s" (substring scope 1))
                                (format "*/%s" scope)))
           return t))

;;; commit-linter.el ends here
