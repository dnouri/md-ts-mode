;;; md-ts-mode.el --- Major mode for Markdown using tree-sitter  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026 Free Software Foundation, Inc.
;; Copyright (C) 2025-2026 Daniel Nouri <daniel.nouri@gmail.com>

;; Author: Daniel Nouri <daniel.nouri@gmail.com>
;; URL: https://github.com/dnouri/md-ts-mode
;; Version: 0.3.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: markdown languages tree-sitter

;; Based on markdown-ts-mode from GNU Emacs 31 by Rahul Martim Juliato.

;; This file is NOT part of GNU Emacs.

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

;; A tree-sitter-based major mode for editing Markdown files.  Works
;; on Emacs 29, 30, and 31.  Features include syntax highlighting for
;; headings, emphasis, code spans, links, block quotes, and fenced
;; code blocks with embedded language highlighting.  Supported links are
;; clickable text buttons; `C-c C-o' runs `md-ts-open-link-at-point'.
;;
;; Requires tree-sitter grammars:
;; - tree-sitter-markdown v0.4.1+
;; - tree-sitter-markdown-inline v0.4.1+

;;; Code:

(require 'treesit)
(require 'button)
(require 'browse-url)
(require 'url-mailto)
(require 'url-parse)
(require 'goto-addr)
(require 'seq)
(require 'subr-x)
(require 'outline)

;;; Compatibility
;;
;; Backport shims for Emacs 31 tree-sitter features.  On Emacs 31+
;; all guards are false and no shims are defined.  Delete this
;; section when minimum Emacs is 31.

;; Silence byte-compiler for variables defined only in Emacs 30/31.
(defvar treesit-enabled-modes)
(defvar treesit-outline-predicate)
;; Ensure `treesit-outline-predicate' is bound on Emacs 29 (where
;; treesit.el doesn't define it) so `setq-local' works in `md-ts-mode'.
(unless (boundp 'treesit-outline-predicate)
  (setq treesit-outline-predicate nil))

;; Forward-declare functions that are either native (Emacs 30/31) or
;; installed via fset below.  Needed because the byte-compiler cannot
;; see inside `unless' guards.
(declare-function derived-mode-add-parents "derived" (mode parents))
(declare-function treesit--cleanup-local-range-overlays "treesit")
(declare-function treesit-ensure-installed "treesit")
(declare-function treesit-local-parsers-on "treesit")
(declare-function treesit-merge-font-lock-feature-list "treesit")
(declare-function treesit-range-rules "treesit")
(declare-function treesit-update-ranges "treesit")

;; Emacs 30 widened the signatures of these C functions (added TAG and
;; LANGUAGE arguments).  Declare the Emacs 30+ arglists so the Emacs
;; 29 byte-compiler accepts multi-version calls without warnings.
(declare-function treesit-parser-create "treesit.c"
  (language &optional buffer no-reuse tag))
(declare-function treesit-parser-list "treesit.c"
  (&optional buffer language))

;; Emacs 29 shims — C-level functions and variables missing before
;; Emacs 30.  Defined with md-ts-- prefix; aliased to the real name
;; when the native version is absent.

(defun md-ts--treesit-node-children (node &optional named)
  "Return a list of NODE's children.
If NAMED is non-nil, return only named children."
  (let ((count (treesit-node-child-count node named))
        (children nil))
    (dotimes (i count)
      (push (treesit-node-child node i named) children))
    (nreverse children)))

(unless (fboundp 'treesit-node-children)
  (fset 'treesit-node-children (symbol-function 'md-ts--treesit-node-children)))

(defun md-ts--derived-mode-add-parents (_mode _parents)
  "No-op shim.  `derived-mode-add-parents' was added in Emacs 30."
  nil)

(unless (fboundp 'derived-mode-add-parents)
  (fset 'derived-mode-add-parents
        (symbol-function 'md-ts--derived-mode-add-parents)))

(defun md-ts--treesit--cleanup-local-range-overlays (modified-tick beg end)
  "Delete local-parser overlays between BEG and END older than MODIFIED-TICK."
  (dolist (ov (overlays-in beg end))
    (when-let* ((ov-timestamp
                 (overlay-get ov 'treesit-parser-ov-timestamp)))
      (when (< ov-timestamp modified-tick)
        (when-let* ((local-parser (overlay-get ov 'treesit-parser)))
          (treesit-parser-delete local-parser))
        (delete-overlay ov)))))

(unless (fboundp 'treesit--cleanup-local-range-overlays)
  (fset 'treesit--cleanup-local-range-overlays
        (symbol-function 'md-ts--treesit--cleanup-local-range-overlays)))

;; Always t after loading: on Emacs 31 the native functions exist;
;; on 29/30 the shims defined below provide them.  Initialized here
;; so that `defvar' is the sole declaration (no top-level `setq').
(defvar md-ts--range-shims-ready t
  "Non-nil when all range-related tree-sitter shims are available.")

(defvar md-ts--range-shims-installed nil
  "Non-nil when md-ts-mode installed its own range shims.
This is nil on Emacs 31+ where the native versions are used.")

;; Emacs 29/30 shims — range infrastructure, utility functions, and
;; C-function arity adapters.  Defined with md-ts-- prefix and
;; aliased to the real name when the native version is absent.
;; Delete this section when minimum Emacs is 31.

(defmacro md-ts--declare-unavailable-functions ()
  "Declare treesit C functions for the byte-compiler."
  '(progn
     (declare-function treesit-language-available-p "treesit.c")
     (declare-function treesit-parser-create "treesit.c")
     (declare-function treesit-node-parent "treesit.c")
     (declare-function treesit-node-child "treesit.c")
     (declare-function treesit-node-type "treesit.c")
     (declare-function treesit-node-start "treesit.c")
     (declare-function treesit-node-end "treesit.c")
     (declare-function treesit-node-string "treesit.c")
     (declare-function treesit-node-check "treesit.c")
     (declare-function treesit-query-capture "treesit.c")
     (declare-function treesit-search-subtree "treesit.c")
     (declare-function treesit-search-forward "treesit.c")
     (declare-function treesit-available-p "treesit.c")
     (defvar treesit-thing-settings)
     (defvar treesit-major-mode-remap-alist)
     (defvar treesit-extra-load-path)
     (defvar treesit-enabled-modes)))

(defun md-ts--treesit-ensure-installed (lang)
  "Ensure the grammar for LANG is available."
  (treesit-ready-p lang t))

(defun md-ts--treesit-merge-font-lock-feature-list (features-1 features-2)
  "Merge FEATURES-1 and FEATURES-2, removing duplicates per level."
  (let ((result nil))
    (while (or (car features-1) (car features-2))
      (cond
       ((and (car features-1) (not (car features-2)))
        (push (car features-1) result))
       ((and (not (car features-1)) (car features-2))
        (push (car features-2) result))
       (t (push (seq-uniq (append (car features-1) (car features-2)))
                result)))
      (setq features-1 (cdr features-1)
            features-2 (cdr features-2)))
    (nreverse result)))

;; Emacs 29/30 C-function arity adapters.
;;
;; Emacs 30 added a TAG argument to `treesit-parser-create' and
;; LANGUAGE/TAG filters to `treesit-parser-list'.  Emacs 29 has
;; narrower signatures.  These helpers abstract the difference.

(defun md-ts--parser-create (lang &optional buffer no-reuse tag)
  "Create a parser for LANG, like `treesit-parser-create'.
BUFFER, NO-REUSE, and TAG are passed through.
On Emacs 29, TAG is silently ignored."
  (if (>= emacs-major-version 30)
      (treesit-parser-create lang buffer no-reuse tag)
    (treesit-parser-create lang buffer no-reuse)))

(defun md-ts--parser-list (&optional buffer language)
  "Return parsers for BUFFER, optionally filtered by LANGUAGE.
On Emacs 29, applies the LANGUAGE filter in Lisp."
  (if (>= emacs-major-version 30)
      (treesit-parser-list buffer language)
    (let ((all (treesit-parser-list buffer)))
      (if language
          (seq-filter (lambda (p)
                        (eq (treesit-parser-language p) language))
                      all)
        all))))

;; Range functions.

(defun md-ts--treesit-range-fn-exclude-children (node offset)
  "Return ranges covering NODE but excluding its children.
OFFSET is a cons (START-OFFSET . END-OFFSET) added to the bounds."
  (let* ((start (+ (treesit-node-start node) (or (car offset) 0)))
         (end (+ (treesit-node-end node) (or (cdr offset) 0)))
         (prev-end start)
         (ranges nil))
    (dolist (child (treesit-node-children node))
      (let ((child-start (treesit-node-start child))
            (child-end (treesit-node-end child)))
        (push (cons prev-end child-start) ranges)
        (setq prev-end child-end)))
    (push (cons prev-end end) ranges)
    (nreverse ranges)))

(defun md-ts--treesit-query-range (node query &optional beg end offset
                                        range-fn)
  "Query NODE with QUERY and return a list of (START . END) ranges.
BEG, END restrict the query.  OFFSET is (START-OFFSET . END-OFFSET).
RANGE-FN, if non-nil, is called with (NODE OFFSET) to produce ranges
instead of simple offset arithmetic.  Captures starting with
underscore are ignored."
  (let ((offset-left (or (car offset) 0))
        (offset-right (or (cdr offset) 0))
        (result nil))
    (dolist (capture (treesit-query-capture node query beg end))
      (let ((name (car capture))
            (cap-node (cdr capture)))
        (unless (string-prefix-p "_" (symbol-name name))
          (if range-fn
              (dolist (r (funcall range-fn cap-node offset))
                (push r result))
            (push (cons (+ (treesit-node-start cap-node) offset-left)
                        (+ (treesit-node-end cap-node) offset-right))
                  result)))))
    (nreverse result)))

(defun md-ts--treesit-query-range-by-language
    (node query language-fn &optional beg end offset range-fn)
  "Like `treesit-query-range', but group ranges by language.
QUERY NODE and return an alist ((LANGUAGE . RANGES) ...).
Nodes captured as @language are passed to LANGUAGE-FN to determine
the language symbol; nil means skip.  Other captures produce ranges
for the most recently resolved language.  BEG, END, OFFSET, and
RANGE-FN have the same meaning as in `treesit-query-range'."
  (let ((offset-left (or (car offset) 0))
        (offset-right (or (cdr offset) 0))
        (current-lang nil)
        (ranges-by-language nil))
    (dolist (capture (treesit-query-capture node query beg end))
      (let ((name (car capture))
            (cap-node (cdr capture)))
        (cond
         ((eq name 'language)
          (setq current-lang (funcall language-fn cap-node)))
         ((string-prefix-p "_" (symbol-name name))
          nil)
         (current-lang
          (let ((ranges (if range-fn
                           (funcall range-fn cap-node offset)
                         (list (cons (+ (treesit-node-start cap-node)
                                        offset-left)
                                     (+ (treesit-node-end cap-node)
                                        offset-right)))))
                (entry (assq current-lang ranges-by-language)))
            (if entry
                (setcdr entry (append (cdr entry) ranges))
              (push (cons current-lang ranges) ranges-by-language)))))))
    (nreverse ranges-by-language)))

(defun md-ts--treesit-range-rules (&rest query-specs)
  "Produce settings for `treesit-range-settings'.
QUERY-SPECS are alternating :KEYWORD VALUE pairs followed by a
QUERY.  Accepts :embed, :host, :local, :offset, and :range-fn.
:embed can be a symbol (language) or a function (dynamic language).
Returns a list of 5-element tuples (QUERY EMBED LOCAL OFFSET RANGE-FN)."
  (let (host embed offset result local range-fn)
    (while query-specs
      (pcase (pop query-specs)
        (:local (when (eq t (pop query-specs))
                  (setq local t)))
        (:host
         (let ((host-lang (pop query-specs)))
           (unless (symbolp host-lang)
             (signal 'treesit-error
                     (list "Value of :host option should be a symbol"
                           host-lang)))
           (setq host host-lang)))
        (:embed
         (let ((embed-lang (pop query-specs)))
           (unless (or (symbolp embed-lang)
                       (functionp embed-lang))
             (signal 'treesit-error
                     (list "Value of :embed option should be a symbol or a function"
                           embed-lang)))
           (setq embed embed-lang)))
        (:offset
         (let ((range-offset (pop query-specs)))
           (unless (and (consp range-offset)
                        (numberp (car range-offset))
                        (numberp (cdr range-offset)))
             (signal 'treesit-error
                     (list "Value of :offset option should be a pair of numbers"
                           range-offset)))
           (setq offset range-offset)))
        (:range-fn
         (let ((fn (pop query-specs)))
           (unless (functionp fn)
             (signal 'treesit-error
                     (list "Value of :range-fn option should be a function"
                           fn)))
           (setq range-fn fn)))
        (query
         (if (functionp query)
             (push (list query nil nil) result)
           (when (null embed)
             (signal 'treesit-error
                     (list "Value of :embed option cannot be omitted")))
           (when (null host)
             (signal 'treesit-error
                     (list "Value of :host option cannot be omitted")))
           (when (treesit-available-p)
             (push (list (treesit-query-compile host query)
                         embed local offset range-fn)
                   result)))
         (setq host nil embed nil offset nil
               local nil range-fn nil))))
    (nreverse result)))

;; Range dispatch.

(defun md-ts--query-ranges-by-lang
    (parser query lang &optional beg end offset range-fn)
  "Query PARSER with QUERY, returning ranges grouped by language.
If LANG is a function, use `md-ts--treesit-query-range-by-language'.
If LANG is a symbol, use `md-ts--treesit-query-range' and wrap the result.
BEG, END, OFFSET, and RANGE-FN are passed through."
  (if (functionp lang)
      (md-ts--treesit-query-range-by-language
       parser query lang beg end offset range-fn)
    (list (cons lang
                (md-ts--treesit-query-range
                 parser query beg end offset range-fn)))))

;; WORKAROUND: tree-sitter < 0.25.0 integer underflow in
;; `length_sub'/`point_sub'.  After an edit outside a local parser's
;; included range, unsigned subtraction underflows, corrupting point
;; fields and making incremental reparse silently produce zero query
;; matches.  Fixed upstream by commit f3d50f27 (ts 0.25.0, 2025-01-31).
;;
;; Workaround: replace the parser with a fresh one so
;; `ts_parser_parse' does a full (non-incremental) reparse.
;;
;; REMOVAL: once tree-sitter >= 0.25.0 can be assumed, delete this
;; function and its two call-sites (in
;; `md-ts--treesit--update-ranges-local' and
;; `md-ts--refresh-local-parsers').
(defun md-ts--recreate-local-parser (ov old-parser)
  "Delete OLD-PARSER on OV and create a fresh replacement.
Return the new parser, or nil if creation fails."
  (let ((lang (treesit-parser-language old-parser))
        (embed-level
         (when (fboundp 'treesit-parser-embed-level)
           (funcall (intern "treesit-parser-embed-level") old-parser))))
    (treesit-parser-delete old-parser)
    (let ((new-parser
           (condition-case nil
               (md-ts--parser-create lang nil t 'embedded)
             (treesit-load-language-error nil))))
      (when new-parser
        (when embed-level
          (funcall (intern "treesit-parser-set-embed-level")
                   new-parser embed-level))
        (overlay-put ov 'treesit-parser new-parser))
      new-parser)))

(defun md-ts--treesit--update-ranges-local
    (query embedded-lang modified-tick &optional beg end offset range-fn)
  "Update ranges for local parsers between BEG and END.
Use QUERY to find ranges and ensure each has a local parser for
EMBEDDED-LANG, which can be a symbol or a function.  MODIFIED-TICK,
OFFSET, and RANGE-FN control overlay timestamps and range computation."
  (let* ((host-lang (treesit-query-language query))
         (host-parser (treesit-parser-create host-lang))
         (ranges-by-lang (md-ts--query-ranges-by-lang
                          host-parser query embedded-lang
                          beg end offset range-fn)))
    (dolist (lang-and-ranges ranges-by-lang)
      (let ((lang (car lang-and-ranges))
            (ranges (cdr lang-and-ranges)))
        (pcase-dolist (`(,beg . ,end) ranges)
          (let ((has-parser
                 (catch 'done
                   (dolist (ov (overlays-in beg end) nil)
                     (when-let* ((embedded-parser
                                  (overlay-get ov 'treesit-parser))
                                 (parser-lang (treesit-parser-language
                                               embedded-parser)))
                       (when (eq parser-lang lang)
                         (let ((ov-tick (overlay-get
                                         ov
                                         'treesit-parser-ov-timestamp)))
                           (when (not (eql ov-tick modified-tick))
                             (setq embedded-parser
                                   (md-ts--recreate-local-parser
                                    ov embedded-parser))))
                         (when embedded-parser
                           (treesit-parser-set-included-ranges
                            embedded-parser `((,beg . ,end)))
                           (move-overlay ov beg end)
                           (overlay-put ov 'treesit-parser-ov-timestamp
                                        modified-tick))
                         (throw 'done t)))))))
            (when (not has-parser)
              (let ((embedded-parser
                     (condition-case nil
                         (md-ts--parser-create lang nil t 'embedded)
                       (treesit-load-language-error nil))))
                (when embedded-parser
                  (let ((ov (make-overlay beg end nil nil t)))
                    (overlay-put ov 'treesit-parser embedded-parser)
                    (overlay-put ov 'treesit-host-parser host-parser)
                    (overlay-put ov 'treesit-parser-ov-timestamp
                                 modified-tick)
                    (treesit-parser-set-included-ranges
                     embedded-parser `((,beg . ,end)))))))))))))

(defun md-ts--treesit-update-ranges (&optional beg end)
  "Update the ranges for each language in the current buffer.
If BEG and END are non-nil, only update ranges in that region."
  (let ((modified-tick (buffer-chars-modified-tick))
        (beg (or beg (point-min)))
        (end (or end (point-max))))
    (dolist (setting treesit-range-settings)
      (let ((query (nth 0 setting))
            (language (nth 1 setting))
            (local (nth 2 setting))
            (offset (nth 3 setting))
            (range-fn (nth 4 setting)))
        (cond
         ((functionp query) (funcall query beg end))
         (local
          (md-ts--treesit--update-ranges-local
           query language modified-tick beg end offset range-fn))
         (t
          (let* ((host-lang (treesit-query-language query))
                 (ranges-by-lang (md-ts--query-ranges-by-lang
                                  host-lang query language
                                  beg end offset range-fn)))
            (dolist (lang-and-ranges ranges-by-lang)
              (let* ((resolved-lang (car lang-and-ranges))
                     (new-ranges (cdr lang-and-ranges))
                     (parser (treesit-parser-create resolved-lang))
                     (old-ranges (treesit-parser-included-ranges parser))
                     (set-ranges (treesit--clip-ranges
                                  (treesit--merge-ranges
                                   old-ranges new-ranges beg end)
                                  (point-min) (point-max))))
                (dolist (p (md-ts--parser-list nil resolved-lang))
                  (treesit-parser-set-included-ranges
                   p (or set-ranges
                         `((,(point-min) . ,(point-min))))))))))))
    (treesit--cleanup-local-range-overlays modified-tick beg end))))

;; Alias all Emacs 31 range infrastructure shims.  The guard checks
;; for a function that only exists in Emacs 31; on 29/30 all shims
;; are installed.
(unless (fboundp 'treesit-range-fn-exclude-children)
  (dolist (pair `((treesit-ensure-installed
                   . md-ts--treesit-ensure-installed)
                  (treesit-merge-font-lock-feature-list
                   . md-ts--treesit-merge-font-lock-feature-list)
                  (treesit-range-fn-exclude-children
                   . md-ts--treesit-range-fn-exclude-children)
                  (treesit-query-range
                   . md-ts--treesit-query-range)
                  (treesit-query-range-by-language
                   . md-ts--treesit-query-range-by-language)
                  (treesit-range-rules
                   . md-ts--treesit-range-rules)
                  ;; Use intern to avoid triggering package-lint's
                  ;; private-symbol check for this Emacs-internal name.
                  (,(intern "treesit--update-ranges-local")
                   . md-ts--treesit--update-ranges-local)
                  (treesit-update-ranges
                   . md-ts--treesit-update-ranges)))
    (fset (car pair) (symbol-function (cdr pair))))
  (setq md-ts--range-shims-installed t))

;; On Emacs 31+ the native `treesit--update-ranges-local' is used
;; (our shims are not installed), so the workaround from
;; `md-ts--recreate-local-parser' must be applied via :before advice
;; on `treesit-update-ranges'.  It must be :before because the native
;; function stamps overlays with the current tick.
(unless md-ts--range-shims-installed
  (defun md-ts--refresh-local-parsers (&optional beg end)
    "Replace local parsers whose buffer was modified since last update.
Workaround for tree-sitter < 0.25.0 integer underflow — see
`md-ts--recreate-local-parser' for details.
Must run as :before advice on `treesit-update-ranges'."
    (let ((tick (buffer-chars-modified-tick))
          (beg (or beg (point-min)))
          (end (or end (point-max))))
      (dolist (ov (overlays-in beg end))
        (when-let* ((old-parser (overlay-get ov 'treesit-parser))
                    ((treesit-parser-language old-parser))
                    (ov-tick (overlay-get ov 'treesit-parser-ov-timestamp)))
          (when (not (eql ov-tick tick))
            (when-let* ((new-parser
                         (md-ts--recreate-local-parser ov old-parser)))
              (treesit-parser-set-included-ranges
               new-parser `((,(overlay-start ov) . ,(overlay-end ov))))))))))
  (advice-add 'treesit-update-ranges :before
              'md-ts--refresh-local-parsers))

;; Emacs 29 font-lock polyfill — local parser support.
;;
;; Emacs 29's `treesit-font-lock-fontify-region' calls
;; `treesit-buffer-root-node' which returns only the first parser for
;; each language.  When local parsers (per-node overlays) exist, a
;; local parser may shadow the non-local one and return a root node
;; that covers only a single inline range — dropping captures for all
;; other ranges.
;;
;; Worse, Emacs 29's `treesit-query-capture' silently returns nil
;; when a parser has disjoint included ranges, so even the non-local
;; parser with merged ranges cannot produce correct results.
;;
;; Emacs 30 added `treesit-local-parsers-on' and collects root nodes
;; from both local and global parsers.  However, it does NOT exclude
;; global parsers when local parsers exist for the same language —
;; so the global parser's cross-paragraph trees still get fontified.
;; We work around this by giving the global markdown-inline parser
;; empty ranges (see `md-ts-mode').  This polyfill goes further and
;; also excludes such global parsers from the root-node list.

(defun md-ts--treesit-local-parsers-on (&optional beg end _language
                                                  _with-host)
  "Return local parsers between BEG and END (Emacs 29 polyfill).
LANGUAGE and WITH-HOST are accepted for signature compatibility but
ignored."
  (let (result)
    (dolist (ov (overlays-in (or beg (point-min)) (or end (point-max))))
      (when-let* ((parser (overlay-get ov 'treesit-parser)))
        (push parser result)))
    (nreverse result)))

(unless (fboundp 'treesit-local-parsers-on)
  (fset 'treesit-local-parsers-on
        (symbol-function 'md-ts--treesit-local-parsers-on)))

(defun md-ts--treesit-font-lock-fontify-region (start end &optional loudly)
  "Fontify the region between START and END.
If LOUDLY is non-nil, display some debugging information.

This is an Emacs 29 polyfill that collects root nodes from both
local (per-overlay) parsers and global parsers, matching the
behavior of Emacs 30's `treesit-font-lock-fontify-region'."
  (when (or loudly treesit--font-lock-verbose)
    (message "Fontifying region: %s-%s" start end))
  (treesit-update-ranges start end)
  (font-lock-unfontify-region start end)
  (let* ((local-parsers (treesit-local-parsers-on start end))
         (local-langs (mapcar #'treesit-parser-language local-parsers))
         ;; Exclude global parsers whose language has local parsers.
         ;; Local parsers each have a single contiguous range and
         ;; produce correct query results; the global parser for the
         ;; same language has disjoint ranges and hits the Emacs 29
         ;; treesit-query-capture bug (silently returns nil).
         (global-parsers
          (seq-remove (lambda (p)
                        (memq (treesit-parser-language p) local-langs))
                      (treesit-parser-list)))
         (root-nodes
          (mapcar #'treesit-parser-root-node
                  (append local-parsers global-parsers))))
    (dolist (setting treesit-font-lock-settings)
      (let* ((query (nth 0 setting))
             (enable (nth 1 setting))
             (override (nth 3 setting))
             (language (treesit-query-language query))
             (root-nodes
              (seq-filter
               (lambda (node)
                 (eq (treesit-node-language node) language))
               root-nodes)))
        (when (eq treesit--font-lock-fast-mode 'unspecified)
          (pcase-let ((`(,max-depth ,max-width)
                       (treesit-subtree-stat
                        (treesit-buffer-root-node language))))
            (if (or (> max-depth 100) (> max-width 4000))
                (setq treesit--font-lock-fast-mode t)
              (setq treesit--font-lock-fast-mode nil))))
        (when-let*
            ((activate (eq t enable))
             (nodes (if (eq t treesit--font-lock-fast-mode)
                        (mapcan
                         (lambda (node)
                           (treesit--children-covering-range-recurse
                            node start end (* 4 jit-lock-chunk-size)))
                         root-nodes)
                      root-nodes)))
          (ignore activate) ; silence byte-compiler unused-variable warning
          (dolist (sub-node nodes)
            (let* ((delta-start
                    (car treesit--font-lock-query-expand-range))
                   (delta-end
                    (cdr treesit--font-lock-query-expand-range))
                   (captures
                    (treesit-query-capture
                     sub-node query
                     (max (- start delta-start) (point-min))
                     (min (+ end delta-end) (point-max)))))
              (with-silent-modifications
                (dolist (capture captures)
                  (let* ((face (car capture))
                         (node (cdr capture))
                         (node-start (treesit-node-start node))
                         (node-end (treesit-node-end node)))
                    (if (and (facep face)
                             (or (>= start node-end)
                                 (>= node-start end)))
                        (when (or loudly treesit--font-lock-verbose)
                          (message
                           "Captured node %s(%s-%s) but it is outside of fontifying region"
                           node node-start node-end))
                      (cond
                       ((facep face)
                        (treesit-fontify-with-override
                         (max node-start start) (min node-end end)
                         face override))
                       ((functionp face)
                        (funcall face node override start end)))
                      (when (or loudly treesit--font-lock-verbose)
                        (message
                         "Fontifying text from %d to %d, Face: %s, Node: %s"
                         (max node-start start) (min node-end end)
                         face
                         (treesit-node-type node)))))))))))))
  `(jit-lock-bounds ,start . ,end))

;; On Emacs 29, the native `treesit-font-lock-fontify-region' only
;; queries global parsers.  Our polyfill also collects local (overlay-
;; based) parsers, matching Emacs 30+ behavior.  We guard on the Emacs
;; version rather than `fboundp' because we already shimmed
;; `treesit-local-parsers-on' above.
(when (< emacs-major-version 30)
  (fset 'treesit-font-lock-fontify-region
        (symbol-function 'md-ts--treesit-font-lock-fontify-region)))

;; On Emacs 31 the macro is built-in.  Expand it unconditionally at
;; compile time so treesit C-function declarations are always visible.
(eval-when-compile
  (if (fboundp 'treesit-declare-unavailable-functions)
      (treesit-declare-unavailable-functions)
    (md-ts--declare-unavailable-functions)))

;;; Grammar recipes

(add-to-list
 'treesit-language-source-alist
 '(markdown
   "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
   "v0.4.1" "tree-sitter-markdown/src")
 t)
(add-to-list
 'treesit-language-source-alist
 '(markdown-inline
   "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
   "v0.4.1" "tree-sitter-markdown-inline/src")
 t)

;;; Variables

(defvar md-ts--code-block-language-map
  '(("c++" . cpp)
    ("c#" . c-sharp)
    ("sh" . bash))
  "Alist mapping code block language names to tree-sitter languages.

Keys should be strings, and values should be language symbols.

For example, \"c++\" in

    ```c++
    int main() {
        return 0;
    }
    ```

maps to tree-sitter language `cpp'.")

(defvar md-ts-code-block-source-mode-map
  '((bash . bash-ts-mode)
    (c . c-ts-mode)
    (c-sharp . csharp-ts-mode)
    (cmake . cmake-ts-mode)
    (cpp . c++-ts-mode)
    (css . css-ts-mode)
    (dockerfile . dockerfile-ts-mode)
    (elixir . elixir-ts-mode)
    (go . go-ts-mode)
    (gomod . go-mod-ts-mode)
    (gowork . go-work-ts-mode)
    (heex . heex-ts-mode)
    (html . html-ts-mode)
    (java . java-ts-mode)
    (javascript . js-ts-mode)
    (json . json-ts-mode)
    (lua . lua-ts-mode)
    (php . php-ts-mode)
    (python . python-ts-mode)
    (ruby . ruby-ts-mode)
    (rust . rust-ts-mode)
    (toml . toml-ts-mode)
    (tsx . tsx-ts-mode)
    (typescript . typescript-ts-mode)
    (yaml . yaml-ts-mode))
  "An alist of supported code block languages and their major mode.")

(defcustom md-ts-hide-markup nil
  "Non-nil means hide Markdown markup delimiters in this buffer.
Visible link text remains activatable when link markup is hidden."
  :type 'boolean
  :safe #'booleanp
  :group 'md-ts)

(defcustom md-ts-heading-scaling nil
  "Whether to use variable-height faces for headings.
When non-nil, the scaling values in `md-ts-heading-scaling-values'
will be applied to headings of levels one through six respectively."
  :type 'boolean
  :initialize #'custom-initialize-default
  :set (lambda (symbol value)
         (set-default symbol value)
         (md-ts-update-heading-faces))
  :group 'md-ts)

(defcustom md-ts-heading-scaling-values
  '(2.0 1.7 1.4 1.1 1.0 1.0)
  "List of scaling values for headings of level one through six.
Used when `md-ts-heading-scaling' is non-nil."
  :type '(repeat float)
  :initialize #'custom-initialize-default
  :set (lambda (symbol value)
         (set-default symbol value)
         (md-ts-update-heading-faces))
  :group 'md-ts)

;;; Faces

(defgroup md-ts-faces nil
  "Faces used in Markdown TS Mode."
  :group 'md-ts-faces
  :group 'faces)

(defface md-ts-delimiter '((t (:inherit shadow)))
  "Face for Markdown structural delimiters.
Applied to heading markers (#), emphasis delimiters (* and **),
code backticks, setext underlines, thematic breaks, table
separators, and other structural markup characters.")

(defface md-ts-heading-1 '((t (:inherit outline-1 :weight bold)))
  "Face for first level Markdown headings.")

(defface md-ts-heading-2 '((t (:inherit outline-2 :weight bold)))
  "Face for second level Markdown headings.")

(defface md-ts-heading-3 '((t (:inherit outline-3 :weight bold)))
  "Face for third level Markdown headings.")

(defface md-ts-heading-4 '((t (:inherit outline-4 :weight bold)))
  "Face for fourth level Markdown headings.")

(defface md-ts-heading-5 '((t (:inherit outline-5 :weight bold)))
  "Face for fifth level Markdown headings.")

(defface md-ts-heading-6 '((t (:inherit outline-6 :weight bold)))
  "Face for sixth level Markdown headings.")

(defface md-ts-list-marker '((t (:inherit shadow)))
  "Face for Markdown list markers like - and *.")

(defface md-ts-block-quote '((t (:inherit font-lock-doc-face)))
  "Face for Markdown block quotes.")

(defface md-ts-strikethrough '((t (:strike-through t)))
  "Face for Markdown strikethrough text.")

(defface md-ts-language-keyword '((t (:inherit font-lock-keyword-face)))
  "Face for the language keyword for Markdown code blocks.")

(defface md-ts-task-list-marker '((t (:inherit font-lock-builtin-face)))
  "Face for task list markers ([ ] and [x]).")

(defface md-ts-code '((t (:inherit (fixed-pitch font-lock-constant-face))))
  "Face for inline code, indented code blocks, and fenced code blocks.
Inherits `fixed-pitch' for a monospace font and
`font-lock-constant-face' for a distinct foreground color.
Customize this face to add a contrasting background, for example:
\(set-face-attribute \\='md-ts-code nil :background \"gray20\").")

(defun md-ts-update-heading-faces ()
  "Update heading faces according to `md-ts-heading-scaling'.
When `md-ts-heading-scaling' is non-nil, apply the heights from
`md-ts-heading-scaling-values' to heading faces 1 through 6.
Otherwise reset heights to `unspecified' so themes can provide
their own scaling."
  (dotimes (num 6)
    (let* ((face (intern (format "md-ts-heading-%s" (1+ num))))
           (scale (if md-ts-heading-scaling
                      (float (nth num md-ts-heading-scaling-values))
                    'unspecified)))
      (unless (get face 'saved-face)
        (set-face-attribute face nil :height scale)))))

;;; Font-lock

(defun md-ts--fontify-delimiter (node override start end &rest _)
  "Fontify delimiter NODE and optionally hide its markup.
OVERRIDE, START, and END are passed to `treesit-fontify-with-override'."
  (treesit-fontify-with-override
   (treesit-node-start node) (treesit-node-end node)
   'md-ts-delimiter override start end)
  (when md-ts-hide-markup
    (let ((hide-end (treesit-node-end node))
          (type (treesit-node-type node)))
      ;; For ATX heading markers, also hide the trailing space.
      ;; For setext underlines, also hide the trailing newline.
      (when (or (string-prefix-p "atx_h" type)
                (string-prefix-p "setext_h" type))
        (setq hide-end (min (1+ hide-end) (point-max))))
      (put-text-property (treesit-node-start node) hide-end
                         'invisible 'md-ts--markup))))

(defun md-ts--fontify-thematic-break (node override start end &rest _)
  "Fontify thematic break NODE as a horizontal rule.
OVERRIDE, START, and END are passed to `treesit-fontify-with-override'.
Replaces the `---` (or `***` etc.) with a line of `─' characters
via the `display' text property."
  (let* ((beg (treesit-node-start node))
         (node-end (treesit-node-end node))
         (rule (make-string (max 3 (- (window-width) 1)) ?─)))
    (treesit-fontify-with-override beg node-end 'md-ts-delimiter
                                   override start end)
    (md-ts--put-display-property beg node-end rule)))

(defun md-ts--fontify-task-marker (node override start end &rest _)
  "Fontify task list marker NODE with face and checkbox display.
OVERRIDE, START, and END are passed to `treesit-fontify-with-override'.
Replaces `[ ]' with ☐ and `[x]' with ☑ via `display' property."
  (let* ((beg (treesit-node-start node))
         (node-end (treesit-node-end node))
         (checked (string= (treesit-node-type node) "task_list_marker_checked"))
         (glyph (if checked "☑" "☐")))
    (treesit-fontify-with-override beg node-end 'md-ts-task-list-marker
                                   override start end)
    (md-ts--put-display-property beg node-end glyph)))

(defun md-ts--child-by-type (node type)
  "Return the first named child of NODE whose type is TYPE."
  (seq-find (lambda (child)
              (string= (treesit-node-type child) type))
            (treesit-node-children node t)))

(defun md-ts--node-text (node)
  "Return NODE text without text properties."
  (buffer-substring-no-properties (treesit-node-start node)
                                  (treesit-node-end node)))

(defconst md-ts--uri-scheme-regexp "\\`[[:alpha:]][[:alnum:]+.-]*:"
  "Regexp matching a URI scheme at the start of a string.")

(defconst md-ts--windows-drive-path-regexp "\\`[[:alpha:]]:[/\\\\]"
  "Regexp matching an absolute Windows drive path.")

(defun md-ts--windows-drive-path-p (destination)
  "Return non-nil if DESTINATION has Windows drive-path syntax."
  (string-match-p md-ts--windows-drive-path-regexp destination))

(defun md-ts--uri-scheme-p (destination)
  "Return non-nil when DESTINATION should be opened as a URI."
  (and (string-match-p md-ts--uri-scheme-regexp destination)
       (not (md-ts--windows-drive-path-p destination))))

(defconst md-ts--markdown-escaped-property 'md-ts-markdown-escaped
  "Text property marking characters decoded from Markdown escapes.")

(defun md-ts--local-link-fragment-start (destination)
  "Return the unescaped # fragment separator index in DESTINATION.
Ignore literal # characters that were decoded from Markdown
backslash escapes by `md-ts--markdown-unescape'."
  (let ((pos 0)
        fragment-start)
    (while (and (not fragment-start)
                (setq pos (string-match-p "#" destination pos)))
      (if (get-text-property pos md-ts--markdown-escaped-property
                             destination)
          (setq pos (1+ pos))
        (setq fragment-start pos)))
    fragment-start))

(defun md-ts--local-link-file (destination)
  "Return the file part of local link DESTINATION.
For local paths with a trailing #fragment, remove the fragment.
Heading navigation for the fragment is intentionally deferred."
  (if-let* ((fragment-start (md-ts--local-link-fragment-start destination)))
      (substring destination 0 fragment-start)
    destination))

(defun md-ts--markdown-unescape (text)
  "Return TEXT with basic Markdown backslash escapes decoded.
Decoded punctuation characters carry `md-ts-markdown-escaped' so
later link handling can distinguish literal punctuation from
Markdown syntax."
  (let ((start 0)
        (pieces nil)
        changed)
    (while (string-match "\\\\\\([[:punct:]]\\)" text start)
      (setq changed t)
      (push (substring text start (match-beginning 0)) pieces)
      (let ((escaped (substring text (match-beginning 1) (match-end 1))))
        (put-text-property 0 (length escaped)
                           md-ts--markdown-escaped-property t escaped)
        (push escaped pieces))
      (setq start (match-end 0)))
    (if changed
        (apply #'concat (nreverse (cons (substring text start) pieces)))
      text)))

(defun md-ts--link-destination-url (destination)
  "Return the URL represented by raw link DESTINATION text.
Unwrap angle-bracket destinations and decode basic Markdown
backslash escapes."
  (let ((url (if (and (> (length destination) 1)
                      (string-prefix-p "<" destination)
                      (string-suffix-p ">" destination))
                 (substring destination 1 -1)
               destination)))
    (md-ts--markdown-unescape url)))

(defvar-local md-ts--link-reference-definitions-cache nil
  "Cached alist of Markdown link reference definitions.
Each entry has the form (LABEL . URL), where LABEL is normalized
with `md-ts--reference-label-key'.")

(defvar-local md-ts--link-reference-definitions-cache-tick nil
  "Buffer modified tick represented by reference definitions cache.
A nil value means no cache is available.")

(defvar-local md-ts--link-reference-definition-change-p nil
  "Non-nil when current change may affect reference definitions.")

(defconst md-ts--markdown-fence-regexp
  (concat "^[ \t]\\{0,3\\}"
          "\\(?:>[ \t]?[ \t]\\{0,3\\}\\)*"
          "\\(?:\\(?:[-+*]\\|[0-9]\\{1,9\\}[.)]\\)[ \t]+\\)?"
          "\\(?:>[ \t]?[ \t]\\{0,3\\}\\)*"
          "\\(?:`\\{3,\\}\\|~\\{3,\\}\\)")
  "Regexp matching a Markdown fenced code block delimiter line.
This includes delimiter lines after block quote or list container markers.")

(defun md-ts--reference-label-key (label)
  "Return the normalized reference key for Markdown LABEL.
LABEL may include surrounding brackets.  The result strips those
brackets, trims leading and trailing whitespace, collapses
internal whitespace, and lowercases with `downcase'.  Backslash
escapes are preserved literally, so escaped punctuation remains
distinct from unescaped punctuation."
  (let* ((trimmed (string-trim label))
         (unbracketed (if (and (> (length trimmed) 1)
                               (string-prefix-p "[" trimmed)
                               (string-suffix-p "]" trimmed))
                          (substring trimmed 1 -1)
                        trimmed))
         (collapsed (replace-regexp-in-string
                     "[[:space:]]+" " " (string-trim unbracketed))))
    (downcase collapsed)))

(defun md-ts--link-reference-definitions ()
  "Return cached Markdown link reference definitions.
The result is an alist of (LABEL . URL).  LABEL is normalized with
`md-ts--reference-label-key'.  URL is normalized with
`md-ts--link-destination-url'.  When duplicate labels exist, the
first definition in source order wins.  The cache ignores any
active narrowing so references resolve against the whole buffer."
  (save-restriction
    (widen)
    (let ((tick (buffer-chars-modified-tick)))
      (unless (equal md-ts--link-reference-definitions-cache-tick tick)
        (let (definitions)
          (when-let* ((root (ignore-errors
                              (treesit-buffer-root-node 'markdown))))
            (dolist (capture (treesit-query-capture
                              root
                              '((link_reference_definition
                                 (link_label) @label))))
              (let* ((label-node (cdr capture))
                     (parent (treesit-node-parent label-node))
                     (destination-node
                      (and parent
                           (md-ts--child-by-type parent
                                                 "link_destination")))
                     (key (md-ts--reference-label-key
                           (md-ts--node-text label-node))))
                (when (and destination-node
                           (not (string-empty-p key))
                           (not (assoc key definitions)))
                  (push (cons key
                              (md-ts--link-destination-url
                               (md-ts--node-text destination-node)))
                        definitions)))))
          (setq md-ts--link-reference-definitions-cache
                (nreverse definitions)
                md-ts--link-reference-definitions-cache-tick tick)))
      md-ts--link-reference-definitions-cache)))

(defun md-ts--resolve-link-reference (label)
  "Resolve Markdown reference LABEL to its destination URL.
Return nil when the current buffer has no matching link reference
definition."
  (alist-get (md-ts--reference-label-key label)
             (md-ts--link-reference-definitions)
             nil nil #'equal))

(defun md-ts--open-link-destination (url)
  "Open supported Markdown or bare link destination URL.
URL may come from parsed links, images, references, autolinks, or
bare prose links.  Use `url-mailto' for `mailto:' URIs,
`browse-url' for other URI schemes, and `find-file' for local or
relative paths.  All fragment navigation is deferred: local paths
with an unescaped `#fragment' open only the file part, and
fragment-only destinations signal a `user-error'.  Escaped `#'
characters are literal filename characters.  Empty destinations are
not supported yet."
  (let* ((case-fold-search t)
         (fragment-start (md-ts--local-link-fragment-start url))
         (plain-url (substring-no-properties url)))
    (cond
     ((string-empty-p url)
      (user-error "Empty link destinations are not supported"))
     ((eq fragment-start 0)
      (user-error "Same-buffer fragment links are not supported yet"))
     ((string-match-p "\\`mailto:" url)
      (url-mailto (url-generic-parse-url plain-url)))
     ((md-ts--windows-drive-path-p url)
      (find-file (substring-no-properties url 0 fragment-start)))
     ((md-ts--uri-scheme-p url)
      (browse-url plain-url))
     (t
      (find-file (substring-no-properties url 0 fragment-start))))))

(defun md-ts--make-link-button (beg end url &optional _dynamic static-target)
  "Make the text from BEG to END open URL as a standard button.
URL is used for help text.  By default activation resolves the
parsed Markdown link target again so reference buttons stay fresh
when definitions elsewhere in the buffer change.  When
STATIC-TARGET is non-nil, activation first revalidates the current
bare-link text at the button position."
  (when (and (< beg end) (not (string-empty-p url)))
    (if (md-ts--foreign-button-in-region-p beg end)
        (md-ts--remove-link-button-properties beg end)
      (unless static-target
        (with-silent-modifications
          (let ((inhibit-read-only t))
            (remove-text-properties
             beg end '(md-ts-link-static-target nil)))))
      (let ((help (substring-no-properties url)))
        (apply #'make-text-button
               beg end
               `(md-ts-link-button t
                 md-ts-link-help-echo ,help
                 action ,#'md-ts--open-link-button
                 help-echo ,help
                 ,@(when static-target
                     `(md-ts-link-static-target ,static-target))))))))

(defconst md-ts--link-node-types
  '("inline_link" "image" "full_reference_link"
    "collapsed_reference_link" "shortcut_link"
    "uri_autolink" "email_autolink"
    "link_reference_definition")
  "Tree-sitter node types that represent parsed Markdown links.")

(defconst md-ts--link-text-owner-node-types
  '("inline_link" "full_reference_link"
    "collapsed_reference_link" "shortcut_link")
  "Tree-sitter node types that own visible `link_text' nodes.")

(defun md-ts--link-text-owner-node (node)
  "Return the parsed link node that owns link_text NODE, or nil."
  (when (string= (treesit-node-type node) "link_text")
    (let ((parent (treesit-node-parent node)))
      (and parent
           (member (treesit-node-type parent)
                   md-ts--link-text-owner-node-types)
           parent))))

(defun md-ts--enclosing-link-text-owner (node)
  "Return nearest parsed link with a `link_text' ancestor of NODE."
  (let (owner)
    (while (and node (not owner))
      (setq owner (md-ts--link-text-owner-node node)
            node (treesit-node-parent node)))
    owner))

(defun md-ts--image-node-for-description-descendant (node)
  "Return nearest image node with an image-description ancestor of NODE."
  (let (description image)
    (while (and node (not description))
      (when (string= (treesit-node-type node) "image_description")
        (setq description node))
      (setq node (treesit-node-parent node)))
    (setq node (and description (treesit-node-parent description)))
    (while (and node (not image))
      (when (string= (treesit-node-type node) "image")
        (setq image node))
      (setq node (treesit-node-parent node)))
    image))

(defun md-ts--nearest-link-node (node)
  "Return the nearest parsed Markdown link node containing NODE."
  (while (and node
              (not (member (treesit-node-type node)
                           md-ts--link-node-types)))
    (setq node (treesit-node-parent node)))
  node)

(defun md-ts--link-node-for-node (node)
  "Return the parsed Markdown link node that owns NODE, or nil.
Visible text inside an enclosing `link_text' belongs to that
outer link.  Link-like syntax inside an image description belongs
rather to the image target, unless the whole image is itself in an
enclosing link label."
  (if-let* ((image-node (md-ts--image-node-for-description-descendant node)))
      (or (md-ts--enclosing-link-text-owner image-node)
          image-node)
    (or (md-ts--enclosing-link-text-owner node)
        (md-ts--nearest-link-node node))))

(defun md-ts--autolink-inner-text (node)
  "Return the target text inside autolink NODE's angle brackets."
  (buffer-substring-no-properties (1+ (treesit-node-start node))
                                  (1- (treesit-node-end node))))

(defun md-ts--link-target-for-node (node)
  "Return the opener-ready target URL for parsed link NODE.
NODE may be a link node itself or any descendant.  Return nil for
missing reference definitions."
  (when-let* ((link-node (md-ts--link-node-for-node node)))
    (pcase (treesit-node-type link-node)
      ("inline_link"
       (when-let* ((destination-node
                    (md-ts--child-by-type link-node "link_destination")))
         (md-ts--link-destination-url
          (md-ts--node-text destination-node))))
      ("image"
       (if-let* ((destination-node
                  (md-ts--child-by-type link-node "link_destination")))
           (md-ts--link-destination-url
            (md-ts--node-text destination-node))
         (if-let* ((label-node (md-ts--child-by-type link-node
                                                       "link_label")))
             (md-ts--resolve-link-reference
              (md-ts--node-text label-node))
           (when-let* ((description-node
                        (md-ts--child-by-type link-node
                                              "image_description")))
             (md-ts--resolve-link-reference
              (md-ts--node-text description-node))))))
      ("link_reference_definition"
       (when-let* ((destination-node
                    (md-ts--child-by-type link-node "link_destination")))
         (md-ts--link-destination-url
          (md-ts--node-text destination-node))))
      ("full_reference_link"
       (when-let* ((label-node (md-ts--child-by-type link-node
                                                     "link_label")))
         (md-ts--resolve-link-reference
          (md-ts--node-text label-node))))
      ((or "collapsed_reference_link" "shortcut_link")
       (when-let* ((text-node (md-ts--child-by-type link-node
                                                   "link_text")))
         (md-ts--resolve-link-reference
          (md-ts--node-text text-node))))
      ("uri_autolink"
       (md-ts--autolink-inner-text link-node))
      ("email_autolink"
       (concat "mailto:" (md-ts--autolink-inner-text link-node))))))

(defun md-ts--fontify-link-text (node override start end &rest _)
  "Fontify visible Markdown link text NODE and make it clickable.
OVERRIDE, START, and END are passed to `treesit-fontify-with-override'."
  (treesit-fontify-with-override
   (treesit-node-start node) (treesit-node-end node)
   'link override start end)
  (when-let* ((url (md-ts--link-target-for-node node)))
    (md-ts--make-link-button
     (treesit-node-start node) (treesit-node-end node) url t)))

(defun md-ts--fontify-autolink (node override start end &rest _)
  "Fontify autolink NODE and make its inner target clickable.
For email autolinks, the button target is prefixed with
\"mailto:\".  When `md-ts-hide-markup' is non-nil, hide only the
angle brackets.  OVERRIDE, START, and END are passed to
`treesit-fontify-with-override'."
  (let ((node-start (treesit-node-start node))
        (node-end (treesit-node-end node)))
    (when (< (1+ node-start) (1- node-end))
      (treesit-fontify-with-override
       (1+ node-start) (1- node-end) 'link override start end)
      (when-let* ((url (md-ts--link-target-for-node node)))
        (md-ts--make-link-button
         (1+ node-start) (1- node-end) url t)))
    (treesit-fontify-with-override
     node-start (1+ node-start) 'shadow override start end)
    (treesit-fontify-with-override
     (1- node-end) node-end 'shadow override start end)
    (when md-ts-hide-markup
      (put-text-property node-start (1+ node-start)
                         'invisible 'md-ts--markup)
      (put-text-property (1- node-end) node-end
                         'invisible 'md-ts--markup))))

(defun md-ts--fontify-link-reference-definition-label
    (node override start end &rest _)
  "Fontify link reference definition label NODE and buttonize it.
Only the text inside the brackets becomes a link button.  The
target is the definition's destination.  OVERRIDE, START, and END
are passed to `treesit-fontify-with-override'."
  (let ((inner-start (1+ (treesit-node-start node)))
        (inner-end (1- (treesit-node-end node))))
    (when (< inner-start inner-end)
      (treesit-fontify-with-override
       inner-start inner-end 'link override start end)
      (when-let* ((url (md-ts--link-target-for-node node)))
        (md-ts--make-link-button inner-start inner-end url t)))))

(defun md-ts--fontify-link-node (node override start end &rest _)
  "Fontify parsed link delimiters in NODE, optionally hiding markup.
Applies `shadow' to bracket/paren delimiters.  When
`md-ts-hide-markup' is non-nil, hides the opening marker and
trailing markup so only the link text remains visible.
OVERRIDE, START, and END are passed to `treesit-fontify-with-override'."
  (dolist (child (treesit-node-children node))
    (let ((type (treesit-node-type child)))
      (when (member type '("[" "]" "(" ")" "!"))
        (treesit-fontify-with-override
         (treesit-node-start child) (treesit-node-end child)
         'shadow override start end)
        (when md-ts-hide-markup
          (cond
           ((member type '("[" "!"))
            (put-text-property (treesit-node-start child)
                               (treesit-node-end child)
                               'invisible 'md-ts--markup))
           ((string= type "]")
            (put-text-property (treesit-node-start child)
                               (treesit-node-end node)
                               'invisible 'md-ts--markup))))))))

(defun md-ts--fontify-fenced-code-block (node _override _start _end &rest _)
  "Fontify fenced code block NODE, hiding fence lines when appropriate.
When `md-ts-hide-markup' is non-nil, hides the opening fence line
\(delimiter + language tag + newline) and closing fence line
\(delimiter + newline) so no phantom blank lines remain.
The `md-ts-code' face is applied separately via a late-running
font-lock rule to avoid interfering with embedded language faces."
  (when md-ts-hide-markup
    (let ((block-start (treesit-node-start node))
          (block-end (treesit-node-end node)))
      ;; Find the code_fence_content child — it holds the actual code body.
      (let ((content-node
             (seq-find (lambda (c)
                         (equal (treesit-node-type c) "code_fence_content"))
                       (treesit-node-children node))))
        (if content-node
            (let ((content-start (treesit-node-start content-node))
                  (content-end (treesit-node-end content-node)))
              ;; Hide opening line: from block start through to content start
              ;; (covers ```, info_string, and the trailing newline)
              (put-text-property block-start content-start
                                 'invisible 'md-ts--markup)
              ;; Hide closing line: from content end through block-end.
              ;; The fenced_code_block node already includes the trailing
              ;; newline of the closing fence, so block-end is correct.
              (put-text-property content-end block-end
                                 'invisible 'md-ts--markup))
          ;; Empty code block (no content node): hide the entire block
          (put-text-property block-start block-end
                             'invisible 'md-ts--markup))))))

(defvar md-ts--treesit-settings
  (treesit-font-lock-rules
   :language 'markdown-inline
   :override t
   :feature 'delimiter
   '((inline_link) @md-ts--fontify-link-node
     (image) @md-ts--fontify-link-node
     (full_reference_link) @md-ts--fontify-link-node
     (collapsed_reference_link) @md-ts--fontify-link-node
     (shortcut_link) @md-ts--fontify-link-node)

   :language 'markdown
   :feature 'heading
   '((atx_heading (atx_h1_marker)) @md-ts-heading-1
     (atx_heading (atx_h2_marker)) @md-ts-heading-2
     (atx_heading (atx_h3_marker)) @md-ts-heading-3
     (atx_heading (atx_h4_marker)) @md-ts-heading-4
     (atx_heading (atx_h5_marker)) @md-ts-heading-5
     (atx_heading (atx_h6_marker)) @md-ts-heading-6
     (setext_heading heading_content: (_) @md-ts-heading-1 (setext_h1_underline))
     (setext_heading heading_content: (_) @md-ts-heading-2 (setext_h2_underline)))

   :language 'markdown
   :feature 'heading
   :override 'prepend
   '((atx_h1_marker) @md-ts--fontify-delimiter
     (atx_h2_marker) @md-ts--fontify-delimiter
     (atx_h3_marker) @md-ts--fontify-delimiter
     (atx_h4_marker) @md-ts--fontify-delimiter
     (atx_h5_marker) @md-ts--fontify-delimiter
     (atx_h6_marker) @md-ts--fontify-delimiter
     (setext_h1_underline) @md-ts--fontify-delimiter
     (setext_h2_underline) @md-ts--fontify-delimiter)

   :language 'markdown
   :feature 'paragraph
   '(((thematic_break) @md-ts--fontify-thematic-break)
     (list_item (list_marker_star) @md-ts-list-marker)
     (list_item (list_marker_plus) @md-ts-list-marker)
     (list_item (list_marker_minus) @md-ts-list-marker)
     (list_item (list_marker_dot) @md-ts-list-marker)
     (list_item (task_list_marker_unchecked) @md-ts--fontify-task-marker)
     (list_item (task_list_marker_checked) @md-ts--fontify-task-marker)
     ((pipe_table_delimiter_row) @md-ts-delimiter)
     ((pipe_table_header) @bold)
     ((html_block) @font-lock-doc-face)
     (link_reference_definition
      (link_label) @md-ts--fontify-link-reference-definition-label)
     (link_reference_definition
      (link_destination) @font-lock-string-face)
     (link_reference_definition
      (link_title) @font-lock-string-face))

   :language 'markdown
   :feature 'paragraph
   :override 'prepend
   '((block_quote) @md-ts-block-quote
     (block_quote_marker) @md-ts--fontify-delimiter
     ((block_continuation) @md-ts--fontify-delimiter
      (:match "^>" @md-ts--fontify-delimiter))
     (fenced_code_block) @md-ts--fontify-fenced-code-block)

   :language 'markdown-inline
   :override 'append
   :feature 'paragraph-inline
   '(((link_destination) @font-lock-string-face)
     ((code_span) @md-ts-code)
     ((code_span_delimiter) @md-ts--fontify-delimiter)
     ((emphasis) @italic)
     ((strong_emphasis) @bold)
     ((strikethrough) @md-ts-strikethrough)
     (inline_link (link_text) @md-ts--fontify-link-text)
     (image (image_description) @md-ts--fontify-link-text)
     (shortcut_link (link_text) @md-ts--fontify-link-text)
     (full_reference_link (link_text) @md-ts--fontify-link-text)
     (full_reference_link (link_label) @shadow)
     (collapsed_reference_link (link_text) @md-ts--fontify-link-text)
     ((uri_autolink) @md-ts--fontify-autolink)
     ((email_autolink) @md-ts--fontify-autolink))

   :language 'markdown-inline
   :feature 'paragraph-inline
   :override 'append
   '((emphasis_delimiter) @md-ts--fontify-delimiter)))

;;; Imenu

(defun md-ts-imenu-node-p (node)
  "Check if NODE is a valid entry to imenu."
  (equal (treesit-node-type (treesit-node-parent node))
         "atx_heading"))

(defun md-ts-imenu-name-function (node)
  "Return an imenu entry if NODE is a valid header."
  (let ((name (treesit-node-text node)))
    (if (md-ts-imenu-node-p node)
	(thread-first (treesit-node-parent node) (treesit-node-text))
      name)))

(defun md-ts-outline-predicate (node)
  "Return non-nil if NODE is a section with an ATX heading child."
  (and (equal (treesit-node-type node) "section")
       (when-let* ((child (treesit-node-child node 0)))
         (equal (treesit-node-type child) "atx_heading"))))

;;; Code blocks

(defvar-local md-ts--configured-languages nil
  "Languages whose font-lock and indent have been loaded in this buffer.")

(defvar-local md-ts--unavailable-languages nil
  "Languages whose mode failed to activate (missing grammars, etc.).")

(defun md-ts--harvest-treesit-configs (mode)
  "Harvest tree-sitter configs from MODE.
Return a plist with :font-lock, :simple-indent, and :range keys,
or nil if MODE fails to activate (e.g. missing grammar dependencies)."
  (condition-case err
      (with-temp-buffer
        (funcall mode)
        (list :font-lock treesit-font-lock-settings
              :simple-indent treesit-simple-indent-rules
              :range treesit-range-settings))
    (error
     (message "md-ts-mode: failed to harvest configs from %s: %s"
              mode (error-message-string err))
     nil)))

(defun md-ts--add-config-for-mode (language mode)
  "Add font-lock and indent configurations for LANGUAGE from MODE.
Re-appends `code' feature rules at the end so `md-ts-code' face
is applied after all embedded language fontification.
Return non-nil on success, nil if MODE could not be harvested."
  (let ((configs (md-ts--harvest-treesit-configs mode)))
    (when configs
      (ignore language)
      ;; Remove existing code-feature rules, append new lang, re-append code.
      ;; This keeps md-ts-code rules physically last in the settings list.
      (let ((code-rules (seq-filter (lambda (s) (eq (nth 2 s) 'code))
                                    treesit-font-lock-settings))
            (non-code (seq-remove (lambda (s) (eq (nth 2 s) 'code))
                                  treesit-font-lock-settings)))
        (setq treesit-font-lock-settings
              (append non-code
                      (plist-get configs :font-lock)
                      code-rules)))
      (setq treesit-simple-indent-rules
            (append treesit-simple-indent-rules
                    (plist-get configs :simple-indent)))
      ;; Only keep query-based range settings; function-based entries
      ;; create host-level parsers that re-parse the whole buffer.
      (let ((safe-ranges (seq-filter
                          (lambda (s) (not (functionp (nth 0 s))))
                          (plist-get configs :range))))
        (setq treesit-range-settings
              (append treesit-range-settings safe-ranges)))
      (setq-local indent-line-function #'treesit-indent)
      (setq-local indent-region-function #'treesit-indent-region)
      t)))

(defun md-ts--convert-code-block-language (node)
  "Convert NODE to a language symbol for the code block.
Return nil if no tree-sitter mode is available for the language."
  (let* ((lang-string (alist-get (treesit-node-text node)
                                 md-ts--code-block-language-map
                                 (treesit-node-text node) nil #'equal))
         (lang (if (symbolp lang-string)
                   lang-string
                 (intern (downcase lang-string)))))
    (let ((mode (alist-get lang md-ts-code-block-source-mode-map)))
      (cond
       ((not (and mode (fboundp mode))) nil)
       ((memq lang md-ts--unavailable-languages) nil)
       ((memq lang md-ts--configured-languages) lang)
       ((md-ts--add-config-for-mode lang mode)
        (push lang md-ts--configured-languages)
        lang)
       (t
        (push lang md-ts--unavailable-languages)
        nil)))))

;;; Range settings

(defun md-ts--range-settings ()
  "Return range settings for `md-ts-mode'.
Inline nodes get local parsers; code blocks get per-block parsers."
  (treesit-range-rules
   ;; Local: one parser per (inline) / (pipe_table_cell) node,
   ;; so delimiter matching cannot cross paragraph boundaries.
   :embed 'markdown-inline
   :host 'markdown
   :local t
   '((inline) @markdown-inline
     (pipe_table_cell) @markdown-inline)

   :embed #'md-ts--convert-code-block-language
   :host 'markdown
   :local t
   '((fenced_code_block (info_string (language) @language)
                        (code_fence_content) @content))))

;;; Hide markup

(defun md-ts--set-hide-markup (value)
  "Set hiding of Markdown markup delimiters in the current buffer.
VALUE non-nil hides markup, nil shows it."
  (if value
      (add-to-invisibility-spec 'md-ts--markup)
    (remove-from-invisibility-spec 'md-ts--markup))
  (font-lock-flush))

(defun md-ts-toggle-hide-markup ()
  "Toggle hiding of Markdown markup delimiters in the current buffer."
  (interactive)
  (setq md-ts-hide-markup (not md-ts-hide-markup))
  (md-ts--set-hide-markup md-ts-hide-markup))

(defun md-ts--node-at (pos language)
  "Return the tree-sitter node at POS for LANGUAGE, ignoring errors."
  (ignore-errors
    (treesit-node-at pos language)))

(defun md-ts--node-contains-position-p (node pos)
  "Return non-nil if NODE includes POS as a character position."
  (and node
       (<= (treesit-node-start node) pos)
       (< pos (treesit-node-end node))))

(defun md-ts--node-at-containing-position (pos language)
  "Return the nearest node for LANGUAGE that includes POS."
  (let ((node (md-ts--node-at pos language)))
    (while (and node
                (not (md-ts--node-contains-position-p node pos)))
      (setq node (treesit-node-parent node)))
    node))

(defun md-ts--node-in-link-reference-definition-p (node)
  "Return non-nil if NODE is inside a link reference definition."
  (while (and node
              (not (string= (treesit-node-type node)
                            "link_reference_definition")))
    (setq node (treesit-node-parent node)))
  node)

(defun md-ts--line-bounds (beg end)
  "Return widened line bounds covering BEG through END."
  (save-excursion
    (save-restriction
      (widen)
      (let ((safe-beg (min (max beg (point-min)) (point-max)))
            (safe-end (min (max end (point-min)) (point-max))))
        (goto-char safe-beg)
        (let ((line-beg (line-beginning-position)))
          (goto-char safe-end)
          (when (and (> safe-end safe-beg) (bolp))
            (forward-char -1))
          (cons line-beg (line-end-position)))))))

(defun md-ts--broadened-line-bounds (beg end)
  "Return line bounds around BEG and END, broadened by one line."
  (save-excursion
    (save-restriction
      (widen)
      (let ((safe-beg (min (max beg (point-min)) (point-max)))
            (safe-end (min (max end (point-min)) (point-max))))
        (goto-char safe-beg)
        (forward-line -1)
        (let ((line-beg (line-beginning-position)))
          (goto-char safe-end)
          (forward-line 1)
          (cons line-beg (line-end-position)))))))

(defun md-ts--region-contains-newline-p (beg end)
  "Return non-nil if the region from BEG to END has a newline."
  (save-excursion
    (save-restriction
      (widen)
      (let ((safe-beg (min (max beg (point-min)) (point-max)))
            (safe-end (min (max end (point-min)) (point-max))))
        (and (< safe-beg safe-end)
             (progn
               (goto-char safe-beg)
               (search-forward "\n" safe-end t)))))))

(defun md-ts--region-has-link-reference-definition-node-p (beg end)
  "Return non-nil if BEG to END intersects a parsed reference definition."
  (save-restriction
    (widen)
    (pcase-let ((`(,line-beg . ,line-end)
                 (md-ts--broadened-line-bounds beg end)))
      (when-let* ((root (ignore-errors (treesit-buffer-root-node 'markdown))))
        (treesit-query-capture root
                               '((link_reference_definition) @definition)
                               line-beg line-end)))))

(defun md-ts--region-needs-adjacent-fence-lines-p (beg end)
  "Return non-nil if fence detection around BEG and END needs adjacent lines.
Newline edits can make a neighboring fence delimiter structural or
non-structural without changing the delimiter text.  A zero-width
BOL/EOL edit gets the same conservative treatment."
  (save-excursion
    (save-restriction
      (widen)
      (let ((safe-beg (min (max beg (point-min)) (point-max)))
            (safe-end (min (max end (point-min)) (point-max))))
        (or (and (< safe-beg safe-end)
                 (progn
                   (goto-char safe-beg)
                   (search-forward "\n" safe-end t)))
            (and (= safe-beg safe-end)
                 (progn
                   (goto-char safe-beg)
                   (or (bolp) (eolp)))))))))

(defun md-ts--fence-detection-line-bounds (beg end)
  "Return line bounds to inspect fence edits from BEG to END."
  (if (md-ts--region-needs-adjacent-fence-lines-p beg end)
      (md-ts--broadened-line-bounds beg end)
    (md-ts--line-bounds beg end)))

(defun md-ts--region-has-fenced-code-delimiter-node-p (beg end)
  "Return non-nil for a parsed fence delimiter near BEG and END."
  (save-restriction
    (widen)
    (pcase-let ((`(,line-beg . ,line-end)
                 (md-ts--fence-detection-line-bounds beg end)))
      (when-let* ((root (ignore-errors (treesit-buffer-root-node 'markdown))))
        (treesit-query-capture root
                               '((fenced_code_block_delimiter) @delimiter)
                               line-beg line-end)))))

(defun md-ts--region-has-markdown-fence-p (beg end)
  "Return non-nil for a Markdown fence near BEG and END.
Parser-recognized delimiter nodes catch valid container-indented
fences, including nested-list fences whose absolute indentation is
more than three columns.  The regexp fallback keeps simple newly
typed delimiter text conservative if tree state is temporarily
unavailable; it is not the source of container correctness."
  (or (md-ts--region-has-fenced-code-delimiter-node-p beg end)
      (save-restriction
        (widen)
        (pcase-let ((`(,line-beg . ,line-end)
                     (md-ts--fence-detection-line-bounds beg end)))
          (string-match-p
           md-ts--markdown-fence-regexp
           (buffer-substring-no-properties line-beg line-end))))))

(defun md-ts--line-start-at-pos (pos)
  "Return the start position of the line containing POS."
  (save-excursion
    (goto-char (min (max pos (point-min)) (point-max)))
    (line-beginning-position)))

(defun md-ts--region-includes-line-start-p (line-start region-beg region-end)
  "Return non-nil if REGION-BEG to REGION-END includes LINE-START."
  (and (<= region-beg line-start)
       (<= line-start region-end)))

(defun md-ts--region-touches-node-boundary-line-p (node region-beg region-end)
  "Return non-nil if REGION-BEG to REGION-END touches NODE boundary lines."
  (let* ((node-start (treesit-node-start node))
         (node-end (treesit-node-end node))
         (start-line (md-ts--line-start-at-pos node-start))
         (end-line (md-ts--line-start-at-pos
                    (max node-start (1- node-end)))))
    (or (md-ts--region-includes-line-start-p
         start-line region-beg region-end)
        (md-ts--region-includes-line-start-p
         end-line region-beg region-end))))

(defun md-ts--region-touches-html-block-boundary-p
    (beg end &optional broaden-touch)
  "Return non-nil if BEG to END touches a parsed HTML block boundary.
Discovery is broadened to find neighboring parsed HTML blocks, but
only the actual changed lines count as boundary touches.  When
BROADEN-TOUCH is non-nil, broaden touch bounds by one line too;
callers use this only for actual newline insert/delete edits.
Ordinary edits inside or next to a large HTML block should not
force whole-buffer link refontification."
  (save-excursion
    (save-restriction
      (widen)
      (pcase-let ((`(,touch-beg . ,touch-end)
                   (if broaden-touch
                       (md-ts--broadened-line-bounds beg end)
                     (md-ts--line-bounds beg end)))
                  (`(,discover-beg . ,discover-end)
                   (md-ts--broadened-line-bounds beg end)))
        (when-let* ((root (ignore-errors
                            (treesit-buffer-root-node 'markdown))))
          (seq-some
           (lambda (capture)
             (md-ts--region-touches-node-boundary-line-p
              (cdr capture) touch-beg touch-end))
           (treesit-query-capture root
                                  '((html_block) @block)
                                  discover-beg discover-end)))))))

(defun md-ts--flush-all-font-lock ()
  "Flush font-lock across the whole buffer, ignoring narrowing."
  (save-restriction
    (widen)
    (font-lock-flush (point-min) (point-max))))

(defun md-ts--before-change-check-link-reference-definition (beg end)
  "Remember if the text from BEG to END can affect definitions."
  (let ((newline-delete (md-ts--region-contains-newline-p beg end)))
    (setq md-ts--link-reference-definition-change-p
          (or (md-ts--region-has-link-reference-definition-node-p beg end)
              (md-ts--region-has-markdown-fence-p beg end)
              (md-ts--region-touches-html-block-boundary-p
               beg end newline-delete)
              (md-ts--node-in-link-reference-definition-p
               (md-ts--node-at beg 'markdown))
              (and (> end beg)
                   (md-ts--node-in-link-reference-definition-p
                    (md-ts--node-at (1- end) 'markdown)))))))

(defun md-ts--after-change-flush-link-reference-links (beg end _length)
  "Flush non-local link fontification after definition edits.
BEG, END, and _LENGTH are the standard `after-change-functions'
arguments.  Reference definitions affect buttons and `help-echo'
far from the edited line, so real definition or fence changes flush
all font-lock state."
  (let ((newline-insert (md-ts--region-contains-newline-p beg end)))
    (when (or md-ts--link-reference-definition-change-p
              (md-ts--region-has-link-reference-definition-node-p beg end)
              (md-ts--region-has-markdown-fence-p beg end)
              (md-ts--region-touches-html-block-boundary-p
               beg end newline-insert))
      (md-ts--flush-all-font-lock)))
  (setq md-ts--link-reference-definition-change-p nil))

(defconst md-ts--link-button-properties
  '(button nil category nil action nil help-echo nil keymap nil
    mouse-face nil follow-link nil md-ts-link-button nil
    md-ts-link-help-echo nil md-ts-link-static-target nil
    md-ts-bare-link-face nil)
  "Text properties owned by md-ts link buttons.")

(defconst md-ts--link-button-residual-properties
  '(md-ts-link-button nil md-ts-link-help-echo nil
    md-ts-link-static-target nil md-ts-bare-link-face nil)
  "Md-ts-specific link props that can remain under foreign buttons.")

(defconst md-ts--link-button-segment-properties
  '(button action category help-echo md-ts-link-button
    md-ts-link-help-echo md-ts-link-static-target md-ts-bare-link-face)
  "Text properties that delimit md-ts link-button cleanup segments.")

(defun md-ts--legacy-link-button-p (button)
  "Return non-nil if BUTTON has c102465's dynamic md-ts shape."
  (and (markerp button)
       (not (button-get button 'md-ts-link-button))
       (eq (button-get button 'action) #'md-ts--open-link-button)
       (stringp (button-get button 'help-echo))))

(defun md-ts--owned-link-button-p (button)
  "Return non-nil if BUTTON is current or dynamic legacy md-ts UI."
  (or (md-ts--link-button-p button)
      (md-ts--legacy-link-button-p button)))

(defun md-ts--foreign-overlay-button-in-region-p (beg end)
  "Return non-nil if a foreign overlay button overlaps BEG to END."
  (seq-some (lambda (overlay)
              (and (overlay-get overlay 'button)
                   (overlay-get overlay 'category)
                   (not (md-ts--owned-link-button-p overlay))
                   overlay))
            (overlays-in beg end)))

(defun md-ts--foreign-button-in-region-p (beg end)
  "Return non-nil if a non-md-ts button overlaps BEG to END."
  (or (md-ts--foreign-overlay-button-in-region-p beg end)
      (let ((pos beg)
            found)
        (while (and (< pos end) (not found))
          (if-let* ((button (button-at pos)))
              (if (md-ts--owned-link-button-p button)
                  (setq pos (min end (max (1+ pos) (button-end button))))
                (setq found button))
            (setq pos (or (next-single-property-change
                           pos 'button nil end)
                          end))))
        found)))

(defun md-ts--property-span (pos prop)
  "Return the span of PROP around POS as a cons cell."
  (cons (or (previous-single-property-change
             (min (1+ pos) (point-max)) prop nil (point-min))
            (point-min))
        (or (next-single-property-change pos prop nil (point-max))
            (point-max))))

(defun md-ts--text-button-at-p (pos)
  "Return non-nil if POS has a text-property button."
  (and (get-text-property pos 'button)
       (get-text-property pos 'category)))

(defun md-ts--current-text-link-button-p (pos)
  "Return non-nil if POS has a current md-ts text link button."
  (and (md-ts--text-button-at-p pos)
       (get-text-property pos 'md-ts-link-button)
       (eq (get-text-property pos 'action) #'md-ts--open-link-button)))

(defun md-ts--legacy-dynamic-text-link-button-p (pos)
  "Return non-nil if POS has c102465's dynamic md-ts text button."
  (and (md-ts--text-button-at-p pos)
       (not (get-text-property pos 'md-ts-link-button))
       (eq (get-text-property pos 'action) #'md-ts--open-link-button)
       (stringp (get-text-property pos 'help-echo))))

(defun md-ts--owned-text-link-button-p (pos)
  "Return non-nil if POS has md-ts-owned text button props."
  (or (md-ts--current-text-link-button-p pos)
      (md-ts--legacy-dynamic-text-link-button-p pos)))

(defun md-ts--link-residual-property-at-p (pos)
  "Return non-nil if POS has md-ts link residual text props."
  (or (get-text-property pos 'md-ts-link-button)
      (get-text-property pos 'md-ts-link-help-echo)
      (get-text-property pos 'md-ts-link-static-target)
      (get-text-property pos 'md-ts-bare-link-face)))

(defun md-ts--stale-link-help-echo-p (pos)
  "Return non-nil if POS has an md-ts-owned `help-echo' value."
  (let ((help (get-text-property pos 'help-echo))
        (owned-help (get-text-property pos 'md-ts-link-help-echo)))
    (and owned-help (equal help owned-help))))

(defun md-ts--next-link-button-property-change (pos limit)
  "Return next possible link-button property change after POS before LIMIT."
  (let ((next limit))
    (dolist (prop md-ts--link-button-segment-properties next)
      (setq next
            (min next
                 (or (next-single-property-change pos prop nil limit)
                     limit))))))

(defun md-ts--link-button-property-segment (pos)
  "Return relevant link-button property segment around POS."
  (let ((beg (point-min))
        (end (point-max))
        (previous-pos (min (1+ pos) (point-max))))
    (dolist (prop md-ts--link-button-segment-properties)
      (setq beg
            (max beg
                 (or (previous-single-property-change
                      previous-pos prop nil (point-min))
                     (point-min))))
      (setq end
            (min end
                 (or (next-single-property-change
                      pos prop nil (point-max))
                     (point-max)))))
    (cons beg end)))

(defun md-ts--remove-link-residual-properties-at (pos)
  "Remove stale md-ts residual link properties at POS.
Return the end of the removed cleanup segment.  Foreign text button
properties are not removed."
  (pcase-let ((`(,span-beg . ,span-end)
               (md-ts--link-button-property-segment pos)))
    (when (md-ts--stale-link-help-echo-p pos)
      (remove-text-properties span-beg span-end '(help-echo nil)))
    (md-ts--remove-link-face-from-region span-beg span-end)
    (remove-text-properties span-beg span-end
                            md-ts--link-button-residual-properties)
    span-end))

(defun md-ts--remove-link-button-properties (beg end)
  "Remove md-ts-owned link button properties overlapping BEG to END.
Foreign text and overlay buttons keep their button properties.  Any
md-ts text button hidden under a foreign overlay is still removed,
and stale md-ts-specific residual props left under foreign text
buttons are cleared without taking ownership."
  (with-silent-modifications
    (save-restriction
      (widen)
      (let ((pos (min (max beg (point-min)) (point-max)))
            (limit (min (max end (point-min)) (point-max))))
        (while (< pos limit)
          (cond
           ((md-ts--owned-text-link-button-p pos)
            (pcase-let ((`(,span-beg . ,span-end)
                         (md-ts--property-span pos 'button)))
              (md-ts--remove-link-face-from-region span-beg span-end)
              (remove-text-properties
               span-beg span-end md-ts--link-button-properties)
              (setq pos (min limit (max (1+ pos) span-end)))))
           ((md-ts--link-residual-property-at-p pos)
            (setq pos (min limit
                            (max (1+ pos)
                                 (md-ts--remove-link-residual-properties-at
                                  pos)))))
           (t
            (setq pos (md-ts--next-link-button-property-change
                       pos limit)))))))))

(defun md-ts--link-face-value-p (face)
  "Return non-nil when FACE includes `link'."
  (if (listp face) (memq 'link face)
    (eq face 'link)))

(defun md-ts--remove-link-face-value (face)
  "Return FACE with md-ts-owned bare `link' face removed."
  (cond
   ((eq face 'link) nil)
   ((and (listp face) (memq 'link face))
    (let ((faces (delq 'link (copy-sequence face))))
      (cond
       ((null faces) nil)
       ((null (cdr faces)) (car faces))
       (t faces))))
   (t face)))

(defun md-ts--next-link-face-property-change (pos limit)
  "Return next `face' or md-ts bare face ownership change after POS before LIMIT."
  (min (or (next-single-property-change pos 'face nil limit) limit)
       (or (next-single-property-change pos 'md-ts-bare-link-face nil limit)
           limit)))

(defun md-ts--add-link-face-to-region (beg end)
  "Add a md-ts-owned bare `link' face to BEG..END where not already present."
  (let ((pos beg))
    (while (< pos end)
      (let ((next (md-ts--next-link-face-property-change pos end)))
        (unless (md-ts--link-face-value-p (get-text-property pos 'face))
          (add-face-text-property pos next 'link t)
          (put-text-property pos next 'md-ts-bare-link-face t))
        (setq pos next)))))

(defun md-ts--remove-link-face-from-region (beg end)
  "Remove md-ts-owned bare `link' face from BEG to END."
  (let ((pos beg))
    (while (< pos end)
      (let* ((next (md-ts--next-link-face-property-change pos end))
             (owned (get-text-property pos 'md-ts-bare-link-face))
             (face (get-text-property pos 'face))
             (new-face (and owned (md-ts--remove-link-face-value face))))
        (when owned
          (unless (equal face new-face)
            (put-text-property pos next 'face new-face))
          (remove-text-properties pos next '(md-ts-bare-link-face nil)))
        (setq pos next)))))

(defun md-ts--static-bare-text-link-button-p (pos)
  "Return non-nil if POS has an md-ts-owned static bare text button."
  (and (md-ts--current-text-link-button-p pos)
       (get-text-property pos 'md-ts-link-static-target)))

(defun md-ts--remove-bare-link-button-properties (beg end)
  "Remove md-ts-owned static bare link properties from BEG to END.
Parsed Markdown link buttons and foreign text or overlay buttons are
left intact."
  (with-silent-modifications
    (let ((inhibit-read-only t))
      (save-restriction
        (widen)
        (let ((pos (min (max beg (point-min)) (point-max)))
              (limit (min (max end (point-min)) (point-max))))
          (while (< pos limit)
            (cond
             ((md-ts--static-bare-text-link-button-p pos)
              (pcase-let ((`(,span-beg . ,span-end)
                           (md-ts--property-span pos 'button)))
                (md-ts--remove-link-face-from-region span-beg span-end)
                (remove-text-properties
                 span-beg span-end md-ts--link-button-properties)
                (setq pos (min limit (max (1+ pos) span-end)))))
             ((get-text-property pos 'md-ts-link-static-target)
              (pcase-let ((`(,span-beg . ,span-end)
                           (md-ts--link-button-property-segment pos)))
                (when (md-ts--stale-link-help-echo-p pos)
                  (remove-text-properties span-beg span-end '(help-echo nil)))
                (md-ts--remove-link-face-from-region span-beg span-end)
                (remove-text-properties
                 span-beg span-end md-ts--link-button-residual-properties)
                (setq pos (min limit (max (1+ pos) span-end)))))
             (t
              (setq pos (or (next-single-property-change
                             pos 'md-ts-link-static-target nil limit)
                            limit))))))))))

(defun md-ts--foreign-display-property-in-region-p (beg end)
  "Return non-nil if unowned `display' occurs from BEG to END."
  (let ((pos beg)
        found)
    (while (and (< pos end) (not found))
      (let ((display (get-text-property pos 'display)))
        (when (and display
                   (not (equal display
                               (get-text-property pos 'md-ts-display))))
          (setq found t)))
      (setq pos (or (next-property-change pos nil end) end)))
    found))

(defun md-ts--put-display-property (beg end display)
  "Set md-ts-owned DISPLAY property from BEG to END."
  (unless (md-ts--foreign-display-property-in-region-p beg end)
    (put-text-property beg end 'display display)
    (put-text-property beg end 'md-ts-display display)))

(defun md-ts--display-property-span (pos)
  "Return the md-ts-owned display property span around POS."
  (cons (or (previous-single-property-change
             (min (1+ pos) (point-max)) 'md-ts-display nil (point-min))
            (point-min))
        (or (next-single-property-change
             pos 'md-ts-display nil (point-max))
            (point-max))))

(defun md-ts--remove-display-properties (beg end)
  "Remove md-ts-owned display properties from BEG to END.
Foreign `display' properties without `md-ts-display' ownership are
left intact."
  (with-silent-modifications
    (let ((inhibit-read-only t))
      (save-restriction
        (widen)
        (let ((pos (min (max beg (point-min)) (point-max)))
              (limit (min (max end (point-min)) (point-max))))
          (while (< pos limit)
            (let ((owned-display (get-text-property pos 'md-ts-display)))
              (if owned-display
                  (pcase-let ((`(,span-beg . ,span-end)
                               (md-ts--display-property-span pos)))
                    (let ((display-pos span-beg))
                      (while (< display-pos span-end)
                        (let ((display-end
                               (or (next-single-property-change
                                    display-pos 'display nil span-end)
                                   span-end)))
                          (when (equal (get-text-property display-pos
                                                          'display)
                                       owned-display)
                            (remove-text-properties display-pos display-end
                                                    '(display nil)))
                          (setq display-pos display-end))))
                    (remove-text-properties span-beg span-end
                                            '(md-ts-display nil))
                    (setq pos (min limit (max (1+ pos) span-end))))
                (setq pos (or (next-single-property-change
                               pos 'md-ts-display nil limit)
                              limit))))))))))

(defun md-ts--font-lock-unfontify-region (beg end)
  "Unfontify BEG to END and clean md-ts-owned side effects."
  (with-silent-modifications
    (let ((inhibit-read-only t))
      (md-ts--remove-display-properties beg end)
      (md-ts--remove-bare-link-button-properties beg end)
      (md-ts--remove-link-button-properties beg end)
      (font-lock-default-unfontify-region beg end))))

(defconst md-ts--bare-link-unsafe-node-types
  '("inline_link" "full_reference_link" "collapsed_reference_link"
    "shortcut_link" "image" "link_reference_definition"
    "uri_autolink" "email_autolink" "link_destination"
    "code_span" "fenced_code_block" "indented_code_block"
    "code_fence_content" "info_string" "html_block" "html_tag")
  "Tree-sitter node types where bare link scanning should not apply.")

(defconst md-ts--bare-link-unsafe-context-no-cache
  'md-ts--bare-link-unsafe-context-no-cache
  "Sentinel for uncached bare-link unsafe-context checks.")

(defvar md-ts--bare-link-unsafe-context-ranges
  md-ts--bare-link-unsafe-context-no-cache
  "Dynamically bound unsafe ranges or range cache for bare-link scans.")

(defconst md-ts--bare-link-unsafe-range-queries
  '((markdown . ((link_reference_definition) @unsafe
                 (fenced_code_block) @unsafe
                 (indented_code_block) @unsafe
                 (code_fence_content) @unsafe
                 (info_string) @unsafe
                 (html_block) @unsafe
                 (link_destination) @unsafe))
    (markdown-inline . ((inline_link) @unsafe
                        (full_reference_link) @unsafe
                        (collapsed_reference_link) @unsafe
                        (shortcut_link) @unsafe
                        (image) @unsafe
                        (uri_autolink) @unsafe
                        (email_autolink) @unsafe
                        (link_destination) @unsafe
                        (code_span) @unsafe
                        (html_tag) @unsafe)))
  "Tree-sitter queries for ranges unsafe for bare-link scanning.")

(defconst md-ts--bare-link-reference-definition-no-cache
  'md-ts--bare-link-reference-definition-no-cache
  "Sentinel for uncached bare-link reference-definition checks.")

(defvar md-ts--bare-link-reference-definition-ranges
  md-ts--bare-link-reference-definition-no-cache
  "Dynamically bound reference-definition ranges for bare-link scans.")

(defun md-ts--node-has-ancestor-type-p (node types)
  "Return non-nil if NODE or an ancestor has one of TYPES."
  (let (found)
    (while (and node (not found))
      (when (member (treesit-node-type node) types)
        (setq found node))
      (setq node (treesit-node-parent node)))
    found))

(defun md-ts--link-reference-definition-ranges (beg end)
  "Return parsed reference-definition ranges between BEG and END."
  (when-let* ((root (ignore-errors (treesit-buffer-root-node 'markdown))))
    (mapcar (lambda (capture)
              (let ((node (cdr capture)))
                (cons (treesit-node-start node)
                      (treesit-node-end node))))
            (treesit-query-capture root
                                   '((link_reference_definition) @definition)
                                   beg end))))

(defun md-ts--bare-link-sort-merge-ranges (ranges)
  "Return RANGES sorted and merged as a vector of cons cells."
  (let (merged)
    (dolist (range (sort ranges (lambda (a b) (< (car a) (car b)))))
      (let ((beg (car range))
            (end (cdr range)))
        (when (< beg end)
          (if (and merged (<= beg (cdar merged)))
              (setcdr (car merged) (max (cdar merged) end))
            (push (cons beg end) merged)))))
    (vconcat (nreverse merged))))

(defun md-ts--bare-link-unsafe-ranges (beg end)
  "Return sorted unsafe ranges for bare-link scans between BEG and END."
  (save-restriction
    (widen)
    (let (ranges)
      (dolist (spec md-ts--bare-link-unsafe-range-queries)
        (pcase-let ((`(,language . ,query) spec))
          (dolist (root (md-ts--font-lock-root-nodes beg end language))
            (dolist (capture (ignore-errors
                                (treesit-query-capture root query beg end)))
              (let* ((node (cdr capture))
                     (node-beg (treesit-node-start node))
                     (node-end (treesit-node-end node)))
                (when (and (< node-beg end) (< beg node-end))
                  (push (cons node-beg node-end) ranges)))))))
      (md-ts--bare-link-sort-merge-ranges ranges))))

(defun md-ts--bare-link-unsafe-range-cache (beg end)
  "Return a nullary function caching unsafe ranges between BEG and END."
  (let (ranges computed)
    (lambda ()
      (unless computed
        (setq ranges (md-ts--bare-link-unsafe-ranges beg end)
              computed t))
      ranges)))

(defun md-ts--range-intersects-sorted-ranges-p (beg end ranges)
  "Return non-nil when BEG..END intersects sorted RANGES."
  (let ((lo 0)
        (hi (length ranges)))
    (while (< lo hi)
      (let* ((mid (+ lo (/ (- hi lo) 2)))
             (range (aref ranges mid)))
        (if (< (car range) end)
            (setq lo (1+ mid))
          (setq hi mid))))
    (let ((index (1- lo)))
      (and (>= index 0)
           (< beg (cdr (aref ranges index)))))))

(defun md-ts--range-in-reference-definition-ranges-p (beg end ranges)
  "Return non-nil when BEG to END is inside one of RANGES."
  (seq-some (lambda (range)
              (and (<= (car range) beg)
                   (<= end (cdr range))))
            ranges))

(defun md-ts--range-in-link-reference-definition-p (beg end)
  "Return non-nil when BEG to END is inside a reference definition."
  (if (eq md-ts--bare-link-reference-definition-ranges
          md-ts--bare-link-reference-definition-no-cache)
      (pcase-let ((`(,line-beg . ,line-end) (md-ts--line-bounds beg end)))
        (md-ts--range-in-reference-definition-ranges-p
         beg end
         (md-ts--link-reference-definition-ranges line-beg line-end)))
    (md-ts--range-in-reference-definition-ranges-p
     beg end md-ts--bare-link-reference-definition-ranges)))

(defun md-ts--bare-link-unsafe-context-p (beg end)
  "Return non-nil when BEG to END is not prose for bare links."
  (cond
   ((eq md-ts--bare-link-unsafe-context-ranges
        md-ts--bare-link-unsafe-context-no-cache)
    (let ((last-pos (max beg (1- end))))
      (or (seq-some
           (lambda (node)
             (md-ts--node-has-ancestor-type-p
              node md-ts--bare-link-unsafe-node-types))
           (list (md-ts--node-at-containing-position beg 'markdown-inline)
                 (md-ts--node-at-containing-position last-pos
                                                     'markdown-inline)
                 (md-ts--node-at-containing-position beg 'markdown)
                 (md-ts--node-at-containing-position last-pos 'markdown)))
          ;; Fall back to the more expensive definition query only when cheap
          ;; point-context checks did not classify the match.
          (md-ts--range-in-link-reference-definition-p beg end))))
   ((functionp md-ts--bare-link-unsafe-context-ranges)
    (md-ts--range-intersects-sorted-ranges-p
     beg end (funcall md-ts--bare-link-unsafe-context-ranges)))
   (t
    (md-ts--range-intersects-sorted-ranges-p
     beg end md-ts--bare-link-unsafe-context-ranges))))

(defun md-ts--button-overlaps-region-p (beg end)
  "Return non-nil when any text or overlay button overlaps BEG to END."
  (or (seq-some (lambda (overlay)
                  (and (overlay-get overlay 'button) overlay))
                (overlays-in beg end))
      (let ((pos beg)
            found)
        (while (and (< pos end) (not found))
          (if (get-text-property pos 'button)
              (setq found t)
            (setq pos (or (next-single-property-change
                           pos 'button nil end)
                          end))))
        found)))

(defconst md-ts--bare-link-terminal-punctuation '(?. ?, ?\; ?\: ?\! ?\?)
  "Prose punctuation trimmed from the end of bare link matches.")

(defconst md-ts--bare-mailto-uri-regexp
  (let ((uri-char "[^]\t\n \\\"'<>[^`{}]"))
    (concat "\\<mailto:"
            "\\(?:"
            ;; Non-empty recipient list containing at least one `@', with
            ;; pragmatic URI characters so percent-escapes and query text are
            ;; preserved as part of the explicit mailto URI.
            "\\(?:" uri-char "*@" uri-char "+\\)"
            "\\|"
            ;; RFC-valid empty-recipient form with a query.
            "\\?" uri-char "+"
            "\\)"))
  "Regexp matching a bare mailto URI with optional recipients and query.")

(defconst md-ts--bare-link-closing-delimiters
  '((?\) . ?\() (?\] . ?\[) (?\} . ?\{) (?> . ?<))
  "Closing delimiters trimmed from bare links when unmatched.")

(defun md-ts--bare-link-matched-closing-delimiters (text)
  "Return a boolean vector for matched closing delimiters in TEXT."
  (let* ((len (length text))
         (matched (make-vector len nil))
         parens brackets braces angles)
    (dotimes (i len)
      (pcase (aref text i)
        (?\( (push i parens))
        (?\) (when parens
               (setq parens (cdr parens))
               (aset matched i t)))
        (?\[ (push i brackets))
        (?\] (when brackets
               (setq brackets (cdr brackets))
               (aset matched i t)))
        (?\{ (push i braces))
        (?\} (when braces
               (setq braces (cdr braces))
               (aset matched i t)))
        (?< (push i angles))
        (?> (when angles
              (setq angles (cdr angles))
              (aset matched i t)))))
    matched))

(defun md-ts--bare-link-normalized-match (beg end &optional terminal-punctuation)
  "Return normalized (BEG END TEXT) for a bare link match.
Terminal prose punctuation and unmatched closing delimiters are
trimmed from END.  Balanced URL delimiters, notably parentheses in
URL paths, are preserved.  TERMINAL-PUNCTUATION, when non-nil,
replaces `md-ts--bare-link-terminal-punctuation' as the prose
punctuation set to trim."
  (let* ((text (buffer-substring-no-properties beg end))
         (trim-length (length text))
         (terminal-punctuation
          (or terminal-punctuation md-ts--bare-link-terminal-punctuation))
         (matched-closers
          (md-ts--bare-link-matched-closing-delimiters text)))
    (while
        (and (> trim-length 0)
             (let* ((last-pos (1- trim-length))
                    (last (aref text last-pos)))
               (or (memq last terminal-punctuation)
                   (and (alist-get last md-ts--bare-link-closing-delimiters)
                        (not (aref matched-closers last-pos))))))
      (setq trim-length (1- trim-length)))
    (let ((normalized-end (+ beg trim-length)))
      (list beg normalized-end (substring text 0 trim-length)))))

(defconst md-ts--bare-mailto-uri-query-terminal-punctuation '(?. ?,)
  "Prose punctuation trimmed from explicit mailto URIs with queries.
Other terminal punctuation such as `!', `?', `:', and `;' is valid
query data after the first question mark.")

(defun md-ts--bare-mailto-uri-query-content-p (text)
  "Return non-nil when mailto URI TEXT has actual query content."
  (save-match-data
    (and (string-match "\\?" text)
         (string-match-p "[[:alnum:]_=&%]" (substring text (match-end 0))))))

(defun md-ts--bare-mailto-uri-normalized-match (beg end)
  "Return normalized (BEG END TEXT) for an explicit bare mailto URI."
  (let ((text (buffer-substring-no-properties beg end)))
    (md-ts--bare-link-normalized-match
     beg end
     (and (md-ts--bare-mailto-uri-query-content-p text)
          md-ts--bare-mailto-uri-query-terminal-punctuation))))

(defun md-ts--regions-intersect-p (beg end other-beg other-end)
  "Return non-nil when BEG..END intersects OTHER-BEG..OTHER-END."
  (if (= other-beg other-end)
      (and (<= beg other-beg) (< other-beg end))
    (and (< beg other-end) (< other-beg end))))

(defun md-ts--fontify-bare-link (beg end target)
  "Fontify BEG to END as a bare prose link to static TARGET."
  (with-silent-modifications
    (let ((inhibit-read-only t))
      (md-ts--add-link-face-to-region beg end)
      (md-ts--make-link-button beg end target nil target))))

(defun md-ts--bare-link-candidate-valid-p (beg end target &optional check-overlap)
  "Return non-nil when BEG..END is a valid bare-link candidate.
TARGET is the candidate activation target.  When CHECK-OVERLAP is
t, reject candidates that overlap any existing button.  When it is
`foreign', reject only candidates that overlap non-md-ts buttons."
  (and (< beg end)
       (not (string-empty-p target))
       (not (pcase check-overlap
              ('foreign (md-ts--foreign-button-in-region-p beg end))
              ((pred identity) (md-ts--button-overlaps-region-p beg end))))
       (not (md-ts--bare-link-unsafe-context-p beg end))))

(defun md-ts--fontify-bare-links-with-regexp
    (regexp scan-beg scan-end apply-beg apply-end target-function
            &optional skip-function normalize-function)
  "Fontify bare links matching REGEXP between SCAN-BEG and SCAN-END.
Only matches intersecting APPLY-BEG to APPLY-END are applied.
TARGET-FUNCTION is called with normalized match text and returns
the static activation target.  Optional SKIP-FUNCTION is called
with normalized match bounds and text; non-nil means skip the
match.  Optional NORMALIZE-FUNCTION maps match bounds to (BEG END
TEXT).  URL matching is intentionally case-insensitive so
uppercase schemes are recognized even when `case-fold-search' is
nil."
  (goto-char scan-beg)
  (while (re-search-forward regexp scan-end t)
    (pcase-let* ((`(,match-beg ,match-end ,text)
                  (funcall (or normalize-function
                               #'md-ts--bare-link-normalized-match)
                           (match-beginning 0) (match-end 0)))
                 (target (funcall target-function text)))
      (unless (or (not (md-ts--regions-intersect-p
                        match-beg match-end apply-beg apply-end))
                  (and skip-function
                       (funcall skip-function match-beg match-end text))
                  (not (md-ts--bare-link-candidate-valid-p
                        match-beg match-end target t)))
        (md-ts--fontify-bare-link match-beg match-end target)))))

(defun md-ts--bare-link-generic-url-ranges
    (scan-beg scan-end &optional check-overlap)
  "Return valid generic bare URL ranges between SCAN-BEG and SCAN-END.
Each returned vector element has the form [BEG END PREFIX-MAX-END TEXT].
CHECK-OVERLAP has the same meaning as in
`md-ts--bare-link-candidate-valid-p'.  The prefix maximum lets
mailto containment checks avoid rescanning `goto-address-url-regexp'
for every explicit mailto candidate."
  (let (ranges
        (prefix-max-end 0))
    (save-excursion
      (save-match-data
        (goto-char scan-beg)
        (while (re-search-forward goto-address-url-regexp scan-end t)
          (pcase-let ((`(,url-beg ,url-end ,text)
                       (md-ts--bare-link-normalized-match
                        (match-beginning 0) (match-end 0))))
            (when (md-ts--bare-link-candidate-valid-p
                   url-beg url-end text check-overlap)
              (setq prefix-max-end (max prefix-max-end url-end))
              (push (vector url-beg url-end prefix-max-end text) ranges))))))
    (vconcat (nreverse ranges))))

(defun md-ts--bare-link-generic-url-range-cache
    (scan-beg scan-end &optional check-overlap)
  "Return a function that lazily caches generic URL ranges.
The returned nullary function collects ranges between SCAN-BEG and
SCAN-END at most once.  CHECK-OVERLAP has the same meaning as in
`md-ts--bare-link-generic-url-ranges'."
  (let (ranges)
    (lambda ()
      (or ranges
          (setq ranges
                (md-ts--bare-link-generic-url-ranges
                 scan-beg scan-end check-overlap))))))

(defun md-ts--bare-link-covered-by-earlier-url-p (beg end url-ranges)
  "Return non-nil when an earlier bare URL in URL-RANGES covers BEG..END.
URL-RANGES should be the vector returned by
`md-ts--bare-link-generic-url-ranges'.  This lets an outer generic
URL own embedded explicit `mailto:' text, while a standalone explicit
mailto URI can own URL-like text inside its query."
  (let ((lo 0)
        (hi (length url-ranges))
        prior-index)
    (while (< lo hi)
      (let* ((mid (+ lo (/ (- hi lo) 2)))
             (range (aref url-ranges mid)))
        (if (< (aref range 0) beg)
            (setq prior-index mid
                  lo (1+ mid))
          (setq hi mid))))
    (and prior-index
         (<= end (aref (aref url-ranges prior-index) 2)))))

(defun md-ts--fontify-bare-url-ranges (url-ranges apply-beg apply-end)
  "Fontify cached URL-RANGES intersecting APPLY-BEG to APPLY-END."
  (dotimes (index (length url-ranges))
    (let* ((range (aref url-ranges index))
           (beg (aref range 0))
           (end (aref range 1))
           (target (aref range 3)))
      (when (and (md-ts--regions-intersect-p beg end apply-beg apply-end)
                 (not (md-ts--button-overlaps-region-p beg end)))
        (md-ts--fontify-bare-link beg end target)))))

(defun md-ts--bare-mailto-uri-embedded-in-scheme-token-p (beg)
  "Return non-nil when a mailto match at BEG is inside a scheme-like token."
  (let ((char (char-before beg)))
    (and char
         (or (and (<= ?a char) (<= char ?z))
             (and (<= ?A char) (<= char ?Z))
             (and (<= ?0 char) (<= char ?9))
             (memq char '(?+ ?- ?.))
             (and (eq char ?:)
                  (save-excursion
                    (goto-char (1- beg))
                    (let ((token-end (point)))
                      (skip-chars-backward "A-Za-z0-9+.-"
                                           (line-beginning-position))
                      (and (< (point) token-end)
                           (let ((first (char-after (point))))
                             (or (and (<= ?a first) (<= first ?z))
                                 (and (<= ?A first) (<= first ?Z))))))))))))

(defun md-ts--bare-mailto-uri-skip-p (beg end url-ranges)
  "Return non-nil when explicit mailto match BEG..END should be skipped.
URL-RANGES are cached generic URL ranges used to detect outer bare URLs."
  (or (md-ts--bare-mailto-uri-embedded-in-scheme-token-p beg)
      (md-ts--bare-link-covered-by-earlier-url-p beg end url-ranges)))

(defun md-ts--bare-email-in-scheme-mailto-uri-p (beg end)
  "Return non-nil when email BEG..END is inside a scheme-prefixed mailto URI."
  (save-excursion
    (let ((case-fold-search t)
          mailto-beg found)
      (goto-char beg)
      (while (search-backward "mailto:" (line-beginning-position) t)
        (unless found
          (setq mailto-beg (point))
          (when (and (eq (char-before mailto-beg) ?:)
                     (md-ts--bare-mailto-uri-embedded-in-scheme-token-p
                      mailto-beg)
                     (looking-at md-ts--bare-mailto-uri-regexp)
                     (pcase-let ((`(,_match-beg ,match-end ,_text)
                                  (md-ts--bare-mailto-uri-normalized-match
                                   (match-beginning 0) (match-end 0))))
                       (<= end match-end)))
            (setq found t))))
      found)))

(defun md-ts--fontify-bare-links (beg end)
  "Fontify bare URLs, email addresses, and `mailto:' URIs.
Operate on lines covering BEG to END."
  (pcase-let ((`(,scan-beg . ,scan-end) (md-ts--line-bounds beg end)))
    (with-silent-modifications
      (let ((inhibit-read-only t))
        (save-restriction
          (widen)
          (md-ts--remove-bare-link-button-properties scan-beg scan-end)
          (save-excursion
            (save-match-data
              (let* ((case-fold-search t)
                     (md-ts--bare-link-unsafe-context-ranges
                      (md-ts--bare-link-unsafe-range-cache
                       scan-beg scan-end))
                     (generic-url-ranges-cache
                      (md-ts--bare-link-generic-url-range-cache
                       scan-beg scan-end t)))
                ;; Scan explicit mailto before generic URLs so a standalone
                ;; mailto owns URL-like query text.  Skip it when a cached
                ;; earlier generic URL covers it, so outer URLs own embedded
                ;; mailto without rescanning the line for every mailto.
                (md-ts--fontify-bare-links-with-regexp
                 md-ts--bare-mailto-uri-regexp
                 scan-beg scan-end scan-beg scan-end #'identity
                 (lambda (match-beg match-end _text)
                   (md-ts--bare-mailto-uri-skip-p
                    match-beg match-end (funcall generic-url-ranges-cache)))
                 #'md-ts--bare-mailto-uri-normalized-match)
                (md-ts--fontify-bare-url-ranges
                 (funcall generic-url-ranges-cache) scan-beg scan-end)
                (md-ts--fontify-bare-links-with-regexp
                 goto-address-mail-regexp
                 scan-beg scan-end scan-beg scan-end
                 (lambda (address) (concat "mailto:" address))
                 (lambda (match-beg match-end _text)
                   (md-ts--bare-email-in-scheme-mailto-uri-p
                    match-beg match-end)))))))))))

(defvar-local md-ts--font-lock-stale-side-effect-bounds nil
  "Old side-effect node bounds recorded before destructive edits.
Indirect buffers share text properties, so this list is stored and
consumed on the base buffer when one exists.  Each element is a
cons of markers in shared buffer coordinates.")

(defun md-ts--font-lock-state-buffer ()
  "Return the buffer that owns shared font-lock side-effect state."
  (or (buffer-base-buffer) (current-buffer)))

(defun md-ts--font-lock-stale-side-effect-bounds ()
  "Return shared stale side-effect bounds for the current buffer family."
  (with-current-buffer (md-ts--font-lock-state-buffer)
    md-ts--font-lock-stale-side-effect-bounds))

(defun md-ts--font-lock-set-stale-side-effect-bounds (bounds)
  "Set shared stale side-effect BOUNDS for the current buffer family."
  (with-current-buffer (md-ts--font-lock-state-buffer)
    (setq md-ts--font-lock-stale-side-effect-bounds bounds)))

(defun md-ts--font-lock-push-stale-side-effect-bounds (beg end)
  "Record shared stale side-effect bounds BEG..END."
  (with-current-buffer (md-ts--font-lock-state-buffer)
    (push (cons (copy-marker beg)
                (copy-marker end t))
          md-ts--font-lock-stale-side-effect-bounds)))

(defconst md-ts--font-lock-side-effect-properties
  '(md-ts-link-button md-ts-link-help-echo md-ts-link-static-target
    md-ts-bare-link-face md-ts-display invisible font-lock-multiline)
  "Text properties that can identify old md-ts side-effect spans.")

(defun md-ts--font-lock-side-effect-node-queries ()
  "Return queries for nodes whose callbacks may write past requested bounds."
  `((markdown . (,@(when md-ts-hide-markup
                    '((fenced_code_block) @node))
                 (link_reference_definition) @node))
    (markdown-inline . ((inline_link) @node
                        (image) @node
                        (full_reference_link) @node
                        (collapsed_reference_link) @node
                        (shortcut_link) @node
                        (uri_autolink) @node
                        (email_autolink) @node))))

(defconst md-ts--font-lock-bare-unsafe-context-node-queries
  '((markdown . ((fenced_code_block) @node
                 (indented_code_block) @node
                 (html_block) @node)))
  "Queries for multi-line nodes that can make existing bare UI unsafe.")

(defun md-ts--font-lock-line-fontify-bounds (beg end)
  "Return line-based fontification bounds covering BEG through END."
  (pcase-let ((`(,line-beg . ,line-end) (md-ts--line-bounds beg end)))
    (cons line-beg
          (if (< line-end (point-max))
              (1+ line-end)
            line-end))))

(defun md-ts--font-lock-parser-language (parser)
  "Return PARSER's language, or nil after safely discarding bad parsers."
  (condition-case nil
      (treesit-parser-language parser)
    (error
     (ignore-errors (treesit-parser-delete parser))
     nil)))

(defun md-ts--font-lock-prune-invalid-local-parsers (beg end)
  "Delete local-parser overlays with invalid parser objects in BEG..END."
  (dolist (overlay (overlays-in beg end))
    (when-let* ((parser (overlay-get overlay 'treesit-parser)))
      (unless (md-ts--font-lock-parser-language parser)
        (delete-overlay overlay)))))

(defun md-ts--font-lock-root-nodes (beg end language)
  "Return tree-sitter root nodes for LANGUAGE overlapping BEG to END."
  (let* ((local-parsers (seq-filter
                         (lambda (parser)
                           (eq (md-ts--font-lock-parser-language parser)
                               language))
                         (ignore-errors
                           (treesit-local-parsers-on beg end))))
         (global-parsers (seq-filter
                          (lambda (parser)
                            (eq (md-ts--font-lock-parser-language parser)
                                language))
                          (ignore-errors
                            (md-ts--parser-list nil nil)))))
    (delq nil
          (mapcar (lambda (parser)
                    (ignore-errors (treesit-parser-root-node parser)))
                  (append local-parsers global-parsers)))))

(defun md-ts--font-lock-multiline-node-p (node)
  "Return non-nil when NODE spans more than one physical line."
  (save-excursion
    (let ((start-line (progn
                        (goto-char (treesit-node-start node))
                        (line-beginning-position)))
          (end-line (progn
                      (goto-char (max (treesit-node-start node)
                                      (1- (treesit-node-end node))))
                      (line-beginning-position))))
      (/= start-line end-line))))

(defun md-ts--font-lock-expanded-node-bounds
    (fontify-beg fontify-end queries &optional boundary-only)
  "Return FONTIFY-BEG..FONTIFY-END expanded over multi-line QUERIES.
When BOUNDARY-ONLY is non-nil, only expand over nodes whose start
or end line is touched by FONTIFY-BEG..FONTIFY-END."
  (let ((expanded-beg fontify-beg)
        (expanded-end fontify-end))
    (dolist (spec queries)
      (pcase-let ((`(,language . ,query) spec))
        (dolist (root (md-ts--font-lock-root-nodes
                       fontify-beg fontify-end language))
          (dolist (capture (ignore-errors
                              (treesit-query-capture
                               root query fontify-beg fontify-end)))
            (let ((node (cdr capture)))
              (when (and (md-ts--font-lock-multiline-node-p node)
                         (md-ts--regions-intersect-p
                          fontify-beg fontify-end
                          (treesit-node-start node)
                          (treesit-node-end node))
                         (or (not boundary-only)
                             (md-ts--region-touches-node-boundary-line-p
                              node fontify-beg fontify-end)))
                (pcase-let ((`(,node-beg . ,node-end)
                             (md-ts--font-lock-line-fontify-bounds
                              (treesit-node-start node)
                              (treesit-node-end node))))
                  (setq expanded-beg (min expanded-beg node-beg)
                        expanded-end (max expanded-end node-end)))))))))
    (cons expanded-beg expanded-end)))

(defun md-ts--font-lock-owned-side-effect-property-p (pos)
  "Return non-nil when POS has an md-ts-owned side-effect property."
  (or (get-text-property pos 'md-ts-link-button)
      (get-text-property pos 'md-ts-link-help-echo)
      (get-text-property pos 'md-ts-link-static-target)
      (get-text-property pos 'md-ts-bare-link-face)
      (get-text-property pos 'md-ts-display)
      (eq (get-text-property pos 'invisible) 'md-ts--markup)
      (get-text-property pos 'font-lock-multiline)))

(defun md-ts--font-lock-side-effect-property-span (pos)
  "Return md-ts side-effect property span around POS."
  (let ((beg pos)
        (end (1+ pos)))
    (dolist (prop md-ts--font-lock-side-effect-properties)
      (when (cond
             ((eq prop 'invisible)
              (eq (get-text-property pos prop) 'md-ts--markup))
             (t
              (get-text-property pos prop)))
        (setq beg (min beg (or (previous-single-property-change
                                 (min (1+ pos) (point-max)) prop nil
                                 (point-min))
                                (point-min)))
              end (max end (or (next-single-property-change
                                 pos prop nil (point-max))
                                (point-max))))))
    (cons beg end)))

(defun md-ts--font-lock-next-side-effect-property-change (pos limit)
  "Return next possible md-ts side-effect property change after POS before LIMIT."
  (cl-loop for prop in md-ts--font-lock-side-effect-properties
           minimize (or (next-single-property-change pos prop nil limit)
                        limit)))

(defun md-ts--font-lock-expand-bounds-for-properties (beg end)
  "Expand BEG..END over existing md-ts side-effect property spans."
  (let ((fontify-beg beg)
        (fontify-end end)
        (pos beg))
    (while (< pos fontify-end)
      (if (md-ts--font-lock-owned-side-effect-property-p pos)
          (pcase-let* ((`(,span-beg . ,span-end)
                        (md-ts--font-lock-side-effect-property-span pos))
                       (`(,expanded-beg . ,expanded-end)
                        (md-ts--font-lock-line-fontify-bounds
                         (min fontify-beg span-beg)
                         (max fontify-end span-end))))
            (setq fontify-beg expanded-beg
                  fontify-end expanded-end
                  pos (min fontify-end (max (1+ pos) span-end))))
        (setq pos (md-ts--font-lock-next-side-effect-property-change
                   pos fontify-end))))
    (cons fontify-beg fontify-end)))

(defun md-ts--font-lock-consume-stale-side-effect-bounds (beg end)
  "Return and consume stale side-effect bounds intersecting BEG..END."
  (let (bounds keep)
    (dolist (range (md-ts--font-lock-stale-side-effect-bounds))
      (let ((range-beg (marker-position (car range)))
            (range-end (marker-position (cdr range))))
        (cond
         ((or (not range-beg) (not range-end) (>= range-beg range-end))
          (set-marker (car range) nil)
          (set-marker (cdr range) nil))
         ((md-ts--regions-intersect-p beg end range-beg range-end)
          (push (cons range-beg range-end) bounds)
          (set-marker (car range) nil)
          (set-marker (cdr range) nil))
         (t
          (push range keep)))))
    (md-ts--font-lock-set-stale-side-effect-bounds (nreverse keep))
    (nreverse bounds)))

(defun md-ts--font-lock-record-stale-side-effect-bounds (beg end)
  "Record old multi-line side-effect node bounds touched by BEG..END."
  (save-excursion
    (save-restriction
      (widen)
      (pcase-let ((`(,fontify-beg . ,fontify-end)
                   (md-ts--font-lock-line-fontify-bounds beg end)))
        (dolist (spec (md-ts--font-lock-side-effect-node-queries))
          (pcase-let ((`(,language . ,query) spec))
            (dolist (root (md-ts--font-lock-root-nodes
                           fontify-beg fontify-end language))
              (dolist (capture (ignore-errors
                                  (treesit-query-capture
                                   root query fontify-beg fontify-end)))
                (let ((node (cdr capture)))
                  (when (and (md-ts--font-lock-multiline-node-p node)
                             (md-ts--regions-intersect-p
                              fontify-beg fontify-end
                              (treesit-node-start node)
                              (treesit-node-end node)))
                    (pcase-let ((`(,expanded-beg . ,expanded-end)
                                 (md-ts--font-lock-line-fontify-bounds
                                  (treesit-node-start node)
                                  (treesit-node-end node))))
                      (md-ts--font-lock-push-stale-side-effect-bounds
                       expanded-beg expanded-end))))))))))))

(defun md-ts--font-lock-expand-bounds-for-side-effects (beg end)
  "Expand BEG..END to cover multi-line callback side-effect nodes.
The returned bounds remain line-based so bare-link scanning cannot
mutate outside the bounds reported to jit-lock."
  (save-excursion
    (save-restriction
      (widen)
      (md-ts--font-lock-prune-invalid-local-parsers beg end)
      (ignore-errors (treesit-update-ranges beg end))
      (pcase-let ((`(,fontify-beg . ,fontify-end)
                   (md-ts--font-lock-line-fontify-bounds beg end)))
        (let ((changed t))
          (while changed
            (setq changed nil)
            (pcase-let ((`(,prop-beg . ,prop-end)
                         (md-ts--font-lock-expand-bounds-for-properties
                          fontify-beg fontify-end)))
              (unless (and (= prop-beg fontify-beg)
                           (= prop-end fontify-end))
                (setq fontify-beg prop-beg
                      fontify-end prop-end
                      changed t)))
            (dolist (range (md-ts--font-lock-consume-stale-side-effect-bounds
                            fontify-beg fontify-end))
              (pcase-let ((`(,expanded-beg . ,expanded-end)
                           (md-ts--font-lock-line-fontify-bounds
                            (min fontify-beg (car range))
                            (max fontify-end (cdr range)))))
                (unless (and (= expanded-beg fontify-beg)
                             (= expanded-end fontify-end))
                  (setq fontify-beg expanded-beg
                        fontify-end expanded-end
                        changed t))))
            (dolist (expansion
                     (list (cons (md-ts--font-lock-side-effect-node-queries)
                                 nil)
                           (cons md-ts--font-lock-bare-unsafe-context-node-queries
                                 t)))
              (pcase-let ((`(,expanded-beg . ,expanded-end)
                           (md-ts--font-lock-expanded-node-bounds
                            fontify-beg fontify-end
                            (car expansion) (cdr expansion))))
                (unless (and (= expanded-beg fontify-beg)
                             (= expanded-end fontify-end))
                  (setq fontify-beg expanded-beg
                        fontify-end expanded-end
                        changed t))))))
        (cons fontify-beg fontify-end)))))

(defun md-ts--font-lock-fontify-region (beg end &optional loudly)
  "Fontify BEG to END with tree-sitter plus bare prose links.
LOUDLY is passed to `treesit-font-lock-fontify-region'.  Return
jit-lock bounds for the expanded physical lines fontified and bare-scanned."
  (pcase-let ((`(,fontify-beg . ,fontify-end)
               (md-ts--font-lock-expand-bounds-for-side-effects beg end)))
    (save-restriction
      (widen)
      (md-ts--remove-display-properties fontify-beg fontify-end)
      (md-ts--font-lock-prune-invalid-local-parsers fontify-beg fontify-end)
      (treesit-font-lock-fontify-region fontify-beg fontify-end loudly))
    (md-ts--fontify-bare-links fontify-beg fontify-end)
    `(jit-lock-bounds ,fontify-beg . ,fontify-end)))

(defun md-ts--link-target-at-point (&optional pos)
  "Return the parsed Markdown link target at POS, or nil.
POS defaults to point.  This covers both visible link text and the
parsed markup belonging to a link."
  (let ((pos (or pos (point))))
    (seq-some (lambda (node)
                (and node (md-ts--link-target-for-node node)))
              (list (md-ts--node-at-containing-position
                     pos 'markdown-inline)
                    (md-ts--node-at-containing-position
                     pos 'markdown)))))

(defun md-ts--bare-link-target-at-point-with-regexp
    (pos regexp line-beg line-end target-function &optional skip-function
         normalize-function check-overlap)
  "Return bare-link target at POS matching REGEXP, or nil.
LINE-BEG and LINE-END bound the scan.  TARGET-FUNCTION maps the
normalized match text to an opener target.  Optional SKIP-FUNCTION
receives normalized match bounds and text; non-nil means skip the
match.  Optional NORMALIZE-FUNCTION maps match bounds to (BEG END
TEXT).  CHECK-OVERLAP has the same meaning as in
`md-ts--bare-link-candidate-valid-p'."
  (save-excursion
    (goto-char line-beg)
    (catch 'target
      (while (re-search-forward regexp line-end t)
        (pcase-let* ((`(,match-beg ,match-end ,text)
                      (funcall (or normalize-function
                                   #'md-ts--bare-link-normalized-match)
                               (match-beginning 0) (match-end 0)))
                     (target (funcall target-function text)))
          (when (and (<= match-beg pos)
                     (< pos match-end)
                     (not (and skip-function
                               (funcall skip-function
                                        match-beg match-end text)))
                     (md-ts--bare-link-candidate-valid-p
                      match-beg match-end target check-overlap))
            (throw 'target target)))))))

(defun md-ts--bare-link-target-at-point (&optional pos check-overlap)
  "Return current valid bare URL, email, or `mailto:' URI target at POS.
This recomputes from buffer text and parser context instead of
trusting possibly stale static button properties.  CHECK-OVERLAP
has the same meaning as in `md-ts--bare-link-candidate-valid-p'."
  (let ((pos (or pos (point))))
    (pcase-let ((`(,line-beg . ,line-end) (md-ts--line-bounds pos pos)))
      (save-restriction
        (widen)
        (save-match-data
          (let* ((case-fold-search t)
                 (md-ts--bare-link-unsafe-context-ranges
                  (md-ts--bare-link-unsafe-range-cache
                   line-beg line-end))
                 (generic-url-ranges-cache
                  (md-ts--bare-link-generic-url-range-cache
                   line-beg line-end check-overlap)))
            ;; Match fontification precedence: standalone mailto owns query
            ;; text, but an outer URL wins over embedded mailto/email-looking
            ;; text in its path or query.
            (or (md-ts--bare-link-target-at-point-with-regexp
                 pos md-ts--bare-mailto-uri-regexp line-beg line-end #'identity
                 (lambda (match-beg match-end _text)
                   (md-ts--bare-mailto-uri-skip-p
                    match-beg match-end (funcall generic-url-ranges-cache)))
                 #'md-ts--bare-mailto-uri-normalized-match check-overlap)
                (md-ts--bare-link-target-at-point-with-regexp
                 pos goto-address-url-regexp line-beg line-end #'identity
                 nil nil check-overlap)
                (md-ts--bare-link-target-at-point-with-regexp
                 pos goto-address-mail-regexp line-beg line-end
                 (lambda (address) (concat "mailto:" address))
                 (lambda (match-beg match-end _text)
                   (md-ts--bare-email-in-scheme-mailto-uri-p
                    match-beg match-end))
                 nil check-overlap))))))))

(defun md-ts--open-link-button (button)
  "Open Markdown link BUTTON.
Static bare-link buttons prefer recomputing their current bare
link target at activation time.  Parsed Markdown buttons prefer
resolving the parsed target at activation time so reference links
stay fresh.  Text-button actions pass a marker at the actual
activation position; use that position when available so stale
multi-URL button spans revalidate the clicked URL, not just the
button start.  If stale button properties no longer match the
current buffer syntax, fall back to the other resolver before
signaling."
  (let* ((pos (or (and (markerp button) (marker-position button))
                  (button-start button)))
         (url (if (button-get button 'md-ts-link-static-target)
                  (or (md-ts--bare-link-target-at-point pos 'foreign)
                      (md-ts--link-target-at-point pos))
                (or (md-ts--link-target-at-point pos)
                    (md-ts--bare-link-target-at-point pos)))))
    (if url
        (md-ts--open-link-destination url)
      (user-error "No link target at point"))))

(defun md-ts--link-button-p (button)
  "Return non-nil if BUTTON is a current md-ts Markdown link button."
  (and (markerp button)
       (button-get button 'md-ts-link-button)
       (eq (button-get button 'action) #'md-ts--open-link-button)))

(defun md-ts--ensure-link-fontification-at-point (&optional pos)
  "Ensure font-lock and tree-sitter link state around POS.
POS defaults to point.  Fontifying the containing line initializes
Markdown-inline parser ranges and link button properties in fresh
`md-ts-mode' buffers."
  (save-excursion
    (goto-char (or pos (point)))
    (font-lock-ensure (line-beginning-position)
                      (line-end-position))))

(defun md-ts-open-link-at-point ()
  "Open the supported Markdown or bare prose link at point.
Supported targets include parsed Markdown links/images and
reference-definition labels with non-empty destinations, resolved
reference links, URI autolinks, email autolinks, bare URLs, bare
email addresses, and explicit bare `mailto:' URIs.  If point is on
buttonized link text, activate that button.  If point is on parsed
Markdown link markup, resolve the same target.  Otherwise, fall
back to a revalidated bare target at point.  All fragment
navigation is deferred: local paths with an unescaped `#fragment'
open only the file part, and fragment-only destinations signal a
`user-error'.  Escaped `#' characters in local paths are literal
filename characters.  Signal a `user-error' when point is not on a
supported link."
  (interactive)
  (md-ts--ensure-link-fontification-at-point)
  (let ((button (button-at (point))))
    ;; Only md-ts-owned text buttons are activated.  Foreign text or overlay
    ;; buttons fall through to parser resolution, never to `push-button'.
    (if (md-ts--link-button-p button)
        (push-button (point))
      (let ((url (or (md-ts--link-target-at-point)
                     (md-ts--bare-link-target-at-point))))
        (if url
            (md-ts--open-link-destination url)
          (user-error "No Markdown or bare link at point"))))))

(defvar md-ts-mode-map (make-sparse-keymap)
  "Keymap for `md-ts-mode'.
\\<md-ts-mode-map>\\[md-ts-open-link-at-point] runs
`md-ts-open-link-at-point'.")

(set-keymap-parent md-ts-mode-map text-mode-map)
(define-key md-ts-mode-map (kbd "C-c C-o") #'md-ts-open-link-at-point)

;;; Major mode

(defun md-ts--setup-clean-side-effect-properties ()
  "Clean md-ts-owned whole-buffer side effects for mode setup.
Indirect buffers share text properties with their base buffer, so a
setup-time whole-buffer sweep there would strip the base buffer's
current UI before regional refontification can recreate it.  Normal
buffers still clean old md-ts properties when the mode starts."
  (unless (buffer-base-buffer)
    (save-restriction
      (widen)
      (md-ts--remove-display-properties (point-min) (point-max))
      (md-ts--remove-bare-link-button-properties (point-min) (point-max))
      (md-ts--remove-link-button-properties (point-min) (point-max)))
    (md-ts--font-lock-set-stale-side-effect-bounds nil)))

(defun md-ts-setup ()
  "Setup treesit for `md-ts-mode'."
  (make-local-variable 'md-ts-hide-markup)
  (setq-local treesit-font-lock-settings md-ts--treesit-settings)
  (setq-local treesit-range-settings (md-ts--range-settings))
  (setq-local font-lock-extra-managed-props
              (seq-uniq
               (cons 'invisible
                     (seq-remove
                      (lambda (prop)
                        (memq prop '(button category action help-echo
                                     md-ts-link-button
                                     md-ts-link-help-echo
                                     md-ts-link-static-target)))
                      font-lock-extra-managed-props))))
  (setq-local font-lock-unfontify-region-function
              #'md-ts--font-lock-unfontify-region)
  (md-ts--setup-clean-side-effect-properties)
  (add-hook 'before-change-functions
            #'md-ts--font-lock-record-stale-side-effect-bounds nil t)
  (add-hook 'before-change-functions
            #'md-ts--before-change-check-link-reference-definition nil t)
  (add-hook 'after-change-functions
            #'md-ts--after-change-flush-link-reference-links nil t)

  (when (treesit-ready-p 'html t)
    (treesit-parser-create 'html)
    (when (require 'html-ts-mode nil t)
      (defvar html-ts-mode--font-lock-settings)
      (setq-local treesit-font-lock-settings
                  (append treesit-font-lock-settings
                          html-ts-mode--font-lock-settings))
      (setq-local treesit-font-lock-feature-list
                  (treesit-merge-font-lock-feature-list
                   treesit-font-lock-feature-list
                   (bound-and-true-p
                    html-ts-mode--treesit-font-lock-feature-list)))
      (setq-local treesit-range-settings
                  (append treesit-range-settings
                          (treesit-range-rules
                           :embed 'html
                           :host 'markdown
                           :local t
                           '((html_block) @html)

                           :embed 'html
                           :host 'markdown-inline
                           '((html_tag) @html))))))

  (when (treesit-ready-p 'yaml t)
    (require 'yaml-ts-mode)
    (defvar yaml-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        yaml-ts-mode--font-lock-settings))
    (setq-local treesit-font-lock-feature-list
                (treesit-merge-font-lock-feature-list
                 treesit-font-lock-feature-list
                 (bound-and-true-p
                  yaml-ts-mode--font-lock-feature-list)))
    (setq-local treesit-range-settings
                (append treesit-range-settings
                        (treesit-range-rules
                         :embed 'yaml
                         :host 'markdown
                         :local t
                         '((minus_metadata) @yaml)))))

  (when (treesit-ready-p 'toml t)
    (require 'toml-ts-mode)
    (defvar toml-ts-mode--font-lock-settings)
    (setq treesit-font-lock-settings
          (append treesit-font-lock-settings
                  toml-ts-mode--font-lock-settings))
    (setq-local treesit-font-lock-feature-list
                (treesit-merge-font-lock-feature-list
                 treesit-font-lock-feature-list
                 (bound-and-true-p
                  toml-ts-mode--font-lock-feature-list)))
    (setq-local treesit-range-settings
                (append treesit-range-settings
                        (treesit-range-rules
                         :embed 'toml
                         :host 'markdown
                         :local t
                         '((plus_metadata) @toml)))))

  (treesit-major-mode-setup)
  (setq-local font-lock-fontify-region-function
              #'md-ts--font-lock-fontify-region)
  (md-ts--set-hide-markup md-ts-hide-markup)

  ;; Append md-ts-code rules LAST so they run after all embedded
  ;; language fontification.  `md-ts--add-config-for-mode' ensures
  ;; code rules stay at the end even when new languages are added
  ;; dynamically.  This ordering is critical:
  ;;   1. Embedded lang rules run first with nil override (set face)
  ;;   2. Code rules run last with :override 'append (layer md-ts-code)
  (setq-local treesit-font-lock-settings
              (append treesit-font-lock-settings
                      (treesit-font-lock-rules
                       :language 'markdown
                       :feature 'code
                       :override 'append
                       '((fenced_code_block) @md-ts-code
                         (indented_code_block) @md-ts-code))))
  (treesit-font-lock-recompute-features '(code)))

;;;###autoload
(define-derived-mode md-ts-mode text-mode "Markdown"
  "Major mode for editing Markdown using tree-sitter grammar."

  (setq-local comment-start "<!-- ")
  (setq-local comment-end " -->")

  (setq-local font-lock-defaults nil
	      treesit-font-lock-feature-list '((delimiter heading)
					       (paragraph)
					       (paragraph-inline)))

  (setq-local treesit-simple-imenu-settings
              `(("Headings" ,#'md-ts-imenu-node-p
                 nil ,#'md-ts-imenu-name-function)))
  (setq-local treesit-outline-predicate #'md-ts-outline-predicate)

  (when (and (treesit-ensure-installed 'markdown)
             (treesit-ensure-installed 'markdown-inline))
    ;; Global markdown-inline parser with empty ranges: prevents
    ;; Emacs from auto-creating a full-buffer parser.  Actual
    ;; fontification uses local per-node parsers (see range settings).
    (let ((inline-parser (treesit-parser-create 'markdown-inline)))
      (treesit-parser-set-included-ranges
       inline-parser `((,(point-min) . ,(point-min)))))
    (treesit-parser-create 'markdown)
    (md-ts-setup)))

(derived-mode-add-parents 'md-ts-mode '(markdown-mode))

;;;###autoload
(defun md-ts-mode-maybe ()
  "Enable `md-ts-mode' when its grammar is available."
  (declare-function treesit-language-available-p "treesit.c")
  (if (or (treesit-language-available-p 'markdown)
          (eq treesit-enabled-modes t)
          (memq 'md-ts-mode treesit-enabled-modes))
      (md-ts-mode)
    (fundamental-mode)))

;;;###autoload
(defun md-ts-mode-enable-global ()
  "Explicitly prefer `md-ts-mode' for Markdown buffers globally.

This is safe to call from user init files and is idempotent.
It adds a `\\.md\\' entry to `auto-mode-alist', remaps
`markdown-mode' through `major-mode-remap-alist', and, when the
built-in `markdown-ts-mode' is available, remaps that mode too."
  ;; Emacs 31 routes .md files through `markdown-ts-mode-maybe', so a
  ;; remap alone would not change plain file visits.
  (add-to-list 'auto-mode-alist '("\\.md\\'" . md-ts-mode-maybe))
  (add-to-list 'major-mode-remap-alist '(markdown-mode . md-ts-mode))
  (when (or (fboundp 'markdown-ts-mode)
            (locate-library "markdown-ts-mode"))
    (add-to-list 'major-mode-remap-alist
                 '(markdown-ts-mode . md-ts-mode))))

(provide 'md-ts-mode)
;;; md-ts-mode.el ends here
