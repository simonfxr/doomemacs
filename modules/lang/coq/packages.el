;; -*- no-byte-compile: t; -*-
;;; lang/coq/packages.el

(package! proof-general
  :pin "b30d65de803148bcd3408ac334b5eab01c98a0ae"
  ;; REVIEW: Remove when ProofGeneral/PG#771 is fixed. Also see #8169.
  :recipe (:build (:not autoloads)))
(package! company-coq :pin "5affe7a96a25df9101f9e44bac8a828d8292c2fa")
