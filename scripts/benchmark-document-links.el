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
  (when-let ((value (getenv name)))
    (split-string value path-separator t)))

(defun md-ts-bench--add-existing-tree-sitter-paths ()
  "Add common tree-sitter grammar directories when they exist."
  (dolist (dir (append (md-ts-bench--env-paths "MD_TS_TREE_SITTER_DIR")
                       (md-ts-bench--env-paths "TREE_SITTER_GRAMMAR_DIR")
                       (list (expand-file-name "tree-sitter"
                                               user-emacs-directory))))
    (when (and (stringp dir)
               (not (string-empty-p dir))
               (file-directory-p dir))
      (add-to-list 'treesit-extra-load-path dir))))

(md-ts-bench--add-existing-tree-sitter-paths)
(add-to-list 'load-path md-ts-bench--repo-root)
(load (expand-file-name "md-ts-mode.el" md-ts-bench--repo-root) nil 'nomessage)

(defvar md-ts-bench-iterations
  (let ((value (getenv "PERF_ITERATIONS")))
    (if (and value (string-match-p "\\`[0-9]+\\'" value))
        (max 1 (string-to-number value))
      3))
  "Number of timed iterations per benchmark case.")

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

(defun md-ts-bench--fontify-text (text)
  "Enable `md-ts-mode' and fontify TEXT in a temporary buffer."
  (let ((buffer (generate-new-buffer " *md-ts-bench*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert text)
          (goto-char (point-min))
          (md-ts-mode)
          (font-lock-ensure (point-min) (point-max)))
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

(defun md-ts-bench--emit-result (case-name op text item-count item-unit times)
  "Print one parseable-ish RESULT line for CASE-NAME and TIMES."
  (md-ts-bench--log
   (concat "RESULT commit=%s case=%s op=%s items=%d item_unit=%s lines=%d chars=%d "
           "iterations=%d median_ms=%.3f min_ms=%.3f max_ms=%.3f times_ms=%s")
   (md-ts-bench--git-output "rev-parse" "--short" "HEAD")
   case-name op item-count item-unit
   (md-ts-bench--line-count text) (length text) (length times)
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
   "ENV commit=%s dirty=%S emacs=%s repo=%s iterations=%d system=%s"
   (md-ts-bench--git-output "rev-parse" "--short" "HEAD")
   (md-ts-bench--git-dirty-p)
   emacs-version
   (abbreviate-file-name md-ts-bench--repo-root)
   md-ts-bench-iterations
   system-configuration)
  (md-ts-bench--log "TREESIT available=%S extra_load_path=%S"
                    (treesit-available-p) treesit-extra-load-path)
  (dolist (language '(markdown markdown-inline html yaml toml))
    (md-ts-bench--log "GRAMMAR lang=%s ready=%S"
                      language (treesit-ready-p language t))))

(defun md-ts-bench-run ()
  "Run advisory document-link fontification benchmarks."
  (md-ts-bench--emit-environment)
  (unless (md-ts-bench--required-grammars-ready-p)
    (md-ts-bench--log
     "SKIP reason=missing-markdown-tree-sitter-grammar hint=set-MD_TS_TREE_SITTER_DIR-or-install-grammars")
    (cl-return-from md-ts-bench-run nil))
  ;; Global warmup keeps first-use parser setup outliers from dominating the
  ;; first reported case without adding an extra expensive run per fixture.
  (md-ts-bench--fontify-text
   "# Warmup\n\nText [x](https://example.com) https://example.org user@example.org\n")
  (let ((cases `(("bare-links-100" mode+font-lock
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
                  ,(md-ts-bench--mixed-chat-prose-doc 100) 100 "threads"))))
    (dolist (case cases)
      (pcase-let ((`(,name ,op ,text ,items ,item-unit) case))
        (md-ts-bench--log "CASE name=%s op=%s items=%d item_unit=%s lines=%d chars=%d"
                          name op items item-unit
                          (md-ts-bench--line-count text) (length text))
        (let ((times (pcase op
                       ('mode+font-lock
                        (md-ts-bench--measure
                         md-ts-bench-iterations
                         (lambda () (md-ts-bench--fontify-text text))))
                       ('jit-one-char
                        (md-ts-bench--measure-jit-one-char
                         md-ts-bench-iterations text)))))
          (md-ts-bench--emit-result name op text items item-unit times)))))
  (md-ts-bench--log "DONE commit=%s" (md-ts-bench--git-output "rev-parse" "--short" "HEAD")))

(md-ts-bench-run)

;;; benchmark-document-links.el ends here
