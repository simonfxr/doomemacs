;;; ui/vc-gutter/config.el -*- lexical-binding: t; -*-

;;
;;; Default styles

;; STYLE: Redefine fringe bitmaps to be sleeker by making them solid bars (with
;;   no border) that only take up half the horizontal space in the fringe. This
;;   approach lets us avoid robbing fringe space from other packages/modes that
;;   may need benefit from it (like magit, flycheck, or flyspell).
(when (modulep! +pretty)
  (if (fboundp 'fringe-mode) (fringe-mode '8))
  (setq-default fringes-outside-margins t)

  (defadvice! +vc-gutter-define-thin-bitmaps-a (&rest _)
    :after #'diff-hl-define-bitmaps
    (let* ((scale (if (and (boundp 'text-scale-mode-amount)
                           (numberp text-scale-mode-amount))
                      (expt text-scale-mode-step text-scale-mode-amount)
                    1))
           (spacing (or (and (display-graphic-p) (default-value 'line-spacing)) 0))
           (h (+ (ceiling (* (frame-char-height) scale))
                 (if (floatp spacing)
                     (truncate (* (frame-char-height) spacing))
                   spacing)))
           (w (min (frame-parameter nil (intern (format "%s-fringe" diff-hl-side)))
                   16))
           (_ (if (zerop w) (setq w 16))))
      (define-fringe-bitmap 'diff-hl-bmp-middle
        (make-vector
         h (string-to-number (let ((half-w (1- (/ w 2))))
                               (concat (make-string half-w ?1)
                                       (make-string (- w half-w) ?0)))
                             2))
        nil nil 'center)))
  (defun +vc-gutter-type-at-pos-fn (type _pos)
    (if (eq type 'delete)
        'diff-hl-bmp-delete
      'diff-hl-bmp-middle))
  (setq diff-hl-fringe-bmp-function #'+vc-gutter-type-at-pos-fn)
  (setq diff-hl-draw-borders nil)

  (add-hook! 'diff-hl-mode-hook
    (defun +vc-gutter-make-diff-hl-faces-transparent-h ()
      (mapc (doom-rpartial #'set-face-background nil)
            '(diff-hl-insert
              diff-hl-delete
              diff-hl-change))))

  ;; FIX: To minimize overlap between flycheck indicators and diff-hl indicators
  ;;   in the left fringe.
  (after! flycheck
    ;; Let diff-hl have left fringe, flycheck can have right fringe
    (setq flycheck-indication-mode 'right-fringe)
    ;; A non-descript, left-pointing arrow
    (define-fringe-bitmap 'flycheck-fringe-bitmap-double-arrow
      [16 48 112 240 112 48 16] nil nil 'center)))


;;
;;; diff-hl

(use-package! diff-hl
  :hook (find-file    . diff-hl-mode)
  :hook (vc-dir-mode  . diff-hl-dir-mode)
  :hook (dired-mode   . diff-hl-dired-mode)
  :hook (diff-hl-mode . diff-hl-flydiff-mode)
  :commands diff-hl-stage-current-hunk diff-hl-revert-hunk diff-hl-next-hunk diff-hl-previous-hunk
  :config
  (set-popup-rule! "^\\*diff-hl" :select nil :size '+popup-shrink-to-fit)

  ;; PERF: A slightly faster algorithm for diffing.
  (setq vc-git-diff-switches '("--histogram"))
  ;; PERF: Slightly more conservative delay before updating the diff
  (setq diff-hl-flydiff-delay 0.5)  ; default: 0.3
  ;; PERF: don't block Emacs when updating vc gutter
  (setq diff-hl-update-async t)

  ;; UX: get realtime feedback in diffs after staging/unstaging hunks.
  (setq diff-hl-show-staged-changes nil)

  ;; UX: Update diffs when it makes sense too, without being too slow
  (when (modulep! :editor evil)
    (map! :after diff-hl-show-hunk
          :map diff-hl-show-hunk-map
          :n "p" #'diff-hl-show-hunk-previous
          :n "n" #'diff-hl-show-hunk-next
          :n "c" #'diff-hl-show-hunk-copy-original-text
          :n "r" #'diff-hl-show-hunk-revert-hunk
          :n "[" #'diff-hl-show-hunk-previous
          :n "]" #'diff-hl-show-hunk-next
          :n "{" #'diff-hl-show-hunk-previous
          :n "}" #'diff-hl-show-hunk-next
          :n "S" #'diff-hl-show-hunk-stage-hunk))
  ;; UX: Refresh gutter on ESC or refocusing the Emacs frame.
  (add-hook! '(doom-escape-hook doom-switch-window-hook) :append
    (defun +vc-gutter-update-h (&rest _)
      "Return nil to prevent shadowing other `doom-escape-hook' hooks."
      (ignore (or inhibit-redisplay
                  (and (or (bound-and-true-p diff-hl-mode)
                           (bound-and-true-p diff-hl-dir-mode))
                       (diff-hl-update-once))))))
  ;; UX: Update diff-hl when magit alters git state.
  (when (modulep! :tools magit)
    (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

  ;; FIX: The revert popup consumes 50% of the frame, whether or not you're
  ;;   reverting 2 lines or 20. This resizes the popup to match its contents.
  (defadvice! +vc-gutter--shrink-popup-a (fn &rest args)
    :around #'diff-hl-revert-hunk-1
    (letf! ((refine-mode diff-auto-refine-mode)
            (diff-auto-refine-mode t)
            (defun diff-refine-hunk ()
              (when refine-mode
                (funcall diff-refine-hunk))
              (shrink-window-if-larger-than-buffer)))
      (apply fn args)))

  ;; UX: Don't delete the current hunk's indicators while we're editing
  (when (modulep! :editor evil)
    (add-hook! 'diff-hl-flydiff-mode-hook
      (defun +vc-gutter-init-flydiff-mode-h ()
        (if diff-hl-flydiff-mode
            (add-hook 'evil-insert-state-exit-hook #'diff-hl-flydiff-update)
          (remove-hook 'evil-insert-state-exit-hook #'diff-hl-flydiff-update)))))

  ;; FIX: Reverting a hunk causes the cursor to be moved to an unexpected place,
  ;;   often far from the target hunk.
  (defadvice! +vc-gutter--save-excursion-a (fn &rest args)
    "Suppresses unexpected cursor movement by `diff-hl-revert-hunk'."
    :around #'diff-hl-revert-hunk
    (let ((pt (point)))
      (prog1 (apply fn args)
        (goto-char pt)))))
