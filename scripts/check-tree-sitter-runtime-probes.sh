#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

check_script=$PWD/scripts/check-tree-sitter-runtime.sh
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT

fake_bin=$probe_dir/bin
fake_lib=$probe_dir/lib
chdir_dir=$probe_dir/chdir
mkdir -p "$fake_bin" "$fake_lib" "$chdir_dir"
: >"$fake_lib/libtree-sitter.so.0.22"

cat >"$fake_bin/emacs" <<'EOF'
#!/usr/bin/env bash
args=" $* "
case "$args" in
  *emacs-major-version*) printf '30'; exit 0 ;;
  *treesit-available-p*) exit 0 ;;
esac
exit 0
EOF
chmod +x "$fake_bin/emacs"

cat >"$fake_bin/ldd" <<EOF
#!/usr/bin/env bash
printf '%s\n' '\tlibtree-sitter.so.0.22 => $fake_lib/libtree-sitter.so.0.22 (0x00000000)'
EOF
chmod +x "$fake_bin/ldd"

probe_path=$fake_bin:$PATH

run_probe() {
  local name=$1
  local expected=$2
  shift 2
  local output status

  set +e
  output=$("$@" 2>&1)
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

run_probe "env -C wrapper fails unsupported runtime" fail \
  env PATH="$probe_path" EMACS="env -C $chdir_dir emacs" "$check_script"

run_probe "SKIP_RUNTIME_CHECK explicitly skips" skip \
  env PATH="$probe_path" EMACS="env -- PATH=$probe_path emacs" \
    SKIP_RUNTIME_CHECK=1 "$check_script"

run_probe "MD_TS_SKIP_RUNTIME_CHECK explicitly skips" skip \
  env PATH="$probe_path" EMACS="env -C $chdir_dir emacs" \
    MD_TS_SKIP_RUNTIME_CHECK=1 "$check_script"
