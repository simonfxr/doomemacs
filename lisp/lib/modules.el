;;; lib/modules.el -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(defvar doom-modules nil
  "A table of enabled modules and metadata. See `doom-modules-initialize'.")

(make-obsolete-variable 'doom-inhibit-module-warnings nil "2.1.0")
(defvar doom-inhibit-module-warnings (not noninteractive)
  "If non-nil, don't emit deprecated or missing module warnings at startup.")


;;
;;; API

;;;###autoload
(defun doom-modules-initialize (&optional force?)
  "Initializes module metadata."
  (when (or (null doom-modules) force?)
    (setq doom-modules (make-hash-table :test 'equal))
    ;; Register Doom's two virtual module categories, representing Doom's core
    ;; and the user's config; which are always enabled.
    (doom-module--put '(:doom . nil) :path doom-core-dir :depth -110)
    (doom-module--put '(:user . nil) :path doom-user-dir :depth '(-105 . 105))
    ;; DEPRECATED: Includes use-package, deprecated APIs/vars, smartparens,
    ;;   projectile -- everything that makes v2 distinct from v3. The module is
    ;;   here to stay, but it won't be hardcoded after v3.
    (doom-module--put '(:doom . compat)
                      :path (doom-module-locate-path '(:doom . compat))
                      :depth -111)
    ;; Load $DOOMDIR/init.el, where the user's `doom!' lives, which will inform
    ;; us of all desired modules.
    (doom-load (file-name-concat doom-user-dir doom-module-init-file)
               'noerror)))

(cl-defun doom-module--put ((group . name) &rest plist)
  "Enable GROUP NAME and associate PLIST with it.

This enables the target module, where GROUP is a keyword, NAME is a symbol, and
PLIST is a property list accepting none, any, or all of the following
properties:

  :group KEYWORD
    Indicating the group this module is in. This doesn't have to match GROUP, as
    it could indicate a module alias.
  :name SYMBOL
    Indicating the name of this module. This doesn't have to match NAME, as it
    could indicate a module alias.
  :path STRING
    Path to the directory where this module lives.
  :depth INT|(INITDEPTH . CONFIGDEPTH)
    Determines module load order. If a cons cell, INITDEPTH determines the load
    order of the module's init.el, while CONFIGDEPTH determines the same for all
    other config files (config.el, packages.el, doctor.el, etc).
  :flags (SYMBOL...)
    A list of activated flags for this module. Will be collapsed into
    pre-existing flags for the module.
  :features (SYMBOL...)
    A list of active features, determined from the module's metadata. Will be
    collapsed into any pre-existing features for the module. NOT IMPLEMENTED
    YET.

\(fn (GROUP . NAME) &key GROUP NAME PATH DEPTH FLAGS FEATURES)"
  (let ((module
         (make-doom-module
          :index (hash-table-count doom-modules)
          :group (or (plist-get plist :group) group)
          :name  (or (plist-get plist :name) name)
          :path  (plist-get plist :path)
          :flags (plist-get plist :flags)
          :features ()  ; TODO
          :depth
          (if (not (plist-member plist :depth))
              '(0 . 0)
            (let ((depth (plist-get plist :depth)))
              (cl-check-type depth (or integer cons))
              (cond ((integerp depth) (cons depth depth))
                    ((consp depth) (cons (or (car depth) 0)
                                         (or (cdr depth) 0)))
                    ((error "Invalid DEPTH value: %S" depth))))))))
    (doom-log 2 "module-put: %s" module)
    (prog1 (puthash (cons group name) module doom-modules)
      ;; PERF: Doom caches module index, flags, and features in symbol plists
      ;;   for fast lookups in `modulep!' and elsewhere. plists are lighter and
      ;;   faster than hash tables for datasets this size, and this information
      ;;   is looked up *very* often.
      (put group name (doom-module->context module)))))

(defun doom-module--remap (group module)
  (cl-loop for (old new v) in
           (with-memoization (get 'doom-module--remap 'cache)
             (cl-loop for dir in (reverse doom-module-load-path)
                      if (doom-config `(,dir modules obsolete))
                      append it))
           if (equal `(,group ,module) old)
           return (list old new v)))

(defun doom-module-mplist-map (fn mplist)
  "Apply FN to each module in MPLIST."
  (let ((mplist (copy-sequence mplist))
        (inhibit-message doom-inhibit-module-warnings)
        results
        group m)
    (while mplist
      (setq m (pop mplist))
      (cond ((keywordp m)
             (setq group m))
            ((null group)
             (error "No module group specified for %s" m))
            ((and (listp m) (keywordp (car m)))
             (pcase (car m)
               (:cond
                (cl-loop for (cond . mods) in (cdr m)
                         if (eval cond t)
                         return (cl-callf2 append mods mplist)))
               (:if (if (eval (cadr m) t)
                        (push (caddr m) mplist)
                      (cl-callf2 append (cdddr m) mplist)))
               (test (if (xor (eval (cadr m) t)
                              (eq test :unless))
                         (cl-callf2 append (cddr m) mplist)))))
            ((catch 'doom-modules
               (let* ((module (if (listp m) (car m) m))
                      (flags  (if (listp m) (cdr m))))
                 (when-let* ((remap (doom-module--remap group module)))
                   (pcase-let* ((`(,old ,new ,when) remap))
                     (when when
                       (setq when (format " in %s" v)))
                     (if (null new)
                         (print! (warn "%s module was removed%s, ignoring..." old when))
                       (if (stringp new)
                           (print! (warn "%s module was removed%s: %s..." old new when))
                         (print! (warn "%s module was moved to %s%s, remapping..." old new when)))
                       (push group mplist)
                       (dolist (f (reverse new))
                         (push (if (keywordp f) f (cons f flags))
                               mplist))
                       (throw 'doom-modules t))))
                 (doom-log "module: %s %s %s -> %s" group module (or flags "")
                           (doom-module-locate-path (cons group module)))
                 (push (funcall fn (cons group module)
                                :flags (if (listp m) (cdr m))
                                :path (doom-module-locate-path (cons group module)))
                       results))))))
    (when noninteractive
      (setq doom-inhibit-module-warnings t))
    (nreverse results)))

(provide 'doom-lib '(modules))
;;; modules.el ends here
