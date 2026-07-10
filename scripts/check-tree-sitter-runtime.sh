#!/usr/bin/env bash
set -euo pipefail

skip_runtime_check=false
if [ -n "${SKIP_RUNTIME_CHECK:-}" ] && [ "${SKIP_RUNTIME_CHECK:-}" != "0" ]; then
  skip_runtime_check=true
fi
if [ -n "${MD_TS_SKIP_RUNTIME_CHECK:-}" ] && [ "${MD_TS_SKIP_RUNTIME_CHECK:-}" != "0" ]; then
  skip_runtime_check=true
fi

if [ "$skip_runtime_check" = true ]; then
  echo "md-ts-mode tests: tree-sitter runtime check skipped by SKIP_RUNTIME_CHECK/MD_TS_SKIP_RUNTIME_CHECK" >&2
  exit 0
fi

emacs_command=${EMACS:-emacs}
emacs_argv=()

if [ "$#" -gt 1 ]; then
  emacs_argv=("$@")
  printf -v emacs_command '%q ' "$@"
elif [ "$#" -eq 1 ]; then
  emacs_command=$1
  read -r -a emacs_argv <<< "$emacs_command"
else
  read -r -a emacs_argv <<< "$emacs_command"
fi

if [ "${#emacs_argv[@]}" -eq 0 ]; then
  echo "md-ts-mode tests: Emacs command is empty" >&2
  exit 2
fi

emacs_label=$(printf '%q ' "${emacs_argv[@]}")
emacs_label=${emacs_label% }

run_emacs() {
  "${emacs_argv[@]}" "$@"
}

major_stderr=$(mktemp)
if ! major=$(run_emacs --batch -Q --eval '(princ emacs-major-version)' 2>"$major_stderr"); then
  cat >&2 <<EOF
md-ts-mode tests: Emacs command failed
  Emacs command: $emacs_label
EOF
  if [ -s "$major_stderr" ]; then
    sed 's/^/  /' "$major_stderr" >&2
  fi
  rm -f "$major_stderr"
  exit 2
fi
rm -f "$major_stderr"

if ! [[ "$major" =~ ^[0-9]+$ ]]; then
  cat >&2 <<EOF
md-ts-mode tests: could not determine Emacs major version
  Emacs command: $emacs_label
  Output: $major
EOF
  exit 2
fi

if ! run_emacs --batch -Q \
    --eval '(unless (and (fboundp (quote treesit-available-p)) (treesit-available-p)) (kill-emacs 2))' \
    >/dev/null 2>&1; then
  cat >&2 <<EOF
md-ts-mode tests: unsupported Emacs runtime
  Emacs command: $emacs_label (major $major)
  Problem: Emacs was not built with usable tree-sitter support.

To bypass this preflight knowingly, set SKIP_RUNTIME_CHECK=1
(or MD_TS_SKIP_RUNTIME_CHECK=1).
EOF
  exit 2
fi

detector_env=()
emacs_exe=""

resolve_bare_executable() {
  local exe=$1
  local resolved=""
  local sh_bin=""

  if [ "${#detector_env[@]}" -gt 0 ]; then
    sh_bin=$(command -v sh 2>/dev/null || true)
    if [ -z "$sh_bin" ]; then
      return 1
    fi
    resolved=$(env "${detector_env[@]}" "$sh_bin" -c \
      'command -v -- "$1"' sh "$exe" 2>/dev/null || true)
  else
    resolved=$(command -v -- "$exe" 2>/dev/null || true)
  fi

  if [ -n "$resolved" ]; then
    emacs_exe=$resolved
    return 0
  fi

  return 1
}

resolve_emacs_executable() {
  local -a words=("${emacs_argv[@]}")
  local i=0
  local word

  while [ "$i" -lt "${#words[@]}" ]; do
    word=${words[$i]}
    case "$word" in
      env|*/env)
        i=$((i + 1))
        while [ "$i" -lt "${#words[@]}" ]; do
          word=${words[$i]}
          case "$word" in
            -i|--ignore-environment|-0|--null)
              detector_env+=("$word")
              i=$((i + 1))
              ;;
            -u|--unset)
              if [ $((i + 1)) -lt "${#words[@]}" ]; then
                detector_env+=("$word" "${words[$((i + 1))]}")
                i=$((i + 2))
              else
                return 1
              fi
              ;;
            --unset=*)
              detector_env+=("$word")
              i=$((i + 1))
              ;;
            --)
              i=$((i + 1))
              break
              ;;
            --*)
              return 1
              ;;
            -*)
              return 1
              ;;
            *=*)
              detector_env+=("$word")
              i=$((i + 1))
              ;;
            *)
              break
              ;;
          esac
        done
        continue
        ;;
    esac

    case "$word" in
      */*)
        emacs_exe=$word
        ;;
      *)
        resolve_bare_executable "$word" || return 1
        ;;
    esac
    return 0
  done

  return 1
}

run_detector() {
  local detector=$1
  shift
  if [ "${#detector_env[@]}" -gt 0 ]; then
    env "${detector_env[@]}" "$detector" "$@"
  else
    "$detector" "$@"
  fi
}

resolve_emacs_executable || true

lib_path=""
detector_name=""

if [ -n "$emacs_exe" ] && [ -x "$emacs_exe" ]; then
  if ldd_bin=$(command -v ldd 2>/dev/null); then
    detector_name="ldd"
    lib_path=$(
      { run_detector "$ldd_bin" "$emacs_exe" 2>/dev/null || true; } \
        | awk '/libtree-sitter/ {
            for (i = 1; i < NF; i++) {
              if ($i == "=>" && $(i + 1) != "not") { print $(i + 1); exit }
            }
            for (i = 1; i <= NF; i++) {
              if ($i ~ /libtree-sitter/ && $i != "=>") { print $i; exit }
            }
          }'
    )
  fi

  if [ -z "$lib_path" ] && otool_bin=$(command -v otool 2>/dev/null); then
    detector_name="otool -L"
    lib_path=$(
      { run_detector "$otool_bin" -L "$emacs_exe" 2>/dev/null || true; } \
        | awk '/libtree-sitter/ { print $1; exit }'
    )
  fi
fi

version_text=$lib_path

if [ -n "$lib_path" ] && command -v realpath >/dev/null 2>&1 && [ -e "$lib_path" ]; then
  resolved_lib_path=$(realpath "$lib_path" 2>/dev/null || true)
  if [ -n "$resolved_lib_path" ]; then
    lib_path=$resolved_lib_path
  fi
elif [ -n "$lib_path" ] && command -v readlink >/dev/null 2>&1 && [ -e "$lib_path" ]; then
  resolved_lib_path=$(readlink -f "$lib_path" 2>/dev/null || true)
  if [ -n "$resolved_lib_path" ]; then
    lib_path=$resolved_lib_path
  fi
fi

if [ -n "$lib_path" ] && [ "$version_text" != "$lib_path" ]; then
  version_text="$version_text $lib_path"
fi

skip_detection() {
  local reason=$1
  cat >&2 <<EOF
md-ts-mode tests: tree-sitter runtime check skipped
  Emacs command: $emacs_label (major $major)
  Emacs executable: ${emacs_exe:-unknown}
  Reason: $reason

This preflight only fails when it can reliably identify an unsupported
libtree-sitter runtime.  To bypass it explicitly, set SKIP_RUNTIME_CHECK=1
(or MD_TS_SKIP_RUNTIME_CHECK=1).
EOF
}

if [ -z "$emacs_exe" ] || [ ! -x "$emacs_exe" ]; then
  skip_detection "could not resolve a direct Emacs executable from EMACS"
  exit 0
fi

if [ -z "$lib_path" ]; then
  skip_detection "no ldd/otool -L libtree-sitter dependency was detected"
  exit 0
fi

if ! [[ "$version_text" =~ 0\.[0-9]+ ]]; then
  skip_detection "$detector_name found libtree-sitter, but no runtime version was visible: $lib_path"
  exit 0
fi

supported=false
if [ "$major" -le 30 ]; then
  case "$version_text" in
    *0.25*) supported=true ;;
  esac
else
  case "$version_text" in
    *0.25*|*0.26*) supported=true ;;
  esac
fi

if [ "$supported" != true ]; then
  cat >&2 <<EOF
md-ts-mode tests: unsupported tree-sitter runtime
  Emacs command: $emacs_label (major $major)
  Emacs executable: $emacs_exe
  Effective libtree-sitter ($detector_name): $lib_path

Supported test runtimes:
  - Emacs 29/30 with libtree-sitter 0.25.x
  - Emacs 31+ with libtree-sitter 0.25.x or 0.26.x

Older runtimes such as 0.22 mis-handle parser ranges and produce
misleading grammar-dependent failures.  For a local supported run, use for
example:

  lib_dir=\$(./scripts/setup-tree-sitter-runtime.sh 0.25.10 "$emacs_exe")
  LD_LIBRARY_PATH="\$lib_dir\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" \\
    EMACS="$emacs_exe" make test

To bypass this preflight knowingly, set SKIP_RUNTIME_CHECK=1
(or MD_TS_SKIP_RUNTIME_CHECK=1).
EOF
  exit 2
fi

echo "tree-sitter runtime OK for tests: Emacs $major using $lib_path ($detector_name)"
