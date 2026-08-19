;;; doom/cli/cli.el -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; The heart of Doom's test DSL and framework. Powered by either ERT or
;; Buttercup, this extends testing frameworks to allow for isolated execution
;; contexts on several levels, a more sophisticated CLI for tests, and
;; integration with Doom's profiles system so testing environments can be
;; generated on-the-fly.
;;
;;; Code:

(if (modulep! +commit-linter) (load! "+commit-linter"))
;; (if (modulep! +tests)         (load! "+tests"))
;; (if (modulep! +linters)       (load! "+linters"))

(provide '+cli)
;;; cli.el ends here
