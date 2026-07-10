#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

check_script=$PWD/scripts/check-tree-sitter-runtime.sh
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT

resolve_probe_shell() {
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

sh_bin=$(resolve_probe_shell || true)
if [ -z "$sh_bin" ]; then
  printf 'FAIL: could not find an executable sh for probes\n' >&2
  exit 1
fi

fake_bin=$probe_dir/bin
fake_lib=$probe_dir/lib
chdir_dir=$probe_dir/chdir
mkdir -p "$fake_bin" "$fake_lib" "$chdir_dir"
: >"$fake_lib/libtree-sitter.so.0.22"

cat >"$fake_bin/emacs" <<EOF
#!$sh_bin
args=" \$* "
case "\$args" in
  *emacs-major-version*) printf '30'; exit 0 ;;
  *treesit-available-p*) exit 0 ;;
esac
exit 0
EOF
chmod +x "$fake_bin/emacs"

cat >"$fake_bin/ldd" <<EOF
#!$sh_bin
printf '%s\n' '\tlibtree-sitter.so.0.22 => $fake_lib/libtree-sitter.so.0.22 (0x00000000)'
EOF
chmod +x "$fake_bin/ldd"

probe_path=$fake_bin:$PATH

env_bin=$(command -v env 2>/dev/null || true)
env_supports_chdir=false
if [ -n "$env_bin" ] && "$env_bin" -C "$chdir_dir" "$sh_bin" -c : >/dev/null 2>&1; then
  env_supports_chdir=true
fi

path_env_bin=$probe_dir/path-env-bin
mkdir -p "$path_env_bin"
cp "$fake_bin/emacs" "$path_env_bin/emacs"
cp "$fake_bin/ldd" "$path_env_bin/ldd"
cat >"$path_env_bin/env" <<EOF
#!$sh_bin
printf 'fake PATH env should not be used for detector replay\n' >&2
exit 127
EOF
chmod +x "$path_env_bin/env"
path_env_probe_path=$path_env_bin:$PATH

reject_env_bin=$probe_dir/reject-env-bin
mkdir -p "$reject_env_bin"
cp "$fake_bin/emacs" "$reject_env_bin/emacs"
cp "$fake_bin/ldd" "$reject_env_bin/ldd"
cat >"$reject_env_bin/env" <<EOF
#!$sh_bin
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --) shift; break ;;
    *=*) export "\$1"; shift ;;
    *) break ;;
  esac
done
case "\${1:-}" in
  emacs|*/emacs) exec "\$@" ;;
esac
printf 'reject-env refuses detector replay\n' >&2
exit 127
EOF
chmod +x "$reject_env_bin/env"
reject_env_probe_path=$reject_env_bin:$PATH

minimal_env_bin=$probe_dir/minimal-env-bin
mkdir -p "$minimal_env_bin"
cp "$fake_bin/emacs" "$minimal_env_bin/emacs"
minimal_env_probe_path=$minimal_env_bin

detector_fail_bin=$probe_dir/detector-fail-bin
mkdir -p "$detector_fail_bin"
cp "$fake_bin/emacs" "$detector_fail_bin/emacs"
cat >"$detector_fail_bin/ldd" <<EOF
#!$sh_bin
printf 'detector execution intentionally failed\n' >&2
exit 127
EOF
chmod +x "$detector_fail_bin/ldd"

not_dynamic_bin=$probe_dir/not-dynamic-bin
mkdir -p "$not_dynamic_bin"
cp "$fake_bin/emacs" "$not_dynamic_bin/emacs"
cat >"$not_dynamic_bin/ldd" <<EOF
#!$sh_bin
printf 'not a dynamic executable\n' >&2
exit 1
EOF
chmod +x "$not_dynamic_bin/ldd"

relative_shell_cwd=$probe_dir/relative-shell-cwd
relative_shell_bin=$relative_shell_cwd/rel-sh-bin
mkdir -p "$relative_shell_bin"
if ! ln -s "$sh_bin" "$relative_shell_bin/sh" 2>/dev/null; then
  cp "$sh_bin" "$relative_shell_bin/sh"
  chmod +x "$relative_shell_bin/sh"
fi

run_probe() {
  local name=$1
  local expected=$2
  shift 2
  local output status

  set +e
  output=$(
    unset SKIP_RUNTIME_CHECK MD_TS_SKIP_RUNTIME_CHECK
    "$@" 2>&1
  )
  status=$?
  set -e

  case "$expected" in
    fail)
      if [ "$status" -eq 0 ]; then
        printf 'FAIL %s: expected non-zero status\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if grep -q 'tree-sitter runtime check skipped' <<<"$output"; then
        printf 'FAIL %s: preflight skipped unexpectedly\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if ! grep -q 'unsupported tree-sitter runtime' <<<"$output"; then
        printf 'FAIL %s: unsupported-runtime message missing\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      ;;
    skip)
      if [ "$status" -ne 0 ]; then
        printf 'FAIL %s: expected zero status\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if ! grep -q 'tree-sitter runtime check skipped by' <<<"$output"; then
        printf 'FAIL %s: explicit skip message missing\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      ;;
    detect-skip)
      if [ "$status" -ne 0 ]; then
        printf 'FAIL %s: expected zero status\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if ! grep -q 'tree-sitter runtime check skipped' <<<"$output"; then
        printf 'FAIL %s: detector skip message missing\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      ;;
    resolve-fail)
      if [ "$status" -eq 0 ]; then
        printf 'FAIL %s: expected non-zero status\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if grep -q 'tree-sitter runtime check skipped' <<<"$output"; then
        printf 'FAIL %s: preflight skipped unexpectedly\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if ! grep -q 'could not safely resolve Emacs executable' <<<"$output"; then
        printf 'FAIL %s: safe-resolve failure message missing\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      ;;
    detector-fail)
      if [ "$status" -eq 0 ]; then
        printf 'FAIL %s: expected non-zero status\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if grep -q 'tree-sitter runtime check skipped' <<<"$output"; then
        printf 'FAIL %s: preflight skipped unexpectedly\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      if ! grep -q 'runtime detector failed' <<<"$output"; then
        printf 'FAIL %s: detector failure message missing\n%s\n' "$name" "$output" >&2
        exit 1
      fi
      ;;
    *)
      printf 'internal error: unknown expectation %s\n' "$expected" >&2
      exit 1
      ;;
  esac

  printf 'ok - %s\n' "$name"
}

run_probe "unsupported plain emacs fails" fail \
  env PATH="$probe_path" EMACS=emacs "$check_script"

run_probe "env -- PATH wrapper fails unsupported runtime" fail \
  env PATH="$probe_path" EMACS="env -- PATH=$probe_path emacs" "$check_script"

if [ "$env_supports_chdir" = true ]; then
  run_probe "env -C wrapper fails unsupported runtime" fail \
    env PATH="$probe_path" EMACS="env -C $chdir_dir emacs" "$check_script"

  run_probe "env -C wrapper ignores relative sh from PATH" fail \
    "$sh_bin" -c 'cd "$1" || exit 1; shift; exec "$@"' sh \
      "$relative_shell_cwd" \
      env PATH="rel-sh-bin:$probe_path" \
      EMACS="env -C $chdir_dir emacs" "$check_script"
else
  printf 'ok - env -C wrapper probes skipped (env lacks -C)\n'
fi

if [ -n "$env_bin" ]; then
  run_probe "env PATH without true still replays detector" fail \
    env PATH="$probe_path" \
      EMACS="$env_bin -- PATH=$minimal_env_probe_path emacs" \
      "$check_script"

  run_probe "path-qualified env wrapper reuses matched env" fail \
    env PATH="$path_env_probe_path" \
      EMACS="$env_bin -- PATH=$path_env_probe_path emacs" \
      "$check_script"

  run_probe "path-qualified env replay failure fails closed" resolve-fail \
    env PATH="$reject_env_probe_path" \
      EMACS="$reject_env_bin/env PATH=$reject_env_probe_path $reject_env_bin/emacs" \
      "$check_script"

  run_probe "detector replay failure fails closed" detector-fail \
    env PATH="$detector_fail_bin:$PATH" \
      EMACS="$env_bin -- PATH=$detector_fail_bin emacs" \
      "$check_script"
fi

run_probe "not-dynamic ldd result skips detection" detect-skip \
  env PATH="$not_dynamic_bin:$PATH" EMACS=emacs "$check_script"

run_probe "SKIP_RUNTIME_CHECK explicitly skips" skip \
  env PATH="$probe_path" EMACS="env -- PATH=$probe_path emacs" \
    SKIP_RUNTIME_CHECK=1 "$check_script"

if [ "$env_supports_chdir" = true ]; then
  run_probe "MD_TS_SKIP_RUNTIME_CHECK explicitly skips" skip \
    env PATH="$probe_path" EMACS="env -C $chdir_dir emacs" \
      MD_TS_SKIP_RUNTIME_CHECK=1 "$check_script"
else
  run_probe "MD_TS_SKIP_RUNTIME_CHECK explicitly skips" skip \
    env PATH="$probe_path" EMACS="env -- PATH=$probe_path emacs" \
      MD_TS_SKIP_RUNTIME_CHECK=1 "$check_script"
fi
