#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:-0.25.10}
EMACS_BIN=${2:-$(command -v emacs)}
ROOT=${3:-$PWD/.cache/tree-sitter-runtime/$VERSION}

abi_version=${VERSION%.*}
lib_name="libtree-sitter.so.${abi_version}"

if [ ! -x "$EMACS_BIN" ]; then
  echo "setup-tree-sitter-runtime: Emacs binary not found: $EMACS_BIN" >&2
  exit 1
fi

needed_name=$(readelf -d "$EMACS_BIN" | awk -F'[][]' '/Shared library: \[libtree-sitter\.so\./ { print $2; exit }')
if [ -z "$needed_name" ]; then
  echo "setup-tree-sitter-runtime: could not determine Emacs tree-sitter dependency" >&2
  exit 1
fi

src_dir="$ROOT/src/tree-sitter-$VERSION"
lib_dir="$ROOT/lib"
real_name="libtree-sitter-real.so.${abi_version}"
compat_src="$ROOT/src/compat-tree-sitter.c"
compat_name="$needed_name"

if [ ! -f "$lib_dir/$compat_name" ]; then
  rm -rf "$ROOT"
  mkdir -p "$ROOT/src" "$lib_dir"
  archive="$ROOT/src/tree-sitter-$VERSION.tar.gz"
  echo "setup-tree-sitter-runtime: downloading tree-sitter v$VERSION" >&2
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v$VERSION.tar.gz" \
    -o "$archive"
  tar -xzf "$archive" -C "$ROOT/src"
  echo "setup-tree-sitter-runtime: building $lib_name" >&2
  make -C "$src_dir" clean >/dev/null 2>&1 || true
  make -C "$src_dir" libtree-sitter.so >&2
  cp "$src_dir/libtree-sitter.so" "$lib_dir/$real_name"
  ln -sf "$real_name" "$lib_dir/libtree-sitter-real.so"

  cat > "$compat_src" <<'EOF'
#include <stddef.h>
#include <stdint.h>
#include "tree_sitter/api.h"

/*
 * Tree-sitter 0.26 removed a handful of symbols that Emacs 29/30/31 binaries
 * linked against tree-sitter 0.25 still import at load time.  Keep this
 * compatibility bridge generic so CI can probe alternate tree-sitter runtimes
 * through the same helper.
 */
uint32_t ts_language_version(const TSLanguage *self) {
  return ts_language_abi_version(self);
}

void ts_parser_set_timeout_micros(TSParser *self, uint64_t timeout_micros) {
  (void)self;
  (void)timeout_micros;
}

uint64_t ts_parser_timeout_micros(const TSParser *self) {
  (void)self;
  return 0;
}

void ts_parser_set_cancellation_flag(TSParser *self, const size_t *flag) {
  (void)self;
  (void)flag;
}

const size_t *ts_parser_cancellation_flag(const TSParser *self) {
  (void)self;
  return NULL;
}

void ts_query_cursor_set_timeout_micros(TSQueryCursor *self, uint64_t timeout_micros) {
  (void)self;
  (void)timeout_micros;
}

uint64_t ts_query_cursor_timeout_micros(const TSQueryCursor *self) {
  (void)self;
  return 0;
}
EOF

  echo "setup-tree-sitter-runtime: building compatibility shim for $needed_name" >&2
  cc -shared -fPIC "$compat_src" \
    -I"$src_dir/lib/include" \
    -L"$lib_dir" -Wl,--no-as-needed -ltree-sitter-real \
    -Wl,-rpath,'$ORIGIN' -Wl,-soname,"$compat_name" \
    -o "$lib_dir/$compat_name" >&2
fi

ln -sf "$real_name" "$lib_dir/$lib_name"
ln -sf "$compat_name" "$lib_dir/libtree-sitter.so"

echo "setup-tree-sitter-runtime: Emacs expects $needed_name" >&2
echo "setup-tree-sitter-runtime: runtime available in $lib_dir" >&2
printf '%s\n' "$lib_dir"
