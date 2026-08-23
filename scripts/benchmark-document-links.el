;;; benchmark-document-links.el --- Document-link fontification benchmarks  -*- lexical-binding: t; -*-
;;
;; Advisory benchmark for local reviewers.  It intentionally has no pass/fail
;; timing thresholds; compare RESULT lines on the same machine before/after a
;; change instead.
;;
;; Usage from the repository root:
;;   make perf
;;
;; Optional environment / Make variables:
;;   PERF_ITERATIONS=5 make perf
;;   MD_TS_TREE_SITTER_DIR=/path/to/grammars make perf

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'treesit)

(defconst md-ts-bench--repo-root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory (or load-file-name
                                                    buffer-file-name
                                                    default-directory))))
  "Repository root for the checkout under benchmark.")

(defun md-ts-bench--env-paths (name)
  "Return path entries from environment variable NAME."
  (when-let* ((value (getenv name)))
    (split-string value path-separator t)))

(defun md-ts-bench--add-existing-tree-sitter-paths ()
  "Add common tree-sitter grammar directories when they exist.
Entries from MD_TS_TREE_SITTER_DIR have highest priority, followed
by TREE_SITTER_GRAMMAR_DIR and finally the default user directory."
  (let (paths)
    (dolist (dir (append (md-ts-bench--env-paths "MD_TS_TREE_SITTER_DIR")
                         (md-ts-bench--env-paths "TREE_SITTER_GRAMMAR_DIR")
                         (list (expand-file-name "tree-sitter"
                                                 user-emacs-directory))))
      (when (and (stringp dir)
                 (not (string-empty-p dir))
                 (file-directory-p dir)
                 (not (member dir paths)))
        (push dir paths)))
    (setq treesit-extra-load-path
          (append (nreverse paths)
                  (cl-remove-if (lambda (dir) (member dir paths))
                                treesit-extra-load-path)))))

(md-ts-bench--add-existing-tree-sitter-paths)
(add-to-list 'load-path md-ts-bench--repo-root)
(load (expand-file-name "md-ts-mode.el" md-ts-bench--repo-root) nil 'nomessage)
(declare-function md-ts-mode "md-ts-mode")

(defvar md-ts-bench-iterations
  (let ((value (getenv "PERF_ITERATIONS")))
    (if (and value (string-match-p "\\`[0-9]+\\'" value))
        (max 1 (string-to-number value))
      3))
  "Number of timed iterations per benchmark case.")

(defvar md-ts-bench-smoke
  (and (member (getenv "MD_TS_BENCH_SMOKE") '("1" "t" "true" "yes")) t)
  "Non-nil means run a tiny runtime smoke instead of full benchmarks.")

(setq inhibit-message t
      message-log-max nil
      font-lock-maximum-decoration t)

(defun md-ts-bench--log (format-string &rest args)
  "Print FORMAT-STRING with ARGS and a trailing newline."
  (princ (concat (apply #'format format-string args) "\n")))

(defun md-ts-bench--git-output (&rest args)
  "Return trimmed git output for ARGS in `md-ts-bench--repo-root'."
  (condition-case nil
      (with-temp-buffer
        (if (zerop (apply #'call-process "git" nil t nil
                          "-C" md-ts-bench--repo-root args))
            (string-trim (buffer-string))
          "unknown"))
    (error "unknown")))

(defun md-ts-bench--git-dirty-p ()
  "Return non-nil when tracked files differ from HEAD."
  (condition-case nil
      (not (zerop (call-process "git" nil nil nil
                                "-C" md-ts-bench--repo-root
                                "diff" "--quiet" "HEAD" "--")))
    (error nil)))

(defun md-ts-bench--git-untracked-p ()
  "Return non-nil when untracked files are present in the checkout."
  (not (string-empty-p (md-ts-bench--git-output
                        "ls-files" "--others" "--exclude-standard"))))

(defun md-ts-bench--line-count (text)
  "Return the number of logical lines in TEXT."
  (if (string-empty-p text)
      0
    (with-temp-buffer
      (insert text)
      (count-lines (point-min) (point-max)))))

(defun md-ts-bench--median (numbers)
  "Return the median of NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (len (length sorted)))
    (if (cl-oddp len)
        (nth (/ len 2) sorted)
      (/ (+ (nth (1- (/ len 2)) sorted)
            (nth (/ len 2) sorted))
         2.0))))

(defun md-ts-bench--format-ms-list (numbers)
  "Format millisecond NUMBERS for RESULT output."
  (mapconcat (lambda (number) (format "%.3f" number)) numbers ","))

(defun md-ts-bench--time-ms (thunk)
  "Run THUNK and return elapsed milliseconds."
  (garbage-collect)
  (let ((gc-cons-threshold most-positive-fixnum)
        (gc-cons-percentage 1.0))
    (let ((start (float-time)))
      (funcall thunk)
      (* 1000.0 (- (float-time) start)))))

(defun md-ts-bench--measure (iterations thunk)
  "Run THUNK ITERATIONS times and return elapsed milliseconds."
  (let (times)
    (dotimes (_ iterations)
      (push (md-ts-bench--time-ms thunk) times))
    (nreverse times)))

(defun md-ts-bench--plain-prose-doc (lines)
  "Return a plain Markdown prose fixture with LINES lines and no links."
  (mapconcat
   (lambda (i)
     (format (concat "Plain prose %04d has ordinary words, punctuation, "
                     "and markdown-free discussion for a no-link control.")
             i))
   (number-sequence 1 lines)
   "\n"))

(defun md-ts-bench--bare-links-doc (lines)
  "Return a bare URL/email Markdown fixture with LINES lines."
  (mapconcat
   (lambda (i)
     (format (concat "Bare %04d: https://example.com/projects/%04d/issues/%04d"
                     "?utm=md-ts#comment-%04d mailto:owner%04d@example.com"
                     "?subject=Thread-%04d owner%04d@example.net")
             i i (+ 1000 i) i i i i))
   (number-sequence 1 lines)
   "\n"))

(defun md-ts-bench--parsed-references-doc (count)
  "Return a reference-heavy Markdown fixture with COUNT references."
  (concat
   "# Reference-heavy fixture\n\n"
   (mapconcat
    (lambda (i)
      (format "Reference %04d: [design note %04d][note-%04d] follows ordinary prose."
              i i i))
    (number-sequence 1 count)
    "\n")
   "\n\n"
   (mapconcat
    (lambda (i)
      (format "[note-%04d]: https://references.example.com/notes/%04d \"Reference title %04d\""
              i i i))
    (number-sequence 1 count)
    "\n")))

(defun md-ts-bench--long-line-doc (items)
  "Return a long-line stress fixture with ITEMS link groups."
  (concat
   "# Long-line one-character JIT fixture\n\n"
   (mapconcat
    (lambda (i)
      (format (concat "https://stress.example.com/%04d/path/(paren)"
                      "?redirect=mailto:user%04d@example.com"
                      "&next=http://nested.example/%04d "
                      "mailto:direct%04d@example.net?subject=Hello-%04d "
                      "user%04d@example.org")
              i i i i i i))
    (number-sequence 1 items)
    " ")
   "\n\nParsed tail [tail](https://parsed.example/tail) and [ref][stress-ref].\n"
   "[stress-ref]: https://reference.example/stress\n"))

(defun md-ts-bench--mixed-chat-prose-doc (threads)
  "Return a mixed chat/prose fixture with THREADS sections."
  (with-temp-buffer
    (insert "# Synthetic support transcript\n\n")
    (insert "A deterministic mix of prose, parsed links, bare links, fences, and HTML.\n\n")
    (dotimes (zero-based threads)
      (let ((i (1+ zero-based)))
        (insert (format "## Thread %03d\n\n" i))
        (insert (format (concat "Alice: please inspect https://chat.example.com/t/%03d"
                                "?from=markdown#message-%03d and email owner%03d@example.com.\n")
                        i i i))
        (insert (format (concat "Bob: parsed [ticket %03d](https://tracker.example.net/issues/%03d)"
                                " plus reference [runbook][runbook-%03d].\n")
                        i i i))
        (insert (format (concat "Carol: autolink <https://auto.example.org/%03d/path?q=a,b>"
                                " and explicit mailto:team%03d@example.org?subject=Thread-%03d.\n")
                        i i i))
        (insert (format "> Quoted prose has http://quoted.example.com/%03d/(paren)/end and quoted%03d@example.net.\n\n"
                        i i))
        (insert (format "[runbook-%03d]: https://references.example.com/runbooks/%03d\n\n"
                        i i))
        (when (= (mod i 10) 0)
          (insert (format (concat "```sh\n"
                                  "# URLs in fences should not become bare buttons\n"
                                  "curl 'https://code.example.invalid/%03d?email=code%03d@example.invalid'\n"
                                  "mailto:code%03d@example.invalid?subject=not-prose\n"
                                  "```\n\n")
                          i i i)))
        (when (= (mod i 8) 0)
          (insert (format (concat "<div class=\"ticket\" data-url=\"https://html.example.invalid/%03d\">\n"
                                  "  Contact html%03d@example.invalid or visit http://html.example.invalid/%03d inside HTML.\n"
                                  "</div>\n\n")
                          i i i)))))
    (buffer-string)))

(defun md-ts-bench--count-property-spans (property)
  "Return the number of non-nil contiguous spans for PROPERTY."
  (let ((pos (point-min))
        (count 0))
    (while (< pos (point-max))
      (let ((next (or (next-single-property-change pos property nil
                                                   (point-max))
                      (point-max))))
        (when (get-text-property pos property)
          (setq count (1+ count)))
        (setq pos next)))
    count))

(defun md-ts-bench--link-counts ()
  "Return counts for md-ts link artifacts in the current buffer."
  (list :link-buttons (md-ts-bench--count-property-spans 'md-ts-link-button)
        :bare-link-props (md-ts-bench--count-property-spans 'md-ts-bare-link-face)
        :static-targets (md-ts-bench--count-property-spans
                         'md-ts-link-static-target)))

(defun md-ts-bench--fontify-text (text &optional count)
  "Enable `md-ts-mode' and fontify TEXT in a temporary buffer.
When COUNT is non-nil, return link artifact counts after fontification."
  (let ((buffer (generate-new-buffer " *md-ts-bench*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert text)
          (goto-char (point-min))
          (md-ts-mode)
          (font-lock-ensure (point-min) (point-max))
          (when count
            (md-ts-bench--link-counts)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun md-ts-bench--measure-jit-one-char (iterations text)
  "Measure one-character refontification in a prepared long-line TEXT buffer."
  (let ((buffer (generate-new-buffer " *md-ts-bench-jit*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert text)
          (goto-char (point-min))
          (md-ts-mode)
          (font-lock-ensure (point-min) (point-max))
          (goto-char (point-min))
          (forward-line 2)
          (let* ((line-beg (line-beginning-position))
                 (line-end (line-end-position))
                 (mid (+ line-beg (/ (- line-end line-beg) 2))))
            (md-ts-bench--measure
             iterations
             (lambda ()
               ;; Simulate jit-lock asking for a tiny region after an edit on
               ;; a pathological URL-heavy physical line.
               (font-lock-fontify-region mid (min line-end (1+ mid)))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun md-ts-bench--measure-mutation-one-char
    (iterations text &optional anchor mutations)
  "Measure per-mutation cost of one-character edits in a TEXT buffer.
Prepare and fontify the buffer once, then time insert+delete pairs of
a single character at ANCHOR (a search string; defaults to the middle
of the buffer).  Each iteration performs MUTATIONS mutations (default
20) and the returned times are per-mutation milliseconds."
  (let ((buffer (generate-new-buffer " *md-ts-bench-mutation*"))
        (pairs (max 1 (/ (or mutations 20) 2))))
    (unwind-protect
        (with-current-buffer buffer
          (insert text)
          (goto-char (point-min))
          (md-ts-mode)
          (font-lock-ensure (point-min) (point-max))
          (if anchor
              (progn
                (goto-char (point-min))
                (search-forward anchor)
                (beginning-of-line)
                (forward-char (min 10 (- (line-end-position)
                                         (line-beginning-position)))))
            (goto-char (+ (point-min)
                          (/ (- (point-max) (point-min)) 2)))
            (forward-line 0))
          (mapcar (lambda (ms) (/ ms (* 2.0 pairs)))
                  (md-ts-bench--measure
                   iterations
                   (lambda ()
                     (dotimes (_ pairs)
                       (insert "x")
                       (delete-char -1))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun md-ts-bench--emit-result (case-name op text item-count item-unit counts times)
  "Print one parseable-ish RESULT line for CASE-NAME and TIMES."
  (md-ts-bench--log
   (concat "RESULT commit=%s tracked_dirty=%S untracked=%S case=%s op=%s "
           "items=%d item_unit=%s lines=%d chars=%d link_buttons=%d "
           "bare_link_props=%d static_targets=%d iterations=%d "
           "median_ms=%.3f min_ms=%.3f max_ms=%.3f times_ms=%s")
   (md-ts-bench--git-output "rev-parse" "--short" "HEAD")
   (md-ts-bench--git-dirty-p)
   (md-ts-bench--git-untracked-p)
   case-name op item-count item-unit
   (md-ts-bench--line-count text) (length text)
   (plist-get counts :link-buttons)
   (plist-get counts :bare-link-props)
   (plist-get counts :static-targets)
   (length times)
   (md-ts-bench--median times) (apply #'min times) (apply #'max times)
   (md-ts-bench--format-ms-list times)))

(defun md-ts-bench--required-grammars-ready-p ()
  "Return non-nil when the Markdown grammars required for md-ts-mode are ready."
  (and (treesit-available-p)
       (treesit-ready-p 'markdown t)
       (treesit-ready-p 'markdown-inline t)))

(defun md-ts-bench--emit-environment ()
  "Print benchmark environment metadata."
  (md-ts-bench--log
   "ENV commit=%s tracked_dirty=%S untracked=%S emacs=%s repo=%s iterations=%d smoke=%S system=%s"
   (md-ts-bench--git-output "rev-parse" "--short" "HEAD")
   (md-ts-bench--git-dirty-p)
   (md-ts-bench--git-untracked-p)
   emacs-version
   (abbreviate-file-name md-ts-bench--repo-root)
   md-ts-bench-iterations
   md-ts-bench-smoke
   system-configuration)
  (md-ts-bench--log "TREESIT available=%S extra_load_path=%S"
                    (treesit-available-p) treesit-extra-load-path)
  (dolist (language '(markdown markdown-inline html yaml toml))
    (md-ts-bench--log "GRAMMAR lang=%s ready=%S"
                      language (treesit-ready-p language t))))

(defun md-ts-bench--cases ()
  "Return benchmark cases, using tiny fixtures in smoke mode."
  (if md-ts-bench-smoke
      `(("plain-prose-smoke" mode+font-lock
         ,(md-ts-bench--plain-prose-doc 5) 5 "lines")
        ("bare-links-smoke" mode+font-lock
         ,(md-ts-bench--bare-links-doc 2) 2 "lines")
        ("long-line-one-char-jit-smoke" jit-one-char
         ,(md-ts-bench--long-line-doc 2) 2 "link-groups")
        ("parsed-refs-smoke" mode+font-lock
         ,(md-ts-bench--parsed-references-doc 2) 2 "references")
        ("mixed-chat-prose-smoke" mode+font-lock
         ,(md-ts-bench--mixed-chat-prose-doc 2) 2 "threads")
        ("mixed-chat-prose-mutation-smoke" mutation-one-char
         ,(md-ts-bench--mixed-chat-prose-doc 2) 8 "mutations"
         "A deterministic mix of prose")
        ("fence-body-mutation-smoke" mutation-one-char
         ,(md-ts-bench--mixed-chat-prose-doc 10) 8 "mutations"
         "curl 'https://code.example.invalid/010"))
    `(("plain-prose-800" mode+font-lock
       ,(md-ts-bench--plain-prose-doc 800) 800 "lines")
      ("bare-links-100" mode+font-lock
       ,(md-ts-bench--bare-links-doc 100) 100 "lines")
      ("bare-links-400" mode+font-lock
       ,(md-ts-bench--bare-links-doc 400) 400 "lines")
      ("bare-links-800" mode+font-lock
       ,(md-ts-bench--bare-links-doc 800) 800 "lines")
      ("long-line-one-char-jit" jit-one-char
       ,(md-ts-bench--long-line-doc 300) 300 "link-groups")
      ("parsed-refs-400" mode+font-lock
       ,(md-ts-bench--parsed-references-doc 400) 400 "references")
      ("parsed-refs-800" mode+font-lock
       ,(md-ts-bench--parsed-references-doc 800) 800 "references")
      ("mixed-chat-prose" mode+font-lock
       ,(md-ts-bench--mixed-chat-prose-doc 100) 100 "threads")
      ("mixed-chat-prose-mutation" mutation-one-char
       ,(md-ts-bench--mixed-chat-prose-doc 100) 40 "mutations"
       "A deterministic mix of prose")
      ("fence-body-mutation" mutation-one-char
       ,(md-ts-bench--mixed-chat-prose-doc 100) 40 "mutations"
       "curl 'https://code.example.invalid/050"))))

(defconst md-ts-bench--smoke-min-counts
  '(("plain-prose-smoke" :link-buttons 0 :bare-link-props 0 :static-targets 0)
    ("bare-links-smoke" :link-buttons 6 :bare-link-props 6 :static-targets 6)
    ("long-line-one-char-jit-smoke" :link-buttons 7 :bare-link-props 6 :static-targets 6)
    ("parsed-refs-smoke" :link-buttons 4)
    ("mixed-chat-prose-smoke" :link-buttons 16 :bare-link-props 10 :static-targets 10)
    ("mixed-chat-prose-mutation-smoke" :link-buttons 16 :bare-link-props 10 :static-targets 10)
    ("fence-body-mutation-smoke" :link-buttons 60 :bare-link-props 40 :static-targets 40))
  "Minimum link artifact counts expected for deterministic smoke fixtures.")

(defun md-ts-bench--validate-smoke-counts (case-name counts)
  "Signal an error in smoke mode if CASE-NAME misses expected link work."
  (when md-ts-bench-smoke
    (let ((minimums (cdr (assoc case-name md-ts-bench--smoke-min-counts))))
      (unless minimums
        (error "Smoke case %s has no expected count entry" case-name))
      (while minimums
        (let* ((property (pop minimums))
               (minimum (pop minimums))
               (actual (or (plist-get counts property) 0)))
          (unless (>= actual minimum)
            (error (concat "Smoke case %s expected %s >= %d, got %d "
                           "(counts=%S)")
                   case-name property minimum actual counts)))))))

(defun md-ts-bench-run ()
  "Run advisory document-link fontification benchmarks."
  (md-ts-bench--emit-environment)
  (if (md-ts-bench--required-grammars-ready-p)
      (progn
        ;; Global warmup keeps first-use parser setup outliers from dominating the
        ;; first reported case without adding an extra expensive run per fixture.
        (md-ts-bench--fontify-text
         "# Warmup\n\nText [x](https://example.com) https://example.org user@example.org\n")
        (dolist (case (md-ts-bench--cases))
          (pcase-let ((`(,name ,op ,text ,items ,item-unit . ,op-args) case))
            (md-ts-bench--log "CASE name=%s op=%s items=%d item_unit=%s lines=%d chars=%d"
                              name op items item-unit
                              (md-ts-bench--line-count text) (length text))
            (let* ((counts (md-ts-bench--fontify-text text t))
                   (times (pcase op
                            ('mode+font-lock
                             (md-ts-bench--measure
                              md-ts-bench-iterations
                              (lambda () (md-ts-bench--fontify-text text))))
                            ('jit-one-char
                             (md-ts-bench--measure-jit-one-char
                              md-ts-bench-iterations text))
                            ('mutation-one-char
                             (md-ts-bench--measure-mutation-one-char
                              md-ts-bench-iterations text
                              (car op-args) items)))))
              (md-ts-bench--validate-smoke-counts name counts)
              (md-ts-bench--emit-result name op text items item-unit
                                        counts times))))
        (md-ts-bench--log "DONE commit=%s"
                          (md-ts-bench--git-output "rev-parse" "--short" "HEAD")))
    (let ((message (concat "missing Markdown tree-sitter grammars; "
                           "set MD_TS_TREE_SITTER_DIR or install grammars")))
      (if md-ts-bench-smoke
          (error "Perf smoke failed: %s" message)
        (md-ts-bench--log
         "SKIP reason=missing-markdown-tree-sitter-grammar hint=set-MD_TS_TREE_SITTER_DIR-or-install-grammars")))))

(md-ts-bench-run)

;;; benchmark-document-links.el ends here
