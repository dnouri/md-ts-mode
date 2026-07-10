#!/usr/bin/env bash
set -euo pipefail

emacs_arg=${1:-${EMACS:-emacs}}

if [ -x "$emacs_arg" ]; then
  emacs_bin=$emacs_arg
else
  emacs_bin=$(command -v "$emacs_arg" 2>/dev/null || true)
fi

if [ -z "${emacs_bin:-}" ] || [ ! -x "$emacs_bin" ]; then
  echo "md-ts-mode tests: Emacs binary not found: $emacs_arg" >&2
  exit 2
fi

major=$(
  "$emacs_bin" --batch -Q \
    --eval '(princ emacs-major-version)' 2>/dev/null
)

if ! "$emacs_bin" --batch -Q \
    --eval '(unless (and (fboundp (quote treesit-available-p)) (treesit-available-p)) (kill-emacs 2))' \
    >/dev/null 2>&1; then
  cat >&2 <<EOF
md-ts-mode tests: unsupported Emacs runtime
  Emacs: $emacs_bin (major $major)
  Problem: Emacs was not built with usable tree-sitter support.
EOF
  exit 2
fi

lib_path=""
if command -v ldd >/dev/null 2>&1; then
  lib_path=$(
    ldd "$emacs_bin" 2>/dev/null \
      | awk '/libtree-sitter/ {
          for (i = 1; i < NF; i++) if ($i == "=>") { print $(i + 1); exit }
          for (i = 1; i <= NF; i++) if ($i ~ /^\// && $i ~ /libtree-sitter/) { print $i; exit }
          print $1; exit
        }'
  )
fi

if [ -z "$lib_path" ]; then
  cat >&2 <<EOF
md-ts-mode tests: could not determine the effective libtree-sitter runtime
  Emacs: $emacs_bin (major $major)
  Hint: on Linux, ldd should show the loaded libtree-sitter path.
EOF
  exit 2
fi

if command -v readlink >/dev/null 2>&1 && [ -e "$lib_path" ]; then
  resolved_lib_path=$(readlink -f "$lib_path" 2>/dev/null || true)
  if [ -n "$resolved_lib_path" ]; then
    lib_path=$resolved_lib_path
  fi
fi

supported=false
if [ "$major" -le 30 ]; then
  case "$lib_path" in
    *0.25*) supported=true ;;
  esac
else
  case "$lib_path" in
    *0.25*|*0.26*) supported=true ;;
  esac
fi

if [ "$supported" != true ]; then
  cat >&2 <<EOF
md-ts-mode tests: unsupported tree-sitter runtime
  Emacs: $emacs_bin (major $major)
  Effective libtree-sitter: $lib_path

Supported test runtimes:
  - Emacs 29/30 with libtree-sitter 0.25.x
  - Emacs 31+ with libtree-sitter 0.25.x or 0.26.x

Older runtimes such as 0.22 mis-handle parser ranges and produce
misleading grammar-dependent failures.  For a local supported run, use for
example:

  lib_dir=\$(./scripts/setup-tree-sitter-runtime.sh 0.25.10 "$emacs_bin")
  LD_LIBRARY_PATH="\$lib_dir\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" \\
    EMACS="$emacs_bin" make test
EOF
  exit 2
fi

echo "tree-sitter runtime OK for tests: Emacs $major using $lib_path"
