;; -*- no-byte-compile: t; -*-
;;; lisp/packages.el

;; doom.el
(package! auto-minor-mode
  :pin "17cfa1b54800fdef2975c0c0531dad34846a5065")
(package! compat
  :recipe (:host github :repo "emacs-compat/compat")
  :pin "b5b48183689b536f72b1214106afeabc465da9d4")  ; 31.0.0.1
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
  :pin "e40a5b7f8b0c1bb2cde0e7e477b5f81303e34b95")

;; doom-ui.el
(package! nerd-icons :pin "d33d12f5dcb6bf2fb23c3f75df5de85beb4afd95")

;; doom-editor.el
(package! better-jumper :pin "b1bf7a3c8cb820d942a0305e0e6412ef369f819c")
(package! smartparens :pin "82d2cf084a19b0c2c3812e0550721f8a61996056")

;; doom-projects.el
(package! projectile :pin "6449fb0465587c757c1fbf1a64bb4ba420a78bfa")
(package! project :pin "f4ec26c30a08663e93449317a5f765032ab84f28")

;; doom-keybinds.el
(package! general :pin "a48768f85a655fe77b5f45c2880b420da1b1b9c3")
(package! which-key :pin "38d4308d1143b61e4004b6e7a940686784e51500")
