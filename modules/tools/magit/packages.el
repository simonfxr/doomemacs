;; -*- no-byte-compile: t; -*-
;;; tools/magit/packages.el

(when (package! magit :pin "6d325d90ba1374d48c4c7088f96864b678155f48")
  (package! compat :pin "2bedcb5ea91914e75d4905bc53e537b33f8f51e9")
  (when (modulep! +forge)
    (package! forge :pin "ce212f8f95838889c51d0327eb8c3979bec6665c")
    (package! code-review
      :recipe (:files ("graphql" "code-review*.el"))
      :pin "95b36ec8e7935f96b2f3c6c9086d49cf4a72cbff"))
  (package! magit-gitflow :pin "cc41b561ec6eea947fe9a176349fb4f771ed865b")
  (package! magit-todos :pin "c5030cc27c7c1a48db52b0134bf2648a59a43176"))
