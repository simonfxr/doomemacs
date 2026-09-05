;;; modules/doom/packages.el -*- lexical-binding: t; no-byte-compile: t; -*-

;; doom.el
(package! compat
  :recipe (:host github :repo "emacs-compat/compat")
  :pin "df03e91f1fc47503ca71e11dd507ed18ca8b5ab0")  ; 31.0.0.2
(unless (fboundp 'igc-info)
  (package! gcmh
    :pin "0089f9c3a6d4e9a310d0791cf6fa8f35642ecfd9"))

;; doom-packages.el
(package! straight
  :type 'core
  :recipe `(:host github
            :repo "radian-software/straight.el"
            :branch "develop"
            :local-repo "straight.el"
            :files ("straight*.el"))
  :pin "6051b6a6ea7a5b65e306b5787988ac4192de534d")

;; doom-ui.el
(package! nerd-icons :pin "17faac7977242b470732efd417d3bcc8eb5a830e")

;; doom-projects.el
(package! project :pin "ffb38d7798d86c7fa6623db0f64b461abb6572c2")

;; doom-keybinds.el
(package! which-key
  :recipe (:host github :repo "emacs-straight/which-key")
  :pin "78bf634e98ff989df3d86bceffe99b3278e32b12"
  :built-in 'prefer)
