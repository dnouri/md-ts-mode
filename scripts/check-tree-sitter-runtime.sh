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
detector_env_exe=""
emacs_exe=""
resolve_error=""

set_resolve_error() {
  resolve_error=$1
  return 1
}

resolve_shell_bin() {
  local candidate=""
  local resolved=""
  local dir=""
  local base=""
  local abs_dir=""

  candidate=$(command -v sh 2>/dev/null || true)
  case "$candidate" in
    /*)
      resolved=$candidate
      ;;
    */*)
      if resolved=$(realpath "$candidate" 2>/dev/null); then
        :
      else
        dir=${candidate%/*}
        base=${candidate##*/}
        if abs_dir=$(cd "$dir" 2>/dev/null && pwd -P); then
          resolved=$abs_dir/$base
        fi
      fi
      ;;
  esac

  if [ -z "$resolved" ] || [ ! -x "$resolved" ]; then
    resolved=/bin/sh
  fi
  if [ ! -x "$resolved" ]; then
    return 1
  fi
  printf '%s\n' "$resolved"
}

record_env_executable() {
  local env_word=$1
  local resolved=""

  case "$env_word" in
    */*)
      if [ ! -x "$env_word" ]; then
        set_resolve_error "env wrapper is not executable: $env_word"
        return 1
      fi
      resolved=$env_word
      ;;
    *)
      resolved=$(command -v -- "$env_word" 2>/dev/null || true)
      if [ -z "$resolved" ]; then
        set_resolve_error "could not resolve env wrapper: $env_word"
        return 1
      fi
      ;;
  esac

  if [ -z "$detector_env_exe" ]; then
    detector_env_exe=$resolved
  elif [ "$detector_env_exe" != "$resolved" ]; then
    set_resolve_error \
      "multiple env wrappers cannot be safely replayed: $detector_env_exe and $resolved"
    return 1
  fi
}

resolve_bare_executable() {
  local exe=$1
  local resolved=""
  local sh_bin=""

  if [ "${#detector_env[@]}" -gt 0 ]; then
    sh_bin=$(resolve_shell_bin || true)
    if [ -z "$sh_bin" ] || [ -z "$detector_env_exe" ]; then
      return 1
    fi
    resolved=$("$detector_env_exe" "${detector_env[@]}" "$sh_bin" -c \
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

emacs_exe_is_executable() {
  local sh_bin=""

  if [ -z "$emacs_exe" ]; then
    return 1
  fi

  if [ "${#detector_env[@]}" -gt 0 ]; then
    sh_bin=$(resolve_shell_bin || true)
    if [ -z "$sh_bin" ] || [ -z "$detector_env_exe" ]; then
      return 1
    fi
    "$detector_env_exe" "${detector_env[@]}" "$sh_bin" -c \
      'test -x "$1"' sh "$emacs_exe" >/dev/null 2>&1
  else
    [ -x "$emacs_exe" ]
  fi
}

consume_env_option_arg() {
  local option=$1
  local index=$2

  if [ $((index + 1)) -ge "${#words[@]}" ]; then
    set_resolve_error "env option $option requires an argument"
    return 1
  fi

  detector_env+=("$option" "${words[$((index + 1))]}")
  return 0
}

resolve_emacs_executable() {
  local -a words=("${emacs_argv[@]}")
  local i=0
  local word
  local parsing_options
  local saw_env=false

  while [ "$i" -lt "${#words[@]}" ]; do
    word=${words[$i]}
    case "$word" in
      env|*/env)
        record_env_executable "$word" || return 1
        saw_env=true
        i=$((i + 1))
        parsing_options=true
        while [ "$i" -lt "${#words[@]}" ]; do
          word=${words[$i]}
          if [ "$parsing_options" = true ]; then
            case "$word" in
              --)
                parsing_options=false
                i=$((i + 1))
                continue
                ;;
              -i|--ignore-environment|-0|--null)
                detector_env+=("$word")
                i=$((i + 1))
                continue
                ;;
              -u|--unset|--chdir|-C)
                consume_env_option_arg "$word" "$i" || return 1
                i=$((i + 2))
                continue
                ;;
              -u?*)
                detector_env+=("-u" "${word#-u}")
                i=$((i + 1))
                continue
                ;;
              -C?*)
                detector_env+=("-C" "${word#-C}")
                i=$((i + 1))
                continue
                ;;
              --unset=*|--chdir=*)
                detector_env+=("$word")
                i=$((i + 1))
                continue
                ;;
              --*)
                set_resolve_error "unsupported env option in EMACS: $word"
                return 1
                ;;
              -*)
                set_resolve_error "unsupported env option in EMACS: $word"
                return 1
                ;;
            esac
          fi

          case "$word" in
            *=*)
              detector_env+=("$word")
              i=$((i + 1))
              ;;
            *)
              break
              ;;
          esac
        done
        if [ "$i" -ge "${#words[@]}" ]; then
          set_resolve_error "env wrapper did not include an Emacs command"
          return 1
        fi
        continue
        ;;
    esac

    case "$word" in
      */*)
        emacs_exe=$word
        ;;
      *)
        if ! resolve_bare_executable "$word"; then
          if [ "$saw_env" = true ]; then
            set_resolve_error "could not resolve env-wrapped Emacs command: $word"
          fi
          return 1
        fi
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
    "$detector_env_exe" "${detector_env[@]}" "$detector" "$@"
  else
    "$detector" "$@"
  fi
}

detector_error=""
detector_not_applicable_reason=""
detector_skip_reason=""

summarize_detector_text() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

append_detector_skip_reason() {
  local reason=$1
  if [ -z "$detector_skip_reason" ]; then
    detector_skip_reason=$reason
  else
    detector_skip_reason="$detector_skip_reason; $reason"
  fi
}

detector_not_applicable_p() {
  local detector_label=$1
  local text=$2

  case "$detector_label" in
    ldd)
      case "$text" in
        *"not a dynamic executable"*|*"statically linked"*|*"not regular file"*)
          return 0
          ;;
      esac
      ;;
    "otool -L")
      case "$text" in
        *"not an object file"*|*"not a Mach-O"*|*"can't open file"*)
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

run_detector_checked() {
  local detector_label=$1
  local output_var=$2
  local output=""
  local stderr_file=""
  local stderr_text=""
  local combined=""
  local summary=""
  local status=0
  shift 2

  stderr_file=$(mktemp)
  set +e
  output=$(run_detector "$@" 2>"$stderr_file")
  status=$?
  set -e
  stderr_text=$(cat "$stderr_file")
  rm -f "$stderr_file"
  combined=$output
  if [ -n "$stderr_text" ]; then
    if [ -n "$combined" ]; then
      combined="$combined
$stderr_text"
    else
      combined=$stderr_text
    fi
  fi
  summary=$(summarize_detector_text "$combined")

  if [ "$status" -ne 0 ]; then
    if detector_not_applicable_p "$detector_label" "$combined"; then
      detector_not_applicable_reason="$detector_label not applicable (exit status $status${summary:+: $summary})"
      printf -v "$output_var" '%s' ""
      return 2
    fi
    detector_error="$detector_label failed with exit status $status${summary:+: $summary}"
    printf -v "$output_var" '%s' ""
    return 1
  fi

  printf -v "$output_var" '%s' "$output"
}

validate_detector_env_replay() {
  local sh_bin=""

  if [ "${#detector_env[@]}" -eq 0 ]; then
    return 0
  fi

  if [ -z "$detector_env_exe" ]; then
    set_resolve_error "env wrapper replay has no validated env executable"
    return 1
  fi

  sh_bin=$(resolve_shell_bin || true)
  if [ -z "$sh_bin" ]; then
    set_resolve_error "could not resolve shell for env wrapper replay validation"
    return 1
  fi

  if ! "$detector_env_exe" "${detector_env[@]}" "$sh_bin" -c : >/dev/null 2>&1; then
    set_resolve_error "could not replay env wrapper for runtime detector"
    return 1
  fi
}

report_resolve_error() {
  cat >&2 <<EOF
md-ts-mode tests: could not safely resolve Emacs executable
  Emacs command: $emacs_label (major $major)
  Reason: $resolve_error

This preflight refuses to inspect a guessed binary when an EMACS env
wrapper cannot be parsed, resolved, or replayed.  To bypass it explicitly,
set SKIP_RUNTIME_CHECK=1 (or MD_TS_SKIP_RUNTIME_CHECK=1).
EOF
}

report_detector_error() {
  cat >&2 <<EOF
md-ts-mode tests: runtime detector failed
  Emacs command: $emacs_label (major $major)
  Emacs executable: ${emacs_exe:-unknown}
  Detector: $detector_name
  Reason: $detector_error

This preflight refuses to skip runtime detection after a detector replay or
execution failure.  To bypass it explicitly, set SKIP_RUNTIME_CHECK=1
(or MD_TS_SKIP_RUNTIME_CHECK=1).
EOF
}

if ! resolve_emacs_executable; then
  if [ -n "$resolve_error" ]; then
    report_resolve_error
    exit 2
  fi
fi

if ! validate_detector_env_replay; then
  report_resolve_error
  exit 2
fi

lib_path=""
detector_name=""
emacs_exe_executable=false

if emacs_exe_is_executable; then
  emacs_exe_executable=true
fi

if [ "$emacs_exe_executable" = true ]; then
  if ldd_bin=$(command -v ldd 2>/dev/null); then
    detector_name="ldd"
    detector_output=""
    if run_detector_checked "$detector_name" detector_output \
        "$ldd_bin" "$emacs_exe"; then
      lib_path=$(
        printf '%s\n' "$detector_output" \
          | awk '/libtree-sitter/ {
              for (i = 1; i < NF; i++) {
                if ($i == "=>" && $(i + 1) != "not") { print $(i + 1); exit }
              }
              for (i = 1; i <= NF; i++) {
                if ($i ~ /libtree-sitter/ && $i != "=>") { print $i; exit }
              }
            }'
      )
    else
      detector_status=$?
      if [ "$detector_status" -eq 2 ]; then
        append_detector_skip_reason "$detector_not_applicable_reason"
      else
        report_detector_error
        exit 2
      fi
    fi
  fi

  if [ -z "$lib_path" ] && otool_bin=$(command -v otool 2>/dev/null); then
    detector_name="otool -L"
    detector_output=""
    if run_detector_checked "$detector_name" detector_output \
        "$otool_bin" -L "$emacs_exe"; then
      lib_path=$(
        printf '%s\n' "$detector_output" \
          | awk '/libtree-sitter/ { print $1; exit }'
      )
    else
      detector_status=$?
      if [ "$detector_status" -eq 2 ]; then
        append_detector_skip_reason "$detector_not_applicable_reason"
      else
        report_detector_error
        exit 2
      fi
    fi
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

if [ "$emacs_exe_executable" != true ]; then
  skip_detection "could not resolve a direct Emacs executable from EMACS"
  exit 0
fi

if [ -z "$lib_path" ]; then
  if [ -n "$detector_skip_reason" ]; then
    skip_detection "no usable ldd/otool -L libtree-sitter dependency was detected ($detector_skip_reason)"
  else
    skip_detection "no ldd/otool -L libtree-sitter dependency was detected"
  fi
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
