;;; lisp/doom-docs.el -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; This file defines `doom-docs-org-mode', a major mode derived from org-mode,
;; intended to make Doom's documentation more readable, insert virtual
;; navigation in the header, prettify org buffers (hiding syntax and special
;; tags, substituting macros, and hiding conditional elements), and defines
;; special link types. It also incorporates an Info-esque node linking system so
;; all the distinct org files don't have to know precisely where each other are.
;;
;; You might think, why not use Info at this point? Because of its other
;; limitations: Org is much more capable and serves as a far more beginner-proof
;; foundation. I also want context-sensitive link types and dynamic content that
;; adjusts to the user's environment and Doom config without a messy build step
;; (that would impose external dependencies on the user, which would be
;; particularly messy on Windows). Org also lower the barrier of entry for
;; contributions to docs.
;;
;;; Code:

;;
;;; * Variables

;;;###autoload
(defvar doom-docs-dir (doom-emacs-dir "docs/")
  "Where Doom's documentation files are stored. Must end with a slash.")

;; DEPRECATED: Will be renamed once docs "framework" is generalized
(defvar doom-docs-link-alist
  '(("doom-tag"                . "https://github.com/doomemacs/core/releases/tag/%s")
    ("doom-contrib-core"       . "id:9ac0c15c-29e7-43f8-8926-5f0edb1098f0")
    ("doom-contrib-docs"       . "id:31f5a61d-d505-4ee8-9adb-97678250f4e2")
    ("doom-contrib-maintainer" . "id:e71e9595-a297-4c49-bd11-f238329372db")
    ("doom-contrib-module"     . "id:b461a050-8702-4e63-9995-c2ef3a78f35d")
    ("doom-faq"                . "id:5fa8967a-532f-4e0c-8ae8-25cd802bf9a9")
    ("doom-help"               . "id:9bb17259-0b07-45a8-ae7a-fc5e0b16244e")
    ("doom-help-changelog"     . "id:7c56cc08-b54b-4f4b-b106-a76e2650addd")
    ("doom-help-modules"       . "id:1ee0b650-f09b-4454-8690-cc145aadef6e")
    ("doom-index"              . "id:3051d3b6-83e2-4afa-b8fe-1956c62ec096")
    ("doom-module-index"       . "id:12d2de30-c569-4b8e-bbc7-85dd5ccc4afa")
    ("doom-module-issues"      . "https://github.com/doomemacs/modules/labels/%s")
    ("doom-module-history"     . "https://github.com/doomemacs/modules/commits/master/modules/%s")
    ("doom-report"             . "https://github.com/doomemacs/core/issues/new/choose")
    ("doom-suggest-edit"       . "id:31f5a61d-d505-4ee8-9adb-97678250f4e2")
    ("doom-suggest-faq"        . "id:aa28b732-0512-49ed-a47b-f20586c0f051")

    ;; TODO: Implement later, once docs are generalized
    ;; ("github-release"          . (lambda (link)
    ;;                                (format "%s/releases/tag/%s"
    ;;                                        doom-docs-this-repo
    ;;                                        link)))
    ;; ("github-label"            . (lambda (link)
    ;;                                (format "%s/labels/%s"
    ;;                                        doom-docs-this-repo
    ;;                                        link)))
    ;; ("github-commits"          . (lambda (link)
    ;;                                (format "%s/commits/%s/modules/%s"
    ;;                                        doom-docs-this-repo
    ;;                                        "master"
    ;;                                        link))"github-repo:/commits/%b/modules/%%s")
    ;; ("github-report"           . "github-repo:/issues/new/choose")
    ))

(defvar doom-docs-header-specs
  '(("/docs/index\\.org$"
     (:label "FAQ"
      :icon "nf-md-message_question_outline"
      :link "doom-faq:"
      :help-echo "Open the FAQ document"))
    (("/docs/[^/]+\\.org$" "/modules/README\\.org$")
     (:label "Back to index"
      :icon "nf-md-arrow_left"
      :link "doom-index"
      :help-echo "Navigate to the root index"))
    ("/modules/[^/]+/README\\.org$"
     (:label "Back to module index"
      :icon "nf-md-arrow_left"
      :link "doom-module-index:"))
    ("/modules/[^/]+/[^/]+/README\\.org$"
     (:label "Back to module index"
      :icon "nf-md-arrow_left"
      :link "doom-module-index:")
     (:label "History"
      :icon "nf-md-history"
      :icon-face font-lock-variable-name-face
      :link (lambda ()
              (cl-destructuring-bind (category . module) (doom-module-from-path (buffer-file-name))
                (format "doom-module-history:%s/%s" (doom-keyword-name category) module)))
      :help-echo "View the module history"
      :align right)
     (:label "Issues"
      :icon "nf-md-flag"
      :icon-face error
      :link (lambda ()
              (cl-destructuring-bind (category . module) (doom-module-from-path (buffer-file-name))
                (format "doom-module-issues::%s %s" category module)))
      :align right))
    (t
     (:label "Suggest edits"
      :icon "nf-md-account_edit"
      :icon-face warning
      :link "doom-suggest-edit"
      :align right)
     (:label "Help"
      :icon "nf-md-timeline_help_outline"
      :icon-face font-lock-function-name-face
      :link (lambda ()
              (let ((title (cadar (org-collect-keywords '("TITLE")))))
                (cond ((equal title "Changelog") "doom-help-changelog:")
                      ((string-prefix-p ":" title) "doom-help-modules:")
                      (t "doom-help:"))))
      :align right))))

(defvar doom-docs-notice-types
  '(("wip"     . "󱌣")
    ("tip"     . "󰐃")
    ("kudos"   . "󰔓")
    ("aside"   . "󰟶")
    ("notice"  . "󰥔")
    ("warning" . ""))
  "An alist mapping Doom notice types to icons.")

(defconst doom-docs--hidden-spec 'doom-docs-hidden)


;;
;;; * Helpers

(defun doom-docs--icon (icon label &rest plist)
  "Prefix LABEL with ICON (from nerd-icons).

Passes PLIST to appropriate nerd-icons-* function."
  (concat
   (when (fboundp 'nerd-icons-octicon)
     (cond ((string-prefix-p "nf-oct-" icon)
            (concat (apply #'nerd-icons-octicon icon plist)
                    " "))
           ((string-prefix-p "nf-md-" icon)
            (concat (apply #'nerd-icons-mdicon icon plist)
                    " "))))
   label))

(defun doom-docs--show-region (beg end visible?)
  (funcall (if (fboundp 'org-fold-core-region)  ; Org 9.6+
               #'org-fold-core-region
             #'org-flag-region)
           beg end visible?
           doom-docs--hidden-spec))

(defun doom-docs--visible-p (pt)
  (if (fboundp 'org-fold-folded-p)
      (org-fold-folded-p pt doom-docs--hidden-spec)
    (memq (org-invisible-p pt)
          '(org-hide-block outline doom-docs-hidden))))


;;; ** Navbar

(defun doom-docs--make-header ()
  "Create a header string for the current buffer."
  (let* ((applicable-specs
          (cl-loop for (condition . specs) in doom-docs-header-specs
                   when (if (symbolp condition)
                            (symbol-value condition)
                          (seq-some (doom-rpartial #'string-match-p (buffer-file-name))
                                    (ensure-list condition)))
                   append specs))
         (left-specs
          (cl-remove-if-not
           (lambda (s) (memq (plist-get s :align) '(nil left)))
           applicable-specs))
         (right-specs
          (cl-remove-if-not
           (lambda (s) (eq (plist-get s :align) 'right))
           applicable-specs))
         (left-string
          (mapconcat #'doom-docs--make-header-link left-specs " "))
         (right-string
          (mapconcat #'doom-docs--make-header-link right-specs " ")))
    (if (string-empty-p right-string)
        (concat " " left-string)
      (concat " " left-string
              (make-string (max (- (window-width)
                                   (length left-string)
                                   (length right-string)
                                   4)
                                1)
                           ?\s)
              right-string))))

(defun doom-docs--make-header-link (spec)
  "Create a header link according to SPEC."
  (let ((icon (plist-get spec :icon))
        (label (pcase (plist-get spec :label)
                 ((and (pred functionp) lab)
                  (funcall lab))
                 ((and (pred stringp) lab)
                  lab)))
        (link (pcase (plist-get spec :link)
                ((and (pred functionp) link)
                 (funcall link))
                ((and (pred stringp) link)
                 link))))
    (propertize
     (concat
      (doom-docs--icon
       icon
       (and label
            (propertize label 'face (cadr (or (plist-get spec :face)
                                              '(nil link)))))
       :face (cadr (or (plist-member spec :icon-face)
                       (plist-member spec :face)))))
     'doom-docs-link link
     'keymap doom-docs--header-link-keymap
     'help-echo (or (plist-get spec :help-echo)
                    (format "LINK: %s" link))
     'mouse-face 'highlight)))

(defvar doom-docs--header-link-keymap
  (let ((km (make-sparse-keymap)))
    (define-key km [header-line mouse-2] 'doom-docs--open-header-link)
    (define-key km [mouse-2] 'doom-docs--open-header-link)
    (define-key km [follow-link] 'mouse-face)
    km))

(defun doom-docs--open-header-link (ev)
  "Open the header link which is the target of the event EV."
  (interactive "e")
  (let* ((string-and-pos (posn-string (event-start ev)))
         (docs-buf (window-buffer (posn-window (event-start ev))))
         (link (get-pos-property (cdr string-and-pos)
                                 'doom-docs-link
                                 (car string-and-pos)))
         (parent-link-abbrevs
          (buffer-local-value 'org-link-abbrev-alist-local docs-buf)))
    (with-temp-buffer
      (setq buffer-file-name (buffer-file-name docs-buf))
      (let ((org-inhibit-startup t))
        (org-mode))
      (setq-local org-link-abbrev-alist-local parent-link-abbrevs)
      (insert "[[" link "]]")
      (set-buffer-modified-p nil)
      (org-link-open (org-element-context)))))


;;; ** Public API

;;;###autoload
(defun doom-docs-generate-id (&optional force?)
  "Generate an ID for a `doom-docs-org-mode' buffer."
  (let ((org-id-link-to-org-use-id t)
        (org-id-method 'uuid)
        (org-id-track-globally t)
        (org-id-locations-file doom-docs--id-location-file)
        (org-id-locations doom-docs--id-locations)
        (org-id-files doom-docs--id-files))
    (doom/reload-docs force?)
    (when-let* ((fname (buffer-file-name (buffer-base-buffer))))
      (let ((id (org-id-new)))
        (org-id-add-location id fname)
        id))))


;;; ** Transformer functions

(defun doom-docs--display-menu-h ()
  "Toggle virtual menu line at top of buffer."
  (setq header-line-format
        (and buffer-read-only
             (doom-docs--make-header)))
  (add-hook 'window-state-change-hook #'doom-docs--display-menu-h nil t))

(defun doom-docs--hide-meta-h ()
  "Hide all meta or comment lines."
  (org-with-wide-buffer
   (goto-char (point-min))
   (save-match-data
     (let ((case-fold-search t))
       (while (re-search-forward "^[ \t]*\\#" nil t)
         (unless (org-in-src-block-p t)
           (catch 'abort
             (doom-docs--show-region
              (line-beginning-position)
              (cond ((looking-at "+\\(?:title\\|subtitle\\): +")
                     (match-end 0))
                    ((looking-at "+\\(?:created\\|since\\|author\\|email\\|date\\): +")
                     (throw 'abort nil))
                    ((or (eq (char-after) ?\s)
                         (looking-at "+\\(begin\\|end\\)_comment"))
                     (line-beginning-position 2))
                    ((looking-at "+\\(?:begin\\|end\\)_\\([^ \n]+\\)")
                     (line-end-position))
                    ((line-beginning-position 2)))
              doom-docs-minor-mode))))))))

(defun doom-docs--hide-drawers-h ()
  "Hide all property drawers."
  (let (pt)
    (org-with-wide-buffer
     (goto-char (point-min))
     (when (looking-at-p org-drawer-regexp)
       (setq pt (org-element-property :end (org-element-at-point))))
     (while (re-search-forward org-drawer-regexp nil t)
       (when-let* ((el (org-element-at-point))
                   (beg (max (point-min) (1- (org-element-property :begin el))))
                   (end (org-element-property :end el))
                   ((memq (org-element-type el) '(drawer property-drawer))))
         (when (org-element-property-inherited :level el)
           (cl-decf end))
         (doom-docs--show-region beg end doom-docs-minor-mode))))
    ;; FIX: If the cursor remains within a newly folded region, that folk will
    ;;   come undone, so we move it.
    (if pt (goto-char pt))))

(defun doom-docs--hide-tags-h ()
  "Hide tags in org headings."
  (org-with-wide-buffer
   (goto-char (point-min))
   (while (re-search-forward org-heading-regexp nil t)
     (when-let* ((tags (org-get-tags nil t)))
       (when (or (member "noorg" tags)
                 (member "unfold" tags))
         ;; prevent `org-ellipsis' around hidden regions
         (org-show-entry))
       (if (member "noorg" tags)
           (doom-docs--show-region (line-end-position 0)
                                   (save-excursion
                                     (org-end-of-subtree t)
                                     (forward-line 1)
                                     (if (and (bolp) (eolp))
                                         (line-beginning-position)
                                       (line-end-position 0)))
                                   doom-docs-minor-mode)
         (doom-docs--show-region (save-excursion
                                   (goto-char (line-beginning-position))
                                   (re-search-forward " +:[^ ]" (line-end-position))
                                   (match-beginning 0))
                                 (line-end-position)
                                 doom-docs-minor-mode))))))

(defun doom-docs--hide-stars-h ()
  "Update invisible property to VISIBILITY for markers in the current buffer."
  (org-with-wide-buffer
   (goto-char (point-min))
   (with-silent-modifications
     (while (re-search-forward "^\\(\\*[ \t]\\|\\*\\*+\\)" nil t)
       (doom-docs--show-region (match-beginning 0)
                               (match-end 0)
                               doom-docs-minor-mode)))))

(defvar doom-docs--babel-cache nil)
(defun doom-docs--hide-src-blocks-h ()
  "Hide babel blocks (and/or their results) depending on their :exports arg."
  (org-with-wide-buffer
   (let ((inhibit-read-only t))
     (goto-char (point-min))
     (make-local-variable 'doom-docs--babel-cache)
     (while (re-search-forward org-babel-src-block-regexp nil t)
       (let* ((beg (match-beginning 0))
              (end (save-excursion (goto-char (match-end 0))
                                   (skip-chars-forward "\n")
                                   (point)))
              (exports
               (save-excursion
                 (goto-char beg)
                 (and (re-search-forward " :exports \\([^ \n]+\\)" (line-end-position) t)
                      (match-string-no-properties 1))))
              (results (org-babel-where-is-src-block-result)))
         (save-excursion
           (when (and (if (stringp exports)
                          (member exports '("results" "both"))
                        org-export-use-babel)
                      (not results)
                      doom-docs-minor-mode)
             (cl-pushnew beg doom-docs--babel-cache)
             (quiet! (org-babel-execute-src-block))
             (setq results (org-babel-where-is-src-block-result))
             (org-element-cache-refresh beg)
             (restore-buffer-modified-p nil)))
         (save-excursion
           (when results
             (when (member exports '("code" "both" "t"))
               (setq beg results))
             (when (member exports '("none" "code"))
               (setq end (progn (goto-char results)
                                (goto-char (org-babel-result-end))
                                (skip-chars-forward "\n")
                                (point))))))
         (unless (member exports '(nil "both" "code" "t"))
           (doom-docs--show-region beg end doom-docs-minor-mode))))
     (unless doom-docs-minor-mode
       (save-excursion
         (dolist (pos doom-docs--babel-cache)
           (goto-char pos)
           (org-babel-remove-result)
           (when (fboundp 'org-element-cache-refresh)
             (org-element-cache-refresh pos)))
         (kill-local-variable 'doom-docs--babel-cache)
         (restore-buffer-modified-p nil))))))

(defvar doom-docs--macro-cache nil)
(defun doom-docs--expand-macros-h ()
  "Expand {{{macros}}} with their value."
  (org-with-wide-buffer
   (goto-char (point-min))
   (make-local-variable 'doom-docs--macro-cache)
   (while (re-search-forward "{{{[^}]+}}}" nil t)
     (with-silent-modifications
       (if doom-docs-minor-mode
           (when-let* ((element (org-element-context))
                       (key (org-element-property :key element))
                       (cachekey (org-element-property :value element))
                       (template (cdr (assoc-string key org-macro-templates t))))
             (let ((value (or (cdr (assoc-string cachekey doom-docs--macro-cache))
                              (setf (alist-get cachekey doom-docs--macro-cache nil nil 'equal)
                                    (org-macro-expand element org-macro-templates)))))
               (add-text-properties (match-beginning 0)
                                    (match-end 0)
                                    `(display ,value))))
         (remove-text-properties (match-beginning 0)
                                 (match-end 0)
                                 '(display))))
     (when (fboundp 'org-element-cache-refresh)
       (org-element-cache-refresh (point))))))

(defun doom-docs--prettify-notices-h ()
  "Render notices with an icon and indentation."
  (org-with-wide-buffer
   (goto-char (point-min))
   (remove-overlays (point-min) (point-max) 'doom-docs t)
   (when doom-docs-minor-mode
     (let ((re (format "^\\( *\\)#\\+begin_quote +%s"
                       (regexp-opt (mapcar #'car doom-docs-notice-types)
                                   t))))
       (while (re-search-forward re nil t)
         (unless (doom-docs--visible-p (point))
           (let* ((icon (propertize (format " %s "
                                            (cdr (assoc (match-string 2)
                                                        doom-docs-notice-types)))
                                    'face 'org-quote))
                  (prefix (propertize " " 'display
                                      `(space :width ,(if (fboundp 'string-pixel-width)  ; Emacs 29+
                                                          (list (string-pixel-width icon))
                                                        (1+ (string-width icon))))
                                      'face 'org-quote))
                  (indent (match-string-no-properties 1))
                  (begoff (length indent))
                  (beg (save-excursion (goto-char (match-end 1))
                                       (point-at-bol 2)))
                  (end (save-excursion
                         (save-match-data
                           (search-forward (concat indent "#+end_quote") nil)
                           (point-at-bol)))))
             ;; Using `before-string' instead of `line-prefix' because
             ;; `org-indent-mode' will highjack the latter.
             (goto-char beg)
             (while (and (< (point) end)
                         (not (eobp)))
               (let ((ov (make-overlay (point-at-bol) (+ (point-at-bol) begoff))))
                 (overlay-put ov 'after-string (if (= (point) beg) icon prefix))
                 (overlay-put ov 'doom-docs t))
               (forward-line 1)))))))))


;;
;;; * `doom-docs-minor-mode'

(defvar doom-docs-mode-alist
  '((flyspell-mode . -1)
    (spell-fu-mode . -1)
    (visual-line-mode . -1)
    (mixed-pitch-mode . -1)
    (variable-pitch-mode . -1))
  "An alist of minor modes to toggle with `doom-docs-minor-mode'.

The CAR is the minor mode symbol, and CDR should be either +1 or -1,
depending.")

(defvar doom-docs--initial-values nil)
(defvar doom-docs--cookies nil)
;;;###autoload
(define-minor-mode doom-docs-minor-mode
  "Hides metadata, tags, & drawers and activates all org-mode prettifications.
This primes `org-mode' for reading."
  :lighter " Doom Docs"
  :after-hook (progn
                (org-restart-font-lock)
                (if (doom-docs--visible-p (point))
                    (goto-char (org-find-visible))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an org mode buffer"))
  (when (fboundp 'org-fold-add-folding-spec)  ; Org 9.6+
    (org-fold-add-folding-spec
     doom-docs--hidden-spec '(:visible nil
                              :ellipsis nil
                              :isearch-ignore t)))
  (mapc (lambda (sym)
          (if doom-docs-minor-mode
              (set (make-local-variable sym) t)
            (kill-local-variable sym)))
        '(org-pretty-entities
          org-hide-emphasis-markers
          org-hide-macro-markers))
  (when doom-docs-minor-mode
    (make-local-variable 'doom-docs--initial-values))
  (mapc (lambda! ((face . plist))
          (if doom-docs-minor-mode
              (push (apply #'face-remap-add-relative face plist) doom-docs--cookies)
            (mapc #'face-remap-remove-relative doom-docs--cookies)))
        '((org-document-title :weight bold :height 1.4)
          (org-document-info  :weight normal :height 1.15)))
  (mapc (lambda! ((mode . state))
          (if doom-docs-minor-mode
              (if (and (boundp mode) (symbol-value mode))
                  (unless (> state 0)
                    (setf (alist-get mode doom-docs--initial-values) t)
                    (funcall mode -1))
                (unless (< state 0)
                  (setf (alist-get mode doom-docs--initial-values) nil)
                  (funcall mode +1)))
            (when-let* ((old-val (assq mode doom-docs--initial-values)))
              (funcall mode (if old-val +1 -1)))))
        doom-docs-mode-alist)
  (unless doom-docs-minor-mode
    (kill-local-variable 'doom-docs--initial-values)))


;;; ** Hooks

(add-hook! 'doom-docs-minor-mode-hook
           #'doom-docs--display-menu-h
           #'doom-docs--hide-meta-h
           #'doom-docs--hide-tags-h
           #'doom-docs--hide-drawers-h
           ;; #'doom-docs--hide-stars-h
           #'doom-docs--expand-macros-h
           #'doom-docs--hide-src-blocks-h
           #'doom-docs--prettify-notices-h)


;;
;;; * `doom-docs-mode'

(defvar doom-docs-font-lock-keywords '()
  "Extra font-lock keywords for Doom documentation.")

(defvar doom-docs-mode-map
  (let ((map (make-sparse-keymap))
        (cmd (cmds! buffer-read-only #'kill-current-buffer)))
    (define-key map "q" cmd)
    (define-key map [remap evil-record-macro] cmd)
    (define-key map "\C-c\C-e" #'read-only-mode)
    map))

;;;###autoload
(define-derived-mode doom-docs-mode org-mode "Doom Manual"
  "A derivative of `org-mode' for Doom's documentation files."
  :after-hook (visual-line-mode -1)  ; uses hard wrapping
  (let ((gc-cons-threshold most-positive-fixnum)
        (gc-cons-percentage 1.0))
    (require 'org-id)
    (require 'ob)
    (setq-local org-id-link-to-org-use-id t
                org-id-method 'uuid
                org-id-track-globally t
                org-id-locations-file doom-docs--id-location-file
                org-id-locations doom-docs--id-locations
                org-id-files doom-docs--id-files
                org-num-max-level 3
                org-footnote-define-inline nil
                org-footnote-auto-label t
                org-footnote-auto-adjust t
                org-footnote-section nil
                wgrep-change-readonly-file t
                org-link-abbrev-alist-local (append org-link-abbrev-alist-local doom-docs-link-alist)
                org-babel-default-header-args
                (append '((:eval . "no") (:tangle . "no"))
                        org-babel-default-header-args)
                save-place-ignore-files-regexp ".")
    (when (featurep 'org-modern)
      (setq-local org-modern-table nil
                  org-modern-block-name nil))

    (font-lock-add-keywords nil doom-docs-font-lock-keywords)
    (unless org-inhibit-startup
      (unless (local-variable-p 'org-startup-with-inline-images)
        (setq org-display-remote-inline-images 'cache)
        (org-display-inline-images))
      (unless (local-variable-p 'org-startup-indented)
        (org-indent-mode +1))
      (unless (local-variable-p 'org-startup-numerated)
        (when (bound-and-true-p org-num-mode)
          (org-num-mode -1))
        (org-num-mode +1))
      (unless (local-variable-p 'org-startup-folded)
        (let ((org-startup-folded 'content)
              org-cycle-hide-drawer-startup)
          (org-set-startup-visibility))))
    (add-hook 'read-only-mode-hook #'doom-docs--toggle-read-only-h nil 'local)))

;; (defun doom-docs-init-glossary-h ()
;;   "Activates `org-glossary-mode', if it's available."
;;   (when (require 'org-glossary nil t)
;;     (setq-local org-glossary-global-terms (doom-glob doom-docs-dir "appendix.org"))
;;     (org-glossary-mode +1)))
;; (add-hook 'doom-docs-org-mode-hook #'doom-docs-init-glossary-h)

(defun doom-docs--toggle-read-only-h ()
  (doom-docs-minor-mode (if buffer-read-only +1 -1)))

;;;###autoload
(defun doom-docs-read-only-h ()
  "Activate `read-only-mode' if the current file exists and is non-empty."
  ;; The rationale: if it's empty or non-existant, you want to write an org
  ;; file, not read it.
  (let ((file-name (buffer-file-name (buffer-base-buffer))))
    (when (and file-name
               (> (buffer-size) 0)
               (not (string-prefix-p "." (file-name-base file-name)))
               (file-exists-p file-name))
      (read-only-mode +1))))

(add-hook 'doom-docs-mode-hook #'doom-docs-read-only-h)


;;
;;; * Commands

(defvar doom-docs--id-locations nil)
(defvar doom-docs--id-files nil)
(defvar doom-docs--id-location-file (file-name-concat doom-cache-dir "doom-docs-org-ids"))
;;;###autoload
(defun doom/reload-docs (&optional force)
  "Reload the ID locations in Doom's documentation and open docs buffers."
  (interactive (list 'interactive))
  (with-temp-buffer
    (let ((org-id-locations-file doom-docs--id-location-file)
          (org-id-track-globally t)
          org-agenda-files
          org-id-extra-files
          org-id-files
          org-id-locations
          org-id-extra-files
          (org-inhibit-startup t)
          org-mode-hook)
      (if (or force (not (file-exists-p org-id-locations-file)))
          (org-id-update-id-locations
           (doom-files-in (cons doom-docs-dir doom-module-load-path)
                          :match "/[^.].+\\.org$"))
        (org-id-locations-load))
      (setq doom-docs--id-files org-id-files
            doom-docs--id-locations org-id-locations)))
  (dolist (buf (doom-buffers-in-mode 'doom-docs-org-mode))
    (with-current-buffer buf
      (setq-local org-id-files doom-docs--id-files
                  org-id-locations doom-docs--id-locations))))


;;
;;; * Doom-specific org links

(defun doom-docs--relative-path (path root)
  (if (and buffer-file-name (file-in-directory-p buffer-file-name root))
      (file-relative-name path)
    path))

(defun doom-docs--read-link-path (key dir &optional fn)
  (let ((file (funcall (or fn #'read-file-name) (format "%s: " (capitalize key)) dir)))
    (format "%s:%s" key (file-relative-name file dir))))

;;;###autoload
(defun doom-docs-define-link (key dir-var &rest plist)
  "Define a link with some basic completion & fontification.

KEY is the name of the link type. DIR-VAR is the directory variable to resolve
links relative to. PLIST is passed to `org-link-set-parameters' verbatim.

Links defined with this will be rendered in the `error' face if the file doesn't
exist, and `org-link' otherwise."
  (declare (indent 2))
  (let ((requires (plist-get plist :requires))
        (dir-fn (if (functionp dir-var)
                    dir-var
                  (lambda () (symbol-value dir-var)))))
    (apply #'org-link-set-parameters
           key
           :complete (lambda ()
                       (if requires (mapc #'require (ensure-list requires)))
                       (doom-docs--relative-path (doom-docs--read-link-path key (funcall dir-fn))
                                                 (funcall dir-fn)))
           :follow   (lambda (link)
                       (org-link-open-as-file (expand-file-name link (funcall dir-fn)) nil))
           :face     (lambda (link)
                       (let* ((path (expand-file-name link (funcall dir-fn)))
                              (option-index (string-match-p "::\\(.*\\)\\'" path))
                              (file-name (substring path 0 option-index)))
                         (if (file-exists-p file-name)
                             'org-link
                           'error)))
           (plist-put plist :requires nil))))

(defun doom-docs-link-read-desc-at-point (&optional default context)
  "TODO"
  (if (and (stringp default) (not (string-empty-p default)))
      (string-trim default)
    (if-let* ((context (or context (org-element-context)))
              (context (org-element-lineage context '(link) t))
              (beg (org-element-property :contents-begin context))
              (end (org-element-property :contents-end context)))
        (unless (= beg end)
          (replace-regexp-in-string
           "[ \n]+" " " (string-trim (buffer-substring-no-properties beg end)))))))

(let (cache)
  (defun doom-docs--help-echo-fn (_window object pos)
    (if (equal (car cache) (cons object pos))
        (cdr cache)
      (let ((link (with-current-buffer object
                    (save-excursion (goto-char pos) (org-element-context)))))
        (cdr (setq cache
                   (cons (cons object (org-element-property :begin link))
                         (doom-docs--help-string link))))))))

(defun doom-docs--help-string (link)
  (pcase (org-element-property :type link)
    ("kbd"
     (concat
      "The key sequence: "
      (propertize (doom-docs--describe-kbd (org-element-property :path link))
                  'face 'help-key-binding)))
    ("cmd"
     (concat
      "The command "
      (propertize (org-element-property :path link) 'face 'font-lock-function-name-face)
      " can be invoked with the key sequence "
      (propertize (doom-docs--command-keys (org-element-property :path link))
                  'face 'help-key-binding)))
    ("doom-package"
     (concat
      (propertize "Emacs package " 'face 'bold)
      (propertize (org-element-property :path link) 'face 'font-lock-keyword-face)
      ", currently "
      (cond
       ((featurep (intern-soft (org-element-property :path link)))
        (propertize "installed and loaded" 'face 'success))
       ((locate-library (org-element-property :path link))
        (propertize "installed but not loaded" 'face 'warning))
       (t (propertize "not installed" 'face 'error )))))
    ("doom-module"
     (concat
      (propertize "Doom module " 'face 'bold)
      (propertize (org-element-property :path link) 'face 'font-lock-keyword-face)
      ", currently "
      (cl-destructuring-bind (&key category module flag)
          (doom-docs--read-module-spec (org-element-property :path link))
        (cond
         ((doom-module-active-p category module)
          (propertize "enabled" 'face 'success))
         ((and category (doom-module-locate-path (cons category module)))
          (propertize "disabled" 'face 'error))
         (t (propertize "unknown" 'face '(bold error)))))))
    ("doom-executable"
     (concat
      (propertize "System executable " 'face 'bold)
      (propertize (org-element-property :path link) 'face 'font-lock-keyword-face)
      ", "
      (if (executable-find (org-element-property :path link))
          (propertize "found" 'face 'success)
        (propertize "not found" 'face 'error))
      " on PATH"))))

;;;###autoload
(defun doom-docs-link-read-kbd-at-point (&optional default context)
  "TODO"
  (let ((keystr (doom-docs-link-read-desc-at-point default context)))
    (dolist (key `(("<leader>" . ,doom-leader-key)
                   ("<localleader>" . ,doom-localleader-key)
                   ("<prefix>" . ,(if (bound-and-true-p evil-mode)
                                      (concat doom-leader-key " u")
                                    "C-u"))
                   ("<help>" . ,(if (bound-and-true-p evil-mode)
                                    (concat doom-leader-key " h")
                                  "C-h"))
                   ("\\<M-" . "alt-")
                   ("\\<S-" . "shift-")
                   ("\\<s-" . "super-")
                   ("\\<C-" . "ctrl-")))
      (setq keystr
            (replace-regexp-in-string (car key) (cdr key)
                                      keystr t t)))
    keystr))

(defun doom-docs--read-module-spec (module-spec-str)
  (if (string-match-p "^[-+]" (string-trim-left module-spec-str))
      (let ((title (cadar (org-collect-keywords '("TITLE")))))
        (if (and title (string-match-p "\\`:[a-z]+\\s-+[A-Za-z0-9]+\\'" title))
            (doom-docs--read-module-spec (concat title " " module-spec-str))
          (list :category nil :module nil :flag (intern module-spec-str))))
    (cl-destructuring-bind (category &optional module flag)
        (mapcar #'intern (split-string
                          (if (string-prefix-p ":" module-spec-str)
                              module-spec-str
                            (concat ":" module-spec-str))
                          "[ \n][-+]" nil))
      (list :category category
            :module module
            :flag flag))))

;;;###autoload
(defun doom-docs--var-link-activate-fn (start end var _bracketed-p)
  (when buffer-read-only
    (add-text-properties
     start end
     (list
      'display
      (concat (nerd-icons-mdicon "nf-md-toggle_switch") ; "󰔡"
              " " (propertize var
                              'face
                              (if (boundp (intern var))
                                  'font-lock-variable-name-face
                                'shadow)))))))

(defun doom-docs--link-activate-fn (start end fn _bracketed-p)
  (when buffer-read-only
    (add-text-properties
     start end
     (list 'display
           (doom-docs--icon
            "nf-md-function"  ; "󰊕"
            (propertize fn
                        'face
                        (if (fboundp (intern fn))
                            'font-lock-function-name-face
                          'shadow)))))))

(defun doom-docs--face-link-activate-fn (start end face _bracketed-p)
  (when buffer-read-only
    (add-text-properties
     start end
     (list 'display
           (doom-docs--icon "nf-md-format_text"  ; "󰊄"
                            (propertize face
                                        'face
                                        (if (facep (intern face))
                                            (intern face)
                                          'shadow)))))))

(defun doom-docs--command-keys (command)
  "Convert command reference TEXT to key binding representation."
  (let* ((cmd-prefix (mapcar #'reverse
                             (split-string (reverse command) " ")))
         (cmd (intern-soft (car cmd-prefix)))
         (prefix (and (cdr cmd-prefix)
                      (string-join (reverse (cdr cmd-prefix)) " ")))
         (key-binding (where-is-internal cmd nil t))
         (key-text (if key-binding
                       (key-description key-binding)
                     (format "M-x %s" cmd))))
    (concat prefix (and prefix " ") key-text)))

(defun doom-docs--command-link-activate-fn (start end command _bracketed-p)
  (when buffer-read-only
    (add-text-properties
     start end (list 'display (doom-docs--command-keys command)))))

(defun doom-docs--module-link-follow-fn (module-path _arg)
  (cl-destructuring-bind (&key category module flag)
      (doom-docs--read-module-spec module-path)
    (when category
      (if-let* ((path (doom-module-locate-path (cons category module)))
                (path (or (car (doom-glob path "README.org"))
                          path)))
          (find-file path)
        (user-error "Can't find Doom module '%s'" module-path)))
    (when flag
      (goto-char (point-min))
      (when (and (re-search-forward "^\\*+ \\(?:TODO \\)?Module flags")
                 (re-search-forward (format "^\\s-*- [-+]%s ::[ \n]"
                                            (substring (symbol-name flag) 1))
                                    (save-excursion (org-get-next-sibling)
                                                    (point))))
        (org-show-entry)
        (recenter)))))

(defun doom-docs--module-link-activate-fn (start end module-path bracketed-p)
  (if (not buffer-read-only)
      (unless (string-blank-p module-path)
        (add-text-properties start end `(display ,module-path)))
    (cl-destructuring-bind (&key category module flag)
        (doom-docs--read-module-spec module-path)
      (let ((overall-face
             (if (and category (doom-module-locate-path (cons category module)))
                 '((:underline nil) org-link org-block bold)
               '(shadow org-block bold)))
            (icon-face
             (cond
              ((doom-module-active-p category module flag) 'success)
              ((and category (doom-module-locate-path (cons category module))) 'warning)
              (t 'error))))
        (add-text-properties
         start end
         (list 'face overall-face
               'display
               (doom-docs--icon "nf-oct-stack"  ; ""
                                module-path
                                :face icon-face)))))))

(defun doom-docs--package-link-activate-fn (start end package _bracketed-p)
  (if (not buffer-read-only)
      (unless (string-blank-p package)
        (add-text-properties start end `(display ,package)))
    (let ((overall-face
           (if (locate-library package)
               '((:underline nil :weight regular) org-link org-block italic)
             '(shadow org-block italic)))
          (icon-face
           (cond
            ((featurep (intern package)) 'success)
            ((locate-library package) 'warning)
            (t 'error))))
      (add-text-properties
       start end
       (list 'face overall-face
             'display
             (doom-docs--icon "nf-oct-package"  ; ""
                              package :face icon-face))))))

(defun doom-docs--package-link-follow-fn (pkg _prefixarg)
  "TODO"
  (doom/describe-package (intern-soft pkg)))


;;
;;; * Org config

(with-eval-after-load 'org
  (dolist (abr `(("emacsdir"
                  . ,(lambda (_) (abbreviate-file-name (doom-emacs-dir "%s"))))
                 ("doomdir"
                  . ,(lambda (_) (abbreviate-file-name (doom-user-dir "%s"))))))
    (add-to-list 'org-link-abbrev-alist abr))

  (doom-docs-define-link "doom" 'doom-emacs-dir)
  (doom-docs-define-link "doom-docs" 'doom-docs-dir)

  (letf! (defun -cmd (fn)
           (lambda (path _prefixarg)
             (funcall (or (command-remapping fn) fn)
                      (or (intern-soft path)
                          (user-error "Can't find documentation for %S" path)))))
    (org-link-set-parameters
     "kbd"
     :follow (lambda (ev)
               (interactive "e")
               (minibuffer-message "%s" (doom-docs--help-echo-fn
                                         nil (current-buffer) (posn-point (event-start ev)))))
     :help-echo #'doom-docs--help-echo-fn
     :face 'help-key-binding)
    (org-link-set-parameters
     "var"
     :follow (-cmd #'describe-variable)
     :activate-func #'doom-docs--var-link-activate-fn
     :face '(font-lock-variable-name-face underline))
    (org-link-set-parameters
     "fn"
     :follow (-cmd #'describe-function)
     :activate-func #'doom-docs--link-activate-fn
     :face '(font-lock-function-name-face underline))
    (org-link-set-parameters
     "face"
     :follow (-cmd #'describe-face)
     :activate-func #'doom-docs--face-link-activate-fn
     :face '(font-lock-type-face underline))
    (org-link-set-parameters
     "cmd"
     :follow (-cmd #'describe-command)
     :activate-func #'doom-docs--command-link-activate-fn
     :face 'help-key-binding
     :help-echo #'doom-docs--help-echo-fn)

    (org-link-set-parameters
     "doom-package"
     :follow #'doom-docs--package-link-follow-fn
     :activate-func #'doom-docs--package-link-activate-fn
     :help-echo #'doom-docs--help-echo-fn)
    (org-link-set-parameters
     "doom-module"
     :follow #'doom-docs--module-link-follow-fn
     :activate-func #'doom-docs--module-link-activate-fn
     :help-echo #'doom-docs--help-echo-fn)
    (org-link-set-parameters
     "doom-ref"
     :follow (lambda (link)
               (let ((link (doom-docs-link-read-desc-at-point link))
                     (url "https://github.com")
                     (doom-repo "doomemacs/core"))
                 (save-match-data
                   (browse-url
                    (cond ((string-match "^\\([^/]+\\(?:/[^/]+\\)?\\)?#\\([0-9]+\\(?:#.*\\)?\\)" link)
                           (format "%s/%s/issues/%s" url
                                   (or (match-string 1 link)
                                       doom-repo)
                                   (match-string 2 link)))
                          ((string-match "^\\([^/]+\\(?:/[^/]+\\)?@\\)?\\([a-z0-9]\\{7,\\}\\(?:#.*\\)?\\)" link)
                           (format "%s/%s/commit/%s" url
                                   (or (match-string 1 link)
                                       doom-repo)
                                   (match-string 2 link)))
                          ((user-error "Invalid doom-ref link: %S" link)))))))
     :face (lambda (link)
             (let ((link (doom-docs-link-read-desc-at-point link)))
               (if (or (string-match "^\\([^/]+\\(?:/[^/]+\\)?\\)?#\\([0-9]+\\(?:#.*\\)?\\)" link)
                       (string-match "^\\([^/]+\\(?:/[^/]+\\)?@\\)?\\([a-z0-9]\\{7,\\}\\(?:#.*\\)?\\)" link))
                   'org-link
                 'error))))
    (org-link-set-parameters
     "doom-user"
     :follow (lambda (link)
               (browse-url
                (format "https://github.com/%s"
                        (string-remove-prefix
                         "@" (doom-docs-link-read-desc-at-point link)))))
     :face (lambda (_)
             ;; Avoid confusion with function `org-priority'
             'org-priority))
    (org-link-set-parameters
     "doom-changelog"
     :follow (lambda (link)
               (find-file (doom-path doom-docs-dir "changelog.org"))
               (org-match-sparse-tree nil link)))))

(provide 'doom-docs)
;;; doom-docs.el ends here
