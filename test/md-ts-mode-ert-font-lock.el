;;; md-ts-mode-ert-font-lock.el --- Tests for md-ts-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Daniel Nouri <daniel.nouri@gmail.com>

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Font lock tests for md-ts-mode.
;;
;; This file intentionally tracks the upstream markdown-ts-mode test file
;; as closely as possible.  The deliberate differences are the md-ts-
;; names, the Emacs-29-safe ert-font-lock stubs, and the explicit
;; resource path helper used by this repository's test harness.

;;; Code:

(require 'ert)
(require 'treesit)

(unless (require 'ert-font-lock nil t)
  ;; Provide stubs so the file loads on Emacs 29 without error.
  ;; All tests will be skipped via skip-unless.
  (defun ert-font-lock-test-file (_file _mode))
  (defun ert-font-lock-test-string (_str _mode)))

(require 'md-ts-mode)

(defvar md-ts-ert-fl--test-dir
  (file-name-directory (or load-file-name buffer-file-name
                           (error "Cannot determine test directory")))
  "Directory containing this test file, captured at load time.")

(defun md-ts-ert-fl--resource-file (name)
  "Return the absolute path to resource file NAME."
  (expand-file-name (concat "md-ts-mode-resources/" name)
                    md-ts-ert-fl--test-dir))

(ert-deftest md-ts-ert-fl-test-font-lock ()
  "Test Markdown font lock against the resource file."
  (skip-unless (and (require 'ert-font-lock nil t)
                    (treesit-ready-p 'markdown t)))
  ;; Level 4 enables all features, including paragraph-inline.
  (let ((treesit-font-lock-level 4))
    (ert-font-lock-test-file
     (md-ts-ert-fl--resource-file "font-lock.md")
     'md-ts-mode)))

(ert-deftest md-ts-ert-fl-test-setext-h1-underline ()
  "Setext H1 underline (===) gets delimiter face."
  (skip-unless (and (require 'ert-font-lock nil t)
                    (treesit-ready-p 'markdown t)))
  (ert-font-lock-test-string
   "Heading
=======
<!-- <- md-ts-delimiter -->
"
   'md-ts-mode))

(ert-deftest md-ts-ert-fl-test-setext-h2-underline ()
  "Setext H2 underline (---) gets delimiter face."
  (skip-unless (and (require 'ert-font-lock nil t)
                    (treesit-ready-p 'markdown t)))
  (ert-font-lock-test-string
   "Heading
-------
<!-- <- md-ts-delimiter -->
"
   'md-ts-mode))

(ert-deftest md-ts-ert-fl-test-setext-h1-text ()
  "Setext H1 text gets heading-1 face."
  (skip-unless (treesit-ready-p 'markdown t))
  (with-temp-buffer
    (insert "Heading\n=======\n")
    (md-ts-mode)
    (font-lock-ensure)
    (should (eq (get-text-property 1 'face) 'md-ts-heading-1))))

(ert-deftest md-ts-ert-fl-test-setext-h2-text ()
  "Setext H2 text gets heading-2 face."
  (skip-unless (treesit-ready-p 'markdown t))
  (with-temp-buffer
    (insert "Heading\n-------\n")
    (md-ts-mode)
    (font-lock-ensure)
    (should (eq (get-text-property 1 'face) 'md-ts-heading-2))))

(ert-deftest md-ts-ert-fl-test-blockquote-continuation-in-list ()
  "Block continuation > in list within blockquote gets delimiter face."
  (skip-unless (and (require 'ert-font-lock nil t)
                    (treesit-ready-p 'markdown t)))
  (ert-font-lock-test-string
   "> - item
> - other
<!-- <- (md-ts-delimiter md-ts-block-quote) -->
"
   'md-ts-mode))

(provide 'md-ts-mode-ert-font-lock)
;;; md-ts-mode-ert-font-lock.el ends here
