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
emacs_bin_override=${EMACS_BIN:-}
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

resolve_emacs_bin_override() {
  local candidate=$emacs_bin_override

  if [ -z "$candidate" ]; then
    return 1
  fi

  case "$candidate" in
    */*)
      emacs_exe=$candidate
      ;;
    *[[:space:]]*)
      set_resolve_error \
        "EMACS_BIN must be a single executable path or name, not a command: $candidate"
      return 1
      ;;
    *)
      if ! resolve_bare_executable "$candidate"; then
        set_resolve_error "could not resolve EMACS_BIN executable: $candidate"
        return 1
      fi
      ;;
  esac
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

    if [ -n "$emacs_bin_override" ]; then
      resolve_emacs_bin_override || return 1
      return 0
    fi

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

resolve_path_for_compare() {
  local path=$1
  local resolved=""

  if [ -n "$path" ] && [ -e "$path" ]; then
    if command -v realpath >/dev/null 2>&1; then
      resolved=$(realpath "$path" 2>/dev/null || true)
    fi
    if [ -z "$resolved" ] && command -v readlink >/dev/null 2>&1; then
      resolved=$(readlink -f "$path" 2>/dev/null || true)
    fi
  fi
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
  else
    printf '%s\n' "$path"
  fi
}

validate_inspected_emacs_executable() {
  local stderr_file=""
  local inspected_major=""
  local invocation_exe=""
  local inspected_compare=""
  local invocation_compare=""
  local status=0
  local stderr_text=""
  local summary=""

  if [ -z "$emacs_exe" ]; then
    return 0
  fi

  if ! emacs_exe_is_executable; then
    set_resolve_error "resolved inspected executable is not executable: $emacs_exe"
    return 1
  fi

  stderr_file=$(mktemp)
  set +e
  inspected_major=$(run_detector "$emacs_exe" --batch -Q \
    --eval '(princ emacs-major-version)' 2>"$stderr_file")
  status=$?
  set -e
  stderr_text=$(cat "$stderr_file")
  rm -f "$stderr_file"
  summary=$(summarize_detector_text "$stderr_text")

  if [ "$status" -ne 0 ] || ! [[ "$inspected_major" =~ ^[0-9]+$ ]]; then
    set_resolve_error \
      "inspected executable is not a runnable Emacs binary: $emacs_exe${summary:+ ($summary)}"
    return 1
  fi

  if [ "$inspected_major" != "$major" ]; then
    set_resolve_error \
      "inspected executable major version ($inspected_major) does not match EMACS command major version ($major): $emacs_exe"
    return 1
  fi

  invocation_exe=$(run_emacs --batch -Q --eval \
    '(when (and invocation-name invocation-directory) (princ (expand-file-name invocation-name invocation-directory)))' \
    2>/dev/null || true)
  if [ -n "$invocation_exe" ]; then
    inspected_compare=$(resolve_path_for_compare "$emacs_exe")
    invocation_compare=$(resolve_path_for_compare "$invocation_exe")
    if [ "$inspected_compare" != "$invocation_compare" ]; then
      set_resolve_error \
        "EMACS runs $invocation_exe, but the detector would inspect $emacs_exe; set EMACS_BIN to the Emacs executable when using wrappers"
      return 1
    fi
  fi
}

report_resolve_error() {
  cat >&2 <<EOF
md-ts-mode tests: could not safely resolve Emacs executable
  Emacs command: $emacs_label (major $major)
  Reason: $resolve_error

This preflight refuses to inspect a guessed binary when EMACS cannot be
resolved to a direct Emacs executable.  Supported command forms are a direct
Emacs executable, optionally behind env(1) variable assignments.  For wrapper
commands such as timeout, set EMACS_BIN to the Emacs executable inspected by
this detector, or bypass explicitly with SKIP_RUNTIME_CHECK=1 (or
MD_TS_SKIP_RUNTIME_CHECK=1).
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

if ! validate_inspected_emacs_executable; then
  report_resolve_error
  exit 2
fi

tree_sitter_display=()
tree_sitter_candidate_names=()
tree_sitter_candidate_sources=()
tree_sitter_effective_candidate_names=()
tree_sitter_effective_candidate_sources=()
tree_sitter_direct_dependency_names=()
tree_sitter_direct_library_paths=()
tree_sitter_ldd_map_names=()
tree_sitter_ldd_map_paths=()
tree_sitter_library_inspection_stack=()
readelf_metadata_needed_names=()
readelf_metadata_soname=""
tree_sitter_unresolved_needed=false
tree_sitter_unresolved_needed_detail=""
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

append_tree_sitter_effective_candidate() {
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

  while [ "$i" -lt "${#tree_sitter_effective_candidate_names[@]}" ]; do
    existing_name=${tree_sitter_effective_candidate_names[$i]}
    existing_source=${tree_sitter_effective_candidate_sources[$i]}
    if [ "$existing_name" = "$name" ] && [ "$existing_source" = "$source" ]; then
      return 0
    fi
    i=$((i + 1))
  done

  tree_sitter_effective_candidate_names+=("$name")
  tree_sitter_effective_candidate_sources+=("$source")
}

record_unresolved_tree_sitter_needed() {
  local base=$1
  local needed=$2
  local detail="ELF NEEDED for $base: $needed"

  tree_sitter_unresolved_needed=true
  if [ -z "$tree_sitter_unresolved_needed_detail" ]; then
    tree_sitter_unresolved_needed_detail=$detail
  else
    tree_sitter_unresolved_needed_detail="$tree_sitter_unresolved_needed_detail; $detail"
  fi
  append_tree_sitter_display "unresolved $detail"
  append_tree_sitter_effective_candidate \
    "unresolved ELF NEEDED leaf for $base" "unresolved-libtree-sitter-needed"
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

append_tree_sitter_ldd_path_map() {
  local name=$1
  local path=$2
  local resolved=""
  local existing_name=""
  local existing_path=""
  local i=0

  name=${name##*/}
  name=${name%:}
  name=${name%,}
  case "$name" in
    *libtree-sitter*) ;;
    *) return 0 ;;
  esac

  path=${path%:}
  path=${path%,}
  case "$path" in
    ""|not|"not found") return 0 ;;
    /*|./*|../*) ;;
    *) return 0 ;;
  esac

  resolved=$(resolve_runtime_path "$path" || true)
  if [ -z "$resolved" ]; then
    return 0
  fi

  while [ "$i" -lt "${#tree_sitter_ldd_map_names[@]}" ]; do
    existing_name=${tree_sitter_ldd_map_names[$i]}
    existing_path=${tree_sitter_ldd_map_paths[$i]}
    if [ "$existing_name" = "$name" ]; then
      if [ "$existing_path" = "$resolved" ]; then
        return 0
      fi
      return 0
    fi
    i=$((i + 1))
  done

  tree_sitter_ldd_map_names+=("$name")
  tree_sitter_ldd_map_paths+=("$resolved")
}

lookup_tree_sitter_ldd_path() {
  local name=$1
  local existing_name=""
  local i=0

  name=${name##*/}
  name=${name%:}
  name=${name%,}
  while [ "$i" -lt "${#tree_sitter_ldd_map_names[@]}" ]; do
    existing_name=${tree_sitter_ldd_map_names[$i]}
    if [ "$existing_name" = "$name" ]; then
      printf '%s\n' "${tree_sitter_ldd_map_paths[$i]}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
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

trim_ldd_field() {
  local value=$1

  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s\n' "$value"
}

strip_ldd_address_suffix() {
  local value=$1

  if [[ "$value" =~ ^(.*)[[:space:]]+\(0x[[:xdigit:]]+\)[[:space:]]*$ ]]; then
    value=${BASH_REMATCH[1]}
  fi
  trim_ldd_field "$value"
}

parse_ldd_tree_sitter_output() {
  local output=$1
  local line=""
  local ldd_name=""
  local ldd_path=""
  local direct_entry=false
  local fallback_entry_seen=false

  while IFS= read -r line; do
    case "$line" in
      *libtree-sitter*) ;;
      *) continue ;;
    esac

    if [[ "$line" == *"=>"* ]]; then
      ldd_name=$(trim_ldd_field "${line%%=>*}")
    else
      ldd_name=$(strip_ldd_address_suffix "$line")
    fi
    if [ -z "$ldd_name" ]; then
      continue
    fi

    direct_entry=false
    if [ "$direct_dependency_scan_reliable" = true ]; then
      if tree_sitter_direct_dependency_p "$ldd_name"; then
        direct_entry=true
      fi
    else
      fallback_ldd_tree_sitter_entries=$((fallback_ldd_tree_sitter_entries + 1))
      if [ "$fallback_entry_seen" != true ]; then
        direct_entry=true
        fallback_entry_seen=true
      fi
    fi

    if [[ "$line" == *"=>"* ]]; then
      ldd_path=$(strip_ldd_address_suffix "${line#*=>}")
      record_tree_sitter_token "ldd name" "$ldd_name" "$direct_entry" false
      if [ -n "$ldd_path" ]; then
        append_tree_sitter_ldd_path_map "$ldd_name" "$ldd_path"
        record_tree_sitter_token "ldd path" "$ldd_path" \
          "$direct_entry" "$direct_entry"
      fi
    else
      append_tree_sitter_ldd_path_map "$ldd_name" "$ldd_name"
      record_tree_sitter_token "ldd entry" "$ldd_name" \
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

  readelf_metadata_needed_names=()
  readelf_metadata_soname=""

  while IFS= read -r line; do
    case "$line" in
      *"Library soname:"*"["*"]"*) source="ELF SONAME for $base" ;;
      *"Shared library:"*"["*"]"*) source="ELF NEEDED for $base" ;;
      *) continue ;;
    esac

    name=${line#*[}
    name=${name%%]*}
    record_tree_sitter_token "$source" "$name"
    case "$name" in
      *libtree-sitter*)
        case "$source" in
          "ELF NEEDED"*) readelf_metadata_needed_names+=("$name") ;;
          "ELF SONAME"*) readelf_metadata_soname=$name ;;
        esac
        ;;
    esac
  done <<< "$output"
}

tree_sitter_library_inspection_stack_contains() {
  local path=$1
  local existing=""

  for existing in "${tree_sitter_library_inspection_stack[@]}"; do
    if [ "$existing" = "$path" ]; then
      return 0
    fi
  done
  return 1
}

pop_tree_sitter_library_inspection_stack() {
  local last_index=$((${#tree_sitter_library_inspection_stack[@]} - 1))

  if [ "$last_index" -ge 0 ]; then
    unset 'tree_sitter_library_inspection_stack[$last_index]'
  fi
}

inspect_tree_sitter_library_leaf() {
  local path=$1
  local resolved=""
  local base=""
  local readelf_bin=""
  local output=""
  local soname=""
  local needed=""
  local needed_path=""
  local -a needed_names=()

  resolved=$(resolve_runtime_path "$path" || true)
  if [ -z "$resolved" ]; then
    append_tree_sitter_effective_candidate "unresolved library path leaf" "$path"
    return 0
  fi
  base=${resolved##*/}

  if tree_sitter_library_inspection_stack_contains "$resolved"; then
    append_tree_sitter_effective_candidate \
      "recursive ELF NEEDED cycle at $base" "$resolved"
    return 0
  fi

  tree_sitter_library_inspection_stack+=("$resolved")

  if readelf_bin=$(command -v readelf 2>/dev/null); then
    output=$(run_detector "$readelf_bin" -d "$resolved" 2>/dev/null || true)
    if [ -n "$output" ]; then
      record_readelf_metadata_names "$output" "$base"
      soname=$readelf_metadata_soname
      needed_names=("${readelf_metadata_needed_names[@]}")

      if [ "${#needed_names[@]}" -gt 0 ]; then
        for needed in "${needed_names[@]}"; do
          needed_path=$(lookup_tree_sitter_ldd_path "$needed" || true)
          if [ -n "$needed_path" ]; then
            inspect_tree_sitter_library_leaf "$needed_path"
          else
            record_unresolved_tree_sitter_needed "$base" "$needed"
          fi
        done
        pop_tree_sitter_library_inspection_stack
        return 0
      fi

      if [ -n "$soname" ]; then
        append_tree_sitter_effective_candidate \
          "ELF SONAME leaf for $base" "$soname"
        pop_tree_sitter_library_inspection_stack
        return 0
      fi
    fi
  fi

  append_tree_sitter_effective_candidate \
    "resolved library path leaf for $base" "$resolved"
  pop_tree_sitter_library_inspection_stack
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
  local otool_bin=""
  local output=""
  local base=""
  local effective_before=0

  while [ "$i" -lt "${#tree_sitter_direct_library_paths[@]}" ]; do
    path=${tree_sitter_direct_library_paths[$i]}
    base=${path##*/}
    effective_before=${#tree_sitter_effective_candidate_names[@]}

    inspect_tree_sitter_library_leaf "$path"

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

    if [ "${#tree_sitter_effective_candidate_names[@]}" -eq "$effective_before" ]; then
      append_tree_sitter_effective_candidate "resolved library path leaf for $base" "$path"
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
effective_runtime_candidates=false
unsupported_effective_detail=""

evaluate_tree_sitter_runtime() {
  local i=0
  local count=0
  local name=""
  local source=""
  local minor=""
  local detail=""
  local supported_seen=false
  local unsupported_seen=false

  if [ "${#tree_sitter_effective_candidate_names[@]}" -gt 0 ]; then
    effective_runtime_candidates=true
    count=${#tree_sitter_effective_candidate_names[@]}
  else
    effective_runtime_candidates=false
    count=${#tree_sitter_candidate_names[@]}
  fi

  while [ "$i" -lt "$count" ]; do
    if [ "$effective_runtime_candidates" = true ]; then
      name=${tree_sitter_effective_candidate_names[$i]}
      source=${tree_sitter_effective_candidate_sources[$i]}
    else
      name=${tree_sitter_candidate_names[$i]}
      source=${tree_sitter_candidate_sources[$i]}
    fi

    if minor=$(extract_tree_sitter_minor "$name"); then
      version_visible=true
      detail="$source: $name"
      if [ -z "$visible_version_summary" ]; then
        visible_version_summary=$detail
      else
        visible_version_summary="$visible_version_summary; $detail"
      fi

      if tree_sitter_minor_supported "$minor"; then
        supported_seen=true
        if [ -z "$supported_detail" ]; then
          supported_detail=$detail
        fi
      else
        unsupported_seen=true
        if [ -z "$unsupported_effective_detail" ]; then
          unsupported_effective_detail=$detail
        fi
      fi
    fi

    i=$((i + 1))
  done

  if [ "$effective_runtime_candidates" = true ] && [ "$unsupported_seen" = true ]; then
    supported=false
  elif [ "$supported_seen" = true ]; then
    supported=true
  fi
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
  tree_sitter_effective_candidate_names=()
  tree_sitter_effective_candidate_sources=()
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

if [ "$tree_sitter_unresolved_needed" = true ] && \
    [ -z "$unsupported_effective_detail" ]; then
  skip_detection "could not resolve libtree-sitter NEEDED through ldd path map: $tree_sitter_unresolved_needed_detail"
  exit 0
fi

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
