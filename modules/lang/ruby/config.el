;;; lang/ruby/config.el -*- lexical-binding: t; -*-

;; DEPRECATED: Remove when projectile is replaced with project.el
(after! projectile
  (add-to-list 'projectile-project-root-files "Gemfile"))


;;
;;; Packages

(use-package! ruby-mode  ; built-in
  ;; Other extensions are already registered in `auto-mode-alist' by `ruby-mode'
  :mode "\\.\\(?:a?rb\\|aslsx\\)\\'"
  :mode "/\\(?:Brew\\|Fast\\)file\\'"
  :interpreter "j?ruby\\(?:[0-9.]+\\)"
  :config
  (setq ruby-insert-encoding-magic-comment nil)

  (set-electric! 'ruby-mode :words '("else" "end" "elsif"))
  (set-repl-handler! 'ruby-mode #'inf-ruby)

  (when (modulep! +lsp)
    (add-hook 'ruby-mode-local-vars-hook #'lsp! 'append))

  (when (modulep! +tree-sitter)
    (add-hook 'ruby-mode-local-vars-hook #'tree-sitter! 'append))

  (after! inf-ruby
    (add-hook 'inf-ruby-mode-hook #'doom-mark-buffer-as-real-h)
    ;; switch to inf-ruby from compile if we detect a breakpoint has been hit
    (add-hook 'compilation-filter-hook #'inf-ruby-auto-enter))

  ;; so class and module pairs work
  (setq-hook! 'ruby-mode-hook sp-max-pair-length 6)

  (map! :localleader
        :map ruby-mode-map
        "[" #'ruby-toggle-block
        "{" #'ruby-toggle-block))


(use-package! yard-mode
  :hook ruby-mode)


(use-package! ruby-json-to-hash
  :defer t
  :init
  (map! :after ruby-mode
        :map ruby-mode-map
        :localleader
        "J" #'ruby-json-to-hash-parse-json
        "j" #'ruby-json-to-hash-toggle-let))


;;
;;; Package & Ruby version management

(use-package! rake
  :defer t
  :init
  (setq rake-cache-file (concat doom-cache-dir "rake.cache"))
  (setq rake-completion-system 'default)
  (map! :after ruby-mode
        :localleader
        :map ruby-mode-map
        :prefix ("k" . "rake")
        "k" #'rake
        "r" #'rake-rerun
        "R" #'rake-regenerate-cache
        "f" #'rake-find-task))

(use-package! bundler
  :defer t
  :init
  (map! :after ruby-mode
        :localleader
        :map ruby-mode-map
        :prefix ("b" . "bundle")
        "c" #'bundle-check
        "C" #'bundle-console
        "i" #'bundle-install
        "u" #'bundle-update
        "e" #'bundle-exec
        "o" #'bundle-open))

(use-package! chruby
  :when (modulep! +chruby)
  :hook (ruby-mode . chruby-use-corresponding)
  :config
  (setq rspec-use-rvm nil
        rspec-use-chruby t))

(after! rbenv
  (setq rspec-use-rvm nil)
  (add-to-list 'exec-path (expand-file-name "shims" rbenv-installation-dir)))


;;
;;; Testing frameworks

(use-package! rspec-mode
  :mode ("/\\.rspec\\'" . text-mode)
  :init
  (setq rspec-use-spring-when-possible nil)
  (when (modulep! :editor evil)
    (add-hook 'rspec-mode-hook #'evil-normalize-keymaps))
  :config
  (set-popup-rule! "^\\*\\(rspec-\\)?compilation" :size 0.3 :ttl nil :select t)
  (setq rspec-use-rvm (executable-find "rvm"))
  (map! :localleader
        :prefix "t"
        :map (rspec-verifiable-mode-map rspec-dired-mode-map rspec-mode-map)
        "a" #'rspec-verify-all
        "r" #'rspec-rerun
        :map (rspec-verifiable-mode-map rspec-mode-map)
        "v" #'rspec-verify
        "c" #'rspec-verify-continue
        "l" #'rspec-run-last-failed
        "T" #'rspec-toggle-spec-and-target
        "t" #'rspec-toggle-spec-and-target-find-example
        :map rspec-verifiable-mode-map
        "f" #'rspec-verify-method
        "m" #'rspec-verify-matching
        :map rspec-mode-map
        "s" #'rspec-verify-single
        "e" #'rspec-toggle-example-pendingness
        :map rspec-dired-mode-map
        "v" #'rspec-dired-verify
        "s" #'rspec-dired-verify-single))


(use-package! minitest
  :defer t
  :config
  (when (modulep! :editor evil)
    (add-hook 'minitest-mode-hook #'evil-normalize-keymaps))
  (map! :localleader
        :map minitest-mode-map
        :prefix "t"
        "r" #'minitest-rerun
        "a" #'minitest-verify-all
        "s" #'minitest-verify-single
        "v" #'minitest-verify))


;;
;;; Rails integration

(use-package! projectile-rails
  :when (modulep! +rails)
  :hook ((ruby-mode inf-ruby-mode projectile-rails-server-mode) . projectile-rails-mode)
  :hook (projectile-rails-server-mode . doom-mark-buffer-as-real-h)
  :hook (projectile-rails-mode . auto-insert-mode)
  :init
  (setq auto-insert-query nil)
  (setq inf-ruby-console-environment "development")
  (when (modulep! :lang web)
    (add-hook 'web-mode-hook #'projectile-rails-mode))
  :config
  (set-popup-rule! "^\\*\\(projectile-\\)?rails" :ttl nil)
  (when (modulep! :editor evil)
    (add-hook 'projectile-rails-mode-hook #'evil-normalize-keymaps))
  (map! :localleader
        :map projectile-rails-mode-map
        "r" #'projectile-rails-command-map))

(use-package! rails-routes
  :when (modulep! +rails)
  :defer t
  :init
  (map! :after ruby-mode
        :map ruby-mode-map
        "C-c o" #'rails-routes-insert
        "C-c C-o" #'rails-routes-insert-no-cache
        "C-c ! o" #'rails-routes-jump)
  (map! :after web-mode
        :map web-mode-map
        "C-c o" #'rails-routes-insert
        "C-c C-o" #'rails-routes-insert-no-cache
        "C-c ! o" #'rails-routes-jump))

(use-package! rails-i18n
  :when (modulep! +rails)
  :defer t
  :init
  (map! :after ruby-mode
        :map ruby-mode-map
        "C-c i" #'rails-i18n-insert-with-cache)
  (map! :after web-mode
        :map web-mode-map
        "C-c i" #'rails-i18n-insert-with-cache))
