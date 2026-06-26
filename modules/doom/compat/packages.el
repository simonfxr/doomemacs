;;; modules/doom/compat/packages.el -*- lexical-binding: t; no-byte-compile: t; -*-

;; TODO: Mirror these packages on doomelpa, to "immortalize" this module and
;;   make Doom core resistant to upstream breakage.

(when (modulep! +use-package)
  (package! auto-minor-mode :pin "17cfa1b54800fdef2975c0c0531dad34846a5065")
  (unless (fboundp 'lisp-data-mode)
    (package! bind-key
      ;; HACK: bind-key-pkg.el tries to set the mode to lisp-data-mode, which
      ;;   doesn't exist prior to Emacs 28.x, so bind-key will fail to build.
      :recipe (:files ("bind-key.el"))
      :pin "6ff8788e347ce31b5c3c4647c2e22e7ee2c5ab7c"))
  (package! use-package :pin "4b3484b550431f74ab9cda060a8dc983fe482131"))

(when (modulep! +better-jumper)
  (package! better-jumper :pin "b1bf7a3c8cb820d942a0305e0e6412ef369f819c"))

(when (modulep! +keybinds)
  (package! general :pin "a48768f85a655fe77b5f45c2880b420da1b1b9c3")
  (package! which-key :pin "38d4308d1143b61e4004b6e7a940686784e51500"))

(when (modulep! +projectile)
  (package! projectile :pin "6449fb0465587c757c1fbf1a64bb4ba420a78bfa"))

(when (modulep! +smartparens)
  (package! smartparens :pin "82d2cf084a19b0c2c3812e0550721f8a61996056"))
