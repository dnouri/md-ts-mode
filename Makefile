EMACS ?= emacs
BATCH = $(EMACS) --batch -Q -L .

SELECTOR ?=
VERBOSE ?=

.PHONY: test compile lint lint-checkdoc lint-package check check-parens clean help install-hooks

help:
	@echo "Targets:"
	@echo "  make test           Run ERT tests (SELECTOR=pattern, VERBOSE=1)"
	@echo "  make compile        Byte-compile with warnings-as-errors"
	@echo "  make lint           Checkdoc + package-lint"
	@echo "  make lint-checkdoc  Docstring warnings only"
	@echo "  make lint-package   MELPA package conventions only"
	@echo "  make check-parens   Verify balanced parentheses"
	@echo "  make check          compile + lint + test (pre-commit)"
	@echo "  make install-hooks  Set up git pre-commit hook"
	@echo "  make clean          Remove .elc files"

test: compile
	@echo "=== Tests ==="
	@OUTPUT=$$(mktemp); \
	$(BATCH) \
		--eval '(add-to-list (quote treesit-extra-load-path) (expand-file-name "~/.emacs.d/tree-sitter"))' \
		-L test \
		-l md-ts-mode-test \
		$(if $(SELECTOR),--eval '(ert-run-tests-batch-and-exit "$(SELECTOR)")',-f ert-run-tests-batch-and-exit) \
		>$$OUTPUT 2>&1; \
	STATUS=$$?; \
	if [ "$(VERBOSE)" = "1" ] || [ $$STATUS -ne 0 ]; then \
		cat $$OUTPUT; \
	else \
		grep -v "^   passed\|^Running [0-9]\|^$$" $$OUTPUT; \
	fi; \
	rm -f $$OUTPUT; \
	exit $$STATUS

compile:
	@rm -f *.elc
	@echo "=== Byte-compile ==="
	@$(BATCH) \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile md-ts-mode.el

lint: lint-checkdoc lint-package

lint-checkdoc:
	@echo "=== Checkdoc ==="
	@OUTPUT=$$($(BATCH) \
		--eval "(require 'checkdoc)" \
		--eval "(setq sentence-end-double-space nil)" \
		--eval "(checkdoc-file \"md-ts-mode.el\")" 2>&1); \
	WARNINGS=$$(echo "$$OUTPUT" | grep -A1 "^Warning" | grep -v "^Warning\|^--$$"); \
	if [ -n "$$WARNINGS" ]; then echo "$$WARNINGS"; exit 1; else echo "OK"; fi

lint-package:
	@echo "=== Package-lint ==="
	@$(BATCH) \
		--eval "(require 'package)" \
		--eval "(push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives)" \
		--eval "(package-initialize)" \
		--eval "(unless (package-installed-p 'package-lint) \
		          (package-refresh-contents) \
		          (package-install 'package-lint))" \
		--eval "(require 'package-lint)" \
		--eval "(setq package-lint-main-file \"md-ts-mode.el\")" \
		-f package-lint-batch-and-exit md-ts-mode.el

check-parens:
	@echo "=== Check Parens ==="
	@OUTPUT=$$($(BATCH) \
		--eval '(condition-case err \
		          (with-current-buffer (find-file-noselect "md-ts-mode.el") \
		            (check-parens) \
		            (message "md-ts-mode.el OK")) \
		          (user-error \
		           (message "FAIL: %s" (error-message-string err)) \
		           (kill-emacs 1)))' 2>&1); \
	echo "$$OUTPUT" | grep -E "OK$$|FAIL:"; \
	echo "$$OUTPUT" | grep -q "FAIL:" && exit 1 || true

check: compile lint test

install-hooks:
	@git config core.hooksPath hooks
	@echo "Git hooks installed (using hooks/)"

clean:
	@rm -f *.elc test/*.elc
