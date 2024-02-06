;; -*- no-byte-compile: t; -*-
;;; lang/emacs-lisp/packages.el

(package! elisp-mode :built-in t)

;; Fontification plugins
(package! highlight-quoted :pin "24103478158cd19fbcfb4339a3f1fa1f054f1469")

;; Tools
(package! macrostep :pin "0b04a89f698c335c9ea492553470a8d45c113edd")
(package! overseer :pin "7fdcf1a6fba6b1569a09c1666b4e51bcde266ed9")
(package! elisp-def :pin "1ad4baccbf3d0d13e7607d332ae6bc60a5dd7360")
(package! elisp-demos :pin "1a108d1c5011f9ced58be2ca98bea1fbd4130a2f")
(when (and (modulep! :checkers syntax)
           (not (modulep! :checkers syntax +flymake)))
  (package! flycheck-package :pin "75efa098cf17dc14c363e2ca9b68afdac7766b5b")
  (package! flycheck-cask :pin "0eeec5197e9d31bfcfc39380b262d65259a87d91"))

;; Libraries
(package! buttercup :pin "24d43b2ce262faf59e5ff9f72466efb293aa6154")
