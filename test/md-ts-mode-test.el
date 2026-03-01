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

(require 'ert)
(require 'md-ts-mode)

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
    (cond
     ((null actual) nil)
     ((listp actual) (memq face actual))
     (t (eq face actual)))))

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

;;; Font-lock correctness tests

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
          (let ((disp (get-text-property (match-beginning 0) 'display)))
            (should disp)
            (should (stringp disp))
            (should (string-match-p "─" disp))))
      (kill-buffer buf))))

(ert-deftest md-ts-test-fenced-code-block ()
  "Fenced code block body should get `md-ts-code' face."
  (should (md-ts-test--has-face
           "```\nsome code\n```\n" "some code" 'md-ts-code)))

(ert-deftest md-ts-test-fenced-code-block-with-language ()
  "Fenced code block with language should get `md-ts-code' face on body."
  (should (md-ts-test--has-face
           "```python\nprint('hi')\n```\n" "print" 'md-ts-code)))

(ert-deftest md-ts-test-blockquote ()
  "Block quote should get `md-ts-block-quote' face."
  (should (md-ts-test--has-face
           "> quoted\n" "quoted" 'md-ts-block-quote)))

(ert-deftest md-ts-test-list-marker ()
  "List markers should get `md-ts-list-marker' face."
  (let ((text "- item one\n- item two\n"))
    (should (md-ts-test--has-face text "-" 'md-ts-list-marker))))

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
          (should (equal (get-text-property (match-beginning 0) 'display) "☐")))
      (kill-buffer buf))))

(ert-deftest md-ts-test-task-list-display-checked ()
  "Checked task marker gets display property showing ☑."
  (let ((buf (md-ts-test--fontify "- [x] done\n")))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "[x]")
          (should (equal (get-text-property (match-beginning 0) 'display) "☑")))
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
When code is syntax-highlighted, the language label is redundant."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "```python\nprint('hi')\n```\n"
                 "python")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-fenced-code-delimiter ()
  "With hide-markup, fenced code block delimiters are hidden."
  (let ((md-ts-hide-markup t))
    (should (eq (md-ts-test--invisible-at
                 "```python\nprint('hi')\n```\n"
                 "```")
                'md-ts--markup))))

(ert-deftest md-ts-test-hide-markup-fenced-code-no-phantom-lines ()
  "With hide-markup, newlines after fence lines are also hidden.
The entire opening line (``` + language + newline) and closing line
(``` + newline) should be invisible, leaving no phantom blank lines."
  (let* ((md-ts-hide-markup t)
         (text "```python\nprint('hi')\n```\n")
         (buf (md-ts-test--fontify text)))
    (unwind-protect
        (with-current-buffer buf
          ;; Newline after opening fence line (```python\n)
          ;; Position of \n is right after "```python" = position 10
          (should (eq (get-text-property 10 'invisible) 'md-ts--markup))
          ;; Code body should NOT be invisible
          (goto-char (point-min))
          (search-forward "print")
          (should-not (get-text-property (match-beginning 0) 'invisible))
          ;; Newline after closing fence (```\n)
          ;; text = "```python\nprint('hi')\n```\n"
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
  "Shimmed treesit-range-rules accepts :range-fn and produces 5-element tuple.
On Emacs 31, the native treesit-range-rules has a variable
shadowing bug that makes :range-fn dead code (nth 4 is always nil)."
  :expected-result (if md-ts--range-shims-installed
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
          (let* ((md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (treesit--update-ranges-local query 'python tick)
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
          (let* ((md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (info_string (language) @language)
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick))
                 (lang-fn (lambda (node)
                            (intern (treesit-node-text node)))))
            (treesit--update-ranges-local query lang-fn tick)
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
          (let* ((md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (treesit--update-ranges-local query 'python tick)
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
          (let* ((md-parser (treesit-parser-create 'markdown))
                 (query (treesit-query-compile
                         'markdown
                         '((fenced_code_block
                            (code_fence_content) @content))))
                 (tick (buffer-chars-modified-tick)))
            (treesit--update-ranges-local
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
          (let* ((md-parser (treesit-parser-create 'markdown))
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
          (let* ((md-parser (treesit-parser-create 'markdown))
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
          (let ((md-parser (treesit-parser-create 'markdown)))
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
  (skip-unless (treesit-language-available-p 'python))
  (let ((buf (generate-new-buffer " *md-ts-test-cblp*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "# Title\n\n```python\ndef foo():\n    pass\n```\n")
          (md-ts-mode)
          (font-lock-ensure)
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
  (skip-unless (treesit-language-available-p 'python))
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
