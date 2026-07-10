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

tree_sitter_display=()
tree_sitter_candidate_names=()
tree_sitter_candidate_sources=()
tree_sitter_direct_dependency_names=()
tree_sitter_direct_library_paths=()
direct_dependency_scan_reliable=false
fallback_ldd_tree_sitter_entries=0
detector_name=""
emacs_exe_executable=false

append_tree_sitter_display() {
  local entry=$1
  local existing=""

  for existing in "${tree_sitter_display[@]}"; do
    if [ "$existing" = "$entry" ]; then
      return 0
    fi
  done
  tree_sitter_display+=("$entry")
}

append_tree_sitter_candidate() {
  local source=$1
  local name=$2
  local existing_source=""
  local existing_name=""
  local i=0

  name=${name##*/}
  name=${name%:}
  name=${name%,}
  if [ -z "$name" ]; then
    return 0
  fi
  case "$name" in
    *libtree-sitter*) ;;
    *) return 0 ;;
  esac

  while [ "$i" -lt "${#tree_sitter_candidate_names[@]}" ]; do
    existing_name=${tree_sitter_candidate_names[$i]}
    existing_source=${tree_sitter_candidate_sources[$i]}
    if [ "$existing_name" = "$name" ] && [ "$existing_source" = "$source" ]; then
      return 0
    fi
    i=$((i + 1))
  done

  tree_sitter_candidate_names+=("$name")
  tree_sitter_candidate_sources+=("$source")
}

append_tree_sitter_direct_dependency_name() {
  local name=$1
  local existing=""

  name=${name##*/}
  name=${name%:}
  name=${name%,}
  if [ -z "$name" ]; then
    return 0
  fi
  case "$name" in
    *libtree-sitter*) ;;
    *) return 0 ;;
  esac

  for existing in "${tree_sitter_direct_dependency_names[@]}"; do
    if [ "$existing" = "$name" ]; then
      return 0
    fi
  done
  tree_sitter_direct_dependency_names+=("$name")
}

tree_sitter_direct_dependency_p() {
  local name=$1
  local direct=""

  if [ "$direct_dependency_scan_reliable" != true ]; then
    return 1
  fi

  name=${name##*/}
  name=${name%:}
  name=${name%,}
  for direct in "${tree_sitter_direct_dependency_names[@]}"; do
    if [ "$direct" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

append_tree_sitter_direct_library_path() {
  local path=$1
  local existing=""

  if [ -z "$path" ]; then
    return 0
  fi
  for existing in "${tree_sitter_direct_library_paths[@]}"; do
    if [ "$existing" = "$path" ]; then
      return 0
    fi
  done
  tree_sitter_direct_library_paths+=("$path")
}

resolve_runtime_path() {
  local path=$1
  local resolved=""

  if [ -z "$path" ] || [ ! -e "$path" ]; then
    return 1
  fi

  if command -v realpath >/dev/null 2>&1; then
    resolved=$(realpath "$path" 2>/dev/null || true)
  fi
  if [ -z "$resolved" ] && command -v readlink >/dev/null 2>&1; then
    resolved=$(readlink -f "$path" 2>/dev/null || true)
  fi
  if [ -z "$resolved" ]; then
    resolved=$path
  fi
  printf '%s\n' "$resolved"
}

record_tree_sitter_token() {
  local source=$1
  local token=$2
  local support_candidate=${3:-true}
  local direct_library=${4:-false}
  local resolved=""

  token=${token%:}
  token=${token%,}
  if [ -z "$token" ] || [ "$token" = "not" ]; then
    return 0
  fi
  case "$token" in
    *libtree-sitter*) ;;
    *) return 0 ;;
  esac

  append_tree_sitter_display "$source: $token"
  if [ "$support_candidate" = true ]; then
    append_tree_sitter_candidate "$source" "$token"
  fi

  case "$token" in
    /*|./*|../*)
      if [ -e "$token" ]; then
        resolved=$(resolve_runtime_path "$token" || true)
        if [ -n "$resolved" ]; then
          if [ "$direct_library" = true ]; then
            append_tree_sitter_direct_library_path "$resolved"
          fi
          if [ "$resolved" != "$token" ]; then
            append_tree_sitter_display "$source resolved: $resolved"
            if [ "$support_candidate" = true ]; then
              append_tree_sitter_candidate "$source resolved" "$resolved"
            fi
          fi
        fi
      fi
      ;;
  esac
}

parse_ldd_tree_sitter_output() {
  local output=$1
  local line=""
  local found_arrow=false
  local direct_entry=false
  local fallback_entry_seen=false
  local i=0
  local -a fields=()

  while IFS= read -r line; do
    case "$line" in
      *libtree-sitter*) ;;
      *) continue ;;
    esac

    read -r -a fields <<< "$line"
    if [ "${#fields[@]}" -eq 0 ]; then
      continue
    fi

    direct_entry=false
    if [ "$direct_dependency_scan_reliable" = true ]; then
      if tree_sitter_direct_dependency_p "${fields[0]}"; then
        direct_entry=true
      fi
    else
      fallback_ldd_tree_sitter_entries=$((fallback_ldd_tree_sitter_entries + 1))
      if [ "$fallback_entry_seen" != true ]; then
        direct_entry=true
        fallback_entry_seen=true
      fi
    fi

    found_arrow=false
    i=0
    while [ "$i" -lt "${#fields[@]}" ]; do
      if [ "${fields[$i]}" = "=>" ]; then
        record_tree_sitter_token "ldd name" "${fields[0]}" "$direct_entry" false
        if [ $((i + 1)) -lt "${#fields[@]}" ]; then
          record_tree_sitter_token "ldd path" "${fields[$((i + 1))]}" \
            "$direct_entry" "$direct_entry"
        fi
        found_arrow=true
        break
      fi
      i=$((i + 1))
    done

    if [ "$found_arrow" != true ]; then
      record_tree_sitter_token "ldd entry" "${fields[0]}" \
        "$direct_entry" "$direct_entry"
    fi
  done <<< "$output"
}

parse_otool_tree_sitter_output() {
  local output=$1
  local source="${2:-otool -L entry}"
  local support_candidate=${3:-true}
  local direct_library=${4:-false}
  local line=""
  local -a fields=()

  while IFS= read -r line; do
    case "$line" in
      *libtree-sitter*) ;;
      *) continue ;;
    esac

    read -r -a fields <<< "$line"
    if [ "${#fields[@]}" -gt 0 ]; then
      record_tree_sitter_token "$source" "${fields[0]}" \
        "$support_candidate" "$direct_library"
    fi
  done <<< "$output"
}

record_readelf_metadata_names() {
  local output=$1
  local base=$2
  local line=""
  local name=""
  local source=""

  while IFS= read -r line; do
    case "$line" in
      *"Library soname:"*"["*"]"*) source="ELF SONAME for $base" ;;
      *"Shared library:"*"["*"]"*) source="ELF NEEDED for $base" ;;
      *) continue ;;
    esac

    name=${line#*[}
    name=${name%%]*}
    record_tree_sitter_token "$source" "$name"
  done <<< "$output"
}

record_readelf_direct_dependency_names() {
  local output=$1
  local line=""
  local name=""

  while IFS= read -r line; do
    case "$line" in
      *"Shared library:"*"["*"]"*) ;;
      *) continue ;;
    esac

    name=${line#*[}
    name=${name%%]*}
    append_tree_sitter_direct_dependency_name "$name"
  done <<< "$output"
}

load_direct_tree_sitter_dependencies() {
  local readelf_bin=""
  local output=""
  local before_count=0

  if readelf_bin=$(command -v readelf 2>/dev/null); then
    before_count=${#tree_sitter_direct_dependency_names[@]}
    output=$(run_detector "$readelf_bin" -d "$emacs_exe" 2>/dev/null || true)
    record_readelf_direct_dependency_names "$output"
    if [ "${#tree_sitter_direct_dependency_names[@]}" -gt "$before_count" ]; then
      direct_dependency_scan_reliable=true
    fi
  fi
}

inspect_tree_sitter_library_metadata() {
  local i=0
  local path=""
  local readelf_bin=""
  local otool_bin=""
  local output=""
  local base=""

  while [ "$i" -lt "${#tree_sitter_direct_library_paths[@]}" ]; do
    path=${tree_sitter_direct_library_paths[$i]}
    base=${path##*/}

    if readelf_bin=$(command -v readelf 2>/dev/null); then
      output=$(run_detector "$readelf_bin" -d "$path" 2>/dev/null || true)
      if [ -n "$output" ]; then
        record_readelf_metadata_names "$output" "$base"
      fi
    fi

    if otool_bin=$(command -v otool 2>/dev/null); then
      output=$(run_detector "$otool_bin" -D "$path" 2>/dev/null || true)
      if [ -n "$output" ]; then
        parse_otool_tree_sitter_output "$output" "Mach-O install name for $base"
      fi

      output=$(run_detector "$otool_bin" -L "$path" 2>/dev/null || true)
      if [ -n "$output" ]; then
        parse_otool_tree_sitter_output "$output" "Mach-O dependency for $base"
      fi
    fi

    i=$((i + 1))
  done
}

tree_sitter_chain_summary() {
  local entry=""
  local first=true

  for entry in "${tree_sitter_display[@]}"; do
    if [ "$first" = true ]; then
      printf '%s' "$entry"
      first=false
    else
      printf '; %s' "$entry"
    fi
  done
}

extract_tree_sitter_minor() {
  local text=$1

  if [[ "$text" =~ (^|[^0-9])0\.([0-9]+)($|[^0-9]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

tree_sitter_minor_supported() {
  local minor=$1

  if [ "$major" -le 30 ]; then
    [ "$minor" = 25 ]
  else
    [ "$minor" = 25 ] || [ "$minor" = 26 ]
  fi
}

supported=false
version_visible=false
supported_detail=""
visible_version_summary=""

evaluate_tree_sitter_runtime() {
  local i=0
  local name=""
  local source=""
  local minor=""
  local detail=""

  while [ "$i" -lt "${#tree_sitter_candidate_names[@]}" ]; do
    name=${tree_sitter_candidate_names[$i]}
    source=${tree_sitter_candidate_sources[$i]}

    if minor=$(extract_tree_sitter_minor "$name"); then
      version_visible=true
      detail="$source: $name"
      if [ -z "$visible_version_summary" ]; then
        visible_version_summary=$detail
      else
        visible_version_summary="$visible_version_summary; $detail"
      fi

      if tree_sitter_minor_supported "$minor"; then
        supported=true
        supported_detail=$detail
        return 0
      fi
    fi

    i=$((i + 1))
  done
}

if emacs_exe_is_executable; then
  emacs_exe_executable=true
fi

if [ "$emacs_exe_executable" = true ]; then
  load_direct_tree_sitter_dependencies

  if ldd_bin=$(command -v ldd 2>/dev/null); then
    detector_name="ldd"
    detector_output=""
    if run_detector_checked "$detector_name" detector_output \
        "$ldd_bin" "$emacs_exe"; then
      parse_ldd_tree_sitter_output "$detector_output"
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

  if [ "${#tree_sitter_display[@]}" -eq 0 ] && otool_bin=$(command -v otool 2>/dev/null); then
    detector_name="otool -L"
    detector_output=""
    if run_detector_checked "$detector_name" detector_output \
        "$otool_bin" -L "$emacs_exe"; then
      parse_otool_tree_sitter_output "$detector_output" "otool -L entry" true true
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

if [ "$direct_dependency_scan_reliable" != true ] && \
    [ "$fallback_ldd_tree_sitter_entries" -gt 1 ]; then
  tree_sitter_candidate_names=()
  tree_sitter_candidate_sources=()
  tree_sitter_direct_library_paths=()
fi

inspect_tree_sitter_library_metadata
evaluate_tree_sitter_runtime

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

if [ "${#tree_sitter_display[@]}" -eq 0 ]; then
  if [ -n "$detector_skip_reason" ]; then
    skip_detection "no usable ldd/otool -L libtree-sitter dependency was detected ($detector_skip_reason)"
  else
    skip_detection "no ldd/otool -L libtree-sitter dependency was detected"
  fi
  exit 0
fi

chain_summary=$(tree_sitter_chain_summary)

if [ "$version_visible" != true ]; then
  skip_detection "$detector_name found libtree-sitter, but no runtime version was visible in library basenames/SONAME/NEEDED entries: $chain_summary"
  exit 0
fi

if [ "$supported" != true ]; then
  cat >&2 <<EOF
md-ts-mode tests: unsupported tree-sitter runtime
  Emacs command: $emacs_label (major $major)
  Emacs executable: $emacs_exe
  Effective libtree-sitter chain ($detector_name): $chain_summary
  Visible runtime versions: $visible_version_summary

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

echo "tree-sitter runtime OK for tests: Emacs $major using $supported_detail ($detector_name)"
