;;; md-ts-mode-test.el --- Tests for md-ts-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026 Daniel Nouri <daniel.nouri@gmail.com>

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

;; ERT tests for md-ts-mode font-lock and compat shims.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'button)
(require 'md-ts-mode)

(declare-function md-ts--refresh-local-parsers "md-ts-mode" (&optional beg end))

(define-derived-mode md-ts-test-derived-mode md-ts-mode "MdTsTest"
  "Test mode derived from `md-ts-mode'.")

;;; Test helpers

(defun md-ts-test--fontify (text)
  "Insert TEXT, activate `md-ts-mode', fontify, return the buffer.
Caller must kill the buffer when done."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (with-current-buffer buf
      (insert text)
      (md-ts-mode)
      (font-lock-ensure))
    buf))

(defun md-ts-test--face-at (text search &optional nth)
  "In markdown TEXT, find the NTH occurrence of SEARCH and return its face.
NTH defaults to 1 (first occurrence).  Returns the face at the
start of the match."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (get-text-property (match-beginning 0) 'face))
      (kill-buffer buf))))

(defun md-ts-test--has-face (text search face &optional nth)
  "Non-nil if SEARCH in TEXT has FACE (or FACE in a list of faces).
NTH selects occurrence (default 1)."
  (let ((actual (md-ts-test--face-at text search nth)))
    (if (eq face 'link)
        (md-ts--link-face-value-p actual)
      (cond
       ((null actual) nil)
       ((listp actual) (memq face actual))
       (t (eq face actual))))))

(defun md-ts-test--invisible-at (text search &optional nth)
  "In markdown TEXT, return the `invisible' property at SEARCH position.
NTH selects occurrence (default 1)."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (get-text-property (match-beginning 0) 'invisible))
      (kill-buffer buf))))

(defun md-ts-test--props-at (text search props &optional nth)
  "In markdown TEXT, return PROPS at SEARCH as an alist.
NTH selects occurrence (default 1)."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (let ((pos (match-beginning 0)))
            (mapcar (lambda (prop)
                      (cons prop (get-text-property pos prop)))
                    props)))
      (kill-buffer buf))))

(defun md-ts-test--jit-lock-bounds (result)
  "Return the bounds cons from a `jit-lock-bounds' RESULT."
  (should (eq (car result) 'jit-lock-bounds))
  (cons (cadr result) (cddr result)))

(defun md-ts-test--property-outside-region (beg end props)
  "Return the first (POS . PROP) from PROPS outside BEG..END, or nil."
  (let ((pos (point-min))
        found)
    (while (and (< pos (point-max)) (not found))
      (unless (and (<= beg pos) (< pos end))
        (dolist (prop props)
          (when (and (not found) (get-text-property pos prop))
            (setq found (cons pos prop)))))
      (setq pos (1+ pos)))
    found))

(defun md-ts-test--button-at-search (text search &optional nth)
  "Non-nil if SEARCH in markdown TEXT is a text button.
NTH selects occurrence (default 1)."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (and (button-at (match-beginning 0)) t))
      (kill-buffer buf))))

(defun md-ts-test--push-button-at-search (text search &optional nth)
  "Activate the text button at SEARCH in markdown TEXT.
NTH selects occurrence (default 1)."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (push-button pos)))
      (kill-buffer buf))))

(defun md-ts-test--help-echo-at-search (text search &optional nth)
  "Return the `help-echo' property at SEARCH in markdown TEXT.
NTH selects occurrence (default 1)."
  (alist-get 'help-echo
             (md-ts-test--props-at text search '(help-echo) nth)))

(defun md-ts-test--open-link-at-search (text search &optional nth)
  "Run `md-ts-open-link-at-point' at SEARCH in markdown TEXT.
NTH selects occurrence (default 1)."
  (let ((buf (md-ts-test--fontify text))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (goto-char (match-beginning 0))
          (md-ts-open-link-at-point))
      (kill-buffer buf))))

(defun md-ts-test--open-link-at-search-no-fontify (text search &optional nth)
  "Run `md-ts-open-link-at-point' at SEARCH without pre-fontifying TEXT.
NTH selects occurrence (default 1)."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        (n (or nth 1)))
    (unwind-protect
        (with-current-buffer buf
          (insert text)
          (md-ts-mode)
          (goto-char (point-min))
          (dotimes (_ n)
            (search-forward search))
          (goto-char (match-beginning 0))
          (md-ts-open-link-at-point))
      (kill-buffer buf))))

(defun md-ts-test--open-link-no-fontify-should-reject (text search
                                                            &optional nth)
  "Assert `md-ts-open-link-at-point' rejects SEARCH in unfontified TEXT.
NTH selects occurrence (default 1).  Link openers fail the test if called."
  (cl-letf (((symbol-function 'browse-url)
             (lambda (&rest _args)
               (ert-fail "browse-url called for unsafe bare link")))
            ((symbol-function 'find-file)
             (lambda (&rest _args)
               (ert-fail "find-file called for unsafe bare link")))
            ((symbol-function 'url-mailto)
             (lambda (&rest _args)
               (ert-fail "url-mailto called for unsafe bare link"))))
    (should-error (md-ts-test--open-link-at-search-no-fontify text search nth)
                  :type 'user-error)))

(defconst md-ts-test--foreign-direct-interactive-props
  '(help-echo action category keymap local-map mouse-face follow-link)
  "Foreign direct text properties that should block md-ts link UI.")

(defun md-ts-test--foreign-direct-interactive-prop-value (prop)
  "Return a distinctive test value for foreign direct text property PROP."
  (pcase prop
    ('help-echo "foreign help")
    ('action (lambda (_button) :foreign))
    ('category 'md-ts-test-foreign-category)
    ((or 'keymap 'local-map)
     (let ((map (make-sparse-keymap)))
       (define-key map [mouse-1] #'ignore)
       map))
    ('mouse-face 'highlight)
    ('follow-link t)
    (_ (error "Unhandled foreign direct prop: %S" prop))))

(defun md-ts-test--should-have-direct-property (pos prop value)
  "Assert POS has direct text property PROP set to VALUE."
  (let ((actual (plist-get (text-properties-at pos) prop)))
    (if (stringp value)
        (should (equal actual value))
      (should (eq actual value)))))

(defconst md-ts-test--repo-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute path to the md-ts-mode checkout under test.")

(defconst md-ts-test--result-marker "MD-TS-TEST-RESULT:"
  "Marker that precedes batch-test result output.")

(defun md-ts-test--batch-result-princ-form ()
  "Return an Elisp form string that prints the batch result marker."
  (format "(princ %S)" (format "\n%s\n" md-ts-test--result-marker)))

(defun md-ts-test--read-batch-emacs-result (expression)
  "Evaluate EXPRESSION in a fresh batch Emacs and read its printed result."
  (let* ((emacs (expand-file-name invocation-name invocation-directory))
         (repo-root md-ts-test--repo-root)
         (output-buffer (generate-new-buffer " *md-ts-batch-emacs*"))
         (exit-code (call-process emacs nil output-buffer nil
                                  "--batch" "-Q" "-L" repo-root
                                  "--eval" "(setq load-prefer-newer t)"
                                  "--eval" expression)))
    (unwind-protect
        (progn
          (unless (eq 0 exit-code)
            (error "Batch Emacs exited with %s:\n%s"
                   exit-code
                   (with-current-buffer output-buffer
                     (buffer-string))))
          (with-current-buffer output-buffer
            (goto-char (point-min))
            (unless (search-forward md-ts-test--result-marker nil t)
              (error "Batch Emacs did not print a result marker: %s"
                     (buffer-string)))
            (forward-line 1)
            (read (current-buffer))))
      (kill-buffer output-buffer))))

(defun md-ts-test--range-rules-supports-range-fn-p ()
  "Return non-nil when current `treesit-range-rules' stores `:range-fn'.
This is true for our Emacs 29/30 shim and for newer native Emacs builds
where the upstream shadowing bug is fixed."
  (let ((settings (treesit-range-rules
                   :embed 'markdown-inline
                   :host 'markdown
                   :range-fn #'treesit-range-fn-exclude-children
                   '((inline) @cap))))
    (and (= 1 (length settings))
         (eq (nth 4 (car settings)) #'treesit-range-fn-exclude-children))))

(defvar md-ts-test--python-local-parser-available :unknown
  "Cached availability result for Python local-parser coverage.")

(defun md-ts-test--python-local-parser-available-p ()
  "Return non-nil if Python local parser creation can be tested."
  (when (eq md-ts-test--python-local-parser-available :unknown)
    (setq md-ts-test--python-local-parser-available
          (and (fboundp 'python-ts-mode)
               (treesit-language-available-p 'python)
               (condition-case nil
                   (let ((inhibit-message t)
                         (message-log-max nil))
                     (with-temp-buffer
                       (insert "def foo():\n    return 42\n")
                       (python-ts-mode)
                       t))
                 (error nil)))))
  md-ts-test--python-local-parser-available)

(defvar md-ts-test--python-ts-mode-font-lock-compatible :unknown
  "Cached compatibility result for probing `python-ts-mode' font lock.")

(defun md-ts-test--python-ts-mode-font-lock-compatible-p ()
  "Return non-nil if `python-ts-mode' font-lock queries work here.
This probes a tiny Python buffer so tests that require embedded
Python fontification can skip when the current tree-sitter runtime
rejects upstream Python queries.  Unexpected non-query errors still
fail the test run."
  (when (eq md-ts-test--python-ts-mode-font-lock-compatible :unknown)
    (setq md-ts-test--python-ts-mode-font-lock-compatible
          (and (fboundp 'python-ts-mode)
               (treesit-language-available-p 'python)
               (condition-case nil
                   (let ((inhibit-message t)
                         (message-log-max nil))
                     (with-temp-buffer
                       (insert "def foo():\n    return 42\n")
                       (python-ts-mode)
                       (font-lock-ensure)
                       t))
                 (treesit-query-error nil)))))
  md-ts-test--python-ts-mode-font-lock-compatible)

;;; Font-lock correctness tests

(ert-deftest md-ts-test-require-leaves-global-markdown-settings-alone ()
  "Requiring `md-ts-mode' must not mutate global Markdown mode selection."
  (let* ((expression
          (mapconcat
           #'identity
           `("(progn"
             "  (defvar major-mode-remap-alist nil)"
             "  (defvar treesit-major-mode-remap-alist nil)"
             "  (let ((before-auto (copy-tree auto-mode-alist))"
             "        (before-major-remap (copy-tree major-mode-remap-alist))"
             "        (before-treesit-remap (copy-tree treesit-major-mode-remap-alist)))"
             "    (require 'md-ts-mode)"
             ,(md-ts-test--batch-result-princ-form)
             "    (prin1 (list"
             "            :auto-unchanged (equal before-auto auto-mode-alist)"
             "            :major-remap-unchanged (equal before-major-remap major-mode-remap-alist)"
             "            :treesit-remap-unchanged (equal before-treesit-remap treesit-major-mode-remap-alist)"
             "            :md-mode-defined (fboundp 'md-ts-mode)"
             "            :md-mode-maybe-defined (fboundp 'md-ts-mode-maybe)))))")
           " "))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq t (plist-get result :auto-unchanged)))
    (should (eq t (plist-get result :major-remap-unchanged)))
    (should (eq t (plist-get result :treesit-remap-unchanged)))
    (should (eq t (plist-get result :md-mode-defined)))
    (should (eq t (plist-get result :md-mode-maybe-defined)))))

(ert-deftest md-ts-test-mode-keeps-invisible-unmanaged-by-font-lock ()
  "Activating `md-ts-mode' must not ask font-lock to own `invisible'."
  (let* ((expression
          (prin1-to-string
           `(progn
              (require 'md-ts-mode)
              (let ((before (copy-tree
                             (default-value
                              'font-lock-extra-managed-props))))
                (with-temp-buffer
                  (md-ts-mode)
                  (princ ,(format "\n%s\n" md-ts-test--result-marker))
                  (prin1
                   (list :global-unchanged
                         (equal before
                                (default-value
                                 'font-lock-extra-managed-props))
                         :buffer-local
                         (local-variable-p 'font-lock-extra-managed-props)
                         :local-managed
                         (memq 'invisible font-lock-extra-managed-props))))))))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq t (plist-get result :global-unchanged)))
    (should (eq t (plist-get result :buffer-local)))
    (should-not (plist-get result :local-managed))))

(ert-deftest md-ts-test-generated-autoloads-leave-global-markdown-settings-alone ()
  "Loading generated autoloads must not mutate global Markdown mode selection."
  (let* ((expression
          (mapconcat
           #'identity
           `("(progn"
             "  (require 'package)"
             ,(format "  (let* ((repo-root %S)" md-ts-test--repo-root)
             "         (tmpdir (make-temp-file \"md-ts-autoload-test-\" t))"
             "         (src (expand-file-name \"md-ts-mode.el\" repo-root))"
             "         (dst (expand-file-name \"md-ts-mode.el\" tmpdir)))"
             "    (unwind-protect"
             "        (progn"
             "          (copy-file src dst t)"
             "          (package-generate-autoloads \"md-ts-mode\" tmpdir)"
             "          (defvar major-mode-remap-alist nil)"
             "          (defvar treesit-major-mode-remap-alist nil)"
             "          (let ((before-auto (copy-tree auto-mode-alist))"
             "                (before-major-remap (copy-tree major-mode-remap-alist))"
             "                (before-treesit-remap (copy-tree treesit-major-mode-remap-alist)))"
             "            (load (expand-file-name \"md-ts-mode-autoloads.el\" tmpdir) nil t)"
             ,(md-ts-test--batch-result-princ-form)
             "            (prin1 (list"
             "                    :auto-unchanged (equal before-auto auto-mode-alist)"
             "                    :major-remap-unchanged (equal before-major-remap major-mode-remap-alist)"
             "                    :treesit-remap-unchanged (equal before-treesit-remap treesit-major-mode-remap-alist)"
             "                    :md-mode-autoload (autoloadp (symbol-function 'md-ts-mode))"
             "                    :md-mode-maybe-autoload (autoloadp (symbol-function 'md-ts-mode-maybe))"
             "                    :enable-global-autoload (autoloadp (symbol-function 'md-ts-mode-enable-global))))))"
             "      (delete-directory tmpdir t))))")
           " "))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq t (plist-get result :auto-unchanged)))
    (should (eq t (plist-get result :major-remap-unchanged)))
    (should (eq t (plist-get result :treesit-remap-unchanged)))
    (should (plist-get result :md-mode-autoload))
    (should (plist-get result :md-mode-maybe-autoload))
    (should (plist-get result :enable-global-autoload))))

(ert-deftest md-ts-test-enable-global-is-explicit-and-idempotent ()
  "Calling the helper should opt into global Markdown handling explicitly."
  (let* ((expression
          (prin1-to-string
           `(progn
              (require 'md-ts-mode)
              (defvar major-mode-remap-alist nil)
              (defvar treesit-major-mode-remap-alist nil)
              (let ((before-auto (copy-tree auto-mode-alist))
                    (before-major-remap (copy-tree major-mode-remap-alist))
                    (before-treesit-remap
                     (copy-tree treesit-major-mode-remap-alist)))
                (md-ts-mode-enable-global)
                (let ((after-first-auto (copy-tree auto-mode-alist))
                      (after-first-major-remap
                       (copy-tree major-mode-remap-alist))
                      (after-first-treesit-remap
                       (copy-tree treesit-major-mode-remap-alist)))
                  (md-ts-mode-enable-global)
                  (princ ,(format "\n%s\n" md-ts-test--result-marker))
                  (prin1
                   (list :helper-defined (fboundp 'md-ts-mode-enable-global)
                         :auto-changed
                         (not (equal before-auto after-first-auto))
                         :major-remap-changed
                         (not (equal before-major-remap
                                     after-first-major-remap))
                         :treesit-remap-unchanged
                         (equal before-treesit-remap
                                after-first-treesit-remap)
                         :auto-idempotent
                         (equal after-first-auto auto-mode-alist)
                         :major-remap-idempotent
                         (equal after-first-major-remap
                                major-mode-remap-alist)
                         :treesit-remap-idempotent
                         (equal after-first-treesit-remap
                                treesit-major-mode-remap-alist)
                         :md-entry (car auto-mode-alist)
                         :markdown-remap
                         (assq 'markdown-mode major-mode-remap-alist))))))))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq t (plist-get result :helper-defined)))
    (should (eq t (plist-get result :auto-changed)))
    (should (eq t (plist-get result :major-remap-changed)))
    (should (eq t (plist-get result :treesit-remap-unchanged)))
    (should (eq t (plist-get result :auto-idempotent)))
    (should (eq t (plist-get result :major-remap-idempotent)))
    (should (eq t (plist-get result :treesit-remap-idempotent)))
    (should (equal '("\\.md\\'" . md-ts-mode-maybe)
                   (plist-get result :md-entry)))
    (should (equal '(markdown-mode . md-ts-mode)
                   (plist-get result :markdown-remap)))))

(ert-deftest md-ts-test-enable-global-prefers-md-ts-mode-over-markdown-ts-mode ()
  "The helper should prefer `md-ts-mode' over built-in `markdown-ts-mode'."
  (skip-unless (locate-library "markdown-ts-mode"))
  (let* ((expression
          (prin1-to-string
           `(progn
              (require 'md-ts-mode)
              (require 'markdown-ts-mode)
              (defvar major-mode-remap-alist nil)
              (fset 'md-ts-mode
                    (lambda ()
                      (interactive)
                      (setq major-mode 'md-ts-mode)))
              (fset 'md-ts-mode-maybe
                    (lambda ()
                      (interactive)
                      (md-ts-mode)))
              (fset 'markdown-ts-mode
                    (lambda ()
                      (interactive)
                      (setq major-mode 'markdown-ts-mode)))
              (fset 'markdown-ts-mode-maybe
                    (lambda ()
                      (interactive)
                      (markdown-ts-mode)))
              (md-ts-mode-enable-global)
              (princ ,(format "\n%s\n" md-ts-test--result-marker))
              (prin1
               (list :markdown-ts-remap (major-mode-remap 'markdown-ts-mode)
                     :opened-mode (with-temp-buffer
                                    (setq buffer-file-name
                                          "/tmp/md-ts-prefer.md")
                                    (set-auto-mode)
                                    major-mode))))))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq 'md-ts-mode (plist-get result :markdown-ts-remap)))
    (should (eq 'md-ts-mode (plist-get result :opened-mode)))))

(ert-deftest md-ts-test-heading ()
  "ATX heading should get md-ts-heading-* face."
  (should (md-ts-test--has-face
           "# Hello\n" "Hello" 'md-ts-heading-1)))

(ert-deftest md-ts-test-heading-levels ()
  "Each heading level should get its own face."
  (let ((text "# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6\n"))
    (should (md-ts-test--has-face text "H1" 'md-ts-heading-1))
    (should (md-ts-test--has-face text "H2" 'md-ts-heading-2))
    (should (md-ts-test--has-face text "H3" 'md-ts-heading-3))
    (should (md-ts-test--has-face text "H4" 'md-ts-heading-4))
    (should (md-ts-test--has-face text "H5" 'md-ts-heading-5))
    (should (md-ts-test--has-face text "H6" 'md-ts-heading-6))))

(ert-deftest md-ts-test-setext-heading-levels ()
  "Setext H1 (===) should get `md-ts-heading-1', H2 (---) should get `md-ts-heading-2'."
  (should (md-ts-test--has-face
           "Title\n===\n" "Title" 'md-ts-heading-1))
  (should (md-ts-test--has-face
           "Title\n---\n" "Title" 'md-ts-heading-2)))

(ert-deftest md-ts-test-heading-bold ()
  "All heading face specs should include bold weight."
  (dolist (face '(md-ts-heading-1 md-ts-heading-2 md-ts-heading-3
                  md-ts-heading-4 md-ts-heading-5 md-ts-heading-6))
    (let* ((spec (face-default-spec face))
           (attrs (cadr (assq t spec))))
      (should (eq (plist-get attrs :weight) 'bold)))))

(ert-deftest md-ts-test-heading-scaling ()
  "When `md-ts-heading-scaling' is non-nil, heading faces get :height."
  (let ((md-ts-heading-scaling t))
    (md-ts-update-heading-faces)
    (unwind-protect
        (progn
          (should (= (face-attribute 'md-ts-heading-1 :height) 2.0))
          (should (= (face-attribute 'md-ts-heading-2 :height) 1.7))
          (should (= (face-attribute 'md-ts-heading-6 :height) 1.0)))
      ;; Reset
      (let ((md-ts-heading-scaling nil))
        (md-ts-update-heading-faces)))))

(ert-deftest md-ts-test-heading-scaling-off ()
  "When `md-ts-heading-scaling' is nil, :height is unspecified.
This allows themes to provide their own heading heights."
  (let ((md-ts-heading-scaling nil))
    (md-ts-update-heading-faces)
    (should (eq (face-attribute 'md-ts-heading-1 :height) 'unspecified))
    (should (eq (face-attribute 'md-ts-heading-3 :height) 'unspecified))))

(ert-deftest md-ts-test-heading-scaling-custom-values ()
  "Custom scaling values should be respected."
  (let ((md-ts-heading-scaling t)
        (md-ts-heading-scaling-values '(1.5 1.3 1.2 1.1 1.0 1.0)))
    (md-ts-update-heading-faces)
    (unwind-protect
        (progn
          (should (= (face-attribute 'md-ts-heading-1 :height) 1.5))
          (should (= (face-attribute 'md-ts-heading-2 :height) 1.3)))
      ;; Reset
      (let ((md-ts-heading-scaling nil))
        (md-ts-update-heading-faces)))))

(ert-deftest md-ts-test-heading-delimiter ()
  "The # marker should get md-ts-delimiter face."
  (should (md-ts-test--has-face
           "# Hello\n" "#" 'md-ts-delimiter)))

(ert-deftest md-ts-test-bold-paragraph ()
  "Bold text in paragraph should get `bold' face."
  (should (md-ts-test--has-face
           "Para **bold** text.\n" "bold" 'bold)))

(ert-deftest md-ts-test-no-bold-leak-across-paragraphs ()
  "Bold must not leak across paragraph boundaries."
  (let ((text "**Performance:**\n- Item ~1ms at 80 cols\n\nPlain text between.\n\n**Incremental wrapping:**\n"))
    (should (md-ts-test--has-face text "Performance:" 'bold))
    (should (md-ts-test--has-face text "Incremental wrapping:" 'bold))
    (should-not (md-ts-test--has-face text "Plain text" 'bold))))

(ert-deftest md-ts-test-no-strikethrough-leak-across-paragraphs ()
  "Strikethrough must not leak across paragraph boundaries."
  (let ((text "Time: ~1ms here.\n\nSpeed: ~2.3× faster.\n"))
    (should-not (md-ts-test--has-face text "1ms" 'md-ts-strikethrough))
    (should-not (md-ts-test--has-face text "Speed" 'md-ts-strikethrough))))

(ert-deftest md-ts-test-no-italic-leak-across-paragraphs ()
  "Italic must not leak across paragraph boundaries."
  (let ((text "Paragraph *starts here.\n\nSecond paragraph *ends.\n"))
    (should-not (md-ts-test--has-face text "starts here" 'italic))
    (should-not (md-ts-test--has-face text "Second paragraph" 'italic))))

(ert-deftest md-ts-test-italic-paragraph ()
  "Italic text in paragraph should get `italic' face."
  (should (md-ts-test--has-face
           "Para *italic* text.\n" "italic" 'italic)))

(ert-deftest md-ts-test-strikethrough ()
  "Strikethrough text should get `md-ts-strikethrough' face."
  (should (md-ts-test--has-face
           "Normal ~~deleted~~ text.\n" "deleted" 'md-ts-strikethrough)))

(ert-deftest md-ts-test-code-face-inherits-constant ()
  "The md-ts-code face should inherit font-lock-constant-face for color."
  (let* ((spec (face-default-spec 'md-ts-code))
         (attrs (cadr (assq t spec)))
         (inherit (plist-get attrs :inherit)))
    (should (and (listp inherit)
                 (memq 'font-lock-constant-face inherit)))))

(ert-deftest md-ts-test-code-span ()
  "Code span should get `md-ts-code' face."
  (should (md-ts-test--has-face
           "Para `code` text.\n" "code" 'md-ts-code)))

(ert-deftest md-ts-test-bold-in-table ()
  "Bold text in table cell should get `bold' face."
  (should (md-ts-test--has-face
           "| **tbl** | cell |\n|---|---|\n| a | b |\n"
           "tbl" 'bold)))

(ert-deftest md-ts-test-code-in-table ()
  "Code span in table cell should get `md-ts-code' face."
  (should (md-ts-test--has-face
           "| `code` | cell |\n|---|---|\n| a | b |\n"
           "code" 'md-ts-code)))

(ert-deftest md-ts-test-link-in-table ()
  "Link text in table cell should get `link' face."
  (should (md-ts-test--has-face
           "| [link](url) | cell |\n|---|---|\n| a | b |\n"
           "link" 'link)))

(ert-deftest md-ts-test-table-header ()
  "Table header row should get `bold' face."
  (should (md-ts-test--has-face
           "| Feature |\n|---|\n| value |\n"
           "Feature" 'bold)))

(ert-deftest md-ts-test-table-delimiter-row ()
  "Table delimiter row should get `md-ts-delimiter' face."
  (should (md-ts-test--has-face
           "| A |\n|---|\n| b |\n"
           "---" 'md-ts-delimiter)))

(ert-deftest md-ts-test-hide-markup-bold-in-table ()
  "With hide-markup, bold delimiters in table cells get invisible property."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "| **bold** | cell |\n|---|---|\n| a | b |\n"
                 "**")
                'md-ts--markup))))

(ert-deftest md-ts-test-strikethrough-in-list ()
  "Strikethrough in list item gets `md-ts-strikethrough' face."
  (should (md-ts-test--has-face
           "- ~~removed~~ stays\n" "removed" 'md-ts-strikethrough)))

(ert-deftest md-ts-test-hide-markup-strikethrough ()
  "With hide-markup, ~~ delimiters should be invisible."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "Normal ~~deleted~~ text.\n"
                 "~~")
                'md-ts--markup))))

(ert-deftest md-ts-test-bold-in-blockquote-after-setext ()
  "Bold text in blockquote after setext heading should get bold face."
  (should (md-ts-test--has-face
           "Title\n=========\n> **bold text**\n"
           "bold text" 'bold)))

(ert-deftest md-ts-test-html-block ()
  "HTML block should get `font-lock-doc-face'."
  (should (md-ts-test--has-face
           "<div>Hello</div>\n"
           "<div>" 'font-lock-doc-face)))

(ert-deftest md-ts-test-thematic-break-display ()
  "Thematic break should get a `display' property showing a horizontal rule."
  (let ((buf (md-ts-test--fontify "Before\n\n---\n\nAfter\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "---")
          (let* ((pos (match-beginning 0))
                 (disp (get-text-property pos 'display)))
            (should disp)
            (should (stringp disp))
            (should (string-match-p "─" disp))
            (should (equal (get-text-property pos 'md-ts-display)
                           disp))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-fenced-code-block ()
  "Fenced code block body should get `md-ts-code' face."
  (should (md-ts-test--has-face
           "```\nsome code\n```\n" "some code" 'md-ts-code)))

(ert-deftest md-ts-test-fenced-code-block-with-language ()
  "Fenced code block with language should get `md-ts-code' face on body."
  (should (md-ts-test--has-face
           "```sample\nprint('hi')\n```\n" "print" 'md-ts-code)))

(ert-deftest md-ts-test-fenced-code-block-language-face ()
  "Fenced code block language tags should use `md-ts-language-keyword'."
  (should (md-ts-test--has-face
           "```sample\nprint('hi')\n```\n" "sample" 'md-ts-language-keyword)))

(ert-deftest md-ts-test-indented-code-block-no-delimiter ()
  "Indented code block continuation indent must not get delimiter face."
  (let ((text "    first line\n    second line\n"))
    (should (md-ts-test--has-face text "    second" 'md-ts-code))
    (should-not (md-ts-test--has-face text "    second" 'md-ts-delimiter))))

(ert-deftest md-ts-test-blockquote ()
  "Block quote should get `md-ts-block-quote' face."
  (should (md-ts-test--has-face
           "> quoted\n" "quoted" 'md-ts-block-quote)))

(ert-deftest md-ts-test-blockquote-continuation-in-list ()
  "Block continuation `> ' inside a list within a blockquote is a delimiter.
Regression test: the old tree-sitter query only matched
block_continuation as a direct child of block_quote or paragraph,
missing continuations inside list items."
  (let ((text "> - item\n> - other\n"))
    (should (md-ts-test--has-face text ">" 'md-ts-delimiter 2))))

(ert-deftest md-ts-test-list-continuation-indent-not-delimiter ()
  "List continuation indent (no `>') must not get delimiter face.
When a list item contains a blockquote, the list's own indentation
produces block_continuation nodes that are pure whitespace.  The
`:match \"^>\"' filter must exclude these."
  (let ((text "- item\n  > quoted\n"))
    (should-not (md-ts-test--has-face text "  >" 'md-ts-delimiter))))

(ert-deftest md-ts-test-list-marker ()
  "List markers should get `md-ts-list-marker' face."
  (let ((text "- item one\n- item two\n"))
    (should (md-ts-test--has-face text "-" 'md-ts-list-marker))))

(ert-deftest md-ts-test-nested-list-indent-no-delimiter ()
  "Indentation before nested list items must not get delimiter face.
The whitespace aligning nested items is structural indentation,
not a delimiter that should be hidden."
  (let ((text "1. First\n   1. Nested\n"))
    (should-not (md-ts-test--has-face text "   1" 'md-ts-delimiter))))

(ert-deftest md-ts-test-task-list-unchecked ()
  "Unchecked task list marker gets `md-ts-task-list-marker' face."
  (should (md-ts-test--has-face
           "- [ ] todo\n" "[ ]" 'md-ts-task-list-marker)))

(ert-deftest md-ts-test-task-list-checked ()
  "Checked task list marker gets `md-ts-task-list-marker' face."
  (should (md-ts-test--has-face
           "- [x] done\n" "[x]" 'md-ts-task-list-marker)))

(ert-deftest md-ts-test-task-list-display-unchecked ()
  "Unchecked task marker gets display property showing ☐."
  (let ((buf (md-ts-test--fontify "- [ ] todo\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "[ ]")
          (should (equal (get-text-property (match-beginning 0) 'display) "☐"))
          (should (equal (get-text-property (match-beginning 0) 'md-ts-display)
                         "☐")))
      (kill-buffer buf))))

(ert-deftest md-ts-test-task-list-display-checked ()
  "Checked task marker gets display property showing ☑."
  (let ((buf (md-ts-test--fontify "- [x] done\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "[x]")
          (should (equal (get-text-property (match-beginning 0) 'display) "☑"))
          (should (equal (get-text-property (match-beginning 0) 'md-ts-display)
                         "☑")))
      (kill-buffer buf))))

(ert-deftest md-ts-test-thematic-break-partial-edit-cleans-stale-display ()
  "Breaking a thematic break should remove md-ts-owned display props."
  (let ((buf (md-ts-test--fontify "Before\n\n---\n\nAfter\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "---")
          (let ((dash-beg (match-beginning 0)))
            (should (get-text-property dash-beg 'display))
            (should (equal (get-text-property dash-beg 'md-ts-display)
                           (get-text-property dash-beg 'display)))
            (delete-region dash-beg (1+ dash-beg))
            (funcall font-lock-fontify-region-function
                     dash-beg (min (point-max) (1+ dash-beg)) nil)
            (goto-char dash-beg)
            (let ((line-beg (line-beginning-position))
                  (line-end (line-end-position)))
              (should-not (cl-loop for pos from line-beg below line-end
                                   thereis (get-text-property pos
                                                              'md-ts-display)))
              (should-not (cl-loop for pos from line-beg below line-end
                                   thereis (get-text-property pos 'display))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-task-marker-partial-edit-cleans-stale-display ()
  "Breaking a task marker should remove md-ts-owned display props."
  (let ((buf (md-ts-test--fontify "- [ ] todo\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "[ ]")
          (let ((marker-beg (match-beginning 0)))
            (should (equal (get-text-property marker-beg 'display) "☐"))
            (should (equal (get-text-property marker-beg 'md-ts-display) "☐"))
            (goto-char (1+ marker-beg))
            (delete-char 1)
            (funcall font-lock-fontify-region-function
                     marker-beg (min (point-max) (+ marker-beg 2)) nil)
            (goto-char marker-beg)
            (let ((line-beg (line-beginning-position))
                  (line-end (line-end-position)))
              (should-not (cl-loop for pos from line-beg below line-end
                                   thereis (get-text-property pos
                                                              'md-ts-display)))
              (should-not (cl-loop for pos from line-beg below line-end
                                   thereis (get-text-property pos 'display))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-display-cleanup-read-only-preserves-foreign-display ()
  "Read-only cleanup should remove md-ts displays without touching foreign display."
  (let ((buf (md-ts-test--fontify "---\nforeign\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "---")
          (let ((dash-beg (match-beginning 0)))
            (should (get-text-property dash-beg 'md-ts-display))
            (search-forward "foreign")
            (let ((foreign-beg (match-beginning 0)))
              (put-text-property foreign-beg (match-end 0)
                                 'display "FOREIGN")
              (setq buffer-undo-list nil)
              (set-buffer-modified-p nil)
              (setq buffer-read-only t)
              (funcall font-lock-unfontify-region-function
                       (point-min) (point-max))
              (should-not (get-text-property dash-beg 'display))
              (should-not (get-text-property dash-beg 'md-ts-display))
              (should (equal (get-text-property foreign-beg 'display)
                             "FOREIGN"))
              (should-not (buffer-modified-p))
              (should (equal buffer-undo-list nil)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-thematic-break-preserves-overlapping-foreign-display ()
  "Thematic break display should not overwrite overlapping foreign display."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "---\n")
          (put-text-property (point-min) (1- (point-max))
                             'display "FOREIGN")
          (md-ts-mode)
          (font-lock-ensure)
          (should (equal (get-text-property (point-min) 'display)
                         "FOREIGN"))
          (should-not (get-text-property (point-min) 'md-ts-display))
          (funcall font-lock-unfontify-region-function
                   (point-min) (point-max))
          (should (equal (get-text-property (point-min) 'display)
                         "FOREIGN"))
          (should-not (get-text-property (point-min) 'md-ts-display)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-task-marker-preserves-overlapping-foreign-display ()
  "Task marker display should not overwrite overlapping foreign display."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "- [ ] todo\n")
          (goto-char (point-min))
          (search-forward "[ ]")
          (let ((marker-beg (match-beginning 0))
                (marker-end (match-end 0)))
            (put-text-property marker-beg marker-end 'display "FOREIGN")
            (md-ts-mode)
            (font-lock-ensure)
            (should (equal (get-text-property marker-beg 'display)
                           "FOREIGN"))
            (should-not (get-text-property marker-beg 'md-ts-display))
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max))
            (should (equal (get-text-property marker-beg 'display)
                           "FOREIGN"))
            (should-not (get-text-property marker-beg 'md-ts-display))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-display-cleanup-preserves-replaced-foreign-display ()
  "Cleanup should not remove a foreign display replacing an md-ts display."
  (let ((buf (md-ts-test--fontify "---\n")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dash-beg (point-min)))
            (should (get-text-property dash-beg 'display))
            (should (equal (get-text-property dash-beg 'md-ts-display)
                           (get-text-property dash-beg 'display)))
            (put-text-property dash-beg (1- (point-max))
                               'display "FOREIGN")
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max))
            (should (equal (get-text-property dash-beg 'display)
                           "FOREIGN"))
            (should-not (get-text-property dash-beg 'md-ts-display))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-bold-in-first-list-item ()
  "Bold in first list item is fontified when second item has code.
Regression test for a tree-sitter font-lock bug where disjoint
inline parser ranges cause the first range's faces to be dropped."
  (should (md-ts-test--has-face
           "- **a**\n- `b`\n"
           "a" 'bold)))

(ert-deftest md-ts-test-code-in-first-list-item ()
  "Code in first list item is fontified when second item has bold."
  (should (md-ts-test--has-face
           "- `a`\n- **b**\n"
           "a" 'md-ts-code)))

(ert-deftest md-ts-test-link-inline ()
  "Inline link text should get `link' face."
  (should (md-ts-test--has-face
           "Visit [here](http://example.com) now.\n"
           "here" 'link)))

(ert-deftest md-ts-test-link-destination ()
  "Link destination should get `font-lock-string-face'."
  (should (md-ts-test--has-face
           "Visit [here](http://example.com) now.\n"
           "http://example.com" 'font-lock-string-face)))

(ert-deftest md-ts-test-link-destination-url-normalizes-markdown-syntax ()
  "Raw link destinations should become opener-ready URLs."
  (should (equal (md-ts--link-destination-url
                  "<https://example.com/a b>")
                 "https://example.com/a b"))
  (should (equal (md-ts--link-destination-url
                  "https://example.com/a\\)b")
                 "https://example.com/a)b"))
  (should (equal (md-ts--link-destination-url
                  "<https://example.com/a\\*b>")
                 "https://example.com/a*b"))
  (should (equal (md-ts--link-destination-url
                  "https://e.test?a=1&amp;b=2&#x21;")
                 "https://e.test?a=1&b=2!"))
  (should (equal (md-ts--link-destination-url "C:\\path")
                 "C:\\path")))

(ert-deftest md-ts-test-link-destination-character-reference-edge-cases ()
  "Character references in destinations decode safely and deterministically."
  (should (equal (md-ts--link-destination-url
                  "https://e.test/a&#x21;&#X21;&#33;")
                 "https://e.test/a!!!"))
  (should (equal (md-ts--link-destination-url
                  "https://e.test/?q=\\&amp;&ok=1")
                 "https://e.test/?q=&amp;&ok=1"))
  (should (equal (md-ts--link-destination-url
                  "https://e.test/&#xD800;&#1114112;&#0;&#999999999999999999999;")
                 "https://e.test/&#xD800;&#1114112;&#0;&#999999999999999999999;")))

(ert-deftest md-ts-test-link-inline-character-reference-destination ()
  "Inline link destinations decode Markdown character references."
  (let ((text "Visit [here](https://e.test?a=1&amp;b=2) now.\n")
        (url "https://e.test?a=1&b=2"))
    (should (equal (md-ts-test--help-echo-at-search text "here") url))))

(ert-deftest md-ts-test-link-inline-escaped-character-reference-destination ()
  "Escaped ampersands in inline link destinations stay literal."
  (let ((text "Visit [here](https://e.test?q=\\&amp;&ok=1) now.\n")
        (url "https://e.test?q=&amp;&ok=1"))
    (should (equal (md-ts-test--help-echo-at-search text "here") url))))

(ert-deftest md-ts-test-link-inline-button ()
  "Inline link text should activate the exact destination."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "Visit [here](http://example.com) now.\n"
       "here"))
    (should (equal opened "http://example.com"))))

(ert-deftest md-ts-test-link-inline-help-echo ()
  "Inline link text should expose the destination as help echo."
  (should (equal (md-ts-test--help-echo-at-search
                  "Visit [here](http://example.com) now.\n"
                  "here")
                 "http://example.com")))

(ert-deftest md-ts-test-link-inline-angle-destination ()
  "Angle-bracket inline destinations should open without brackets."
  (let ((text "Visit [here](<https://example.com/a b>) now.\n")
        (url "https://example.com/a b")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "here") url))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (dest &rest _args)
                 (setq opened dest))))
      (md-ts-test--push-button-at-search text "here"))
    (should (equal opened url))))

(ert-deftest md-ts-test-link-inline-escaped-destination ()
  "Markdown backslash escapes in destinations should be decoded."
  (let ((text "Visit [here](https://example.com/a\\)b) now.\n")
        (url "https://example.com/a)b")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "here") url))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (dest &rest _args)
                 (setq opened dest))))
      (md-ts-test--push-button-at-search text "here"))
    (should (equal opened url))))

(ert-deftest md-ts-test-link-autolink-character-reference-destination ()
  "URI autolinks decode Markdown character references in their target."
  (let ((text "Visit <https://e.test?a=1&amp;b=2> now.\n")
        (url "https://e.test?a=1&b=2"))
    (should (equal (md-ts-test--help-echo-at-search text
                                                    "https://e.test")
                   url))))

(ert-deftest md-ts-test-link-inline-help-echo-strips-escaped-properties ()
  "Help strings should not retain Markdown escape provenance properties."
  (let ((buf (md-ts-test--fontify "Open [notes](docs/a\\#b.md) please.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "notes")
          (let* ((pos (match-beginning 0))
                 (help (get-text-property pos 'help-echo))
                 (owned-help (get-text-property pos 'md-ts-link-help-echo)))
            (should (equal help "docs/a#b.md"))
            (should (equal owned-help "docs/a#b.md"))
            (dolist (string (list help owned-help))
              (should-not
               (text-property-any 0 (length string)
                                  md-ts--markdown-escaped-property t
                                  string)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-inline-relative-path-uses-find-file ()
  "Relative inline destinations should use `find-file' semantics."
  (let ((text "Open [notes](docs/notes.md) please.\n")
        (dir (file-name-as-directory
              (make-temp-file "md-ts-link-default-directory-" t)))
        opened)
    (unwind-protect
        (cl-letf (((symbol-function 'find-file)
                   (lambda (file &rest _args)
                     (setq opened (list file default-directory))))
                  ((symbol-function 'browse-url)
                   (lambda (&rest _args)
                     (ert-fail "browse-url called for relative path"))))
          (let ((buf (md-ts-test--fontify text)))
            (unwind-protect
                (with-current-buffer buf
                  (setq default-directory dir)
                  (goto-char (point-min))
                  (search-forward "notes")
                  (push-button (match-beginning 0)))
              (kill-buffer buf))))
      (delete-directory dir t))
    (should (equal opened (list "docs/notes.md" dir)))))

(ert-deftest md-ts-test-link-inline-mailto-uses-url-mailto ()
  "Mailto inline destinations should use Emacs's URL mailto handler."
  (let (mailed)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for mailto link")))
              ((symbol-function 'find-file)
               (lambda (&rest _args)
                 (ert-fail "find-file called for mailto link"))))
      (md-ts-test--push-button-at-search
       "Email [me](mailto:me@example.com?subject=Hi).\n"
       "me"))
    (should (equal mailed '("mailto" "me@example.com?subject=Hi")))))

(ert-deftest md-ts-test-link-inline-uri-scheme-uses-browse-url ()
  "Non-mail URI schemes should still use `browse-url'."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'find-file)
               (lambda (&rest _args)
                 (ert-fail "find-file called for URI link"))))
      (md-ts-test--push-button-at-search
       "Read [capsule](gemini://example.com).\n"
       "capsule"))
    (should (equal opened "gemini://example.com"))))

(ert-deftest md-ts-test-link-inline-fragment-is-deferred ()
  "Same-buffer fragment-only destinations are explicitly deferred."
  (cl-letf (((symbol-function 'browse-url)
             (lambda (&rest _args)
               (ert-fail "browse-url called for fragment link")))
            ((symbol-function 'find-file)
             (lambda (&rest _args)
               (ert-fail "find-file called for fragment link"))))
    (should-error (md-ts--open-link-destination "#intro")
                  :type 'user-error)))

(ert-deftest md-ts-test-link-inline-local-path-fragment-opens-file-only ()
  "Local path fragments open the file; heading navigation is deferred."
  (let ((text "Open [notes](docs/file.md#intro) please.\n")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "notes")
                   "docs/file.md#intro"))
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (setq opened file)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for local path fragment"))))
      (md-ts-test--push-button-at-search text "notes"))
    (should (equal opened "docs/file.md"))))

(ert-deftest md-ts-test-link-inline-escaped-hash-local-path-opens-literal-file ()
  "Escaped hashes in local paths are literal filename characters."
  (let ((text "Open [notes](docs/a\\#b.md) please.\n")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "notes")
                   "docs/a#b.md"))
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (setq opened file)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for escaped local hash"))))
      (md-ts-test--push-button-at-search text "notes"))
    (should (equal-including-properties opened "docs/a#b.md"))))

(ert-deftest md-ts-test-link-inline-escaped-hash-before-fragment-opens-file-only ()
  "Escaped hashes stay literal before an unescaped local fragment."
  (let ((text "Open [notes](docs/a\\#b.md#intro) please.\n")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "notes")
                   "docs/a#b.md#intro"))
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (setq opened file)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for escaped local hash fragment"))))
      (md-ts-test--push-button-at-search text "notes"))
    (should (equal-including-properties opened "docs/a#b.md"))))

(ert-deftest md-ts-test-link-inline-windows-drive-paths-use-find-file ()
  "Windows drive paths should be opened as files, not URI schemes."
  (let (opened)
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (push file opened)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for Windows drive path"))))
      (md-ts--open-link-destination "C:/foo")
      (md-ts--open-link-destination "C:\\foo"))
    (should (equal (nreverse opened) '("C:/foo" "C:\\foo")))))

(ert-deftest md-ts-test-link-inline-empty-destination-is-not-buttonized ()
  "Empty inline destinations should not create unusable buttons."
  (let ((text "Empty [x](<>) link.\n"))
    (should-not (md-ts-test--button-at-search text "x"))
    (should-not (md-ts-test--help-echo-at-search text "x")))
  (cl-letf (((symbol-function 'find-file)
             (lambda (&rest _args)
               (ert-fail "find-file called for empty destination")))
            ((symbol-function 'browse-url)
             (lambda (&rest _args)
               (ert-fail "browse-url called for empty destination"))))
    (should-error (md-ts--open-link-destination "")
                  :type 'user-error)))

(ert-deftest md-ts-test-link-inline-button-spans-visible-label-only ()
  "Inline link buttons should cover the label, not markup or URL."
  (let ((buf (md-ts-test--fontify
              "Visit [here](http://example.com) now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "here")
          (let* ((label-start (match-beginning 0))
                 (label-end (match-end 0))
                 (button (button-at label-start)))
            (should button)
            (should (equal (cons (button-start button)
                                 (button-end button))
                           (cons label-start label-end)))
            (should-not (button-at (1- label-start)))
            (should-not (button-at label-end))
            (search-forward "http://example.com")
            (should-not (button-at (match-beginning 0)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-inline-button-properties-clean-after-edit ()
  "Editing an inline link into plain text should remove button props."
  (let ((buf (md-ts-test--fontify
              "Visit [here](http://example.com) now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "here")
          (should (button-at (match-beginning 0)))
          (goto-char (point-min))
          (search-forward "[here](http://example.com)")
          (replace-match "here" t t)
          (font-lock-flush)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "here")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (dolist (prop '(button category action help-echo keymap
                                   mouse-face follow-link))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-cleanup-preserves-foreign-direct-interactive-props ()
  "Stale md-ts cleanup should keep each foreign direct UI prop."
  (dolist (case '((parsed "[link](https://example.com)\n" "link")
                  (bare "Visit https://example.com now.\n"
                        "https://example.com")))
    (pcase-let ((`(,label ,text ,search) case))
      (dolist (prop md-ts-test--foreign-direct-interactive-props)
        (ert-info ((format "%s direct %S" label prop))
          (let ((buf (md-ts-test--fontify text))
                (value (md-ts-test--foreign-direct-interactive-prop-value prop)))
            (unwind-protect
                (with-current-buffer buf
                  (goto-char (point-min))
                  (search-forward search)
                  (let ((pos (match-beginning 0))
                        (end (match-end 0)))
                    (should (md-ts--link-button-p (button-at pos)))
                    (put-text-property pos end prop value)
                    (md-ts--remove-link-button-properties pos end)
                    (md-ts-test--should-have-direct-property pos prop value)
                    (should-not (get-text-property pos 'md-ts-link-button))
                    (should-not (get-text-property pos 'md-ts-link-help-echo))
                    (should-not (get-text-property pos
                                                   'md-ts-link-static-target))
                    (when (eq prop 'help-echo)
                      (should (equal (get-text-property pos 'help-echo)
                                     "foreign help")))
                    (if (eq prop 'action)
                        (progn
                          (should (button-at pos))
                          (should-not (md-ts--link-button-p (button-at pos))))
                      (should-not (button-at pos)))))
              (kill-buffer buf))))))))

(ert-deftest md-ts-test-link-foreign-direct-interactive-props-prevent-fontification ()
  "Each direct non-button UI prop should block md-ts buttonization."
  (dolist (case '((parsed "[link](https://example.com)\n" "link")
                  (bare "Visit https://example.com now.\n"
                        "https://example.com")))
    (pcase-let ((`(,label ,text ,search) case))
      (dolist (prop md-ts-test--foreign-direct-interactive-props)
        (ert-info ((format "%s link direct %S" label prop))
          (let ((buf (generate-new-buffer " *md-ts-test*"))
                (value (md-ts-test--foreign-direct-interactive-prop-value prop)))
            (unwind-protect
                (with-current-buffer buf
                  (insert text)
                  (goto-char (point-min))
                  (search-forward search)
                  (let ((pos (match-beginning 0))
                        (end (match-end 0)))
                    (put-text-property pos end prop value)
                    (md-ts-mode)
                    (font-lock-ensure)
                    (should-not (button-at pos))
                    (should-not (get-text-property pos 'md-ts-link-button))
                    (should-not (get-text-property pos 'md-ts-link-help-echo))
                    (should-not (get-text-property pos
                                                   'md-ts-link-static-target))
                    (md-ts-test--should-have-direct-property pos prop value)
                    (unless (eq prop 'help-echo)
                      (should-not (get-text-property pos 'help-echo)))
                    (unless (eq prop 'action)
                      (should-not (get-text-property pos 'action)))
                    (unless (eq prop 'category)
                      (should-not (get-text-property pos 'category)))))
              (kill-buffer buf))))))))

(ert-deftest md-ts-test-link-multiline-button-cleanup-expands-span ()
  "Partial unfontification should clean a whole md-ts multiline button."
  (let ((buf (md-ts-test--fontify
              "[foo\nbar](https://example.com)\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "foo")
          (let ((first-pos (match-beginning 0))
                second-pos)
            (search-forward "bar")
            (setq second-pos (match-beginning 0))
            (should (button-at first-pos))
            (should (button-at second-pos))
            (funcall font-lock-unfontify-region-function
                     (point-min) (save-excursion
                                   (goto-char first-pos)
                                   (line-end-position)))
            (dolist (pos (list first-pos second-pos))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-dynamic-legacy-button-cleaned-on-mode-setup ()
  "Legacy dynamic md-ts buttons are removed when mode is enabled."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "legacy button text.\n")
          (goto-char (point-min))
          (search-forward "button")
          (let ((pos (match-beginning 0)))
            (make-text-button pos (match-end 0)
                              'action #'md-ts--open-link-button
                              'help-echo "https://old.example")
            (should (button-at pos))
            (should-not (get-text-property pos 'md-ts-link-button))
            (md-ts-mode)
            (font-lock-ensure)
            (should-not (button-at pos))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-mode-setup-cleans-buttons-outside-narrowing ()
  "Mode setup should clean stale md-ts buttons in the whole buffer."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (insert "current outside\nvisible inside\nlegacy outside\nforeign outside\n")
          (goto-char (point-min))
          (search-forward "current")
          (let ((current-pos (match-beginning 0))
                (current-end (match-end 0))
                legacy-pos legacy-end foreign-pos foreign-end
                narrow-beg narrow-end)
            (make-text-button current-pos current-end
                              'md-ts-link-button t
                              'md-ts-link-help-echo "https://old.example"
                              'action #'md-ts--open-link-button
                              'help-echo "https://old.example")
            (search-forward "visible")
            (setq narrow-beg (match-beginning 0)
                  narrow-end (match-end 0))
            (search-forward "legacy")
            (setq legacy-pos (match-beginning 0)
                  legacy-end (match-end 0))
            (make-text-button legacy-pos legacy-end
                              'action #'md-ts--open-link-button
                              'help-echo "https://legacy.example")
            (search-forward "foreign")
            (setq foreign-pos (match-beginning 0)
                  foreign-end (match-end 0))
            (make-text-button foreign-pos foreign-end
                              'action (lambda (_button)
                                        (setq called t))
                              'help-echo "foreign")
            (narrow-to-region narrow-beg narrow-end)
            (md-ts-mode)
            (widen)
            (dolist (pos (list current-pos legacy-pos))
              (should-not (button-at pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo))
                (should-not (get-text-property pos prop))))
            (let ((button (button-at foreign-pos)))
              (should button)
              (should (equal (button-get button 'help-echo) "foreign"))
              (push-button foreign-pos)
              (should called))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-mode-setup-read-only-keeps-buffer-state ()
  "Mode setup should silently clean stale buttons in read-only buffers."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "stale link text\n")
          (goto-char (point-min))
          (search-forward "link")
          (let ((pos (match-beginning 0))
                (end (match-end 0))
                (undo-list (list :sentinel)))
            (make-text-button pos end
                              'md-ts-link-button t
                              'md-ts-link-help-echo "https://old.example"
                              'action #'md-ts--open-link-button
                              'help-echo "https://old.example")
            (setq buffer-undo-list undo-list)
            (set-buffer-modified-p nil)
            (setq buffer-read-only t)
            (md-ts-mode)
            (should-not (buffer-modified-p))
            (should (eq buffer-undo-list undo-list))
            (should-not (button-at pos))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button md-ts-link-help-echo))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-unfontify-read-only-keeps-buffer-state ()
  "Unfontification should silently clean stale md-ts link buttons."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "stale link text\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "link")
          (let ((pos (match-beginning 0))
                (end (match-end 0))
                (undo-list (list :sentinel))
                initial-modified)
            (make-text-button pos end
                              'md-ts-link-button t
                              'md-ts-link-help-echo "https://old.example"
                              'action #'md-ts--open-link-button
                              'help-echo "https://old.example")
            (put-text-property pos end 'face 'link)
            (setq buffer-undo-list undo-list)
            (set-buffer-modified-p nil)
            (setq initial-modified (buffer-modified-p))
            (setq buffer-read-only t)
            (funcall font-lock-unfontify-region-function pos end)
            (should (eq (buffer-modified-p) initial-modified))
            (should (eq buffer-undo-list undo-list))
            (should-not (button-at pos))
            (dolist (prop '(button category action help-echo face
                                   md-ts-link-button md-ts-link-help-echo))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-image-button ()
  "Image descriptions should activate the image destination."
  (let (opened)
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (setq opened file)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for image path"))))
      (md-ts-test--push-button-at-search
       "Check ![alt text](image.png) now.\n"
       "alt text"))
    (should (equal opened "image.png"))))

(ert-deftest md-ts-test-link-image-reference-button ()
  "Reference-style images should activate the resolved definition."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (push url opened))))
      (md-ts-test--push-button-at-search
       "See ![Full][img].\n\n[img]: https://full.example/image.png\n"
       "Full")
      (md-ts-test--push-button-at-search
       "See ![Collapsed][].\n\n[collapsed]: https://collapsed.example/image.png\n"
       "Collapsed")
      (md-ts-test--push-button-at-search
       "See ![Shortcut].\n\n[shortcut]: https://shortcut.example/image.png\n"
       "Shortcut"))
    (should (equal (nreverse opened)
                   '("https://full.example/image.png"
                     "https://collapsed.example/image.png"
                     "https://shortcut.example/image.png")))))

(ert-deftest md-ts-test-link-image-alt-inline-link-uses-outer-target ()
  "Inline link syntax inside image alt text should not leak its target."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See ![foo [bar](https://inner.example)](https://outer.example/img.png).\n"
       "bar"))
    (should (equal opened "https://outer.example/img.png"))))

(ert-deftest md-ts-test-link-image-alt-reference-link-uses-outer-target ()
  "Reference link syntax inside image alt text should not leak its target."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       (concat "See ![foo [bar][inner]](https://outer.example/img.png).\n\n"
               "[inner]: https://inner.example\n")
       "bar"))
    (should (equal opened "https://outer.example/img.png"))))

(ert-deftest md-ts-test-link-image-alt-autolink-uses-outer-target ()
  "Autolink syntax inside image alt text should not leak its target."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See ![foo <https://inner.example>](https://outer.example/img.png).\n"
       "https://inner.example"))
    (should (equal opened "https://outer.example/img.png"))))

(ert-deftest md-ts-test-link-image-inside-inline-link-uses-outer-target ()
  "Image alt text inside an inline link should open the enclosing link."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'find-file)
               (lambda (&rest _args)
                 (ert-fail "find-file called for nested image target"))))
      (md-ts-test--push-button-at-search
       "[![Alt](image.png)](https://outer.example)\n"
       "Alt"))
    (should (equal opened "https://outer.example"))))

(ert-deftest md-ts-test-link-image-inside-reference-link-uses-outer-target ()
  "Image alt text inside a reference link should open the enclosing link."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'find-file)
               (lambda (&rest _args)
                 (ert-fail "find-file called for nested image target"))))
      (md-ts-test--push-button-at-search
       (concat "[![Alt](image.png)][outer]\n\n"
               "[outer]: https://outer.example\n")
       "Alt"))
    (should (equal opened "https://outer.example"))))

(ert-deftest md-ts-test-link-autolink-inside-inline-link-uses-outer-target ()
  "Autolink text inside an inline link should open the enclosing link."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "[<https://inner.example>](https://outer.example)\n"
       "https://inner.example"))
    (should (equal opened "https://outer.example"))))

(ert-deftest md-ts-test-link-autolink-inside-reference-link-uses-outer-target ()
  "Autolink text inside a reference link should open the enclosing link."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       (concat "[<https://inner.example>][outer]\n\n"
               "[outer]: https://outer.example\n")
       "https://inner.example"))
    (should (equal opened "https://outer.example"))))

(ert-deftest md-ts-test-link-full-reference-button ()
  "Full reference links should activate the resolved definition."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See [Python docs][py] now.\n\n[py]: https://python.org\n"
       "Python docs"))
    (should (equal opened "https://python.org"))))

(ert-deftest md-ts-test-link-reference-escaped-hash-local-path-opens-literal-file ()
  "Escaped hashes in reference destinations are literal filename characters."
  (let ((text (concat "See [Doc][hash].\n\n"
                      "[hash]: docs/a\\#b.md\n"))
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "Doc")
                   "docs/a#b.md"))
    (cl-letf (((symbol-function 'find-file)
               (lambda (file &rest _args)
                 (setq opened file)))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for escaped local hash"))))
      (md-ts-test--push-button-at-search text "Doc"))
    (should (equal-including-properties opened "docs/a#b.md"))))

(ert-deftest md-ts-test-link-reference-label-normalization ()
  "Reference labels should be whitespace-folded and simply downcased."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See [Topic][FOO   BAR].\n\n[ foo bar ]: https://example.com\n"
       "Topic"))
    (should (equal opened "https://example.com"))))

(ert-deftest md-ts-test-link-reference-label-escaped-punctuation-distinct ()
  "Escaped punctuation in reference labels should remain distinct."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (push url opened))))
      (md-ts-test--push-button-at-search
       (concat "See [Escaped][a\\*b] and [Plain][a*b].\n\n"
               "[a\\*b]: https://escaped.example\n"
               "[a*b]: https://plain.example\n")
       "Escaped")
      (md-ts-test--push-button-at-search
       (concat "See [Escaped][a\\*b] and [Plain][a*b].\n\n"
               "[a\\*b]: https://escaped.example\n"
               "[a*b]: https://plain.example\n")
       "Plain"))
    (should (equal (nreverse opened)
                   '("https://escaped.example"
                     "https://plain.example")))))

(ert-deftest md-ts-test-link-reference-label-escaped-bracket-literal ()
  "Escaped brackets in reference labels should match literally."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       (concat "See [Doc][foo\\]bar].\n\n"
               "[foo]: https://prefix.example\n"
               "[foo\\]bar]: https://escaped-bracket.example\n")
       "Doc"))
    (should (equal opened "https://escaped-bracket.example"))))

(ert-deftest md-ts-test-link-reference-label-key-preserves-escaped-brackets ()
  "Reference label keys should keep escaped brackets distinct."
  (should-not (equal (md-ts--reference-label-key "[a\\[b]")
                     (md-ts--reference-label-key "[a[b]")))
  (should-not (equal (md-ts--reference-label-key "[a\\]b]")
                     (md-ts--reference-label-key "[a]b]"))))

(ert-deftest md-ts-test-link-reference-first-definition-wins ()
  "Reference resolution should use the first matching definition."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See [Doc][dup].\n\n[dup]: https://first.example\n[dup]: https://second.example\n"
       "Doc"))
    (should (equal opened "https://first.example"))))

(ert-deftest md-ts-test-link-reference-cache-rebuilds-after-edit ()
  "Reference definition edits should rebuild cached button targets."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n[id]: https://old.example\n"))
        opened)
    (unwind-protect
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url &rest _args)
                     (push url opened))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (push-button (match-beginning 0))
            (goto-char (point-min))
            (search-forward "https://old.example")
            (replace-match "https://new.example" t t)
            ;; Do not refontify the referring link text here.  Its
            ;; existing button action must resolve through the fresh
            ;; reference cache at activation time.
            (goto-char (point-min))
            (search-forward "Doc")
            (push-button (match-beginning 0))))
      (kill-buffer buf))
    (should (equal (nreverse opened)
                   '("https://old.example" "https://new.example")))))

(ert-deftest md-ts-test-link-reference-cache-rebuilds-after-unrelated-edit ()
  "Any text edit should invalidate the reference cache by buffer tick."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n[id]: https://cached.example\n")))
    (unwind-protect
        (with-current-buffer buf
          (let ((cache (md-ts--link-reference-definitions))
                (tick md-ts--link-reference-definitions-cache-tick))
            (goto-char (point-min))
            (insert "Intro line.\n")
            (should (equal md-ts--link-reference-definitions-cache-tick
                           tick))
            (should-not (equal tick (buffer-chars-modified-tick)))
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://cached.example"))
            (should-not (eq cache md-ts--link-reference-definitions-cache))
            (should (equal md-ts--link-reference-definitions-cache-tick
                           (buffer-chars-modified-tick)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-cache-widens-before-rebuild ()
  "First cache rebuild while narrowed should not poison widening."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "See [Doc][id].\n\n[id]: https://wide.example\n")
          (md-ts-mode)
          (goto-char (point-min))
          (forward-line 1)
          (narrow-to-region (point-min) (point))
          (let ((narrowed-result (md-ts--resolve-link-reference "[id]")))
            (widen)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://wide.example"))
            (should (equal narrowed-result "https://wide.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-cache-widens-before-duplicates ()
  "A narrowed first rebuild should still let the first definition win."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (concat "[dup]: https://first.example\n\n"
                          "[dup]: https://second.example\n"))
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "second.example")
          (narrow-to-region (line-beginning-position)
                            (line-end-position))
          (let ((narrowed-result (md-ts--resolve-link-reference "[dup]")))
            (widen)
            (should (equal (md-ts--resolve-link-reference "[dup]")
                           "https://first.example"))
            (should (equal narrowed-result "https://first.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-cache-rebuilds-after-fence-insertion ()
  "Inserting a fence before a distant definition should unresolve links."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n[id]: https://old.example\n")))
    (unwind-protect
        (with-current-buffer buf
          (should (equal (md-ts--resolve-link-reference "[id]")
                         "https://old.example"))
          (goto-char (point-min))
          (search-forward "Doc")
          (should (button-at (match-beginning 0)))
          (goto-char (point-min))
          (search-forward "[id]:")
          (beginning-of-line)
          (insert "```\n")
          (should-not (md-ts--resolve-link-reference "[id]"))
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'help-echo))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-cache-rebuilds-after-fence-removal ()
  "Removing a fence before a distant definition should resolve links."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n```\n[id]: https://new.example\n")))
    (unwind-protect
        (with-current-buffer buf
          (should-not (md-ts--resolve-link-reference "[id]"))
          (goto-char (point-min))
          (search-forward "Doc")
          (should-not (button-at (match-beginning 0)))
          (goto-char (point-min))
          (search-forward "```")
          (delete-region (line-beginning-position)
                         (min (1+ (line-end-position)) (point-max)))
          (should (equal (md-ts--resolve-link-reference "[id]")
                         "https://new.example"))
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://new.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-blockquote-fence-insertion-flushes-stale-links ()
  "Inserting a blockquote fence should flush stale link props."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n> [id]: https://old.example\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://old.example")))
          (goto-char (point-min))
          (search-forward "> [id]:")
          (beginning-of-line)
          (insert "> ```\n")
          (should-not (md-ts--resolve-link-reference "[id]"))
          ;; The changed line is away from the referring link.  Without a
          ;; structural fence flush, the old button/help would survive until
          ;; incidental refontification; the command must refresh it first.
          (goto-char (point-min))
          (search-forward "Doc")
          (goto-char (match-beginning 0))
          (cl-letf (((symbol-function 'browse-url)
                     (lambda (&rest _args)
                       (ert-fail "browse-url called for fenced reference")))
                    ((symbol-function 'find-file)
                     (lambda (&rest _args)
                       (ert-fail "find-file called for fenced reference")))
                    ((symbol-function 'url-mailto)
                     (lambda (&rest _args)
                       (ert-fail "url-mailto called for fenced reference"))))
            (should-error (md-ts-open-link-at-point) :type 'user-error))
          (let ((pos (point)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'help-echo)))
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'help-echo))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-blockquote-fence-removal-flushes-stale-links ()
  "Removing a blockquote fence should flush stale link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "> ```\n"
                      "> code\n"
                      "> ```\n"
                      "> [id]: https://new.example\n"
                      "[id]: https://old.example\n"))))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://new.example")))
          (goto-char (point-min))
          (search-forward "> ```" nil nil 2)
          (delete-region (line-beginning-position)
                         (min (1+ (line-end-position)) (point-max)))
          (should (equal (md-ts--resolve-link-reference "[id]")
                         "https://old.example"))
          ;; The old help text pointed at the now-hidden blockquote
          ;; definition.  The command should force the flushed referring line
          ;; current before any incidental refontification.
          (goto-char (point-min))
          (search-forward "Doc")
          (goto-char (match-beginning 0))
          (let (opened)
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://old.example")))
          (let ((pos (point)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://old.example")))
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://old.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-nested-list-fence-insertion-flushes-stale-links ()
  "Inserting a nested-list fence should flush stale link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "- item\n"
                      "  - sub\n\n"
                      "      [id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))
            (goto-char (point-min))
            (search-forward "  - sub")
            (end-of-line)
            (insert "\n      ```")
            (should full-flushes)
            (should-not (md-ts--resolve-link-reference "[id]"))
            ;; The parser recognizes this delimiter even though it is indented
            ;; more than three absolute columns for a nested list item.  The
            ;; command should see the referring line was flushed before opening.
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (&rest _args)
                         (ert-fail "browse-url called for fenced reference")))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for fenced reference")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for fenced reference"))))
              (should-error (md-ts-open-link-at-point) :type 'user-error))
            (let ((pos (point)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-nested-list-fence-removal-flushes-stale-links ()
  "Removing a nested-list fence should flush stale link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "- item\n"
                      "  - sub\n"
                      "      ```\n\n\n"
                      "      [id]: https://new.example\n\n"
                      "[id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))
            (goto-char (point-min))
            (search-forward "```")
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max)))
            (should full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://new.example"))
            ;; The dynamic action would open the new target either way; the
            ;; help text proves the remote line was flushed before the command
            ;; initialized it.
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (let (opened)
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url))))
                (md-ts-open-link-at-point))
              (should (equal opened "https://new.example")))
            (let ((pos (point)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://new.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-fence-split-before-delimiter-flushes-stale-links ()
  "Splitting text before a fence delimiter should flush stale link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "para```\n\n"
                      "[id]: https://new.example\n"
                      "```\n"
                      "[id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://new.example"))
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://new.example")))
            (goto-char (point-min))
            (search-forward "para")
            (insert "\n")
            (should full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://old.example"))
            ;; No explicit refontification here: the command should refresh
            ;; the flushed remote link before using its stale help/button.
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (let (opened)
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url))))
                (md-ts-open-link-at-point))
              (should (equal opened "https://old.example")))
            (let ((pos (point)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-fence-join-before-delimiter-flushes-stale-links ()
  "Joining a fence delimiter onto text should flush stale link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "para\n"
                      "```\n\n"
                      "[id]: https://new.example\n"
                      "```\n"
                      "[id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://old.example"))
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))
            (goto-char (point-min))
            (search-forward "para")
            (delete-char 1)
            (should full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://new.example"))
            ;; No explicit refontification here: the command should refresh
            ;; the flushed remote link before using its stale help/button.
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (let (opened)
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url))))
                (md-ts-open-link-at-point))
              (should (equal opened "https://new.example")))
            (let ((pos (point)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://new.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-opener-insertion-flushes-stale-links ()
  "Inserting a raw HTML opener should flush stale reference link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "intro\n\n"
                      "[id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))
            (goto-char (point-min))
            (search-forward "intro")
            (beginning-of-line)
            (insert "<script>\n")
            (should full-flushes)
            (should-not (md-ts--resolve-link-reference "[id]"))
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (&rest _args)
                         (ert-fail "browse-url called for HTML-hidden reference")))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for HTML-hidden reference")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for HTML-hidden reference"))))
              (should-error (md-ts-open-link-at-point) :type 'user-error))
            (let ((pos (point)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-opener-removal-flushes-stale-links ()
  "Removing a raw HTML opener should flush stale reference link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "<script>\n"
                      "intro\n\n"
                      "[id]: https://new.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should-not (button-at (match-beginning 0)))
            (goto-char (point-min))
            (search-forward "<script>")
            (delete-region (line-beginning-position)
                           (min (1+ (line-end-position)) (point-max)))
            (should full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://new.example"))
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://new.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-opener-line-split-flushes-stale-links ()
  "Splitting a paragraph before an HTML opener flushes stale refs."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "para<script>\n\n"
                      "[id]: https://old.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://old.example")))
            (goto-char (point-min))
            (search-forward "<script>")
            (goto-char (match-beginning 0))
            (insert "\n")
            (should full-flushes)
            (should-not (md-ts--resolve-link-reference "[id]"))
            (goto-char (point-min))
            (search-forward "Doc")
            (goto-char (match-beginning 0))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (&rest _args)
                         (ert-fail "browse-url called for HTML-hidden reference")))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for HTML-hidden reference")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for HTML-hidden reference"))))
              (should-error (md-ts-open-link-at-point) :type 'user-error))
            (let ((pos (point)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-opener-line-join-flushes-new-links ()
  "Joining a paragraph with an HTML opener flushes newly visible refs."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "para\n"
                      "<script>\n\n"
                      "[id]: https://new.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should-not (button-at (match-beginning 0)))
            (should-not (md-ts--resolve-link-reference "[id]"))
            (goto-char (point-min))
            (search-forward "para")
            (delete-char 1)
            (should full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://new.example"))
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://new.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-inner-edit-does-not-flush ()
  "Ordinary edits inside an HTML block should not flush all link props."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "<script>\n"
                      "line one\n"
                      "line two\n"
                      "line three\n"
                      "</script>\n\n"
                      "[id]: https://live.example\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "line two")
            (replace-match "line 2" t t)
            (should-not full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://live.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-html-nearby-edits-do-not-flush ()
  "Ordinary edits near HTML block boundaries should not full-flush."
  (dolist (line '("line before" "first content" "last content" "line after"))
    (ert-info ((format "editing %s" line))
      (let ((buf (md-ts-test--fontify
                  (concat "See [Doc][id].\n\n"
                          "line before\n"
                          "<script>\n"
                          "first content\n"
                          "middle content\n"
                          "last content\n"
                          "</script>\n"
                          "line after\n\n"
                          "[id]: https://live.example\n")))
            (original-flush (symbol-function 'font-lock-flush))
            full-flushes)
        (unwind-protect
            (cl-letf (((symbol-function 'font-lock-flush)
                       (lambda (&optional beg end)
                         (when (and (equal beg (point-min))
                                    (equal end (point-max)))
                           (push t full-flushes))
                         (funcall original-flush beg end))))
              (with-current-buffer buf
                (goto-char (point-min))
                (search-forward line)
                (end-of-line)
                (insert " changed")
                (should-not full-flushes)
                (should (equal (md-ts--resolve-link-reference "[id]")
                               "https://live.example"))))
          (kill-buffer buf))))))

(ert-deftest md-ts-test-link-reference-definition-change-refontifies-links ()
  "Definition edits should non-locally update reference link buttons."
  (let ((buf (md-ts-test--fontify "See [Doc][id].\n"))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes
        opened)
    (unwind-protect
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url &rest _args)
                     (push url opened)))
                  ((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should-not (button-at (match-beginning 0)))
            (goto-char (point-max))
            (insert "\n[id]: https://added.example\n")
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://added.example"))
              (push-button pos))
            (setq full-flushes nil)
            (goto-char (point-min))
            (search-forward "[id]: https://added.example")
            (delete-region (match-beginning 0) (line-end-position))
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))
    (should (equal (nreverse opened) '("https://added.example")))))

(ert-deftest md-ts-test-link-reference-definition-escaped-label-flushes ()
  "Escaped labels in new definitions should trigger non-local flushing."
  (let ((buf (md-ts-test--fontify "See [Doc][foo\\]bar].\n"))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should-not (button-at (match-beginning 0)))
            (goto-char (point-max))
            (insert "\n[foo\\]bar]: https://escaped.example\n")
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'help-echo)
                             "https://escaped.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-enclosed-escaped-delete-flushes ()
  "Deleting a region enclosing an escaped-label definition should flush links."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][foo\\]bar].\n\n"
                      "before\n\n"
                      "[foo\\]bar]: https://old.example\n\n"
                      "after\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should (equal (get-text-property (match-beginning 0) 'help-echo)
                           "https://old.example"))
            (goto-char (point-min))
            (search-forward "before")
            (let ((beg (match-beginning 0)))
              (search-forward "after")
              (delete-region beg (line-end-position)))
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-enclosed-escaped-replace-flushes ()
  "Replacing a region enclosing an escaped-label definition should flush links."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][foo\\]bar].\n\n"
                      "before\n\n"
                      "[foo\\]bar]: https://old.example\n\n"
                      "after\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should (button-at (match-beginning 0)))
            (goto-char (point-min))
            (search-forward (concat "before\n\n"
                                    "[foo\\]bar]: https://old.example\n\n"
                                    "after"))
            (replace-match "replacement" t t)
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-change-updates-help-echo ()
  "Destination edits should non-locally refresh reference help text."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n[id]: https://old.example\n"))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "Doc")
            (should (equal (get-text-property (match-beginning 0) 'help-echo)
                           "https://old.example"))
            (goto-char (point-min))
            (search-forward "https://old.example")
            (replace-match "https://new.example" t t)
            (should full-flushes)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward "Doc")
            (should (equal (get-text-property (match-beginning 0) 'help-echo)
                           "https://new.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-add-flushes-while-narrowed ()
  "Adding a definition while narrowed should refresh links outside it."
  (let ((buf (md-ts-test--fontify "See [Doc][id].\n\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "Doc")
          (should-not (button-at (match-beginning 0)))
          (narrow-to-region (point-max) (point-max))
          (goto-char (point-max))
          (insert "[id]: https://narrow.example\n")
          (widen)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (button-at pos))
            (should (equal (get-text-property pos 'help-echo)
                           "https://narrow.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-remove-flushes-while-narrowed ()
  "Removing a definition while narrowed should refresh links outside it."
  (let ((buf (md-ts-test--fontify
              "See [Doc][id].\n\n[id]: https://old.example\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "Doc")
          (should (button-at (match-beginning 0)))
          (goto-char (point-min))
          (search-forward "[id]:")
          (narrow-to-region (line-beginning-position) (point-max))
          (delete-region (point-min) (point-max))
          (widen)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'help-echo))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-reference-definition-in-fence-does-not-flush ()
  "Editing definition-like code should not cause a full link flush."
  (let ((buf (md-ts-test--fontify
              (concat "See [Doc][id].\n\n"
                      "[id]: https://live.example\n\n"
                      "```\n"
                      "[notdef]: https://old.example\n"
                      "```\n")))
        (original-flush (symbol-function 'font-lock-flush))
        full-flushes)
    (unwind-protect
        (cl-letf (((symbol-function 'font-lock-flush)
                   (lambda (&optional beg end)
                     (when (and (equal beg (point-min))
                                (equal end (point-max)))
                       (push t full-flushes))
                     (funcall original-flush beg end))))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "https://old.example")
            (replace-match "https://still-code.example" t t)
            (should-not full-flushes)
            (should (equal (md-ts--resolve-link-reference "[id]")
                           "https://live.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-collapsed-reference-button ()
  "Collapsed reference links should use their link text as the label."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See [Python][].\n\n[python]: https://python.org\n"
       "Python"))
    (should (equal opened "https://python.org"))))

(ert-deftest md-ts-test-link-shortcut-reference-button ()
  "Shortcut reference links should use their link text as the label."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "See [Python].\n\n[python]: https://python.org\n"
       "Python"))
    (should (equal opened "https://python.org"))))

(ert-deftest md-ts-test-link-missing-reference-is-not-buttonized ()
  "Missing reference links should keep `link' face without a bogus button."
  (let ((text "See [Missing][nope].\n"))
    (should (md-ts-test--has-face text "Missing" 'link))
    (should-not (md-ts-test--button-at-search text "Missing"))))

(ert-deftest md-ts-test-link-reference-definition-label-button ()
  "Reference definition labels should activate their destination."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search
       "[docs]: https://example.com/docs\n"
       "docs"))
    (should (equal opened "https://example.com/docs"))))

(ert-deftest md-ts-test-link-reference-definition-destination-face ()
  "Reference definition destinations should get string face."
  (should (md-ts-test--has-face
           "[docs]: https://example.com/docs\n"
           "https://example.com/docs" 'font-lock-string-face)))

(ert-deftest md-ts-test-link-uri-autolink-button ()
  "URI autolinks should activate the inner target, not angle brackets."
  (let ((text "Visit <https://example.com> now.\n")
        opened)
    (should (equal (md-ts-test--help-echo-at-search text "https://example.com")
                   "https://example.com"))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search text "https://example.com"))
    (should (equal opened "https://example.com"))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "<")
            (should-not (button-at (match-beginning 0)))
            (search-forward "https://example.com")
            (should (button-at (match-beginning 0)))
            (search-forward ">")
            (should-not (button-at (match-beginning 0))))
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-email-autolink-button ()
  "Email autolinks should activate through a mailto URL."
  (let ((text "Email <person@example.com> please.\n")
        mailed)
    (should (equal (md-ts-test--help-echo-at-search text "person@example.com")
                   "mailto:person@example.com"))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for email autolink"))))
      (md-ts-test--push-button-at-search text "person@example.com"))
    (should (equal mailed '("mailto" "person@example.com")))))

(ert-deftest md-ts-test-link-bare-url-button ()
  "Bare URLs in prose should be static buttons using `browse-url'."
  (let ((text "Visit https://example.com/path now.\n")
        opened)
    (should (md-ts-test--has-face text "https://example.com/path" 'link))
    (should (equal (md-ts-test--help-echo-at-search
                    text "https://example.com/path")
                   "https://example.com/path"))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search text "https://example.com/path"))
    (should (equal opened "https://example.com/path"))))

(ert-deftest md-ts-test-link-bare-email-button ()
  "Bare email addresses in prose should activate through mailto."
  (let ((text "Email person@example.com please.\n")
        mailed)
    (should (md-ts-test--has-face text "person@example.com" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "person@example.com")
                   "mailto:person@example.com"))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare email"))))
      (md-ts-test--push-button-at-search text "person@example.com"))
    (should (equal mailed '("mailto" "person@example.com")))))

(ert-deftest md-ts-test-link-bare-mailto-uri-button ()
  "Bare mailto URIs should activate with query strings intact."
  (let ((text "Contact mailto:me@example.com?subject=Hi now.\n")
        mailed)
    (should (md-ts-test--has-face
             text "mailto:me@example.com?subject=Hi" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   "mailto:me@example.com?subject=Hi"))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "mailto:me@example.com?subject=Hi")
            (let* ((uri-beg (match-beginning 0))
                   (uri-end (match-end 0))
                   (uri-button (button-at uri-beg)))
              (should uri-button)
              (should (equal (cons (button-start uri-button)
                                   (button-end uri-button))
                             (cons uri-beg uri-end)))
              (goto-char uri-beg)
              (search-forward "me@example.com")
              (let ((mail-button (button-at (match-beginning 0))))
                (should mail-button)
                (should (equal (cons (button-start mail-button)
                                     (button-end mail-button))
                               (cons uri-beg uri-end)))
                (should (equal (button-get mail-button
                                           'md-ts-link-static-target)
                               "mailto:me@example.com?subject=Hi")))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal mailed '("mailto" "me@example.com?subject=Hi")))))

(ert-deftest md-ts-test-link-bare-mailto-uri-query-only ()
  "Bare mailto URIs may omit recipients when a query is present."
  (let ((text "Contact mailto:?subject=Hi now.\n")
        mailed)
    (should (md-ts-test--has-face text "mailto:?subject=Hi" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   "mailto:?subject=Hi"))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url))))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal mailed '("mailto" "?subject=Hi")))))

(ert-deftest md-ts-test-link-bare-mailto-uri-empty-query-punctuation ()
  "Bare mailto URIs should trim a prose question mark without query content."
  (let ((text "Contact mailto:me@example.com?\n")
        mailed)
    (should (md-ts-test--has-face text "mailto:me@example.com" 'link))
    (should-not (md-ts-test--has-face text "?" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   "mailto:me@example.com"))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "mailto:me@example.com")
            (let* ((uri-beg (match-beginning 0))
                   (uri-end (match-end 0))
                   (uri-button (button-at uri-beg)))
              (should uri-button)
              (should (equal (cons (button-start uri-button)
                                   (button-end uri-button))
                             (cons uri-beg uri-end)))
              (should-not (button-at uri-end))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal mailed '("mailto" "me@example.com")))
    (setq mailed nil)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
    (should (equal mailed '("mailto" "me@example.com")))))

(ert-deftest md-ts-test-link-bare-mailto-uri-query-terminal-punctuation ()
  "Bare mailto query values should keep valid terminal punctuation."
  (dolist (punct '("!" "?" ":" ";"))
    (let* ((target (format "mailto:me@example.com?subject=Hi%s" punct))
           (text (format "Contact %s now.\n" target))
           mailed)
      (should (md-ts-test--has-face text target 'link))
      (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                     target))
      (cl-letf (((symbol-function 'url-mailto)
                 (lambda (parsed-url)
                   (setq mailed (list (url-type parsed-url)
                                      (url-filename parsed-url)))))
                ((symbol-function 'browse-url)
                 (lambda (&rest _args)
                   (ert-fail "browse-url called for bare mailto URI"))))
        (md-ts-test--push-button-at-search text "mailto:"))
      (should (equal mailed
                     (list "mailto" (substring target (length "mailto:")))))
      (setq mailed nil)
      (cl-letf (((symbol-function 'url-mailto)
                 (lambda (parsed-url)
                   (setq mailed (list (url-type parsed-url)
                                      (url-filename parsed-url)))))
                ((symbol-function 'browse-url)
                 (lambda (&rest _args)
                   (ert-fail "browse-url called for bare mailto URI"))))
        (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
      (should (equal mailed
                     (list "mailto" (substring target (length "mailto:"))))))))

(ert-deftest md-ts-test-link-bare-mailto-uri-multiple-recipients ()
  "Bare mailto URIs should keep comma-separated recipients and query."
  (let ((text "Contact mailto:me@example.com,you@example.com?subject=Hi now.\n")
        mailed)
    (should (md-ts-test--has-face
             text "mailto:me@example.com,you@example.com?subject=Hi" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   "mailto:me@example.com,you@example.com?subject=Hi"))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url))))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal mailed '("mailto" "me@example.com,you@example.com?subject=Hi")))))

(ert-deftest md-ts-test-link-bare-mailto-uri-not-inside-scheme-token ()
  "Explicit mailto URIs should not start inside scheme-like tokens."
  (let ((text "Custom x-mailto:me@example.com?subject=Hi now.\n")
        mailed)
    (should-not (md-ts-test--has-face text "mailto:" 'link))
    (should-not (md-ts-test--button-at-search text "mailto:"))
    (should-not (md-ts-test--help-echo-at-search text "mailto:"))
    (should (md-ts-test--has-face text "me@example.com" 'link))
    (should (equal (md-ts-test--help-echo-at-search text "me@example.com")
                   "mailto:me@example.com"))
    (should-error (md-ts-test--open-link-at-search-no-fontify text "mailto:")
                  :type 'user-error)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url))))))
      (md-ts-test--push-button-at-search text "me@example.com"))
    (should (equal mailed '("mailto" "me@example.com"))))
  (let ((text "Custom foo:mailto:me@example.com?subject=Hi now.\n"))
    (should-not (md-ts-test--has-face text "mailto:" 'link))
    (should-not (md-ts-test--button-at-search text "mailto:"))
    (should-not (md-ts-test--help-echo-at-search text "mailto:"))
    (should-not (md-ts-test--has-face text "me@example.com" 'link))
    (should-not (md-ts-test--button-at-search text "me@example.com"))
    (should-not (md-ts-test--help-echo-at-search text "me@example.com"))
    (should-error (md-ts-test--open-link-at-search-no-fontify text "mailto:")
                  :type 'user-error)
    (should-error (md-ts-test--open-link-at-search-no-fontify text "me@example.com")
                  :type 'user-error))
  (let* ((target "urn:mailto:me@example.com?subject=Hi")
         (mailto-target "mailto:me@example.com?subject=Hi")
         (text (format "Custom %s now.\n" target))
         opened)
    (should (md-ts-test--has-face text target 'link))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   target))
    (should (equal (md-ts-test--help-echo-at-search text "me@example.com")
                   target))
    (should-not (equal (md-ts-test--help-echo-at-search text "mailto:")
                       mailto-target))
    (should-not (equal (md-ts-test--help-echo-at-search text "me@example.com")
                       "mailto:me@example.com"))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for mailto inside urn"))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal opened target))
    (setq opened nil)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for mailto inside urn"))))
      (md-ts-test--push-button-at-search text "me@example.com"))
    (should (equal opened target))
    (setq opened nil)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for mailto inside urn"))))
      (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
    (should (equal opened target))
    (setq opened nil)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for mailto inside urn"))))
      (md-ts-test--open-link-at-search-no-fontify text "me@example.com"))
    (should (equal opened target))))

(ert-deftest md-ts-test-link-bare-mailto-query-url-owned-by-mailto ()
  "Explicit mailto URIs should own URL-looking query text."
  (let* ((target "mailto:?body=https://example.com")
         (text (format "Contact %s now.\n" target))
         mailed)
    (should (md-ts-test--has-face text target 'link))
    (should (equal (md-ts-test--help-echo-at-search text "https://example.com")
                   target))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward target)
            (let ((target-beg (match-beginning 0))
                  (target-end (match-end 0)))
              (goto-char target-beg)
              (search-forward "https://example.com")
              (let ((button (button-at (match-beginning 0))))
                (should button)
                (should (equal (cons (button-start button)
                                     (button-end button))
                               (cons target-beg target-end))))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for mailto query URL"))))
      (md-ts-test--push-button-at-search text "https://example.com"))
    (should (equal mailed '("mailto" "?body=https://example.com")))
    (setq mailed nil)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for mailto query URL"))))
      (md-ts-test--open-link-at-search-no-fontify text "https://example.com"))
    (should (equal mailed '("mailto" "?body=https://example.com")))))

(ert-deftest md-ts-test-link-bare-mailto-query-scheme-owned-by-mailto ()
  "Explicit mailto URIs should own scheme-looking query text."
  (let* ((target "mailto:me@example.com?subject=tel:123")
         (text (format "Contact %s now.\n" target))
         mailed)
    (should (md-ts-test--has-face text target 'link))
    (should (equal (md-ts-test--help-echo-at-search text "tel:123") target))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward target)
            (let ((target-beg (match-beginning 0))
                  (target-end (match-end 0)))
              (goto-char target-beg)
              (search-forward "tel:123")
              (let ((button (button-at (match-beginning 0))))
                (should button)
                (should (equal (cons (button-start button)
                                     (button-end button))
                               (cons target-beg target-end))))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for mailto query scheme"))))
      (md-ts-test--push-button-at-search text "tel:123"))
    (should (equal mailed '("mailto" "me@example.com?subject=tel:123")))
    (setq mailed nil)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for mailto query scheme"))))
      (md-ts-test--open-link-at-search-no-fontify text "tel:123"))
    (should (equal mailed '("mailto" "me@example.com?subject=tel:123")))))

(ert-deftest md-ts-test-link-bare-mailto-percent-recipient ()
  "Explicit mailto URIs should support percent escapes in recipients."
  (let* ((target "mailto:gorby%25kremvax@example.com")
         (text (format "Contact %s now.\n" target))
         mailed)
    (should (md-ts-test--has-face text target 'link))
    (should (equal (md-ts-test--help-echo-at-search text "kremvax@example.com")
                   target))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward target)
            (let ((target-beg (match-beginning 0))
                  (target-end (match-end 0)))
              (goto-char target-beg)
              (search-forward "kremvax@example.com")
              (let ((button (button-at (match-beginning 0))))
                (should button)
                (should (equal (cons (button-start button)
                                     (button-end button))
                               (cons target-beg target-end))))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for percent mailto"))))
      (md-ts-test--push-button-at-search text "kremvax@example.com"))
    (should (equal mailed '("mailto" "gorby%25kremvax@example.com")))
    (setq mailed nil)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for percent mailto"))))
      (md-ts-test--open-link-at-search-no-fontify text "kremvax@example.com"))
    (should (equal mailed '("mailto" "gorby%25kremvax@example.com")))))

(ert-deftest md-ts-test-link-bare-url-containing-mailto-uri-wins ()
  "Outer bare URLs should take precedence over embedded mailto: text."
  (let* ((target "https://example.com/mailto:me@example.com?subject=Hi")
         (text (format "Visit %s now.\n" target))
         opened)
    (should (md-ts-test--has-face text target 'link))
    (should (equal (md-ts-test--help-echo-at-search text target) target))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:") target))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward target)
            (let* ((target-beg (match-beginning 0))
                   (target-end (match-end 0))
                   (target-button (button-at target-beg)))
              (should target-button)
              (should (equal (cons (button-start target-button)
                                   (button-end target-button))
                             (cons target-beg target-end)))
              (goto-char target-beg)
              (search-forward "mailto:")
              (let ((mailto-button (button-at (match-beginning 0))))
                (should mailto-button)
                (should (equal (cons (button-start mailto-button)
                                     (button-end mailto-button))
                               (cons target-beg target-end)))
                (should (equal (button-get mailto-button
                                           'md-ts-link-static-target)
                               target)))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for embedded mailto text"))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal opened target))
    (setq opened nil)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url)))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for embedded mailto text"))))
      (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
    (should (equal opened target))))

(ert-deftest md-ts-test-link-bare-url-containing-mailto-terminal-punctuation-wins ()
  "Outer bare URLs should own embedded mailto text through terminal punctuation."
  (dolist (punct '("!" "?" ":" ";"))
    (let* ((raw (format "https://example.com/mailto:me@example.com?subject=Hi%s"
                        punct))
           ;; Bare URL normalization trims these terminal prose characters, but
           ;; containment should still cover the raw regexp match so the inner
           ;; mailto candidate cannot steal the click target.
           (target (substring raw 0 -1))
           (text (format "Visit %s now.\n" raw))
           opened)
      (ert-info ((format "checking terminal %S" punct))
        (should (md-ts-test--has-face text target 'link))
        (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                       target))
        (let ((buf (md-ts-test--fontify text)))
          (unwind-protect
              (with-current-buffer buf
                (goto-char (point-min))
                (search-forward target)
                (let* ((target-beg (match-beginning 0))
                       (target-end (match-end 0))
                       (target-button (button-at target-beg)))
                  (should target-button)
                  (should (equal (cons (button-start target-button)
                                       (button-end target-button))
                                 (cons target-beg target-end)))
                  (should-not (button-at target-end))
                  (goto-char target-beg)
                  (search-forward "mailto:")
                  (let ((mailto-button (button-at (match-beginning 0))))
                    (should mailto-button)
                    (should (equal (cons (button-start mailto-button)
                                         (button-end mailto-button))
                                   (cons target-beg target-end)))
                    (should (equal (button-get mailto-button
                                               'md-ts-link-static-target)
                                   target)))))
            (kill-buffer buf)))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url &rest _args)
                     (setq opened url)))
                  ((symbol-function 'url-mailto)
                   (lambda (&rest _args)
                     (ert-fail "url-mailto called for embedded mailto text"))))
          (md-ts-test--push-button-at-search text "mailto:"))
        (should (equal opened target))
        (setq opened nil)
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url &rest _args)
                     (setq opened url)))
                  ((symbol-function 'url-mailto)
                   (lambda (&rest _args)
                     (ert-fail "url-mailto called for embedded mailto text"))))
          (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
        (should (equal opened target))))))

(ert-deftest md-ts-test-link-bare-mailto-after-inline-link-destination ()
  "Inline-link destinations should not suppress following bare mailto URIs."
  (let ((text "See [x](https://x)mailto:a@example.com now.\n")
        opened
        mailed)
    (should (equal (md-ts-test--help-echo-at-search text "x") "https://x"))
    (should (equal (md-ts-test--help-echo-at-search text "mailto:")
                   "mailto:a@example.com"))
    (let ((buf (md-ts-test--fontify text)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "mailto:a@example.com")
            (let* ((mailto-beg (match-beginning 0))
                   (mailto-end (match-end 0))
                   (mailto-button (button-at mailto-beg)))
              (should mailto-button)
              (should (equal (cons (button-start mailto-button)
                                   (button-end mailto-button))
                             (cons mailto-beg mailto-end)))
              (goto-char mailto-beg)
              (search-forward "a@example.com")
              (let ((email-button (button-at (match-beginning 0))))
                (should email-button)
                (should (equal (cons (button-start email-button)
                                     (button-end email-button))
                               (cons mailto-beg mailto-end)))
                (should (equal (button-get email-button
                                           'md-ts-link-static-target)
                               "mailto:a@example.com")))))
        (kill-buffer buf)))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--push-button-at-search text "x"))
    (should (equal opened "https://x"))
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--push-button-at-search text "mailto:"))
    (should (equal mailed '("mailto" "a@example.com")))
    (setq mailed nil)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--open-link-at-search-no-fontify text "mailto:"))
    (should (equal mailed '("mailto" "a@example.com")))))

(ert-deftest md-ts-test-link-open-at-point-bare-mailto-uri ()
  "`md-ts-open-link-at-point' should open a bare mailto URI at its prefix."
  (let (mailed)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare mailto URI"))))
      (md-ts-test--open-link-at-search-no-fontify
       "Contact mailto:me@example.com?subject=Hi now.\n"
       "mailto:"))
    (should (equal mailed '("mailto" "me@example.com?subject=Hi")))))

(ert-deftest md-ts-test-link-bare-mailto-uses-cached-url-ranges ()
  "Explicit mailto containment checks should reuse generic URL ranges."
  (with-temp-buffer
    (let ((case-fold-search t))
      (insert (concat "Visit https://example.com/mailto:one@example.com "
                      "then https://second.example/a "
                      "or mailto:two@example.com now.\n"))
      (let* ((scan-beg (point-min))
             (scan-end (point-max))
             (ranges (md-ts--bare-link-generic-url-ranges scan-beg scan-end))
             (first-beg (progn
                          (goto-char scan-beg)
                          (search-forward "mailto:one")
                          (match-beginning 0)))
             (first-end (progn
                          (search-forward "@example.com")
                          (match-end 0)))
             (standalone-beg (progn
                               (search-forward "mailto:two")
                               (match-beginning 0)))
             (standalone-end (progn
                               (search-forward "@example.com")
                               (match-end 0))))
        (should (md-ts--bare-link-covered-by-earlier-url-p
                 first-beg first-end ranges))
        (should-not (md-ts--bare-link-covered-by-earlier-url-p
                     standalone-beg standalone-end ranges))
        (cl-letf (((symbol-function 're-search-forward)
                   (lambda (&rest args)
                     (ert-fail
                      (format "unexpected URL rescan: %S" args)))))
          (dotimes (_ 20)
            (should (md-ts--bare-link-covered-by-earlier-url-p
                     first-beg first-end ranges))
            (should-not (md-ts--bare-link-covered-by-earlier-url-p
                         standalone-beg standalone-end ranges))))))))

(ert-deftest md-ts-test-link-bare-mailto-long-line-url-scan-smoke ()
  "Many explicit mailto URIs should share one generic URL range cache."
  (let* ((count 64)
         (text (concat (mapconcat
                        (lambda (n)
                          (format "mailto:person%d@example.com?subject=Hi" n))
                        (number-sequence 1 count)
                        " ")
                       "\n"))
         (url-range-builds 0)
         (generic-url-ranges-original
          (symbol-function 'md-ts--bare-link-generic-url-ranges))
         buf)
    (unwind-protect
        (progn
          (setq buf (generate-new-buffer " *md-ts-test*"))
          (with-current-buffer buf
            (insert text)
            (md-ts-mode)
            (cl-letf (((symbol-function 'md-ts--bare-link-generic-url-ranges)
                       (lambda (&rest args)
                         (setq url-range-builds (1+ url-range-builds))
                         (apply generic-url-ranges-original args))))
              (md-ts--fontify-bare-links (point-min) (point-max)))
            (should (= url-range-builds 1))
            (dotimes (n count)
              (goto-char (point-min))
              (search-forward
               (format "mailto:person%d@example.com?subject=Hi" (1+ n)))
              (should (button-at (match-beginning 0))))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-mailto-invalid-long-candidate-smoke ()
  "Invalid long `mailto:' candidates should stay plain without regexp blowups."
  (with-temp-buffer
    (insert "mailto:" (make-string 400000 ?a))
    (goto-char (point-min))
    (should (re-search-forward md-ts--bare-mailto-uri-regexp nil t))
    (should (= (match-end 0)
               (+ (point-min) md-ts--bare-mailto-uri-prefix-length))))
  (let* ((tail (make-string 50000 ?a))
         (email "person@example.com")
         (text (concat "Contact mailto:" tail " " email "\n"))
         (normalized-count 0)
         (normalize-original
          (symbol-function 'md-ts--bare-mailto-uri-normalized-match))
         buf)
    (unwind-protect
        (progn
          (setq buf (generate-new-buffer " *md-ts-test*"))
          (with-current-buffer buf
            (insert text)
            (md-ts-mode)
            (cl-letf (((symbol-function 'md-ts--bare-mailto-uri-normalized-match)
                       (lambda (&rest args)
                         (setq normalized-count (1+ normalized-count))
                         (apply normalize-original args))))
              (md-ts--fontify-bare-links (point-min) (point-max)))
            (should (= normalized-count 0))
            (goto-char (point-min))
            (search-forward "mailto:")
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'md-ts-link-static-target))
              (should-not (get-text-property pos 'md-ts-bare-link-face))
              (should-not (md-ts--bare-link-target-at-point pos)))
            (search-forward email)
            (let ((pos (match-beginning 0)))
              (should (button-at pos))
              (should (equal (get-text-property pos 'md-ts-link-static-target)
                             (concat "mailto:" email)))
              (should (equal (md-ts--bare-link-target-at-point pos)
                             (concat "mailto:" email))))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-email-scheme-mailto-long-line-cache ()
  "Many emails should share one scheme-prefixed mailto range cache."
  (let* ((count 64)
         (text (concat (mapconcat
                        (lambda (n)
                          (format (concat "foo:mailto:hidden%d@example.com?subject=Hi "
                                          "visible%d@example.net")
                                  n n))
                        (number-sequence 1 count)
                        " ")
                       "\n"))
         (scheme-range-builds 0)
         (scheme-ranges-original
          (symbol-function 'md-ts--bare-scheme-mailto-uri-ranges))
         (search-backward-original (symbol-function 'search-backward))
         buf)
    (unwind-protect
        (progn
          (setq buf (generate-new-buffer " *md-ts-test*"))
          (with-current-buffer buf
            (insert text)
            (md-ts-mode)
            (cl-letf (((symbol-function 'md-ts--bare-scheme-mailto-uri-ranges)
                       (lambda (&rest args)
                         (setq scheme-range-builds (1+ scheme-range-builds))
                         (apply scheme-ranges-original args)))
                      ((symbol-function 'search-backward)
                       (lambda (string &optional bound noerror count)
                         (if (equal string "mailto:")
                             (ert-fail
                              (format "unexpected mailto backscan: %S"
                                      (list string bound noerror count)))
                           (funcall search-backward-original
                                    string bound noerror count)))))
              (md-ts--fontify-bare-links (point-min) (point-max)))
            (should (= scheme-range-builds 1))
            (dotimes (n count)
              (goto-char (point-min))
              (search-forward (format "hidden%d@example.com" (1+ n)))
              (should-not (button-at (match-beginning 0)))
              (goto-char (point-min))
              (search-forward (format "visible%d@example.net" (1+ n)))
              (should (button-at (match-beginning 0))))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-fontification-caches-unsafe-contexts ()
  "Bare link scans should not do point-node unsafe checks per candidate."
  (let* ((count 48)
         (text (concat
                (mapconcat
                 (lambda (n)
                   (format "Visit https://example%d.test/path and user%d@example.test."
                           n n))
                 (number-sequence 1 count)
                 "\n")
                "\nCode `https://unsafe.example/span` here.\n"
                "See [label](https://unsafe.example/parsed).\n"))
         (node-at-calls 0)
         (node-at-original
          (symbol-function 'md-ts--node-at-containing-position))
         buf)
    (unwind-protect
        (progn
          (setq buf (generate-new-buffer " *md-ts-test*"))
          (with-current-buffer buf
            (insert text)
            (md-ts-mode)
            (font-lock-ensure)
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max))
            (cl-letf (((symbol-function 'md-ts--node-at-containing-position)
                       (lambda (&rest args)
                         (setq node-at-calls (1+ node-at-calls))
                         (apply node-at-original args))))
              (md-ts--fontify-bare-links (point-min) (point-max)))
            (should (= node-at-calls 0))
            (dotimes (n count)
              (goto-char (point-min))
              (search-forward (format "https://example%d.test/path" (1+ n)))
              (should (button-at (match-beginning 0)))
              (search-forward (format "user%d@example.test" (1+ n)))
              (should (button-at (match-beginning 0))))
            (goto-char (point-min))
            (search-forward "https://unsafe.example/span")
            (should-not (button-at (match-beginning 0)))
            (should-not (get-text-property (match-beginning 0)
                                           'md-ts-link-static-target))
            (search-forward "https://unsafe.example/parsed")
            (should-not (button-at (match-beginning 0)))
            (should-not (get-text-property (match-beginning 0)
                                           'md-ts-link-static-target))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-url-trims-trailing-prose-punctuation ()
  "Bare URL buttons should not include prose punctuation or delimiters."
  (let ((buf (md-ts-test--fontify
              (concat "See (https://example.com/path), "
                      "https://example.com/a(b). "
                      "https://example.com/a)b(c) "
                      "https://example.com/(a)) "
                      "and https://example.com/a(b)).\n")))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'browse-url)
                     (lambda (url &rest _args)
                       (setq opened url))))
            (let ((search-start (point-min)))
              (dolist (target '("https://example.com/path"
                                "https://example.com/a(b)"
                                "https://example.com/a)b(c)"
                                "https://example.com/(a)"
                                "https://example.com/a(b)"))
                (goto-char search-start)
                (search-forward target)
                (let ((pos (match-beginning 0))
                      (end (match-end 0)))
                  (setq search-start end
                        opened nil)
                  (let ((button (button-at pos)))
                    (should button)
                    (should (equal (get-text-property pos 'help-echo) target))
                    (should (equal (cons (button-start button)
                                         (button-end button))
                                   (cons pos end))))
                  (push-button pos)
                  (should (equal opened target)))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-normalized-match-long-trailing-run ()
  "Bare URL normalization should trim long trailing runs without rescans."
  (with-temp-buffer
    (let* ((target "https://example.com/a(b)")
           (tail (mapconcat #'identity (make-list 512 ")]}>.,;:!?") ""))
           (substring-calls 0)
           (buffer-substring-original
            (symbol-function 'buffer-substring-no-properties)))
      (insert target tail)
      (cl-letf (((symbol-function 'buffer-substring-no-properties)
                 (lambda (&rest args)
                   (setq substring-calls (1+ substring-calls))
                   (apply buffer-substring-original args))))
        (should (equal (md-ts--bare-link-normalized-match
                        (point-min) (point-max))
                       (list (point-min) (+ (point-min) (length target))
                             target))))
      (should (<= substring-calls 1)))))

(ert-deftest md-ts-test-link-open-at-point-bare-url ()
  "`md-ts-open-link-at-point' should open bare URL buttons."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search-no-fontify
       "Visit https://example.com/path now.\n"
       "https://example.com/path"))
    (should (equal opened "https://example.com/path"))))

(ert-deftest md-ts-test-link-open-at-point-bare-email ()
  "`md-ts-open-link-at-point' should open bare email buttons."
  (let (mailed)
    (cl-letf (((symbol-function 'url-mailto)
               (lambda (parsed-url)
                 (setq mailed (list (url-type parsed-url)
                                    (url-filename parsed-url)))))
              ((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for bare email"))))
      (md-ts-test--open-link-at-search-no-fontify
       "Email person@example.com please.\n"
       "person@example.com"))
    (should (equal mailed '("mailto" "person@example.com")))))

(ert-deftest md-ts-test-link-bare-skips-markdown-link-contexts ()
  "Bare scanners should not buttonize parsed link destinations/autolinks."
  (let ((buf (md-ts-test--fontify
              (concat "Visit [here](https://example.com/inline).\n"
                      "See <https://example.com/auto>.\n"
                      "Mail <person@example.com>.\n"
                      "\n[id]: https://example.com/ref\n"))))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/inline")
          (should-not (button-at (match-beginning 0)))
          (should-not (get-text-property (match-beginning 0)
                                         'md-ts-link-static-target))
          (search-forward "https://example.com/auto")
          (should (button-at (match-beginning 0)))
          (should-not (get-text-property (match-beginning 0)
                                         'md-ts-link-static-target))
          (search-forward "person@example.com")
          (should (button-at (match-beginning 0)))
          (should-not (get-text-property (match-beginning 0)
                                         'md-ts-link-static-target))
          (search-forward "https://example.com/ref")
          (should-not (button-at (match-beginning 0)))
          (should-not (get-text-property (match-beginning 0)
                                         'md-ts-link-static-target)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-skips-code-contexts ()
  "Bare scanners should not buttonize code spans or code blocks."
  (let ((text (concat "Code `https://example.com/span` here.\n"
                      "```\nhttps://example.com/fenced\n```\n"
                      "    https://example.com/indented\n")))
    (should-not (md-ts-test--button-at-search text "https://example.com/span"))
    (should-not (md-ts-test--button-at-search text "https://example.com/fenced"))
    (should-not (md-ts-test--button-at-search text "https://example.com/indented"))))

(ert-deftest md-ts-test-link-bare-html-policy ()
  "Bare scanners buttonize inline HTML text, not tags or HTML blocks."
  (let ((buf (md-ts-test--fontify
              (concat "<span>https://example.com/text</span>\n"
                      "<a href=\"https://example.com/attr\">label</a>\n"
                      "<!-- https://example.com/comment -->\n"
                      "<div>\nhttps://example.com/block\n</div>\n"))))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/text")
          (should (md-ts--link-button-p (button-at (match-beginning 0))))
          (search-forward "https://example.com/attr")
          (should-not (button-at (match-beginning 0)))
          (search-forward "https://example.com/comment")
          (should-not (button-at (match-beginning 0)))
          (search-forward "https://example.com/block")
          (should-not (button-at (match-beginning 0))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-url-prevents-nested-email-button ()
  "Email-looking text inside a bare URL should keep one URL button."
  (let ((buf (md-ts-test--fontify
              "Visit https://user@example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://user@example.com/path")
          (let* ((url-beg (match-beginning 0))
                 (url-end (match-end 0))
                 (url-button (button-at url-beg)))
            (should url-button)
            (should (equal (cons (button-start url-button)
                                 (button-end url-button))
                           (cons url-beg url-end)))
            (goto-char url-beg)
            (search-forward "user@example.com")
            (let ((mail-button (button-at (match-beginning 0))))
              (should mail-button)
              (should (equal (cons (button-start mail-button)
                                   (button-end mail-button))
                             (cons url-beg url-end)))
              (should (equal (button-get mail-button
                                         'md-ts-link-static-target)
                             "https://user@example.com/path")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-button-properties-clean-after-edit ()
  "Editing bare links into plain text should remove md-ts props."
  (let ((buf (md-ts-test--fontify
              "Visit https://example.com and email person@example.com.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com")
          (should (button-at (match-beginning 0)))
          (replace-match "example" t t)
          (search-forward "person@example.com")
          (should (button-at (match-beginning 0)))
          (replace-match "person" t t)
          (font-lock-flush)
          (font-lock-ensure)
          (dolist (search '("example" "person"))
            (goto-char (point-min))
            (search-forward search)
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (dolist (prop '(button category action help-echo keymap
                                     mouse-face follow-link
                                     md-ts-link-button md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property pos prop))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-partial-unfontify-cleans-url-tails ()
  "Partial unfontification inside a bare URL should clean full bare state."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let* ((url-beg (match-beginning 0))
                 (url-end (match-end 0))
                 (unfont-beg (+ url-beg 8))
                 (unfont-end (+ url-beg 15)))
            (should (button-at url-beg))
            (funcall font-lock-unfontify-region-function
                     unfont-beg unfont-end)
            (dolist (pos (number-sequence url-beg (1- url-end)))
              (let ((face (get-text-property pos 'face)))
                (should-not (if (listp face) (memq 'link face)
                              (eq face 'link))))
              (dolist (prop '(button category action help-echo keymap
                                     mouse-face follow-link
                                     md-ts-link-button md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property pos prop))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-foreign-button-survives-fontification ()
  "Bare-link fontification should preserve unrelated text buttons."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://example.com")
          (let ((pos (match-beginning 0)))
            (make-text-button pos (match-end 0)
                              'action (lambda (_button)
                                        (setq called t))
                              'help-echo "foreign")
            (font-lock-ensure)
            (let ((button (button-at pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))
              (should (equal (button-get button 'help-echo) "foreign"))
              (push-button pos)
              (should called))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-foreign-overlay-survives-fontification ()
  "Bare-link fontification should preserve unrelated overlay buttons."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://example.com")
          (let* ((pos (match-beginning 0))
                 (overlay (make-button pos (match-end 0)
                                       'action (lambda (_button)
                                                 (setq called t))
                                       'help-echo "overlay")))
            (font-lock-ensure)
            (should (eq (button-at pos) overlay))
            (should-not (md-ts--link-button-p overlay))
            (should-not (button-get overlay 'md-ts-link-static-target))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property pos prop)))
            (push-button pos)
            (should called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-categoryless-button-overlay-does-not-block-fontification ()
  "A category-less `button' overlay should not suppress bare link UI."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com now.\n")
          (goto-char (point-min))
          (search-forward "https://example.com")
          (let* ((pos (match-beginning 0))
                 (end (match-end 0))
                 (overlay (make-overlay pos end)))
            (overlay-put overlay 'button t)
            (overlay-put overlay 'help-echo "overlay help")
            (md-ts-mode)
            (font-lock-ensure)
            (should-not (overlay-get overlay 'category))
            (let ((button (button-at pos)))
              (should button)
              (should (markerp button))
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-foreign-overlap-suppresses-nested-links ()
  "Foreign-overlapped URLs should still suppress nested mailto/email UI."
  (dolist (case '(("https://example.com/mailto:me@example.com?subject=Hi"
                   "mailto:me@example.com?subject=Hi")
                  ("https://example.com/foo@example.org/path"
                   "foo@example.org")))
    (pcase-let ((`(,outer ,nested) case))
      (let ((buf (generate-new-buffer " *md-ts-test*"))
            opened)
        (unwind-protect
            (with-current-buffer buf
              (insert (format "Visit %s now.\n" outer))
              (md-ts-mode)
              (goto-char (point-min))
              (search-forward "example.com")
              (make-text-button (match-beginning 0) (match-end 0)
                                'action (lambda (_button)
                                          (ert-fail "foreign button activated"))
                                'help-echo "foreign")
              (font-lock-ensure)
              (goto-char (point-min))
              (search-forward nested)
              (let ((pos (match-beginning 0)))
                (should-not (button-at pos))
                (should-not (get-text-property pos 'md-ts-link-static-target))
                (should-not (get-text-property pos 'md-ts-bare-link-face))
                (cl-letf (((symbol-function 'browse-url)
                           (lambda (url &rest _args)
                             (setq opened url)))
                          ((symbol-function 'url-mailto)
                           (lambda (&rest _args)
                             (ert-fail "url-mailto called for nested link"))))
                  (goto-char pos)
                  (md-ts-open-link-at-point))
                (should (equal opened outer))))
          (kill-buffer buf))))))

(ert-deftest md-ts-test-link-bare-partial-fontification-starts-inside-url ()
  "Bare URL scanning should broaden from partial fontification regions."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "First https://one.example and second https://two.example/path.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://two.example/path")
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (funcall font-lock-fontify-region-function
                     (+ url-beg 8) (+ url-beg 16) nil)
            (let ((button (button-at url-beg)))
              (should button)
              (should (equal (cons (button-start button)
                                   (button-end button))
                             (cons url-beg url-end)))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://two.example/path"))))
          (goto-char (point-min))
          (search-forward "https://one.example")
          (let ((button (button-at (match-beginning 0))))
            (should button)
            (should (equal (button-get button 'md-ts-link-static-target)
                           "https://one.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-partial-fontification-fontifies-parsed-link-on-line ()
  "Partial bare URL fontification should fontify parsed links on the line."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (concat "See [label](https://parsed.example) and bare "
                          "https://bare.example/path.\n"))
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://bare.example/path")
          (let ((bare-beg (match-beginning 0)))
            (funcall font-lock-fontify-region-function
                     (+ bare-beg 8) (+ bare-beg 16) nil))
          (goto-char (point-min))
          (search-forward "label")
          (let* ((label-beg (match-beginning 0))
                 (button (button-at label-beg)))
            (should button)
            (should (md-ts--link-button-p button))
            (should-not (button-get button 'md-ts-link-static-target))
            (should (equal (get-text-property label-beg 'help-echo)
                           "https://parsed.example"))
            (let ((face (get-text-property label-beg 'face)))
              (should (if (listp face) (memq 'link face)
                        (eq face 'link)))))
          (search-forward "https://bare.example/path")
          (let ((button (button-at (match-beginning 0))))
            (should button)
            (should (equal (button-get button 'md-ts-link-static-target)
                           "https://bare.example/path"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-partial-fontification-expands-multiline-link ()
  "Partial bare URL fontification should report multi-line parsed-link writes."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (concat "[first\nsecond](https://parsed.example) and "
                          "https://bare.example/path.\n"))
          (md-ts-mode)
          (font-lock-ensure)
          (funcall font-lock-unfontify-region-function (point-min) (point-max))
          (goto-char (point-min))
          (search-forward "https://bare.example/path")
          (let* ((bare-beg (match-beginning 0))
                 (result (funcall font-lock-fontify-region-function
                                  (+ bare-beg 8) (+ bare-beg 16) nil))
                 (bounds (md-ts-test--jit-lock-bounds result))
                 (bound-beg (car bounds))
                 (bound-end (cdr bounds)))
            (goto-char (point-min))
            (search-forward "first")
            (let ((label-beg (match-beginning 0)))
              (should (<= bound-beg label-beg))
              (should (< label-beg bound-end))
              (should (md-ts--link-button-p (button-at label-beg))))
            (search-forward "second")
            (should (md-ts--link-button-p (button-at (match-beginning 0))))
            (should-not
             (md-ts-test--property-outside-region
              bound-beg bound-end
              '(face button category action help-echo mouse-face follow-link
                     md-ts-link-button md-ts-link-help-echo
                     md-ts-link-static-target invisible display)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-edit-destroyed-multiline-link-cleans-stale-button ()
  "Edits that destroy old multi-line links should return cleanup bounds."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "[first\nsecond](https://parsed.example)\n")
          (md-ts-mode)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "second")
          (let ((second-marker (copy-marker (match-beginning 0))))
            (should (md-ts--link-button-p (button-at second-marker)))
            (goto-char (point-min))
            (delete-char 1)
            (let* ((second-beg (marker-position second-marker))
                   (result (funcall font-lock-fontify-region-function
                                    (point-min) (1+ (point-min)) nil))
                   (bounds (md-ts-test--jit-lock-bounds result))
                   (bound-beg (car bounds))
                   (bound-end (cdr bounds)))
              (should (<= bound-beg second-beg))
              (should (< second-beg bound-end))
              (should-not (md-ts--link-button-p (button-at second-beg)))
              (should-not
               (md-ts-test--property-outside-region
                bound-beg bound-end
                '(face button category action help-echo mouse-face follow-link
                       md-ts-link-button md-ts-link-help-echo
                       md-ts-link-static-target invisible display))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-line-start-refontification-preserves-later-url ()
  "Line-wide cleanup should reapply valid bare links outside BEG..END."
  (let ((buf (md-ts-test--fontify
              "Start https://one.example and later https://two.example/path.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (insert "!")
          (funcall font-lock-fontify-region-function
                   (point-min) (1+ (point-min)) nil)
          (goto-char (point-min))
          (search-forward "https://two.example/path")
          (let ((button (button-at (match-beginning 0))))
            (should button)
            (should (equal (button-get button 'md-ts-link-static-target)
                           "https://two.example/path"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-partial-fontification-starts-inside-email ()
  "Bare email scanning should broaden from partial fontification regions."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Email person@example.com please.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "person@example.com")
          (let ((mail-beg (match-beginning 0))
                (mail-end (match-end 0)))
            (funcall font-lock-fontify-region-function
                     (+ mail-beg 3) (+ mail-beg 10) nil)
            (let ((button (button-at mail-beg)))
              (should button)
              (should (equal (cons (button-start button)
                                   (button-end button))
                             (cons mail-beg mail-end)))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "mailto:person@example.com")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-fontify-region-returns-line-bounds ()
  "Bare line scanning should report the physical line it fontified."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "intro\nVisit https://example.com/path now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let* ((url-beg (match-beginning 0))
                 (url-end (match-end 0))
                 (line-beg (line-beginning-position))
                 (fontify-end (1+ (line-end-position)))
                 called
                 result)
            (cl-letf (((symbol-function 'treesit-font-lock-fontify-region)
                       (lambda (tree-beg tree-end &optional _loudly)
                         (setq called (cons tree-beg tree-end))
                         `(jit-lock-bounds ,(point-min) . ,url-beg))))
              (setq result (funcall font-lock-fontify-region-function
                                    (+ url-beg 8) (+ url-beg 15) nil)))
            (should (equal called (cons line-beg fontify-end)))
            (should (equal result `(jit-lock-bounds ,line-beg . ,fontify-end)))
            (let ((button (button-at url-beg)))
              (should button)
              (should (equal (cons (button-start button)
                                   (button-end button))
                             (cons url-beg url-end)))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-fontify-region-does-not-claim-tree-widening ()
  "The wrapper should not return bounds tree-sitter widened on its own."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://widened.example/path now.\nOriginal region here.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (forward-line 1)
          (let* ((original-beg (point))
                 (original-end (+ (point) 8))
                 (line-beg (line-beginning-position))
                 (fontify-end (1+ (line-end-position)))
                 result)
            (cl-letf (((symbol-function 'treesit-font-lock-fontify-region)
                       (lambda (_beg _end &optional _loudly)
                         `(jit-lock-bounds ,(point-min) . ,(point-max)))))
              (setq result (funcall font-lock-fontify-region-function
                                    original-beg original-end nil)))
            (should (equal result `(jit-lock-bounds ,line-beg . ,fontify-end)))
            (goto-char (point-min))
            (search-forward "https://widened.example/path")
            (should-not (button-at (match-beginning 0)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-fontification-is-silent ()
  "Bare URL/email fontification should not dirty clean buffers or undo."
  (dolist (text '("Visit https://example.com/path now.\n"
                  "Email person@example.com please.\n"))
    (let ((buf (generate-new-buffer " *md-ts-test*")))
      (unwind-protect
          (with-current-buffer buf
            (insert text)
            (md-ts-mode)
            (setq buffer-undo-list nil)
            (set-buffer-modified-p nil)
            (font-lock-ensure)
            (should-not (buffer-modified-p))
            (should (equal buffer-undo-list nil)))
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-fontification-is-silent-in-read-only-buffer ()
  "Bare link fontification should be silent in read-only buffers too."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com and email person@example.com.\n")
          (md-ts-mode)
          (setq buffer-undo-list nil)
          (set-buffer-modified-p nil)
          (setq buffer-read-only t)
          (font-lock-ensure)
          (should-not (buffer-modified-p))
          (should (equal buffer-undo-list nil))
          (goto-char (point-min))
          (search-forward "https://example.com")
          (should (button-at (match-beginning 0)))
          (search-forward "person@example.com")
          (should (button-at (match-beginning 0))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-read-only-unfontify-and-flush-is-safe ()
  "Read-only unfontify/flush should remove and restore bare buttons safely."
  (let ((buf (md-ts-test--fontify
              "Visit https://example.com and email person@example.com.\n")))
    (unwind-protect
        (with-current-buffer buf
          (setq buffer-undo-list nil)
          (set-buffer-modified-p nil)
          (setq buffer-read-only t)
          (should
           (condition-case nil
               (progn
                 (funcall font-lock-unfontify-region-function
                          (point-min) (point-max))
                 (font-lock-flush (point-min) (point-max))
                 (font-lock-ensure)
                 t)
             (buffer-read-only nil)))
          (goto-char (point-min))
          (search-forward "https://example.com")
          (should (button-at (match-beginning 0)))
          (search-forward "person@example.com")
          (should (button-at (match-beginning 0))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-indirect-setup-preserves-base-parsed-button ()
  "Indirect `md-ts-mode' setup should not strip base parsed link buttons."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect link-pos)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0))
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          ;; No explicit refontification: this catches setup-only cleanup of
          ;; shared text properties in the base buffer.
          (with-current-buffer indirect
            (md-ts-mode))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://example.com/doc")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-inherited-parsed-button-prefers-destination ()
  "Indirect parsed button activation should not open a URL-like label."
  (let ((base (md-ts-test--fontify
               (concat "See [https://label.example]"
                       "(https://destination.example) now.\n")))
        indirect link-pos opened)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://label.example")
            (setq link-pos (match-beginning 0))
            (let ((button (button-at link-pos)))
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (goto-char link-pos)
            (let ((button (button-at link-pos)))
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target)))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (push-button link-pos))
            (should (equal opened "https://destination.example"))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-foreign-overlay-preserves-base-parsed-button ()
  "Indirect foreign overlays should not strip base parsed link buttons."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect link-pos link-end opened overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (should (eq (button-at link-pos) overlay))
              (funcall font-lock-unfontify-region-function
                       (point-min) (point-max))
              (funcall font-lock-fontify-region-function
                       (point-min) (point-max) nil)
              (should (eq (button-at link-pos) overlay))))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url)))
                        ((symbol-function 'find-file)
                         (lambda (&rest _args)
                           (ert-fail "find-file called for URI link")))
                        ((symbol-function 'url-mailto)
                         (lambda (&rest _args)
                           (ert-fail "url-mailto called for URI link"))))
                (push-button link-pos))
              (should (equal opened "https://example.com/doc"))
              (should-not overlay-called))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-setup-preserves-base-button ()
  "Indirect `md-ts-mode' setup should not strip base bare link buttons."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect link-pos)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0))
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path"))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          ;; No explicit refontification: this catches setup-only cleanup of
          ;; shared text properties in the base buffer.
          (with-current-buffer indirect
            (md-ts-mode))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path"))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://example.com/path")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-foreign-overlay-preserves-base-button ()
  "Indirect foreign overlays should not strip base bare link buttons."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect link-pos link-end opened overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path"))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (should (eq (button-at link-pos) overlay))
              (funcall font-lock-unfontify-region-function
                       (point-min) (point-max))
              (funcall font-lock-fontify-region-function
                       (point-min) (point-max) nil)
              (should (eq (button-at link-pos) overlay))))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path"))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url)))
                        ((symbol-function 'find-file)
                         (lambda (&rest _args)
                           (ert-fail "find-file called for URI link")))
                        ((symbol-function 'url-mailto)
                         (lambda (&rest _args)
                           (ert-fail "url-mailto called for URI link"))))
                (push-button link-pos))
              (should (equal opened "https://example.com/path"))
              (should-not overlay-called))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-indirect-edit-clears-stale-managed-face ()
  "Editing Markdown in an indirect buffer should clear stale faces."
  (let ((base (md-ts-test--fontify "**bold**\n"))
        indirect)
    (unwind-protect
        (progn
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (goto-char (point-min))
            (search-forward "bold")
            (let ((face (get-text-property (match-beginning 0) 'face)))
              (should (or (eq face 'bold)
                          (and (listp face) (memq 'bold face)))))
            (goto-char (point-min))
            (delete-char 2)
            (search-forward "**")
            (delete-region (match-beginning 0) (match-end 0))
            (font-lock-ensure (point-min) (point-max))
            (goto-char (point-min))
            (search-forward "bold")
            (should-not (get-text-property (match-beginning 0) 'face))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-unfontify-preserves-base-parsed-button ()
  "Unfontifying an indirect buffer should not strip base parsed link buttons."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect link-pos opened)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max)))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://example.com/doc"))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url)))
                        ((symbol-function 'find-file)
                         (lambda (&rest _args)
                           (ert-fail "find-file called for URI link")))
                        ((symbol-function 'url-mailto)
                         (lambda (&rest _args)
                           (ert-fail "url-mailto called for URI link"))))
                (push-button link-pos))
              (should (equal opened "https://example.com/doc")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-unfontify-preserves-base-button ()
  "Unfontifying an indirect buffer should not strip base bare link buttons."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect link-pos opened)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max)))
          (with-current-buffer base
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path"))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://example.com/path"))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url)))
                        ((symbol-function 'find-file)
                         (lambda (&rest _args)
                           (ert-fail "find-file called for URI link")))
                        ((symbol-function 'url-mailto)
                         (lambda (&rest _args)
                           (ert-fail "url-mailto called for URI link"))))
                (push-button link-pos))
              (should (equal opened "https://example.com/path")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-mode-exit-cleans-parsed-link-button ()
  "Leaving `md-ts-mode' should remove parsed link button side effects."
  (let ((buf (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "Doc")
          (let ((pos (match-beginning 0)))
            (should (md-ts--link-button-p (button-at pos)))
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (should-not (button-at pos))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-exit-cleans-bare-link-button-read-only-narrowed ()
  "Mode-exit cleanup should remove bare buttons despite read-only/narrowing."
  (let ((buf (md-ts-test--fontify
              "Narrowed line only.\nVisit https://example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((pos (match-beginning 0)))
            (should (md-ts--link-button-p (button-at pos)))
            (should (get-text-property pos 'md-ts-bare-link-face))
            (goto-char (point-min))
            (narrow-to-region (line-beginning-position)
                              (line-end-position))
            (setq buffer-read-only t)
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (save-restriction
              (widen)
              (should-not (button-at pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target
                                     md-ts-bare-link-face))
                (should-not (get-text-property pos prop)))
              (should-not (md-ts--link-face-value-p
                           (get-text-property pos 'face))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-exit-cleans-display-properties ()
  "Leaving `md-ts-mode' should remove md-ts-owned display properties."
  (let ((buf (md-ts-test--fontify "- [ ] todo\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "[ ]")
          (let ((pos (match-beginning 0)))
            (should (equal (get-text-property pos 'display) "☐"))
            (should (equal (get-text-property pos 'md-ts-display) "☐"))
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (should-not (get-text-property pos 'display))
            (should-not (get-text-property pos 'md-ts-display))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-exit-cleans-invisible-markup ()
  "Leaving `md-ts-mode' should remove md-ts-owned invisible markup."
  (let* ((md-ts-hide-markup t)
         (buf (md-ts-test--fontify "**bold**\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "**")
          (let ((pos (match-beginning 0)))
            (should (md-ts--invisible-value-includes-p
                     (get-text-property pos 'invisible) 'md-ts--markup))
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (should-not (md-ts--invisible-value-includes-p
                         (get-text-property pos 'invisible)
                         'md-ts--markup))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-live-reload-backfills-legacy-cleanup-owner ()
  "Live reload should make existing derived md-ts buffers cleanup owners."
  (let ((buf (generate-new-buffer " *md-ts-test-live-reload-owner*"))
        parsed-pos)
    (unwind-protect
        (with-current-buffer buf
          (insert "See [Doc](https://example.com/doc) now.\n")
          (md-ts-test-derived-mode)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (setq parsed-pos (match-beginning 0))
          (should (md-ts--link-button-p (button-at parsed-pos)))
          (setq-local md-ts--side-effect-properties-owner nil)
          (md-ts--backfill-side-effect-properties-ownership)
          (should-not (md-ts--side-effect-properties-owner-p))
          (kill-local-variable 'md-ts--side-effect-properties-owner)
          (should-not (local-variable-p 'md-ts--side-effect-properties-owner
                                        (current-buffer)))
          (md-ts--backfill-side-effect-properties-ownership)
          (should (md-ts--side-effect-properties-owner-p))
          (fundamental-mode)
          (should (eq major-mode 'fundamental-mode))
          (should-not (button-at parsed-pos)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-exit-derived-cleans-link-buttons ()
  "Leaving a mode derived from `md-ts-mode' should clean link props."
  (let ((buf (generate-new-buffer " *md-ts-test-derived-exit*"))
        parsed-pos bare-pos)
    (unwind-protect
        (with-current-buffer buf
          (insert "See [Doc](https://example.com/doc) and https://example.com/path.\n")
          (md-ts-test-derived-mode)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "Doc")
          (setq parsed-pos (match-beginning 0))
          (search-forward "https://example.com/path")
          (setq bare-pos (match-beginning 0))
          (should (eq major-mode 'md-ts-test-derived-mode))
          (should (derived-mode-p 'md-ts-mode))
          (should (md-ts--link-button-p (button-at parsed-pos)))
          (should (md-ts--link-button-p (button-at bare-pos)))
          (fundamental-mode)
          (should (eq major-mode 'fundamental-mode))
          (should-not (button-at parsed-pos))
          (should-not (button-at bare-pos))
          (dolist (pos (list parsed-pos bare-pos))
            (dolist (prop '(button category action help-echo mouse-face
                                   follow-link md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property pos prop)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-exit-indirect-preserves-base-link-buttons ()
  "Indirect mode exit must not strip valid base-buffer link buttons."
  (let ((base (md-ts-test--fontify
               "See [Doc](https://example.com/doc) and https://example.com/path.\n"))
        indirect parsed-pos bare-pos)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq parsed-pos (match-beginning 0))
            (search-forward "https://example.com/path")
            (setq bare-pos (match-beginning 0))
            (should (md-ts--link-button-p (button-at parsed-pos)))
            (should (md-ts--link-button-p (button-at bare-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (fundamental-mode))
          (with-current-buffer base
            (let ((parsed-button (button-at parsed-pos))
                  (bare-button (button-at bare-pos)))
              (should (md-ts--link-button-p parsed-button))
              (should-not (button-get parsed-button
                                      'md-ts-link-static-target))
              (should (md-ts--link-button-p bare-button))
              (should (equal (button-get bare-button
                                         'md-ts-link-static-target)
                             "https://example.com/path")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-mode-exit-base-keeps-until-indirect-kill-cleans ()
  "Base mode exit should preserve indirect-owned props until last owner dies."
  (let ((base (md-ts-test--fontify
               "See [Doc](https://example.com/doc) and https://example.com/path.\n"))
        indirect parsed-pos bare-pos)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq parsed-pos (match-beginning 0))
            (search-forward "https://example.com/path")
            (setq bare-pos (match-beginning 0))
            (should (md-ts--link-button-p (button-at parsed-pos)))
            (should (md-ts--link-button-p (button-at bare-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode))
          (with-current-buffer base
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (should (md-ts--link-button-p (button-at parsed-pos)))
            (should (md-ts--link-button-p (button-at bare-pos))))
          (kill-buffer indirect)
          (setq indirect nil)
          (with-current-buffer base
            (should-not (button-at parsed-pos))
            (should-not (button-at bare-pos))
            (dolist (pos (list parsed-pos bare-pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-mode-exit-base-keeps-derived-indirect-owner ()
  "Base mode exit should preserve props for a derived indirect owner."
  (let ((base (md-ts-test--fontify
               "See [Doc](https://example.com/doc) and https://example.com/path.\n"))
        indirect parsed-pos bare-pos)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq parsed-pos (match-beginning 0))
            (search-forward "https://example.com/path")
            (setq bare-pos (match-beginning 0))
            (should (md-ts--link-button-p (button-at parsed-pos)))
            (should (md-ts--link-button-p (button-at bare-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-derived-indirect*" t))
          (with-current-buffer indirect
            (md-ts-test-derived-mode)
            (should (derived-mode-p 'md-ts-mode)))
          (with-current-buffer base
            (fundamental-mode)
            (should (eq major-mode 'fundamental-mode))
            (should (md-ts--link-button-p (button-at parsed-pos)))
            (should (md-ts--link-button-p (button-at bare-pos))))
          (kill-buffer indirect)
          (setq indirect nil)
          (with-current-buffer base
            (should-not (button-at parsed-pos))
            (should-not (button-at bare-pos))
            (dolist (pos (list parsed-pos bare-pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-parsed-narrowed-base-fontifies-and-opens ()
  "Indirect parsed links should fontify/open when the base is narrowed away."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect link-pos opened)
    (unwind-protect
        (progn
          (with-current-buffer base
            (insert "Base narrowed only.\n\nVisit [Label](https://target.example) now.\n")
            (md-ts-mode)
            (goto-char (point-min))
            (search-forward "Label")
            (setq link-pos (match-beginning 0))
            (goto-char (point-min))
            (narrow-to-region (line-beginning-position) (line-end-position))
            (should (> link-pos (point-max))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (widen)
            (md-ts-mode)
            (goto-char link-pos)
            (should-not (button-at link-pos))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button 'md-ts-link-static-target))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://target.example")))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url)))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for URI link")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for URI link"))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://target.example"))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-narrowed-base-fontifies-and-opens ()
  "Indirect bare links should fontify/open when the base is narrowed away."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect link-pos opened)
    (unwind-protect
        (progn
          (with-current-buffer base
            (insert "Base narrowed only.\n\nVisit https://target.example/path now.\n")
            (md-ts-mode)
            (goto-char (point-min))
            (search-forward "https://target.example/path")
            (setq link-pos (match-beginning 0))
            (goto-char (point-min))
            (narrow-to-region (line-beginning-position) (line-end-position))
            (should (> link-pos (point-max))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (widen)
            (md-ts-mode)
            (goto-char link-pos)
            (should-not (button-at link-pos))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (let ((button (button-at link-pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://target.example/path"))
              (should (get-text-property link-pos 'md-ts-bare-link-face))
              (should (equal (get-text-property link-pos 'help-echo)
                             "https://target.example/path")))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url)))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for URI link")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for URI link"))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://target.example/path"))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-base-foreign-overlay-keeps-parsed-props-clean ()
  "Indirect refontification should respect base-origin parsed-link overlays."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (font-lock-flush (point-min) (point-max))
              (font-lock-ensure)
              (should (eq (button-at link-pos) overlay))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property link-pos prop)))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (should-not overlay-called)
            (let ((button (button-at link-pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should (equal (button-get button 'help-echo) "overlay")))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property link-pos prop)))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-late-base-foreign-overlay-keeps-parsed-props-clean ()
  "Indirect refontification should respect base overlays added later."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode))
          (with-current-buffer base
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (font-lock-flush (point-min) (point-max))
              (font-lock-ensure)
              (should (eq (button-at link-pos) overlay))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property link-pos prop)))))
          (with-current-buffer indirect
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (should-not overlay-called)
            (let ((button (button-at link-pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should (equal (button-get button 'help-echo) "overlay")))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property link-pos prop)))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-late-narrowed-base-foreign-overlay-keeps-parsed-props-clean ()
  "Indirect refontification should see late base overlays outside narrowing."
  (let ((base (md-ts-test--fontify "Base only.\n\nSee [Doc](https://example.com/doc) now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (widen)
            (md-ts-mode))
          (with-current-buffer base
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (save-restriction
                (widen)
                (font-lock-flush (point-min) (point-max))
                (font-lock-ensure)
                (should (eq (button-at link-pos) overlay))
                (dolist (prop '(button category action help-echo
                                       md-ts-link-button
                                       md-ts-link-help-echo
                                       md-ts-link-static-target))
                  (should-not (get-text-property link-pos prop))))
              (goto-char (point-min))
              (narrow-to-region (line-beginning-position) (line-end-position))
              (should (> link-pos (point-max)))))
          (with-current-buffer indirect
            (widen)
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (save-restriction
              (widen)
              (should-not overlay-called)
              (let ((button (button-at link-pos)))
                (should button)
                (should-not (md-ts--link-button-p button))
                (should (equal (button-get button 'help-echo) "overlay")))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property link-pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-base-foreign-overlay-keeps-props-clean ()
  "Indirect refontification should respect base-origin bare-link overlays."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (font-lock-flush (point-min) (point-max))
              (font-lock-ensure)
              (should (eq (button-at link-pos) overlay))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property link-pos prop)))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (should-not overlay-called)
            (let ((button (button-at link-pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should (equal (button-get button 'help-echo) "overlay")))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target))
              (should-not (get-text-property link-pos prop)))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-late-base-foreign-overlay-keeps-props-clean ()
  "Indirect bare refontification should respect base overlays added later."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode))
          (with-current-buffer base
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (font-lock-flush (point-min) (point-max))
              (font-lock-ensure)
              (should (eq (button-at link-pos) overlay))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target
                                     md-ts-bare-link-face))
                (should-not (get-text-property link-pos prop)))))
          (with-current-buffer indirect
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (should-not overlay-called)
            (let ((button (button-at link-pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should (equal (button-get button 'help-echo) "overlay")))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo
                                   md-ts-link-static-target
                                   md-ts-bare-link-face))
              (should-not (get-text-property link-pos prop)))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-late-narrowed-base-foreign-overlay-keeps-props-clean ()
  "Indirect bare refontification should see late base overlays outside narrowing."
  (let ((base (md-ts-test--fontify
               "Base only.\n\nVisit https://example.com/path now.\n"))
        indirect link-pos link-end overlay-called)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (setq link-pos (match-beginning 0)
                  link-end (match-end 0))
            (should (md-ts--link-button-p (button-at link-pos))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (widen)
            (md-ts-mode))
          (with-current-buffer base
            (let ((overlay (make-button link-pos link-end
                                        'action (lambda (_button)
                                                  (setq overlay-called t))
                                        'help-echo "overlay")))
              (save-restriction
                (widen)
                (font-lock-flush (point-min) (point-max))
                (font-lock-ensure)
                (should (eq (button-at link-pos) overlay))
                (dolist (prop '(button category action help-echo
                                       md-ts-link-button
                                       md-ts-link-help-echo
                                       md-ts-link-static-target
                                       md-ts-bare-link-face))
                  (should-not (get-text-property link-pos prop))))
              (goto-char (point-min))
              (narrow-to-region (line-beginning-position) (line-end-position))
              (should (> link-pos (point-max)))))
          (with-current-buffer indirect
            (widen)
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (save-restriction
              (widen)
              (should-not overlay-called)
              (let ((button (button-at link-pos)))
                (should button)
                (should-not (md-ts--link-button-p button))
                (should (equal (button-get button 'help-echo) "overlay")))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target
                                     md-ts-bare-link-face))
                (should-not (get-text-property link-pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-fontification-recreates-base-button ()
  "Fontifying an indirect buffer should not leave base bare buttons deleted."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect)
    (unwind-protect
        (progn
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max))
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (let ((button (button-at (match-beginning 0))))
              (should button)
              (should (md-ts--link-button-p button))
              (should (equal (button-get button 'md-ts-link-static-target)
                             "https://example.com/path")))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-kill-does-not-break-base-fontify ()
  "Killing an indirect md-ts buffer should not break base fontification."
  (let ((base (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        indirect)
    (unwind-protect
        (progn
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (font-lock-ensure))
          (kill-buffer indirect)
          (setq indirect nil)
          (with-current-buffer base
            (should-not
             (condition-case err
                 (progn
                   (funcall font-lock-fontify-region-function
                            (point-min) (point-max) nil)
                   nil)
               (error err)))
            (goto-char (point-min))
            (search-forward "https://example.com/path")
            (should (md-ts--link-button-p (button-at (match-beginning 0))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-root-nodes-ignore-bad-parsers ()
  "Root collection should ignore and delete parser objects that error."
  (let (deleted)
    (cl-letf (((symbol-function 'treesit-local-parsers-on)
               (lambda (&rest _args) '(bad-parser)))
              ((symbol-function 'md-ts--parser-list)
               (lambda (&rest _args) nil))
              ((symbol-function 'treesit-parser-language)
               (lambda (parser)
                 (if (eq parser 'bad-parser)
                     (error "deleted parser")
                   'markdown)))
              ((symbol-function 'treesit-parser-delete)
               (lambda (parser)
                 (push parser deleted))))
      (should-not (md-ts--font-lock-root-nodes (point-min) (point-max)
                                               'markdown))
      (should (equal deleted '(bad-parser))))))

(ert-deftest md-ts-test-link-indirect-edit-cleans-stale-single-line-parsed-link ()
  "Indirect single-line edits should clear stale parsed-link UI."
  (let ((base (md-ts-test--fontify "See [Doc](https://example.com/doc) now.\n"))
        indirect doc-marker)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq doc-marker (copy-marker (match-beginning 0)))
            (should (md-ts--link-button-p (button-at doc-marker)))
            (should (equal (get-text-property doc-marker 'help-echo)
                           "https://example.com/doc")))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (goto-char (1- (marker-position doc-marker)))
            (should (looking-at-p "\\["))
            (delete-char 1)
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil))
          (with-current-buffer base
            (let ((doc-pos (marker-position doc-marker)))
              (should (equal (buffer-substring-no-properties
                              doc-pos (+ doc-pos 3))
                             "Doc"))
              (should-not (button-at doc-pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property doc-pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-edit-cleans-stale-parsed-link-after-clean-region ()
  "Indirect edits should clean parsed-link UI after unrelated fontification."
  (let ((base (md-ts-test--fontify
               "Clean line before.\nSee [Doc](https://example.com/doc) now.\n"))
        indirect doc-marker)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq doc-marker (copy-marker (match-beginning 0)))
            (should (md-ts--link-button-p (button-at doc-marker)))
            (should (equal (get-text-property doc-marker 'help-echo)
                           "https://example.com/doc")))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (goto-char (1- (marker-position doc-marker)))
            (delete-char 1)
            (goto-char (point-min))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (goto-char (marker-position doc-marker))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil))
          (with-current-buffer base
            (let ((doc-pos (marker-position doc-marker)))
              (should-not (button-at doc-pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property doc-pos prop))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-indirect-non-md-edit-cleans-stale-parsed-link ()
  "Non-md indirect edits should still dirty stale parsed-link UI."
  (let ((base (md-ts-test--fontify
               "Clean line.\nSee [Doc](https://example.com/doc) now.\n"))
        viewer editor doc-marker)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "Doc")
            (setq doc-marker (copy-marker (match-beginning 0)))
            (should (md-ts--link-button-p (button-at doc-marker)))
            (should (equal (get-text-property doc-marker 'help-echo)
                           "https://example.com/doc")))
          (setq viewer (make-indirect-buffer base " *md-ts-viewer*" nil))
          (with-current-buffer viewer
            (md-ts-mode))
          (setq editor (make-indirect-buffer base " *md-ts-editor*" nil))
          (with-current-buffer editor
            (fundamental-mode)
            (should-not
             (memq #'md-ts--font-lock-record-dirty-side-effect-bounds
                   before-change-functions))
            (goto-char (point-min))
            (search-forward "[")
            (delete-char -1))
          (with-current-buffer viewer
            (goto-char (point-min))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (goto-char (marker-position doc-marker))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil))
          (with-current-buffer base
            (let ((doc-pos (marker-position doc-marker)))
              (should (equal (buffer-substring-no-properties
                              doc-pos (+ doc-pos 3))
                             "Doc"))
              (should-not (button-at doc-pos))
              (dolist (prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target))
                (should-not (get-text-property doc-pos prop))))))
      (when (buffer-live-p editor)
        (kill-buffer editor))
      (when (buffer-live-p viewer)
        (kill-buffer viewer))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-indirect-edit-base-cleans-stale-multiline-link ()
  "Stale multiline bounds recorded in an indirect buffer are shared."
  (let ((base (md-ts-test--fontify "[first\nsecond](https://parsed.example)\n"))
        indirect)
    (unwind-protect
        (progn
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (font-lock-ensure)
            (goto-char (point-min))
            (delete-char 1))
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "second")
            (let ((second-beg (match-beginning 0)))
              (should (md-ts--link-button-p (button-at second-beg)))
              (let* ((result (funcall font-lock-fontify-region-function
                                      (point-min) (1+ (point-min)) nil))
                     (bounds (md-ts-test--jit-lock-bounds result)))
                (should (<= (car bounds) second-beg))
                (should (< second-beg (cdr bounds)))
                (should-not (md-ts--link-button-p
                             (button-at second-beg)))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-side-effect-property-span-starts-at-prop ()
  "Side-effect span lookup should not expand to point-min at prop starts."
  (with-temp-buffer
    (insert "prefix\nlinked text\n")
    (let ((beg (progn
                 (goto-char (point-min))
                 (search-forward "linked")
                 (match-beginning 0)))
          (end (match-end 0)))
      (put-text-property beg end 'md-ts-link-static-target "target")
      (should (equal (md-ts--font-lock-side-effect-property-span beg)
                     (cons beg end))))))

(ert-deftest md-ts-test-link-bare-cleanup-preserves-foreign-link-face ()
  "Bare cleanup should not remove pre-existing foreign `link' faces."
  (let ((buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com/path now.\n")
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (add-face-text-property url-beg url-end 'link)
            (md-ts--make-link-button url-beg url-end
                                     "https://example.com/path" nil
                                     "https://example.com/path")
            (should (button-at url-beg))
            (should-not (get-text-property url-beg 'md-ts-bare-link-face))
            (md-ts--remove-bare-link-button-properties url-beg url-end)
            (should-not (button-at url-beg))
            (should (md-ts--link-face-value-p
                     (get-text-property url-beg 'face)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-cleanup-preserves-later-foreign-link-face ()
  "Bare cleanup should not remove a later foreign `link' face addition."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (get-text-property url-beg 'md-ts-bare-link-face))
            (put-text-property url-beg url-end 'face '(link underline))
            (md-ts--remove-bare-link-button-properties url-beg url-end)
            (should-not (button-at url-beg))
            (should-not (get-text-property url-beg 'md-ts-bare-link-face))
            (should (md-ts--link-face-value-p
                     (get-text-property url-beg 'face)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-cleanup-removes-owned-face-with-later-face ()
  "Bare cleanup should remove only its face after foreign face additions."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (get-text-property url-beg 'md-ts-bare-link-face))
            (add-face-text-property url-beg url-end 'underline t)
            (md-ts--remove-bare-link-button-properties url-beg url-end)
            (should-not (button-at url-beg))
            (should-not (get-text-property url-beg 'md-ts-bare-link-face))
            (let ((face (get-text-property url-beg 'face)))
              (should (if (listp face) (memq 'underline face)
                        (eq face 'underline)))
              (should-not (md-ts--link-face-value-p face)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-narrowed-same-line-multi-url-refontify ()
  "Narrowed same-line cleanup should reapply all physical-line URLs."
  (let ((base (md-ts-test--fontify
               (concat "First https://one.example/path and "
                       "second https://two.example/path.\n")))
        indirect one-beg one-end)
    (unwind-protect
        (progn
          (with-current-buffer base
            (goto-char (point-min))
            (search-forward "https://one.example/path")
            (setq one-beg (match-beginning 0)
                  one-end (match-end 0))
            (save-restriction
              (narrow-to-region one-beg one-end)
              (md-ts--fontify-bare-links
               (+ one-beg 4) (+ one-beg 12)))
            (dolist (target '("https://one.example/path"
                              "https://two.example/path"))
              (goto-char (point-min))
              (search-forward target)
              (let ((button (button-at (match-beginning 0))))
                (should button)
                (should (equal (button-get button
                                           'md-ts-link-static-target)
                               target)))))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (md-ts-mode)
            (save-restriction
              (narrow-to-region one-beg one-end)
              (md-ts--fontify-bare-links
               (+ one-beg 5) (+ one-beg 13))))
          (with-current-buffer base
            (dolist (target '("https://one.example/path"
                              "https://two.example/path"))
              (goto-char (point-min))
              (search-forward target)
              (let ((button (button-at (match-beginning 0))))
                (should button)
                (should (equal (button-get button
                                           'md-ts-link-static-target)
                               target))))))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-link-bare-code-span-context-edit-cleans-stale-button ()
  "Wrapping an existing bare URL in code should remove stale bare props."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/path now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (button-at url-beg))
            (goto-char url-end)
            (insert "`")
            (goto-char url-beg)
            (insert "`")
            ;; Refontify only delimiter context; line-wide bare cleanup should
            ;; remove the old button even though the URL text is outside BEG..END.
            (funcall font-lock-fontify-region-function url-beg (1+ url-beg) nil)
            (search-forward "https://example.com/path")
            (let ((pos (match-beginning 0)))
              (should-not (button-at pos))
              (should-not (get-text-property pos 'md-ts-link-static-target))
              (should-not (get-text-property pos 'md-ts-link-help-echo)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-fence-context-edit-cleans-stale-button ()
  "Moving an existing bare URL into a fence should clear stale bare props."
  (let ((buf (md-ts-test--fontify "https://example.com/path\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (should (button-at (point)))
          (insert "```\n")
          (goto-char (point-max))
          (insert "```\n")
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'md-ts-link-static-target))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-fence-regional-context-edit-cleans-stale-button ()
  "Regional fence refontification should clear enclosed stale bare UI."
  (let ((buf (md-ts-test--fontify "https://example.com/path\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (should (button-at (point)))
          (insert "```\n")
          (goto-char (point-max))
          (insert "```\n")
          ;; Refontify only the changed delimiter line.  Expansion over the
          ;; new multi-line unsafe node should clean the URL line too.
          (goto-char (point-min))
          (funcall font-lock-fontify-region-function
                   (line-beginning-position) (line-end-position) nil)
          (search-forward "https://example.com/path")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'md-ts-link-static-target))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-html-regional-context-edit-cleans-stale-button ()
  "Regional HTML-block refontification should clear enclosed stale bare UI."
  (let ((buf (md-ts-test--fontify "https://example.com/path\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (should (button-at (point)))
          (insert "<div>\n")
          (goto-char (point-max))
          (insert "</div>\n")
          ;; Refontify only the changed opening tag line.  Expansion over the
          ;; new multi-line unsafe node should clean the URL line too.
          (goto-char (point-min))
          (funcall font-lock-fontify-region-function
                   (line-beginning-position) (line-end-position) nil)
          (search-forward "https://example.com/path")
          (let ((pos (match-beginning 0)))
            (should-not (button-at pos))
            (should-not (get-text-property pos 'md-ts-link-static-target))))
      (kill-buffer buf))))

(defun md-ts-test--fontify-line-at (pos)
  "Run md-ts fontification for the physical line containing POS."
  (save-excursion
    (goto-char pos)
    (funcall font-lock-fontify-region-function
             (line-beginning-position) (line-end-position) nil)))

(defun md-ts-test--assert-no-bare-button-at-search (target)
  "Assert TARGET has no stale md-ts bare-link behavior or properties."
  (goto-char (point-min))
  (search-forward target)
  (let ((pos (match-beginning 0)))
    (should-not (button-at pos))
    (should-not (get-text-property pos 'md-ts-link-static-target))
    (should-not (get-text-property pos 'md-ts-link-help-echo))
    (should-not (get-text-property pos 'md-ts-bare-link-face))
    (goto-char pos)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (&rest _args)
                 (ert-fail "browse-url called for unsafe bare link")))
              ((symbol-function 'find-file)
               (lambda (&rest _args)
                 (ert-fail "find-file called for unsafe bare link")))
              ((symbol-function 'url-mailto)
               (lambda (&rest _args)
                 (ert-fail "url-mailto called for unsafe bare link"))))
      (should-error (md-ts-open-link-at-point) :type 'user-error))))

(defun md-ts-test--assert-bare-button-opens-at-search (target)
  "Assert TARGET has a current bare-link button that opens TARGET."
  (goto-char (point-min))
  (search-forward target)
  (let* ((pos (match-beginning 0))
         (button (button-at pos))
         opened)
    (should button)
    (should (md-ts--link-button-p button))
    (should (equal (button-get button 'md-ts-link-static-target) target))
    (should (equal (get-text-property pos 'help-echo) target))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (push-button pos))
    (should (equal opened target))))

(ert-deftest md-ts-test-link-bare-unsafe-ranges-skip-front-matter-metadata ()
  "Bare links are prose-oriented and should skip front matter metadata."
  (dolist (case '(("YAML" . "---\nurl: https://meta.example/path\n---\n\nhttps://prose.example/path\n")
                  ("TOML" . "+++\nurl = \"https://meta.example/path\"\n+++\n\nhttps://prose.example/path\n")))
    (ert-info ((format "checking %s front matter" (car case)))
      (let ((buf (md-ts-test--fontify (cdr case))))
        (unwind-protect
            (with-current-buffer buf
              (md-ts-test--assert-no-bare-button-at-search
               "https://meta.example/path")
              (md-ts-test--assert-bare-button-opens-at-search
               "https://prose.example/path"))
          (kill-buffer buf))))))

(ert-deftest md-ts-test-link-bare-regional-context-edit-buttonizes-unsafe-to-prose ()
  "Boundary-only unsafe-to-prose edits should rescan old unsafe bodies."
  (dolist (case '(("fenced code" "```\nhttps://fence.example/path\n```\n"
                   "```" "x``" "https://fence.example/path")
                  ("HTML block" "<div>\nhttps://block.example/path\n</div>\n"
                   "<div>" "xdiv>" "https://block.example/path")
                  ("indented code" "    https://indent.example/path\n"
                   " " "x" "https://indent.example/path")
                  ("multiline code span" "`\nhttps://span.example/path\n`\n"
                   "`" "x" "https://span.example/path")
                  ("multiline HTML tag" "<tag\nhref=\"https://tag.example/path\">\n"
                   "<tag" "xtag" "https://tag.example/path")
                  ("YAML metadata" "---\nurl: https://yaml.example/path\n---\n\n"
                   "---" "xxx" "https://yaml.example/path")
                  ("TOML metadata" "+++\nurl = \"https://toml.example/path\"\n+++\n\n"
                   "+++" "xxx" "https://toml.example/path")))
    (pcase-let ((`(,label ,text ,search ,replacement ,target) case))
      (ert-info ((format "checking %s" label))
        (let ((buf (md-ts-test--fontify text)))
          (unwind-protect
              (with-current-buffer buf
                (md-ts-test--assert-no-bare-button-at-search target)
                (goto-char (point-min))
                (search-forward search)
                (let ((line-pos (match-beginning 0)))
                  (replace-match replacement t t)
                  (md-ts-test--fontify-line-at line-pos))
                (md-ts-test--assert-bare-button-opens-at-search target))
            (kill-buffer buf)))))))

(ert-deftest md-ts-test-link-bare-regional-context-edit-cleans-prose-to-unsafe ()
  "Boundary-only prose-to-unsafe edits should clear enclosed bare UI."
  (dolist (case '(("fenced code" "x``\nhttps://fence.example/path\n```\n"
                   "x``" "```" "https://fence.example/path")
                  ("HTML block" "xdiv>\nhttps://block.example/path\n</div>\n"
                   "xdiv>" "<div>" "https://block.example/path")
                  ("indented code" "x   https://indent.example/path\n"
                   "x" " " "https://indent.example/path")
                  ("multiline code span" "x\nhttps://span.example/path\n`\n"
                   "x" "`" "https://span.example/path")
                  ("multiline HTML tag" "xtag\nhref=\"https://tag.example/path\">\n"
                   "xtag" "<tag" "https://tag.example/path")
                  ("YAML metadata" "xxx\nurl: https://yaml.example/path\n---\n\n"
                   "xxx" "---" "https://yaml.example/path")
                  ("TOML metadata" "xxx\nurl = \"https://toml.example/path\"\n+++\n\n"
                   "xxx" "+++" "https://toml.example/path")))
    (pcase-let ((`(,label ,text ,search ,replacement ,target) case))
      (ert-info ((format "checking %s" label))
        (let ((buf (md-ts-test--fontify text)))
          (unwind-protect
              (with-current-buffer buf
                (md-ts-test--assert-bare-button-opens-at-search target)
                (goto-char (point-min))
                (search-forward search)
                (let ((line-pos (match-beginning 0)))
                  (replace-match replacement t t)
                  (md-ts-test--fontify-line-at line-pos))
                (md-ts-test--assert-no-bare-button-at-search target))
            (kill-buffer buf)))))))

(ert-deftest md-ts-test-link-bare-regional-newline-before-opener-cleans-unsafe ()
  "Newline insertion before opener lines should clear newly unsafe bare UI."
  (dolist (case '(("fenced code" "before```\nhttps://fence-newline.example/path\n```\n"
                   "https://fence-newline.example/path")
                  ("HTML block" "before<div>\nhttps://html-newline.example/path\n</div>\n"
                   "https://html-newline.example/path")))
    (pcase-let ((`(,label ,text ,target) case))
      (dolist (refontify '(inserted-newline previous-eol opener-bol))
        (ert-info ((format "checking %s via %s" label refontify))
          (let ((buf (md-ts-test--fontify text)))
            (unwind-protect
                (with-current-buffer buf
                  (md-ts-test--assert-bare-button-opens-at-search target)
                  (goto-char (point-min))
                  (search-forward "before")
                  (let ((edit-beg (point)))
                    (insert "\n")
                    (pcase refontify
                      ('inserted-newline
                       (funcall font-lock-fontify-region-function
                                edit-beg (1+ edit-beg) nil))
                      ('previous-eol
                       (funcall font-lock-fontify-region-function
                                edit-beg edit-beg nil))
                      ('opener-bol
                       (funcall font-lock-fontify-region-function
                                (1+ edit-beg) (1+ edit-beg) nil))))
                  (md-ts-test--assert-no-bare-button-at-search target))
              (kill-buffer buf))))))))

(ert-deftest md-ts-test-link-bare-regional-delete-newline-before-opener-buttonizes-prose ()
  "Deleting newlines before opener lines should rescan newly prose bodies."
  (dolist (case '(("fenced code" "before\n```\nhttps://fence-delete.example/path\n```\n"
                   "https://fence-delete.example/path")
                  ("HTML block" "before\n<div>\nhttps://html-delete.example/path\n</div>\n"
                   "https://html-delete.example/path")))
    (pcase-let ((`(,label ,text ,target) case))
      (ert-info ((format "checking %s" label))
        (let ((buf (md-ts-test--fontify text)))
          (unwind-protect
              (with-current-buffer buf
                (md-ts-test--assert-no-bare-button-at-search target)
                (goto-char (point-min))
                (search-forward "before")
                (let ((edit-beg (point)))
                  (delete-char 1)
                  (funcall font-lock-fontify-region-function
                           edit-beg edit-beg nil))
                (md-ts-test--assert-bare-button-opens-at-search target))
            (kill-buffer buf)))))))

(ert-deftest md-ts-test-link-bare-edit-to-autolink-clears-static-target ()
  "Editing a bare URL into an autolink should keep a parsed button."
  (let ((url "https://example.com/path")
        (buf (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward url)
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (button-at url-beg))
            (should (get-text-property url-beg
                                       'md-ts-link-static-target))
            (goto-char url-end)
            (insert ">")
            (goto-char url-beg)
            (insert "<")
            (font-lock-flush)
            (font-lock-ensure)
            (goto-char (point-min))
            (search-forward url)
            (let* ((pos (match-beginning 0))
                   (button (button-at pos)))
              (should button)
              (should (md-ts--link-button-p button))
              (should-not (button-get button
                                      'md-ts-link-static-target))
              (should-not (get-text-property pos
                                             'md-ts-link-static-target))
              (should (equal (cons (button-start button)
                                   (button-end button))
                             (cons pos (match-end 0))))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (target &rest _args)
                           (setq opened target))))
                (push-button pos))
              (should (equal opened url)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-direct-push-falls-back-to-parsed-autolink ()
  "Stale bare buttons should resolve parsed autolinks without refontifying."
  (let ((url "https://example.com/path")
        (buf (md-ts-test--fontify "Visit https://example.com/path now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward url)
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (button-at url-beg))
            (should (get-text-property url-beg 'md-ts-link-static-target))
            (goto-char url-end)
            (insert ">")
            (goto-char url-beg)
            (insert "<")
            ;; No font-lock flush/ensure: exercise direct stale-button
            ;; activation across the bare -> parsed transition.
            (goto-char (point-min))
            (search-forward url)
            (let* ((pos (match-beginning 0))
                   (button (button-at pos)))
              (should button)
              (should (button-get button 'md-ts-link-static-target))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (target &rest _args)
                           (setq opened target))))
                (push-button pos))
              (should (equal opened url)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-direct-push-falls-back-to-bare-url ()
  "Stale parsed autolink buttons should resolve bare URLs without refontifying."
  (let ((url "https://example.com/path")
        (buf (md-ts-test--fontify "Visit <https://example.com/path> now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward url)
          (let ((url-beg (match-beginning 0))
                (url-end (match-end 0)))
            (should (button-at url-beg))
            (should-not (get-text-property url-beg 'md-ts-link-static-target))
            (goto-char url-end)
            (delete-char 1)
            (goto-char (1- url-beg))
            (delete-char 1)
            ;; No font-lock flush/ensure: exercise direct stale-button
            ;; activation across the parsed -> bare transition.
            (goto-char (point-min))
            (search-forward url)
            (let* ((pos (match-beginning 0))
                   (button (button-at pos)))
              (should button)
              (should-not (button-get button 'md-ts-link-static-target))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (target &rest _args)
                           (setq opened target))))
                (push-button pos))
              (should (equal opened url)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-direct-push-uses-activation-position ()
  "Stale parsed buttons should revalidate at the activated URL text."
  (let ((buf (md-ts-test--fontify
              (concat "[https://one.example and https://two.example]"
                      "(https://old.example)\n")))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "](https://old.example)")
          (delete-region (match-beginning 0) (match-end 0))
          (goto-char (point-min))
          (delete-char 1)
          ;; No font-lock flush/ensure: exercise direct stale-button
          ;; activation on the second of two bare URLs in one old link span.
          (goto-char (point-min))
          (search-forward "https://one.example")
          (let ((first-pos (match-beginning 0)))
            (search-forward "https://two.example")
            (let* ((second-pos (match-beginning 0))
                   (button (button-at second-pos)))
              (should button)
              (should-not (button-get button 'md-ts-link-static-target))
              (should (= (button-start button) first-pos))
              (should (< (button-start button) second-pos))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (target &rest _args)
                           (setq opened target))))
                (push-button second-pos))
              (should (equal opened "https://two.example")))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-uppercase-url-with-case-fold-search-nil ()
  "Uppercase bare URL schemes should buttonize when search is case-sensitive."
  (let ((case-fold-search nil)
        (buf nil)
        opened)
    (unwind-protect
        (progn
          (setq buf (md-ts-test--fontify "Visit HTTPS://EXAMPLE.COM/Path now.\n"))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "HTTPS://EXAMPLE.COM/Path")
            (let ((pos (match-beginning 0))
                  (end (match-end 0)))
              (let ((button (button-at pos)))
                (should button)
                (should (equal (cons (button-start button)
                                     (button-end button))
                               (cons pos end)))
                (should (equal (button-get button 'md-ts-link-static-target)
                               "HTTPS://EXAMPLE.COM/Path")))
              (cl-letf (((symbol-function 'browse-url)
                         (lambda (url &rest _args)
                           (setq opened url))))
                (push-button pos))
              (should (equal opened "HTTPS://EXAMPLE.COM/Path")))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-static-activation-recomputes-edited-url ()
  "Activating a stale bare button should open the current URL text."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/old now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "old")
          (insert "-new")
          (goto-char (point-min))
          (search-forward "https://example.com/old-new")
          (let ((pos (match-beginning 0)))
            (should (equal (get-text-property pos 'help-echo)
                           "https://example.com/old"))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (push-button pos)))
          (should (equal opened "https://example.com/old-new")))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-uppercase-static-activation-recomputes-with-case-fold-search-nil ()
  "Uppercase stale bare URLs should revalidate when search is case-sensitive."
  (let ((case-fold-search nil)
        (buf nil)
        opened)
    (unwind-protect
        (progn
          (setq buf (md-ts-test--fontify "Visit HTTPS://EXAMPLE.COM/old now.\n"))
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "old")
            (insert "-NEW")
            (goto-char (point-min))
            (search-forward "HTTPS://EXAMPLE.COM/old-NEW")
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (push-button (match-beginning 0)))
            (should (equal opened "HTTPS://EXAMPLE.COM/old-NEW"))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest md-ts-test-link-bare-static-activation-rejects-broken-url ()
  "Activating a stale bare button should not open an old broken URL."
  (let ((buf (md-ts-test--fontify "Visit https://example.com/old now.\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "https")
          (goto-char (+ (match-beginning 0) 2))
          (insert " ")
          (goto-char (point-min))
          (search-forward "ht tps://example.com/old")
          (cl-letf (((symbol-function 'browse-url)
                     (lambda (&rest _args)
                       (ert-fail "browse-url called for broken stale URL"))))
            (should-error (push-button (match-beginning 0))
                          :type 'user-error)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-long-line-smoke ()
  "Bare scanner should handle long prose lines with many misses and URLs."
  (let* ((chunks (append (make-list 120 "not.a/link@example")
                         (cl-loop for i below 12
                                  collect (format "https://example.com/%d" i))))
         (text (concat (mapconcat #'identity chunks " ") "\n"))
         (buf (md-ts-test--fontify text)))
    (unwind-protect
        (with-current-buffer buf
          (let ((count 0)
                (pos (point-min)))
            (while (< pos (point-max))
              (when (get-text-property pos 'md-ts-link-static-target)
                (setq count (1+ count))
                (setq pos (or (next-single-property-change
                               pos 'md-ts-link-static-target nil (point-max))
                              (point-max))))
              (setq pos (1+ pos)))
            (should (= count 12))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-caches-unsafe-ranges ()
  "Bare scanner should precompute unsafe ranges once per pass."
  (let* ((chunks (cl-loop for i below 20
                          collect (format "https://example.com/%d" i)))
         (text (concat (mapconcat #'identity chunks " ") "\n"))
         (buf (generate-new-buffer " *md-ts-test*"))
         (calls 0)
         (original (symbol-function 'md-ts--bare-link-unsafe-ranges)))
    (unwind-protect
        (with-current-buffer buf
          (insert text)
          (md-ts-mode)
          (cl-letf (((symbol-function 'md-ts--bare-link-unsafe-ranges)
                     (lambda (&rest args)
                       (setq calls (1+ calls))
                       (apply original args))))
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (should (= calls 1)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-bare-plain-prose-skips-unsafe-ranges ()
  "Bare scanner should not precompute unsafe ranges without candidates."
  (let ((text (mapconcat
               (lambda (i)
                 (format "Plain prose line %03d has words and punctuation." i))
               (number-sequence 1 40)
               "\n"))
        (buf (generate-new-buffer " *md-ts-test*"))
        (calls 0)
        (original (symbol-function 'md-ts--bare-link-unsafe-ranges)))
    (unwind-protect
        (with-current-buffer buf
          (insert text)
          (md-ts-mode)
          (cl-letf (((symbol-function 'md-ts--bare-link-unsafe-ranges)
                     (lambda (&rest args)
                       (setq calls (1+ calls))
                       (apply original args))))
            (funcall font-lock-fontify-region-function
                     (point-min) (point-max) nil))
          (should (= calls 0)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-command ()
  "`md-ts-open-link-at-point' should activate a buttonized link at point."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "Visit [here](https://example.com) now.\n"
       "here"))
    (should (equal opened "https://example.com"))))

(ert-deftest md-ts-test-link-push-button-parsed-works-while-narrowed ()
  "Parsed text buttons should resolve destinations while narrowed to text."
  (let ((buf (md-ts-test--fontify
              "Visit [here](https://target.example) now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "here")
          (let ((beg (match-beginning 0))
                (end (match-end 0)))
            (narrow-to-region beg end)
            (goto-char beg)
            (should (md-ts--link-button-p (button-at beg)))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (push-button beg))
            (should (equal opened "https://target.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-parsed-works-while-narrowed ()
  "`md-ts-open-link-at-point' should resolve destinations while narrowed."
  (let ((buf (md-ts-test--fontify
              "Visit [here](https://target.example) now.\n"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "here")
          (let ((beg (match-beginning 0))
                (end (match-end 0)))
            (narrow-to-region beg end)
            (goto-char beg)
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://target.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-parsed-narrowed ()
  "`md-ts-open-link-at-point' should fontify a narrowed fresh link."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        opened)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit [here](https://target.example) now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "here")
          (let ((beg (match-beginning 0))
                (end (match-end 0)))
            (should-not (button-at beg))
            (narrow-to-region beg end)
            (goto-char beg)
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url)))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for URI link")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for URI link"))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://target.example"))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-on-markup ()
  "`md-ts-open-link-at-point' should reuse parser targets on link markup."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "Visit [here](https://example.com) now.\n"
       "https://example.com"))
    (should (equal opened "https://example.com"))))

(ert-deftest md-ts-test-link-open-at-point-image ()
  "`md-ts-open-link-at-point' should open image targets."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "See ![Alt](https://example.com/image.png).\n"
       "Alt"))
    (should (equal opened "https://example.com/image.png"))))

(ert-deftest md-ts-test-link-open-at-point-reference ()
  "`md-ts-open-link-at-point' should open reference links."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "See [Doc][id].\n\n[id]: https://example.com/ref\n"
       "Doc"))
    (should (equal opened "https://example.com/ref"))))

(ert-deftest md-ts-test-link-image-character-reference-destination ()
  "Image destinations decode Markdown character references."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "See ![Alt](https://e.test/img?x=1&amp;y=2).\n"
       "Alt"))
    (should (equal opened "https://e.test/img?x=1&y=2"))))

(ert-deftest md-ts-test-link-reference-character-reference-destination ()
  "Reference definitions decode Markdown character references."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "See [Doc][id].\n\n[id]: https://e.test/ref?x=1&amp;y=2\n"
       "Doc"))
    (should (equal opened "https://e.test/ref?x=1&y=2"))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-inline ()
  "`md-ts-open-link-at-point' should work before explicit fontification."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search-no-fontify
       "Visit [here](https://example.com) now.\n"
       "here"))
    (should (equal opened "https://example.com"))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-reference ()
  "`md-ts-open-link-at-point' should initialize reference-link state."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search-no-fontify
       "See [Doc][id].\n\n[id]: https://example.com/ref\n"
       "Doc"))
    (should (equal opened "https://example.com/ref"))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-rejects-unsafe-bare ()
  "`md-ts-open-link-at-point' should reject unsafe bare-looking text."
  (dolist (case
           '(("code span URL"
              "Code `https://unsafe.example/span` here.\n"
              "https://unsafe.example/span")
             ("code span email"
              "Code `person@example.com` here.\n"
              "person@example.com")
             ("fenced code URL"
              "```\nhttps://unsafe.example/fenced\n```\n"
              "https://unsafe.example/fenced")
             ("fenced code email"
              "```\nperson@example.com\n```\n"
              "person@example.com")
             ("indented code URL"
              "    https://unsafe.example/indented\n"
              "https://unsafe.example/indented")
             ("indented code email"
              "    person@example.com\n"
              "person@example.com")
             ("HTML attribute URL"
              "<a href=\"https://unsafe.example/attr\">label</a>\n"
              "https://unsafe.example/attr")
             ("HTML attribute email"
              "<a data-email=\"person@example.com\">label</a>\n"
              "person@example.com")
             ("HTML block URL"
              "<div>\nhttps://unsafe.example/block\n</div>\n"
              "https://unsafe.example/block")
             ("HTML block email"
              "<div>\nperson@example.com\n</div>\n"
              "person@example.com")
             ("YAML front matter URL"
              "---\nurl: https://unsafe.example/meta\n---\n\n"
              "https://unsafe.example/meta")
             ("YAML front matter email"
              "---\nemail: person@example.com\n---\n\n"
              "person@example.com")
             ("TOML front matter URL"
              "+++\nurl = \"https://unsafe.example/meta\"\n+++\n\n"
              "https://unsafe.example/meta")
             ("TOML front matter email"
              "+++\nemail = \"person@example.com\"\n+++\n\n"
              "person@example.com")))
    (ert-info ((format "checking %s" (nth 0 case)))
      (md-ts-test--open-link-no-fontify-should-reject
       (nth 1 case) (nth 2 case)))))

(ert-deftest md-ts-test-link-open-at-point-bare-fallback-rejects-destinations ()
  "Bare fallback should reject URL/email text in parsed destinations."
  (dolist (case
           '(("inline link destination URL"
              "Visit [label](https://unsafe.example/inline).\n"
              "https://unsafe.example/inline")
             ("inline link destination email"
              "Visit [label](person@example.com).\n"
              "person@example.com")
             ("reference definition destination URL"
              "[id]: https://unsafe.example/ref\n\nSee [id].\n"
              "https://unsafe.example/ref")
             ("reference definition destination email"
              "[id]: person@example.com\n\nSee [id].\n"
              "person@example.com")))
    (ert-info ((format "checking %s" (nth 0 case)))
      (let ((buf (generate-new-buffer " *md-ts-test*")))
        (unwind-protect
            (with-current-buffer buf
              (insert (nth 1 case))
              (md-ts-mode)
              (goto-char (point-min))
              (search-forward (nth 2 case))
              (goto-char (match-beginning 0))
              (cl-letf (((symbol-function 'md-ts--link-target-at-point)
                         (lambda (&optional _pos) nil))
                        ((symbol-function 'browse-url)
                         (lambda (&rest _args)
                           (ert-fail "browse-url called for parsed destination")))
                        ((symbol-function 'find-file)
                         (lambda (&rest _args)
                           (ert-fail "find-file called for parsed destination")))
                        ((symbol-function 'url-mailto)
                         (lambda (&rest _args)
                           (ert-fail "url-mailto called for parsed destination"))))
                (should-error (md-ts-open-link-at-point) :type 'user-error)))
          (kill-buffer buf))))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-foreign-text-button ()
  "Foreign text buttons should not block no-fontify parser fallback."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called
        opened)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit [here](https://example.com) now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "here")
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (lambda (_button)
                                      (setq called t))
                            'help-echo "foreign")
          (goto-char (match-beginning 0))
          (cl-letf (((symbol-function 'browse-url)
                     (lambda (url &rest _args)
                       (setq opened url))))
            (md-ts-open-link-at-point))
          (should (equal opened "https://example.com"))
          (should-not called))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-no-fontify-foreign-overlay ()
  "Foreign overlay buttons should not block no-fontify parser fallback."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called
        opened)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit [here](https://example.com) now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "here")
          (let ((overlay (make-button (match-beginning 0) (match-end 0)
                                      'action (lambda (_button)
                                                (setq called t))
                                      'help-echo "foreign")))
            (goto-char (match-beginning 0))
            (should (eq (button-at (point)) overlay))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://example.com"))
            (should-not called)
            (should (eq (button-at (point)) overlay))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-reference-definition ()
  "`md-ts-open-link-at-point' should open reference definition labels."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "[id]: https://example.com/def\n"
       "id"))
    (should (equal opened "https://example.com/def"))))

(ert-deftest md-ts-test-link-open-at-point-autolink ()
  "`md-ts-open-link-at-point' should open parsed autolinks."
  (let (opened)
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url &rest _args)
                 (setq opened url))))
      (md-ts-test--open-link-at-search
       "Visit <https://example.com/auto>.\n"
       "https://example.com/auto"))
    (should (equal opened "https://example.com/auto"))))

(ert-deftest md-ts-test-link-open-at-point-missing-reference ()
  "`md-ts-open-link-at-point' should reject unresolved reference links."
  (cl-letf (((symbol-function 'browse-url)
             (lambda (&rest _args)
               (ert-fail "browse-url called for unresolved reference")))
            ((symbol-function 'find-file)
             (lambda (&rest _args)
               (ert-fail "find-file called for unresolved reference"))))
    (should-error
     (md-ts-test--open-link-at-search "See [Missing][nope].\n" "Missing")
     :type 'user-error)))

(ert-deftest md-ts-test-link-open-at-point-missing-link ()
  "`md-ts-open-link-at-point' should clearly reject ordinary text."
  (let ((err (should-error
              (md-ts-test--open-link-at-search "No links here.\n" "links")
              :type 'user-error)))
    (should (equal (error-message-string err)
                   "No Markdown or bare link at point"))))

(ert-deftest md-ts-test-link-target-at-point-rejects-adjacent-prose ()
  "Adjacent prose should not inherit neighboring parsed link targets."
  (let ((buf (md-ts-test--fontify
              (concat "before[one](https://one.example) "
                      "middle [two](https://two.example)after\n"))))
    (unwind-protect
        (with-current-buffer buf
          (dolist (case '(("prose before a link" "before" end)
                          ("prose between two links" "middle" beginning)
                          ("prose after a link" "after" beginning)))
            (pcase-let ((`(,label ,search ,edge) case))
              (ert-info ((format "checking %s" label))
                (goto-char (point-min))
                (search-forward search)
                (goto-char (if (eq edge 'end)
                               (1- (match-end 0))
                             (match-beginning 0)))
                (should-not (md-ts--link-target-at-point))
                (cl-letf (((symbol-function 'browse-url)
                           (lambda (&rest _args)
                             (ert-fail "browse-url called for prose")))
                          ((symbol-function 'find-file)
                           (lambda (&rest _args)
                             (ert-fail "find-file called for prose")))
                          ((symbol-function 'url-mailto)
                           (lambda (&rest _args)
                             (ert-fail "url-mailto called for prose"))))
                  (should-error (md-ts-open-link-at-point)
                                :type 'user-error))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-rejects-foreign-button ()
  "`md-ts-open-link-at-point' should not activate non-Markdown buttons."
  (let ((buf (md-ts-test--fontify "Plain button text.\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "button")
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (lambda (_button)
                                      (setq called t)))
          (goto-char (match-beginning 0))
          (should (button-at (point)))
          (should-error (md-ts-open-link-at-point) :type 'user-error)
          (should-not called))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-bare-under-foreign-text-button ()
  "Foreign text buttons should not hide bare-link fallback opening."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called
        opened)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com/path now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let ((pos (match-beginning 0)))
            (make-text-button pos (match-end 0)
                              'action (lambda (_button)
                                        (setq called t))
                              'help-echo "foreign")
            (font-lock-ensure)
            (goto-char pos)
            (should (button-at (point)))
            (should-not (md-ts--link-button-p (button-at (point))))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://example.com/path"))
            (should-not called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-bare-under-foreign-overlay-button ()
  "Foreign overlay buttons should not hide bare-link fallback opening."
  (let ((buf (generate-new-buffer " *md-ts-test*"))
        called
        opened)
    (unwind-protect
        (with-current-buffer buf
          (insert "Visit https://example.com/path now.\n")
          (md-ts-mode)
          (goto-char (point-min))
          (search-forward "https://example.com/path")
          (let* ((pos (match-beginning 0))
                 (overlay (make-button pos (match-end 0)
                                       'action (lambda (_button)
                                                 (setq called t))
                                       'help-echo "overlay")))
            (font-lock-ensure)
            (goto-char pos)
            (should (eq (button-at (point)) overlay))
            (should-not (md-ts--link-button-p overlay))
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://example.com/path"))
            (should-not called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-rejects-foreign-button-before-link ()
  "A foreign button on prose before a link should not borrow its target."
  (let ((buf (md-ts-test--fontify "before[one](https://one.example)\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "before")
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (lambda (_button)
                                      (setq called t))
                            'help-echo "foreign")
          (goto-char (1- (match-end 0)))
          (should (button-at (point)))
          (cl-letf (((symbol-function 'browse-url)
                     (lambda (&rest _args)
                       (ert-fail "browse-url called for prose button")))
                    ((symbol-function 'find-file)
                     (lambda (&rest _args)
                       (ert-fail "find-file called for prose button")))
                    ((symbol-function 'url-mailto)
                     (lambda (&rest _args)
                       (ert-fail "url-mailto called for prose button"))))
            (should-error (md-ts-open-link-at-point) :type 'user-error))
          (should-not called))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-foreign-button-survives-refontification ()
  "Refontifying `md-ts-mode' should not remove unrelated text buttons."
  (let ((buf (md-ts-test--fontify "Plain button text.\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "button")
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (lambda (_button)
                                      (setq called t))
                            'help-echo "foreign")
          (font-lock-flush (point-min) (point-max))
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "button")
          (let ((button (button-at (match-beginning 0))))
            (should button)
            (should (equal (button-get button 'help-echo) "foreign"))
            (push-button (match-beginning 0))
            (should called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-foreign-button-on-link-text-survives-refontification ()
  "Foreign buttons on link text should not be mistaken for md-ts buttons."
  (let ((buf (md-ts-test--fontify "[link](https://example.com)\n"))
        called
        opened)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "link")
          (let ((pos (match-beginning 0))
                (end (match-end 0)))
            (should (md-ts--link-button-p (button-at pos)))
            (make-text-button pos end
                              'action (lambda (_button)
                                        (setq called t))
                              'help-echo "foreign")
            (should (get-text-property pos 'md-ts-link-button))
            (should-not (md-ts--link-button-p (button-at pos)))
            (goto-char pos)
            (cl-letf (((symbol-function 'browse-url)
                       (lambda (url &rest _args)
                         (setq opened url)))
                      ((symbol-function 'find-file)
                       (lambda (&rest _args)
                         (ert-fail "find-file called for URI link")))
                      ((symbol-function 'url-mailto)
                       (lambda (&rest _args)
                         (ert-fail "url-mailto called for URI link"))))
              (md-ts-open-link-at-point))
            (should (equal opened "https://example.com"))
            (should-not called)
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure)
            (let ((button (button-at pos)))
              (should button)
              (should-not (button-get button 'md-ts-link-button))
              (should (equal (button-get button 'help-echo) "foreign"))
              (push-button pos)
              (should called))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-wider-foreign-button-keeps-equal-help ()
  "A wider foreign text button may own help text equal to old md-ts help."
  (let ((buf (md-ts-test--fontify "pre [link](https://example.com) post\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "link")
          (let ((pos (match-beginning 0))
                (wide-beg (point-min))
                (wide-end (line-end-position)))
            (should (md-ts--link-button-p (button-at pos)))
            (should (equal (get-text-property pos 'help-echo)
                           "https://example.com"))
            (make-text-button wide-beg wide-end
                              'action (lambda (_button)
                                        (setq called t))
                              'help-echo "https://example.com")
            (should (button-at pos))
            (should (get-text-property pos 'md-ts-link-button))
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure)
            (let ((button (button-at pos)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should-not (get-text-property pos 'md-ts-link-button))
              (should-not (get-text-property pos 'md-ts-link-help-echo))
              (should (equal (plist-get (text-properties-at pos) 'help-echo)
                             "https://example.com"))
              (push-button pos)
              (should called))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-partial-foreign-action-preserved-on-refontify ()
  "A direct foreign action inside old md-ts button text should survive."
  (let ((buf (md-ts-test--fontify "[link](https://example.com)\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "link")
          (let* ((link-beg (match-beginning 0))
                 (link-end (match-end 0))
                 (foreign-beg (1+ link-beg))
                 (foreign-end (1- link-end))
                 (foreign-action (lambda (_button)
                                   (setq called t))))
            (should (md-ts--link-button-p (button-at link-beg)))
            (put-text-property foreign-beg foreign-end
                               'action foreign-action)
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure)
            (should-not (button-at link-beg))
            (let ((button (button-at foreign-beg)))
              (should button)
              (should-not (md-ts--link-button-p button))
              (should (eq (button-get button 'action) foreign-action))
              (should-not (get-text-property foreign-beg
                                             'md-ts-link-button))
              (push-button foreign-beg)
              (should called))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-partial-foreign-button-overlap-cleans-tails ()
  "Partial foreign text-button overlaps should not leave stale md-ts tails."
  (dolist (case '((start 0 2 (2 3))
                  (middle 1 3 (0 3))
                  (end 2 4 (0 1))))
    (pcase-let ((`(,label ,foreign-start ,foreign-end ,plain-positions)
                 case))
      (ert-info ((format "partial %s overlap" label))
        (let ((buf (md-ts-test--fontify "[link](https://example.com)\n"))
              called)
          (unwind-protect
              (with-current-buffer buf
                (goto-char (point-min))
                (search-forward "link")
                (let* ((link-beg (match-beginning 0))
                       (link-end (match-end 0))
                       (foreign-beg (+ link-beg foreign-start))
                       (foreign-limit (+ link-beg foreign-end)))
                  (should (md-ts--link-button-p (button-at link-beg)))
                  (make-text-button foreign-beg foreign-limit
                                    'action (lambda (_button)
                                              (setq called t))
                                    'help-echo "foreign")
                  (font-lock-flush (point-min) (point-max))
                  (font-lock-ensure)
                  (dolist (rel plain-positions)
                    (let ((pos (+ link-beg rel)))
                      (dolist (prop '(button category action help-echo
                                             md-ts-link-button
                                             md-ts-link-help-echo))
                        (should-not (get-text-property pos prop)))))
                  (dolist (pos (number-sequence foreign-beg
                                                (1- foreign-limit)))
                    (let ((button (button-at pos)))
                      (should button)
                      (should-not (md-ts--link-button-p button))
                      (should-not (get-text-property pos 'md-ts-link-button))
                      (should-not (get-text-property pos
                                                     'md-ts-link-help-echo))
                      (should (equal (button-get button 'help-echo)
                                     "foreign"))))
                  (push-button foreign-beg)
                  (should called)
                  (should (= link-end (+ link-beg 4)))))
            (kill-buffer buf)))))))

(ert-deftest md-ts-test-link-foreign-overlay-removes-hidden-md-ts-props ()
  "A foreign overlay should not leave hidden md-ts text button props."
  (let ((buf (md-ts-test--fontify "[link](https://example.com)\n"))
        called)
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "link")
          (let* ((pos (match-beginning 0))
                 (end (match-end 0))
                 (overlay (make-button pos end
                                       'action (lambda (_button)
                                                 (setq called t))
                                       'help-echo "overlay")))
            (should (md-ts--link-button-p (copy-marker pos t)))
            (should (eq (button-at pos) overlay))
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure)
            (should (eq (button-at pos) overlay))
            (should (equal (button-get overlay 'help-echo) "overlay"))
            (dolist (prop '(button category action help-echo
                                   md-ts-link-button
                                   md-ts-link-help-echo))
              (should-not (get-text-property pos prop)))
            (push-button pos)
            (should called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-link-open-at-point-key-binding ()
  "`md-ts-mode-map' should bind the common open-link key."
  (should (eq (lookup-key md-ts-mode-map (kbd "C-c C-o"))
              #'md-ts-open-link-at-point)))

(ert-deftest md-ts-test-link-open-at-point-key-binding-survives-reload ()
  "Reloading after an older mode map exists should still install the key."
  (let* ((expression
          (mapconcat
           #'identity
           `("(progn"
             "  (defvar md-ts-mode-map (make-sparse-keymap))"
             ,(format "  (let ((old-map md-ts-mode-map)) (load %S nil t)"
                      (expand-file-name "md-ts-mode.el" md-ts-test--repo-root))
             ,(md-ts-test--batch-result-princ-form)
             "    (prin1 (list"
             "            :same-map (eq old-map md-ts-mode-map)"
             "            :binding (eq (lookup-key md-ts-mode-map (kbd \"C-c C-o\"))"
             "                         #'md-ts-open-link-at-point)"
             "            :parent (eq (keymap-parent md-ts-mode-map) text-mode-map)))))")
           " "))
         (result (md-ts-test--read-batch-emacs-result expression)))
    (should (eq t (plist-get result :same-map)))
    (should (eq t (plist-get result :binding)))
    (should (eq t (plist-get result :parent)))))

(ert-deftest md-ts-test-link-open-at-point-map-inherits-text-mode ()
  "`md-ts-mode-map' should keep `text-mode-map' as an ancestor."
  (should (eq (keymap-parent md-ts-mode-map) text-mode-map)))

(defun md-ts-test--invisible-includes-p (value member)
  "Return non-nil when invisible VALUE includes MEMBER."
  (if (listp value)
      (memq member value)
    (eq value member)))

(ert-deftest md-ts-test-hide-markup-fontify-preserves-foreign-invisible-symbol ()
  "Fontification should add md-ts invisibility without clobbering foreign symbols."
  (let ((md-ts-hide-markup t)
        (buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Heading\n")
          (put-text-property (point-min) (1+ (point-min))
                             'invisible 'foreign-hide)
          (md-ts-mode)
          (font-lock-ensure)
          (let ((invisible (get-text-property (point-min) 'invisible)))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'md-ts--markup))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'foreign-hide))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fontify-preserves-foreign-invisible-list ()
  "Fontification should add md-ts invisibility to composite foreign values."
  (let ((md-ts-hide-markup t)
        (buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Heading\n")
          (put-text-property (point-min) (1+ (point-min))
                             'invisible '(foreign-hide other-hide))
          (md-ts-mode)
          (font-lock-ensure)
          (let ((invisible (get-text-property (point-min) 'invisible)))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'md-ts--markup))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'foreign-hide))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'other-hide))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-unfontify-preserves-foreign-invisible ()
  "Unfontification should remove only md-ts-owned invisible text."
  (let ((md-ts-hide-markup t)
        (buf (md-ts-test--fontify "# Heading\n")))
    (unwind-protect
        (with-current-buffer buf
          (put-text-property (point-min) (point-max)
                             'invisible 'foreign-hide)
          (funcall font-lock-unfontify-region-function
                   (point-min) (point-max))
          (should (eq (get-text-property (point-min) 'invisible)
                      'foreign-hide)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-unfontify-cleans-composite-invisible ()
  "Unfontification should remove md-ts invisibility from composite values."
  (let ((buf (md-ts-test--fontify "# Heading\n")))
    (unwind-protect
        (with-current-buffer buf
          (put-text-property (point-min) (1+ (point-min))
                             'invisible '(md-ts--markup foreign-hide))
          (funcall font-lock-unfontify-region-function
                   (point-min) (point-max))
          (let ((invisible (get-text-property (point-min) 'invisible)))
            (should-not (md-ts-test--invisible-includes-p invisible
                                                          'md-ts--markup))
            (should (md-ts-test--invisible-includes-p invisible
                                                      'foreign-hide))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-indirect-unfontify-preserves-base-invisible ()
  "Indirect unfontification should not strip shared base markup hiding."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup t)
          (font-lock-ensure)
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (funcall font-lock-unfontify-region-function
                     (point-min) (point-max)))
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup)))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-hide-markup-indirect-edit-cleans-stale-markup ()
  "Indirect refontification should clear stale md-ts markup invisibility."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup t)
          (font-lock-ensure)
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup))
          (should (eq (get-text-property (1+ (point-min)) 'invisible)
                      'md-ts--markup))
          (goto-char (point-min))
          (search-forward "Heading")
          (put-text-property (match-beginning 0) (1+ (match-beginning 0))
                             'invisible 'foreign-hide)
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (goto-char (point-min))
            (delete-char 1)
            (insert "X")
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure))
          (should-not (get-text-property (point-min) 'invisible))
          (should-not (get-text-property (1+ (point-min)) 'invisible))
          (goto-char (point-min))
          (search-forward "Heading")
          (should (eq (get-text-property (match-beginning 0) 'invisible)
                      'foreign-hide)))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-hide-markup-indirect-edit-cleans-stale-after-clean-region ()
  "Indirect edits should clean stale invisibility after unrelated fontification."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n\nClean line.\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup t)
          (font-lock-ensure)
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup))
          (should (eq (get-text-property (1+ (point-min)) 'invisible)
                      'md-ts--markup))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (goto-char (point-min))
            (delete-char 1)
            (insert "X")
            (search-forward "Clean line.")
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (goto-char (point-min))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil))
          (should-not (md-ts-test--invisible-includes-p
                       (get-text-property (point-min) 'invisible)
                       'md-ts--markup))
          (should-not (md-ts-test--invisible-includes-p
                       (get-text-property (1+ (point-min)) 'invisible)
                       'md-ts--markup)))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-hide-markup-indirect-non-md-edit-cleans-stale-markup ()
  "Non-md indirect edits should dirty stale shared markup hiding."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        viewer editor)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n\nClean line.\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup t)
          (font-lock-ensure)
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup))
          (should (eq (get-text-property (1+ (point-min)) 'invisible)
                      'md-ts--markup))
          (setq viewer (make-indirect-buffer base " *md-ts-viewer*" nil))
          (with-current-buffer viewer
            (md-ts-mode))
          (setq editor (make-indirect-buffer base " *md-ts-editor*" nil))
          (with-current-buffer editor
            (fundamental-mode)
            (should-not
             (memq #'md-ts--font-lock-record-dirty-side-effect-bounds
                   before-change-functions))
            (goto-char (point-min))
            (delete-char 1))
          (with-current-buffer viewer
            (goto-char (point-min))
            (search-forward "Clean line.")
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil)
            (goto-char (point-min))
            (funcall font-lock-fontify-region-function
                     (line-beginning-position) (line-end-position) nil))
          (should (equal (buffer-substring-no-properties
                          (point-min) (+ (point-min) 8))
                         " Heading"))
          (should-not (md-ts-test--invisible-includes-p
                       (get-text-property (point-min) 'invisible)
                       'md-ts--markup))
          (should-not (md-ts-test--invisible-includes-p
                       (get-text-property (1+ (point-min)) 'invisible)
                       'md-ts--markup)))
      (when (buffer-live-p editor)
        (kill-buffer editor))
      (when (buffer-live-p viewer)
        (kill-buffer viewer))
      (kill-buffer base))))

(ert-deftest md-ts-test-hide-markup-indirect-disabled-preserves-base-hidden ()
  "Indirect refontification should follow base hide-markup when disabled locally."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup t)
          (font-lock-ensure)
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (setq-local md-ts-hide-markup nil)
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure))
          (should (eq (get-text-property (point-min) 'invisible)
                      'md-ts--markup)))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-hide-markup-indirect-enabled-keeps-base-visible ()
  "Indirect refontification should not hide shared base text when base is visible."
  (let ((base (generate-new-buffer " *md-ts-test*"))
        indirect)
    (unwind-protect
        (with-current-buffer base
          (insert "# Heading\n")
          (md-ts-mode)
          (setq-local md-ts-hide-markup nil)
          (font-lock-ensure)
          (should-not (get-text-property (point-min) 'invisible))
          (setq indirect (make-indirect-buffer base " *md-ts-indirect*" t))
          (with-current-buffer indirect
            (setq-local md-ts-hide-markup t)
            (font-lock-flush (point-min) (point-max))
            (font-lock-ensure))
          (should-not (md-ts-test--invisible-includes-p
                       (get-text-property (point-min) 'invisible)
                       'md-ts--markup)))
      (when (buffer-live-p indirect)
        (kill-buffer indirect))
      (kill-buffer base))))

(ert-deftest md-ts-test-full-reference-link ()
  "Full reference link [text][ref] should get `link' face on text."
  (should (md-ts-test--has-face
           "See [Python docs][py] now.\n\n[py]: http://python.org\n"
           "Python docs" 'link)))

(ert-deftest md-ts-test-collapsed-reference-link ()
  "Collapsed reference link [text][] should get `link' face on text."
  (should (md-ts-test--has-face
           "See [Python][] now.\n"
           "Python" 'link)))

(ert-deftest md-ts-test-hide-markup-reference-link ()
  "With hide-markup, reference link brackets and label are hidden."
  (let ((md-ts-hide-markup t))
    ;; Opening [ is hidden
    (should (eq (md-ts-test--invisible-at
                 "See [Python docs][py] now.\n\n[py]: http://python.org\n"
                 "[P")
                'md-ts--markup))
    ;; ][py] is hidden
    (should (eq (md-ts-test--invisible-at
                 "See [Python docs][py] now.\n\n[py]: http://python.org\n"
                 "][")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-link-url ()
  "With hide-markup, link URL and delimiters should be invisible."
  (let ((md-ts-hide-markup t))
    ;; Brackets should be hidden
    (should (eq (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "[")
                'md-ts--markup))
    ;; URL + parens should be hidden
    (should (eq (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "(http")
                'md-ts--markup))
    ;; But link text should remain visible
    (should-not (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "here"))))

(ert-deftest md-ts-test-hide-markup-link-inline-button ()
  "With hide-markup, visible inline link text should stay activatable."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "[")
                'md-ts--markup))
    (should (eq (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "(http")
                'md-ts--markup))
    (should-not (md-ts-test--invisible-at
                 "Visit [here](http://example.com) now.\n"
                 "here"))
    (should (md-ts-test--button-at-search
             "Visit [here](http://example.com) now.\n"
             "here"))))

(ert-deftest md-ts-test-hide-markup-link-autolink-angles ()
  "With hide-markup, autolinks should hide only angle brackets."
  (let ((md-ts-hide-markup t)
        (text "Visit <https://example.com> now.\n"))
    (should (eq (md-ts-test--invisible-at text "<") 'md-ts--markup))
    (should (eq (md-ts-test--invisible-at text ">") 'md-ts--markup))
    (should-not (md-ts-test--invisible-at text "https://example.com"))
    (should (md-ts-test--button-at-search text "https://example.com"))))

(ert-deftest md-ts-test-hide-markup-image ()
  "With hide-markup, image URL and delimiters should be invisible."
  (let ((md-ts-hide-markup t))
    ;; The ! should be hidden
    (should (eq (md-ts-test--invisible-at
                 "Check ![alt](image.png) out.\n"
                 "!")
                'md-ts--markup))
    ;; URL + parens should be hidden
    (should (eq (md-ts-test--invisible-at
                 "Check ![alt](image.png) out.\n"
                 "(image")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-fenced-code-language ()
  "With hide-markup, the language tag is hidden along with fences.
Language labels are markup whether or not an embedded grammar is active."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "```sample\nprint('hi')\n```\n"
                 "sample")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-fenced-code-delimiter ()
  "With hide-markup, fenced code block delimiters are hidden."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "```sample\nprint('hi')\n```\n"
                 "```")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-fenced-code-partial-expands-bounds ()
  "Partial hide-markup fontification should report full fence-line writes."
  (let ((md-ts-hide-markup t)
        (buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Before\n```\ncode line\n```\nAfter\n")
          (md-ts-mode)
          (font-lock-ensure)
          (funcall font-lock-unfontify-region-function (point-min) (point-max))
          (goto-char (point-min))
          (search-forward "code")
          (let* ((result (funcall font-lock-fontify-region-function
                                  (match-beginning 0) (match-end 0) nil))
                 (bounds (md-ts-test--jit-lock-bounds result))
                 (bound-beg (car bounds))
                 (bound-end (cdr bounds)))
            (goto-char (point-min))
            (search-forward "```")
            (let ((open-beg (match-beginning 0)))
              (should (<= bound-beg open-beg))
              (should (< open-beg bound-end))
              (should (eq (get-text-property open-beg 'invisible)
                          'md-ts--markup)))
            (search-forward "```")
            (let ((close-beg (match-beginning 0)))
              (should (<= bound-beg close-beg))
              (should (< close-beg bound-end))
              (should (eq (get-text-property close-beg 'invisible)
                          'md-ts--markup)))
            (should-not
             (md-ts-test--property-outside-region
              bound-beg bound-end
              '(face button category action help-echo mouse-face follow-link
                     md-ts-link-button md-ts-link-help-echo
                     md-ts-link-static-target invisible display)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fenced-code-opening-edit-cleans-old-close ()
  "Edits to an old opening fence should return bounds covering stale markup."
  (let ((md-ts-hide-markup t)
        (buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "Before\n```\ncode line\n```\nAfter\n")
          (md-ts-mode)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "```" nil nil 2)
          (let ((close-marker (copy-marker (match-beginning 0))))
            (should (eq (get-text-property close-marker 'invisible)
                        'md-ts--markup))
            (goto-char (point-min))
            (search-forward "```")
            (let ((open-beg (match-beginning 0))
                  (open-end (match-end 0)))
              (goto-char open-beg)
              (insert "`")
              (let* ((close-beg (marker-position close-marker))
                     (result (funcall font-lock-fontify-region-function
                                      open-beg (1+ open-end) nil))
                     (bounds (md-ts-test--jit-lock-bounds result))
                     (bound-beg (car bounds))
                     (bound-end (cdr bounds)))
                (should (<= bound-beg close-beg))
                (should (< close-beg bound-end))
                (should-not (get-text-property close-beg 'invisible))
                (should-not
                 (md-ts-test--property-outside-region
                  bound-beg bound-end
                  '(face button category action help-echo mouse-face follow-link
                         md-ts-link-button md-ts-link-help-echo
                         md-ts-link-static-target invisible display)))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fenced-code-hide-off-does-not-expand ()
  "Ordinary fenced-code edits should not expand to whole blocks by default."
  (let ((md-ts-hide-markup nil)
        (buf (generate-new-buffer " *md-ts-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (concat "Before\n```\n"
                          (mapconcat (lambda (n) (format "code %d" n))
                                     (number-sequence 1 40) "\n")
                          "\n```\nAfter\n"))
          (md-ts-mode)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "code 20")
          (let* ((edit-beg (match-beginning 0))
                 (edit-end (match-end 0))
                 (line-beg (line-beginning-position))
                 (line-end (1+ (line-end-position)))
                 (result (funcall font-lock-fontify-region-function
                                  edit-beg edit-end nil)))
            (should (equal result `(jit-lock-bounds ,line-beg . ,line-end)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fenced-code-no-phantom-lines ()
  "With hide-markup, newlines after fence lines are also hidden.
The entire opening line (``` + language + newline) and closing line
(``` + newline) should be invisible, leaving no phantom blank lines."
  (let* ((md-ts-hide-markup t)
         (text "```sample\nprint('hi')\n```\n")
         (buf (md-ts-test--fontify text)))
    (unwind-protect
        (with-current-buffer buf
          ;; Newline after opening fence line (```sample\n)
          ;; Position of \n is right after "```sample" = position 10
          (should (eq (get-text-property 10 'invisible) 'md-ts--markup))
          ;; Code body should NOT be invisible
          (goto-char (point-min))
          (search-forward "print")
          (should-not (get-text-property (match-beginning 0) 'invisible))
          ;; Newline after closing fence (```\n)
          ;; text = "```sample\nprint('hi')\n```\n"
          ;;         1234567890 1234567890123 456 7
          ;; closing ``` starts at 23, newline at 26
          (let ((closing-newline (1- (point-max))))
            (should (eq (get-text-property closing-newline 'invisible)
                        'md-ts--markup))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fenced-code-preserves-paragraph-gap ()
  "With hide-markup, the blank line after a code block stays visible.
The paragraph separator between a fenced code block and the following
text must not be hidden — only the fence lines themselves."
  (let* ((md-ts-hide-markup t)
         ;;                       fence  body       fence  gap  next paragraph
         (text "```\ncode line\n```\n\n✅ All fixed!\n")
         (buf (md-ts-test--fontify text)))
    (unwind-protect
        (with-current-buffer buf
          ;; Closing fence (```) should be invisible
          (goto-char (point-min))
          (search-forward "```" nil nil 2)  ; second occurrence = closing
          (should (eq (get-text-property (match-beginning 0) 'invisible)
                      'md-ts--markup))
          ;; Paragraph separator (blank line) must NOT be invisible
          (goto-char (point-min))
          (search-forward "✅")
          (let ((gap-newline (1- (match-beginning 0))))
            (should-not (get-text-property gap-newline 'invisible)))
          ;; Next paragraph must NOT be invisible
          (should-not (get-text-property (match-beginning 0) 'invisible)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-hide-markup-fenced-code-empty-block ()
  "With hide-markup, an empty fenced code block is entirely hidden."
  (let* ((md-ts-hide-markup t)
         (text "```\n```\n")
         (buf (md-ts-test--fontify text)))
    (unwind-protect
        (with-current-buffer buf
          ;; The entire block should be invisible
          (should (eq (get-text-property 1 'invisible) 'md-ts--markup))
          (should (eq (get-text-property 5 'invisible) 'md-ts--markup)))
      (kill-buffer buf))))

;;; Hide-markup tests

(ert-deftest md-ts-test-hide-markup-delimiter ()
  "With `md-ts-hide-markup' non-nil, delimiters get invisible property."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at "# Hello\n" "#")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-heading-space ()
  "With hide-markup, the space after # in headings should also be hidden."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at "# Hello\n" " H")
                'md-ts--markup))
    (should (eq (md-ts-test--invisible-at "## Hello\n" " H")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-off ()
  "With `md-ts-hide-markup' nil, delimiters have no invisible property."
  (let ((md-ts-hide-markup nil))
    (should (null (md-ts-test--invisible-at "# Hello\n" "#")))))

(ert-deftest md-ts-test-hide-markup-emphasis ()
  "With hide-markup, emphasis delimiters get invisible property."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "Para *italic* text.\n" "*")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-setext-h1 ()
  "With hide-markup, setext H1 underline (===) gets invisible property."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "Title\n===\n" "===")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-setext-h2 ()
  "With hide-markup, setext H2 underline (---) gets invisible property."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "Title\n---\n" "---")
                'md-ts--markup))))

(ert-deftest md-ts-test-toggle-hide-markup ()
  "Toggling hide-markup should flip the variable and update invisibility."
  (let ((buf (generate-new-buffer " *md-ts-test-toggle*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (md-ts-mode)
          (font-lock-ensure)
          ;; Initially off
          (should (null md-ts-hide-markup))
          ;; Toggle on
          (md-ts-toggle-hide-markup)
          (should md-ts-hide-markup)
          (should (memq 'md-ts--markup buffer-invisibility-spec))
          ;; Toggle off
          (md-ts-toggle-hide-markup)
          (should (null md-ts-hide-markup))
          (should (not (memq 'md-ts--markup buffer-invisibility-spec))))
      (kill-buffer buf))))

;;; Compat shim tests

(ert-deftest md-ts-test-shim-ensure-installed ()
  "treesit-ensure-installed is available and works for installed grammars."
  (should (fboundp 'treesit-ensure-installed))
  (should (treesit-ensure-installed 'markdown)))

(ert-deftest md-ts-test-shim-merge-feature-list ()
  "treesit-merge-font-lock-feature-list merges correctly."
  (should (fboundp 'treesit-merge-font-lock-feature-list))
  (let ((merged (treesit-merge-font-lock-feature-list
                 '((a b) (c d))
                 '((b e) (f)))))
    ;; First level: union of (a b) and (b e)
    (should (= (length (car merged)) 3))
    (should (memq 'a (car merged)))
    (should (memq 'b (car merged)))
    (should (memq 'e (car merged)))
    ;; Second level: union of (c d) and (f)
    (should (= (length (cadr merged)) 3))
    (should (memq 'c (cadr merged)))
    (should (memq 'd (cadr merged)))
    (should (memq 'f (cadr merged)))))

(ert-deftest md-ts-test-shim-merge-unequal-length ()
  "Merging feature lists of different lengths works."
  (let ((merged (treesit-merge-font-lock-feature-list
                 '((a) (b) (c))
                 '((x)))))
    (should (= (length merged) 3))
    (should (memq 'a (nth 0 merged)))
    (should (memq 'x (nth 0 merged)))
    (should (equal (nth 1 merged) '(b)))
    (should (equal (nth 2 merged) '(c)))))

(ert-deftest md-ts-test-range-fn-exclude-children ()
  "treesit-range-fn-exclude-children returns node range minus children.
Use an atx_heading node which has two children: atx_h1_marker and
inline.  For `# Hello\\n' (buffer positions 1-9):
  atx_h1_marker: 1-2
  inline:        3-8
Expected gaps: (1 . 1) (2 . 3) (8 . 9)."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-exclude*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (section (treesit-node-child root 0))
                 (heading (treesit-node-child section 0))
                 (ranges (treesit-range-fn-exclude-children heading nil)))
            ;; Verify the node we got
            (should (equal (treesit-node-type heading) "atx_heading"))
            ;; Three ranges: before first child, between children, after last
            (should (equal ranges '((1 . 1) (2 . 3) (8 . 9))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-fn-exclude-children-offset ()
  "treesit-range-fn-exclude-children respects OFFSET argument.
With offset (1 . -1) on the same atx_heading (1-9):
  start = 1+1 = 2, end = 9+(-1) = 8
  child gaps computed from offset-adjusted start/end.
Expected: (2 . 1) (2 . 3) (8 . 8)."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-exclude-off*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (section (treesit-node-child root 0))
                 (heading (treesit-node-child section 0))
                 (ranges (treesit-range-fn-exclude-children
                          heading '(1 . -1))))
            (should (equal ranges '((2 . 1) (2 . 3) (8 . 8))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-fn-exclude-children-no-children ()
  "treesit-range-fn-exclude-children on a childless node returns one range.
The atx_h1_marker node has no children, so the result is a single
range spanning the whole node."
  (let ((buf (generate-new-buffer " *md-ts-test-exclude-leaf*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (section (treesit-node-child root 0))
                 (heading (treesit-node-child section 0))
                 (marker (treesit-node-child heading 0))
                 (ranges (treesit-range-fn-exclude-children marker nil)))
            (should (equal (treesit-node-type marker) "atx_h1_marker"))
            ;; No children → single range covering the whole node
            (should (equal ranges '((1 . 2))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-baseline ()
  "Shimmed treesit-query-range without RANGE-FN matches Emacs 30 behavior.
Query (inline) nodes in `# Hello\\nPara *bold* end.\\n' and verify
ranges match the original: ((3 . 8) (10 . 26))."
  (let ((buf (generate-new-buffer " *md-ts-test-qr*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n\nPara *bold* end.\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (ranges (treesit-query-range
                          root '((inline) @cap))))
            (should (equal ranges '((3 . 8) (10 . 26))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-offset ()
  "Shimmed treesit-query-range with offset works correctly."
  (let ((buf (generate-new-buffer " *md-ts-test-qr-off*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n\nPara *bold* end.\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (ranges (treesit-query-range
                          root '((inline) @cap)
                          nil nil '(1 . -1))))
            (should (equal ranges '((4 . 7) (11 . 25))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-with-range-fn ()
  "Shimmed treesit-query-range calls RANGE-FN when provided.
Pass `treesit-range-fn-exclude-children' as RANGE-FN for an
atx_heading query.  The heading has children, so the returned
ranges should be the gaps between children, not a single range."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-qr-fn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 ;; Query captures the atx_heading node
                 (ranges (treesit-query-range
                          root '((atx_heading) @cap)
                          nil nil nil
                          #'treesit-range-fn-exclude-children)))
            ;; atx_heading (1-9) has children at 1-2 and 3-8
            ;; exclude-children returns gaps: (1.1) (2.3) (8.9)
            (should (equal ranges '((1 . 1) (2 . 3) (8 . 9))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-range-fn-with-offset ()
  "Shimmed treesit-query-range passes OFFSET to RANGE-FN."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-qr-fn-off*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (ranges (treesit-query-range
                          root '((atx_heading) @cap)
                          nil nil '(1 . -1)
                          #'treesit-range-fn-exclude-children)))
            ;; With offset (1 . -1): start=2, end=8
            ;; Gaps: (2.1) (2.3) (8.8)
            (should (equal ranges '((2 . 1) (2 . 3) (8 . 8))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-by-language ()
  "treesit-query-range-by-language groups ranges by resolved language.
Two fenced code blocks (python and bash) should produce an alist
with separate range lists for each language."
  (let ((buf (generate-new-buffer " *md-ts-test-qrbl*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n\n```bash\necho hi\n```\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (query '((fenced_code_block
                           (info_string (language) @language)
                           (code_fence_content) @content)))
                 (result (treesit-query-range-by-language
                          root query
                          (lambda (node)
                            (intern (treesit-node-text node))))))
            ;; Should return alist with python and bash entries
            (should (assq 'python result))
            (should (assq 'bash result))
            ;; Each entry's ranges should be a list of (START . END) pairs
            (should (= 1 (length (cdr (assq 'python result)))))
            (should (= 1 (length (cdr (assq 'bash result)))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-by-language-nil-skips ()
  "treesit-query-range-by-language skips ranges when LANGUAGE-FN returns nil."
  (let ((buf (generate-new-buffer " *md-ts-test-qrbl-nil*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ncode\n```\n\n```unknown\nstuff\n```\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (query '((fenced_code_block
                           (info_string (language) @language)
                           (code_fence_content) @content)))
                 (result (treesit-query-range-by-language
                          root query
                          (lambda (node)
                            (let ((text (treesit-node-text node)))
                              (if (string= text "python")
                                  'python
                                nil))))))
            ;; Only python should appear; "unknown" returns nil
            (should (assq 'python result))
            (should-not (assq 'unknown result))
            (should (= 1 (length result)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-query-range-by-language-range-fn ()
  "treesit-query-range-by-language passes RANGE-FN through.
The code_fence_content node has parser-injected children, so
exclude-children returns multiple gap ranges rather than a single
range.  Verify that RANGE-FN is called by checking the number of
ranges differs from 1 (which is what you'd get without RANGE-FN)."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-qrbl-fn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let* ((parser (treesit-parser-create 'markdown))
                 (root (treesit-parser-root-node parser))
                 (query '((fenced_code_block
                           (info_string (language) @language)
                           (code_fence_content) @content)))
                 ;; Without range-fn: one range per captured node
                 (result-plain (treesit-query-range-by-language
                                root query
                                (lambda (node)
                                  (intern (treesit-node-text node)))))
                 ;; With range-fn: exclude-children splits into gaps
                 (result-fn (treesit-query-range-by-language
                             root query
                             (lambda (node)
                               (intern (treesit-node-text node)))
                             nil nil nil
                             #'treesit-range-fn-exclude-children))
                 (plain-ranges (cdr (assq 'python result-plain)))
                 (fn-ranges (cdr (assq 'python result-fn))))
            ;; Without range-fn: exactly 1 range
            (should (= 1 (length plain-ranges)))
            ;; With range-fn: more ranges (exclude-children splits)
            (should (> (length fn-ranges) 1))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-rules-range-fn ()
  "treesit-range-rules accepts :range-fn and produces a 5-element tuple.
This should pass for our Emacs 29/30 shim and for native Emacs builds
where the upstream shadowing bug is fixed.  On affected Emacs 31 builds,
we still expect the historical failure until upstream is corrected."
  :expected-result (if (md-ts-test--range-rules-supports-range-fn-p)
                       :passed :failed)
  (let ((settings (treesit-range-rules
                   :embed 'markdown-inline
                   :host 'markdown
                   :range-fn #'treesit-range-fn-exclude-children
                   '((inline) @cap))))
    (should (= 1 (length settings)))
    (let ((tuple (car settings)))
      ;; 5 elements: (QUERY EMBED LOCAL OFFSET RANGE-FN)
      (should (= 5 (length tuple)))
      (should (eq (nth 1 tuple) 'markdown-inline))
      (should (null (nth 2 tuple)))   ; local
      (should (null (nth 3 tuple)))   ; offset
      (should (eq (nth 4 tuple) #'treesit-range-fn-exclude-children)))))

(ert-deftest md-ts-test-range-rules-function-embed ()
  "Shimmed treesit-range-rules accepts function-form :embed."
  (skip-unless md-ts--range-shims-installed)
  (let ((settings (treesit-range-rules
                   :embed #'md-ts--convert-code-block-language
                   :host 'markdown
                   :local t
                   '((fenced_code_block
                      (info_string (language) @language)
                      (code_fence_content) @content)))))
    (should (= 1 (length settings)))
    (let ((tuple (car settings)))
      (should (= 5 (length tuple)))
      ;; embed is a function, stored at position 1
      (should (functionp (nth 1 tuple)))
      (should (eq (nth 2 tuple) t)))))  ; local

(ert-deftest md-ts-test-optional-front-matter-query-probes-capture ()
  "Optional front matter query support should catch deferred query errors."
  (cl-letf (((symbol-function 'treesit-query-compile)
             (lambda (_language _query) t))
            ((symbol-function 'md-ts--buffer-root-node)
             (lambda (_language) :root))
            ((symbol-function 'treesit-query-capture)
             (lambda (&rest _args)
               (signal 'treesit-query-error '("bad node")))))
    (should-not (md-ts--query-supported-p
                 'markdown '((minus_metadata) @yaml)))))

(ert-deftest md-ts-test-optional-front-matter-range-rules-skip-unsupported ()
  "Optional front matter range rules should skip missing node types."
  (cl-letf (((symbol-function 'md-ts--query-supported-p)
             (lambda (_language _query) nil))
            ((symbol-function 'treesit-range-rules)
             (lambda (&rest _args)
               (ert-fail "treesit-range-rules called for unsupported query"))))
    (should-not (md-ts--front-matter-range-settings
                 'yaml '((minus_metadata) @yaml)))))

(ert-deftest md-ts-test-optional-front-matter-range-rules-catch-query-error ()
  "Optional front matter range rules should tolerate range-rule query errors."
  (cl-letf (((symbol-function 'md-ts--query-supported-p)
             (lambda (_language _query) t))
            ((symbol-function 'treesit-range-rules)
             (lambda (&rest _args)
               (signal 'treesit-query-error '("bad node")))))
    (should-not (md-ts--front-matter-range-settings
                 'yaml '((minus_metadata) @yaml)))))

(ert-deftest md-ts-test-refresh-local-parsers-ignores-non-md-ts-buffers ()
  "Global native range advice should not refresh non-md-ts buffers."
  (skip-unless (and (fboundp 'md-ts--refresh-local-parsers)
                    (treesit-ready-p 'markdown t)))
  (let ((buf (generate-new-buffer " *md-ts-test-refresh-non-md*"))
        (called nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Not md-ts-mode\n")
          (text-mode)
          (let* ((parser (treesit-parser-create 'markdown))
                 (ov (make-overlay (point-min) (point-max))))
            (overlay-put ov 'treesit-parser parser)
            (overlay-put ov 'treesit-parser-ov-timestamp 0)
            (cl-letf (((symbol-function 'md-ts--recreate-local-parser)
                       (lambda (&rest _args)
                         (setq called t)
                         parser)))
              (funcall 'md-ts--refresh-local-parsers))
            (should-not called)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-rules-no-range-fn ()
  "Shimmed treesit-range-rules without :range-fn still produces 5-element tuple.
The 5th element should be nil."
  (skip-unless md-ts--range-shims-installed)
  (let ((settings (treesit-range-rules
                   :embed 'markdown-inline
                   :host 'markdown
                   :offset '(1 . -1)
                   '((inline) @cap))))
    (should (= 1 (length settings)))
    (let ((tuple (car settings)))
      (should (= 5 (length tuple)))
      (should (eq (nth 1 tuple) 'markdown-inline))
      (should (equal (nth 3 tuple) '(1 . -1)))
      (should (null (nth 4 tuple))))))

(ert-deftest md-ts-test-update-ranges-local-symbol-embed ()
  "treesit--update-ranges-local creates local parsers for symbol embed.
Create a markdown buffer with a python code block, call
treesit--update-ranges-local with a symbol embed language, and
verify that a local python parser overlay is created."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-url-sym*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (funcall (symbol-function 'treesit--update-ranges-local) query 'python tick)
            ;; Should have created an overlay with a python parser
            (let ((found nil))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (when-let* ((p (overlay-get ov 'treesit-parser)))
                  (when (eq (treesit-parser-language p) 'python)
                    (setq found t))))
              (should found))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-local-function-embed ()
  "treesit--update-ranges-local handles function-form embedded-lang.
Use a language resolver function that returns \\='python for the
\\='python info string.  Verify a local python parser is created."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-url-fn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (info_string (language) @language)
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick))
                 (lang-fn (lambda (node)
                            (intern (treesit-node-text node)))))
            (funcall (symbol-function 'treesit--update-ranges-local) query lang-fn tick)
            ;; Should have created an overlay with a python parser
            (let ((found nil))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (when-let* ((p (overlay-get ov 'treesit-parser)))
                  (when (eq (treesit-parser-language p) 'python)
                    (setq found t))))
              (should found))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-local-one-overlay ()
  "treesit--update-ranges-local without range-fn creates one overlay per range."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-url-one*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (funcall (symbol-function 'treesit--update-ranges-local) query 'python tick)
            (let ((count 0))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (when (overlay-get ov 'treesit-parser)
                  (setq count (1+ count))))
              (should (= 1 count)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-local-range-fn ()
  "treesit--update-ranges-local with range-fn creates multiple overlays.
exclude-children splits code_fence_content (which has children)
into multiple gap ranges, creating more overlays than without."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-url-rfn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (funcall (symbol-function 'treesit--update-ranges-local)
                     query 'python tick nil nil nil
                     #'treesit-range-fn-exclude-children)
            (let ((count 0))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (when (overlay-get ov 'treesit-parser)
                  (setq count (1+ count))))
              ;; code_fence_content has children → multiple gap overlays
              (should (> count 1)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-non-local ()
  "Shimmed treesit-update-ranges handles non-local range settings.
Set treesit-range-settings with a symbol embed, call
treesit-update-ranges, and verify the embedded parser's ranges
are set correctly."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-ur-nl*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n\nPara *bold* end.\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (inline-parser (treesit-parser-create 'markdown-inline)))
            (setq-local treesit-range-settings
                        (treesit-range-rules
                         :embed 'markdown-inline
                         :host 'markdown
                         '((inline) @cap)))
            (treesit-update-ranges)
            ;; The inline parser should have ranges matching (inline) nodes
            (let ((ranges (treesit-parser-included-ranges inline-parser)))
              (should ranges)
              (should (= 2 (length ranges))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-non-local-range-fn ()
  "Shimmed treesit-update-ranges passes range-fn for non-local settings.
With treesit-range-fn-exclude-children as range-fn, the inline
parser should get multiple gap ranges per (inline) node."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-ur-rfn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Hello\n\nPara *bold* end.\n")
          (let* ((_md-parser (treesit-parser-create 'markdown))
                 (inline-parser (treesit-parser-create 'markdown-inline)))
            ;; Without range-fn: 2 ranges (one per inline node)
            (setq-local treesit-range-settings
                        (treesit-range-rules
                         :embed 'markdown-inline
                         :host 'markdown
                         '((inline) @cap)))
            (treesit-update-ranges)
            (let ((ranges-without (treesit-parser-included-ranges
                                   inline-parser)))
              ;; With range-fn: more ranges (gaps between children)
              (setq-local treesit-range-settings
                          (treesit-range-rules
                           :embed 'markdown-inline
                           :host 'markdown
                           :range-fn #'treesit-range-fn-exclude-children
                           '((inline) @cap)))
              (treesit-update-ranges)
              (let ((ranges-with (treesit-parser-included-ranges
                                  inline-parser)))
                (should (> (length ranges-with)
                           (length ranges-without)))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-update-ranges-local-dispatch ()
  "Shimmed treesit-update-ranges dispatches :local settings correctly.
Set treesit-range-settings with :local t and function embed,
call treesit-update-ranges, and verify a local parser overlay
is created."
  (skip-unless md-ts--range-shims-installed)
  (let ((buf (generate-new-buffer " *md-ts-test-ur-loc*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    pass\n```\n")
          (let ((_md-parser (treesit-parser-create 'markdown)))
            (setq-local treesit-range-settings
                        (treesit-range-rules
                         :embed #'(lambda (node)
                                    (intern (treesit-node-text node)))
                         :host 'markdown
                         :local t
                         '((fenced_code_block
                            (info_string (language) @language)
                            (code_fence_content) @content))))
            (treesit-update-ranges)
            ;; Should have a local python parser overlay
            (let ((found nil))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (when-let* ((p (overlay-get ov 'treesit-parser)))
                  (when (eq (treesit-parser-language p) 'python)
                    (setq found t))))
              (should found))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-settings-active ()
  "Range settings should be active after mode setup.
At minimum two rules exist (inline parser + code block).
Additional rules appear when html/yaml/toml grammars are installed."
  (let ((buf (generate-new-buffer " *md-ts-test-range*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# test\n")
          (md-ts-mode)
          (should treesit-range-settings)
          (should (>= (length treesit-range-settings) 2)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-settings-inline-tuple ()
  "Inline range rule is local for paragraph (inline) nodes."
  (let ((buf (generate-new-buffer " *md-ts-test-inline*")))
    (unwind-protect
        (with-current-buffer buf
          (md-ts-mode)
          (let ((inline-rule (car treesit-range-settings)))
            ;; 5-element tuple: (QUERY EMBED LOCAL OFFSET RANGE-FN)
            (should (= 5 (length inline-rule)))
            ;; EMBED is markdown-inline
            (should (eq 'markdown-inline (nth 1 inline-rule)))
            ;; LOCAL is t — each (inline) gets its own parser
            (should (eq t (nth 2 inline-rule)))
            ;; RANGE-FN is nil
            (should (null (nth 4 inline-rule)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-global-inline-parser-empty-ranges ()
  "The global markdown-inline parser should have empty ranges."
  (let ((buf (generate-new-buffer " *md-ts-test-gip*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "**Bold** text.\n\nMore text.\n")
          (md-ts-mode)
          (font-lock-ensure)
          ;; Collect overlay-owned parsers so we can identify the
          ;; global one (Emacs 29 returns both from treesit-parser-list).
          (let* ((local-parsers
                  (mapcar (lambda (ov) (overlay-get ov 'treesit-parser))
                          (seq-filter (lambda (ov)
                                        (overlay-get ov 'treesit-parser))
                                      (overlays-in (point-min) (point-max)))))
                 (global-p
                  (car (seq-filter
                        (lambda (p)
                          (and (eq (treesit-parser-language p)
                                   'markdown-inline)
                               (not (memq p local-parsers))))
                        (treesit-parser-list)))))
            (should global-p)
            (should (equal (treesit-parser-included-ranges global-p)
                           `((,(point-min) . ,(point-min)))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-range-settings-code-block-tuple ()
  "Code block range rule uses function-form embed and local flag."
  (let ((buf (generate-new-buffer " *md-ts-test-cb*")))
    (unwind-protect
        (with-current-buffer buf
          (md-ts-mode)
          ;; Find the rule with a function-form embed (the code-block rule)
          (let ((code-rule (seq-find (lambda (r) (functionp (nth 1 r)))
                                     treesit-range-settings)))
            (should code-rule)
            ;; 5-element tuple
            (should (= 5 (length code-rule)))
            ;; EMBED is a function
            (should (functionp (nth 1 code-rule)))
            ;; LOCAL is t
            (should (eq t (nth 2 code-rule)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-harvest-filters-function-range-settings ()
  "Harvested configs keep query-based range settings, drop function-based."
  (let ((treesit-range-settings nil)
        (treesit-font-lock-settings nil)
        (treesit-simple-indent-rules nil)
        ;; 5-element tuple: (QUERY LANGUAGE LOCAL OFFSET RANGE-FN)
        (query-setting '("(query)" c nil nil nil))
        (fn-setting (list #'ignore nil nil nil nil)))
    (cl-letf (((symbol-function 'md-ts--harvest-treesit-configs)
               (lambda (_mode)
                 (list :font-lock nil
                       :simple-indent nil
                       :range (list query-setting fn-setting)))))
      (md-ts--add-config-for-mode 'c 'c-ts-mode)
      (should (equal (length treesit-range-settings) 1))
      (should (equal (car treesit-range-settings) query-setting)))))

;;; Emacs 29 compat shim tests

(ert-deftest md-ts-test-node-children-shim ()
  "treesit-node-children returns all children of a node."
  (let ((buf (generate-new-buffer " *md-ts-test-nc*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Heading\n")
          (treesit-parser-create 'markdown)
          (font-lock-ensure)
          (let* ((root (treesit-buffer-root-node 'markdown))
                 (children (treesit-node-children root)))
            (should (listp children))
            (should (> (length children) 0))
            ;; Each child should be a node
            (dolist (child children)
              (should (treesit-node-type child)))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-parser-create-wrapper ()
  "md-ts--parser-create accepts TAG without error."
  (skip-unless (fboundp 'md-ts--parser-create))
  (let ((buf (generate-new-buffer " *md-ts-test-pc*")))
    (unwind-protect
        (with-current-buffer buf
          ;; 4-arg call should work on any Emacs version via wrapper
          (let ((parser (md-ts--parser-create 'markdown nil t 'test)))
            (should parser)
            (should (eq (treesit-parser-language parser) 'markdown))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-parser-list-wrapper ()
  "md-ts--parser-list filters by language."
  (skip-unless (fboundp 'md-ts--parser-list))
  (let ((buf (generate-new-buffer " *md-ts-test-pl*")))
    (unwind-protect
        (with-current-buffer buf
          (treesit-parser-create 'markdown)
          (treesit-parser-create 'markdown-inline)
          ;; Filter by language
          (let ((md-parsers (md-ts--parser-list nil 'markdown)))
            (should (= 1 (length md-parsers)))
            (should (eq (treesit-parser-language (car md-parsers))
                        'markdown)))
          ;; No filter
          (let ((all-parsers (md-ts--parser-list)))
            (should (>= (length all-parsers) 2))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-derived-mode-add-parents-exists ()
  "derived-mode-add-parents should be callable without error."
  ;; On Emacs 30+ it's native, on 29 it's our no-op shim.
  (should (fboundp 'derived-mode-add-parents))
  (derived-mode-add-parents 'md-ts-mode '(markdown-mode)))

(ert-deftest md-ts-test-outline-predicate-bound ()
  "treesit-outline-predicate should be a bound variable."
  (should (boundp 'treesit-outline-predicate)))

;;; End-to-end integration tests (Phase 4.2)

(ert-deftest md-ts-test-code-block-local-parser ()
  "Python code block should get a local python parser."
  (skip-unless (md-ts-test--python-local-parser-available-p))
  (let ((buf (generate-new-buffer " *md-ts-test-cblp*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Title\n\n```python\ndef foo():\n    pass\n```\n")
          (md-ts-mode)
          (treesit-update-ranges)
          (let ((found nil))
            (dolist (ov (overlays-in (point-min) (point-max)))
              (when-let* ((p (overlay-get ov 'treesit-parser)))
                (when (eq (treesit-parser-language p) 'python)
                  (setq found t))))
            (should found)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-code-block-fontification ()
  "Python code block content should have python-specific font-lock faces.
The face property is a list because `md-ts-code' is appended as a
base layer beneath the language-specific faces."
  (skip-unless (md-ts-test--python-ts-mode-font-lock-compatible-p))
  (let ((buf (generate-new-buffer " *md-ts-test-cbf*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```python\ndef foo():\n    return 42\n```\n")
          (md-ts-mode)
          (font-lock-ensure)
          ;; `def' should have keyword face (with md-ts-code appended)
          (goto-char (point-min))
          (search-forward "def")
          (let ((face (get-text-property (match-beginning 0) 'face)))
            (should (memq 'font-lock-keyword-face
                          (if (listp face) face (list face)))))
          ;; `foo' should have function-name face
          (goto-char (point-min))
          (search-forward "foo")
          (let ((face (get-text-property (match-beginning 0) 'face)))
            (should (memq 'font-lock-function-name-face
                          (if (listp face) face (list face)))))
          ;; Both should also carry md-ts-code as the base layer
          (goto-char (point-min))
          (search-forward "def")
          (let ((face (get-text-property (match-beginning 0) 'face)))
            (should (memq 'md-ts-code
                          (if (listp face) face (list face))))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-unknown-grammar-graceful ()
  "Code block with unavailable grammar should not error."
  (let ((buf (generate-new-buffer " *md-ts-test-ugr*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "```unknownlang42\nsome code\n```\n")
          (md-ts-mode)
          ;; Should not error
          (font-lock-ensure)
          (should t))
      (kill-buffer buf))))

;;; Mode activation test

(ert-deftest md-ts-test-mode-activation ()
  "md-ts-mode should activate without error."
  (let ((buf (generate-new-buffer " *md-ts-test-mode*")))
    (unwind-protect
        (with-current-buffer buf
          (md-ts-mode)
          (should (eq major-mode 'md-ts-mode))
          (should (derived-mode-p 'text-mode)))
      (kill-buffer buf))))

(ert-deftest md-ts-test-mode-parents ()
  "md-ts-mode should report markdown-mode as parent.
`derived-mode-add-parents' is a no-op on Emacs 29, so the parent
relationship only exists on Emacs 30+."
  (skip-unless (>= emacs-major-version 30))
  (let ((buf (generate-new-buffer " *md-ts-test-parents*")))
    (unwind-protect
        (with-current-buffer buf
          (md-ts-mode)
          (should (derived-mode-p 'markdown-mode)))
      (kill-buffer buf))))

;;; Fixture snapshot helpers

(defun md-ts-test--normalize-face (face)
  "Normalize FACE for deterministic snapshots.
nil stays nil.  A bare symbol stays as-is.  A single-element list
becomes a bare symbol.  A multi-element list is deduplicated and
sorted alphabetically."
  (cond
   ((null face) nil)
   ((symbolp face) face)
   ((and (listp face) (= 1 (length face))) (car face))
   ((listp face)
    (let ((deduped (seq-uniq face)))
      (if (= 1 (length deduped))
          (car deduped)
        (sort (copy-sequence deduped)
              (lambda (a b)
                (string< (symbol-name a) (symbol-name b)))))))
   (t face)))

(defun md-ts-test--face-spans (buffer)
  "Extract face spans from BUFFER as a list of (TEXT FACE) entries.
Contiguous characters with the same normalized face are merged.
Consecutive nil-face spans are collapsed into one."
  (with-current-buffer buffer
    (let ((spans nil)
          (pos (point-min))
          (max (point-max)))
      (while (< pos max)
        (let* ((raw-face (get-text-property pos 'face))
               (face (md-ts-test--normalize-face raw-face))
               (next (next-single-property-change pos 'face nil max))
               (text (buffer-substring-no-properties pos next)))
          ;; Merge with previous span if same face
          (if (and spans (equal face (cadar spans)))
              (setcar (car spans) (concat (caar spans) text))
            (push (list text face) spans))
          (setq pos next)))
      (nreverse spans))))

(defun md-ts-test--test-dir ()
  "Return the test/ directory, resolved from `md-ts-mode' source location."
  (let ((mode-file (locate-library "md-ts-mode")))
    (if mode-file
        (expand-file-name "test/"
                          (file-name-directory mode-file))
      ;; Fallback: assume cwd is the project root
      (expand-file-name "test/" default-directory))))

(defun md-ts-test--fixture-path ()
  "Return absolute path to test/fixture.md."
  (expand-file-name "fixture.md" (md-ts-test--test-dir)))

(defun md-ts-test--snapshot-path ()
  "Return absolute path to the face snapshot for this Emacs version."
  (let ((versioned (expand-file-name "fixture-faces-emacs31.eld"
                                     (md-ts-test--test-dir))))
    (if (and (>= emacs-major-version 31)
             (file-exists-p versioned))
        versioned
      (expand-file-name "fixture-faces.eld" (md-ts-test--test-dir)))))

(defun md-ts-test--visible-path ()
  "Return absolute path to test/fixture-visible.txt."
  (expand-file-name "fixture-visible.txt" (md-ts-test--test-dir)))

(defun md-ts-test--fontify-fixture ()
  "Load test/fixture.md, fontify it, return face spans.
Returns a list of (TEXT FACE) entries."
  (let ((buf (generate-new-buffer " *md-ts-fixture*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (insert-file-contents (md-ts-test--fixture-path))
            (md-ts-mode)
            (font-lock-ensure))
          (md-ts-test--face-spans buf))
      (kill-buffer buf))))

(defun md-ts-test--setup-fixture-streamed ()
  "Create a buffer with fixture.md inserted line by line.
Activates `md-ts-mode', then inserts each line and calls
`font-lock-ensure' after every insertion.  Returns the live
buffer — caller must kill it."
  (let ((buf (generate-new-buffer " *md-ts-fixture-stream*"))
        (lines (with-temp-buffer
                 (insert-file-contents (md-ts-test--fixture-path))
                 (split-string (buffer-string) "\n"))))
    (with-current-buffer buf
      (md-ts-mode)
      (dolist (line lines)
        (goto-char (point-max))
        (insert line "\n")
        (font-lock-ensure))
      ;; split-string + rejoin adds a trailing newline; remove it
      ;; so the buffer content matches insert-file-contents exactly.
      (goto-char (point-max))
      (when (eq (char-before) ?\n)
        (delete-char -1))
      (font-lock-ensure))
    buf))

(defun md-ts-test--fontify-fixture-streamed ()
  "Like `md-ts-test--fontify-fixture', but insert line by line.
Simulates streaming (e.g. an LLM writing into the buffer).
Returns the same kind of (TEXT FACE) span list as the batch variant."
  (let ((buf (md-ts-test--setup-fixture-streamed)))
    (unwind-protect
        (md-ts-test--face-spans buf)
      (kill-buffer buf))))

(defun md-ts-test--visible-text (buf)
  "Extract visible text from BUF, skipping invisible characters."
  (with-current-buffer buf
    (let ((parts nil)
          (pos (point-min))
          (max (point-max)))
      (while (< pos max)
        (unless (get-text-property pos 'invisible)
          (push (buffer-substring-no-properties pos (1+ pos)) parts))
        (setq pos (1+ pos)))
      (apply #'concat (nreverse parts)))))

;;; Fixture snapshot test

(ert-deftest md-ts-test-fixture-snapshot ()
  "Fontified fixture.md must match the recorded face snapshot.
Run `make snapshot' to regenerate the current Emacs snapshot after
intentional changes."
  (let* ((snapshot-path (md-ts-test--snapshot-path))
         (expected (with-temp-buffer
                     (insert-file-contents snapshot-path)
                     (read (current-buffer))))
         (actual (md-ts-test--fontify-fixture)))
    (should (equal actual expected))))

(ert-deftest md-ts-test-fixture-visible ()
  "With hide-markup, visible text of fixture.md must match expected.
Fontifies fixture.md with `md-ts-hide-markup' enabled, extracts
only the characters that are not invisible, and compares against
test/fixture-visible.txt."
  (let* ((md-ts-hide-markup t)
         (buf (generate-new-buffer " *md-ts-visible*")))
    (unwind-protect
        (let (actual expected)
          (with-current-buffer buf
            (insert-file-contents (md-ts-test--fixture-path))
            (md-ts-mode)
            (font-lock-ensure))
          (setq actual (md-ts-test--visible-text buf))
          (setq expected (with-temp-buffer
                           (insert-file-contents (md-ts-test--visible-path))
                           (buffer-string)))
          (should (string= actual expected)))
      (kill-buffer buf))))

;;; Streamed (line-by-line) fixture tests
;;
;; These tests guard local-parser refresh by comparing streamed edits with
;; batch fontification.  See `md-ts--recreate-local-parser'.

(ert-deftest md-ts-test-fixture-snapshot-streamed ()
  "Streaming line-by-line must produce the same faces as batch.
Inserts fixture.md one line at a time with `font-lock-ensure'
after each insertion, then compares against the same recorded
face snapshot used by `md-ts-test-fixture-snapshot'."
  (let* ((snapshot-path (md-ts-test--snapshot-path))
         (expected (with-temp-buffer
                     (insert-file-contents snapshot-path)
                     (read (current-buffer))))
         (actual (md-ts-test--fontify-fixture-streamed)))
    (should (equal actual expected))))

(ert-deftest md-ts-test-fixture-visible-streamed ()
  "Streaming line-by-line with hide-markup must match expected visible text.
Like `md-ts-test-fixture-visible' but inserts fixture.md one line
at a time to simulate streaming output."
  (let* ((md-ts-hide-markup t)
         (buf (md-ts-test--setup-fixture-streamed)))
    (unwind-protect
        (let ((actual (md-ts-test--visible-text buf))
              (expected (with-temp-buffer
                          (insert-file-contents (md-ts-test--visible-path))
                          (buffer-string))))
          (should (string= actual expected)))
      (kill-buffer buf))))

;;; Grammar recipe tests

(ert-deftest md-ts-test-markdown-grammar-recipe-format ()
  "Markdown grammar recipes should use positional format for Emacs 30.
Keyword format (:commit, :source-dir) is Emacs 31 only.
Positional format (URL REVISION SOURCE-DIR) works on both."
  (let ((md-recipe (assq 'markdown treesit-language-source-alist))
        (mdi-recipe (assq 'markdown-inline treesit-language-source-alist)))
    ;; Both recipes should exist
    (should md-recipe)
    (should mdi-recipe)
    ;; URL (2nd element) should be a string
    (should (stringp (nth 1 md-recipe)))
    ;; REVISION (3rd element) should be a string tag, not a keyword
    (should (stringp (nth 2 md-recipe)))
    (should (not (keywordp (nth 2 md-recipe))))
    ;; SOURCE-DIR (4th element) should be a string
    (should (stringp (nth 3 md-recipe)))
    ;; Same for inline
    (should (stringp (nth 2 mdi-recipe)))
    (should (not (keywordp (nth 2 mdi-recipe))))))

(provide 'md-ts-mode-test)
;;; md-ts-mode-test.el ends here
