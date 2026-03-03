;;; generate-snapshot.el --- Generate face snapshot for fixture  -*- lexical-binding: t; -*-
;;
;; Usage:
;;   emacs --batch -Q -L . -L test \
;;     --eval '(add-to-list (quote treesit-extra-load-path) ...)' \
;;     -l md-ts-mode-test \
;;     -l scripts/generate-snapshot.el
;;
;; Writes test/fixture-faces.eld with the current fontification output.

(require 'md-ts-mode-test)

(let* ((spans (md-ts-test--fontify-fixture))
       (snapshot-path (md-ts-test--snapshot-path))
       (print-escape-newlines t))
  (with-temp-file snapshot-path
    (insert ";; Face snapshot for test/fixture.md\n")
    (insert ";; Format: (TEXT FACE) — concatenating all TEXT values reconstructs the file\n")
    (insert ";; Regenerate with: make snapshot\n")
    (insert "(\n")
    (dolist (span spans)
      (insert (format " (%S %S)\n" (car span) (cadr span))))
    (insert ")\n"))
  (message "Wrote %d spans to %s" (length spans) snapshot-path))
