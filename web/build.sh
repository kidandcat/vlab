#!/usr/bin/env bash
# Build the leanlab browser UI (WebAssembly + WebGPU).
#
# Adapted from uvl `web/build.sh` at the revision pinned in lakefile.lean.
# The Lean runtime and `Init` are compiled once per toolchain and cached under
# .lake/build/wasm. The app and the uvl modules it imports are compiled from
# the C that `lake build` emits.
#
#   web/build.sh [Module] [init-symbol]
#
# Requires `emcc` on PATH and the toolchain in lean-toolchain.
# Output: web/dist/{index.html,uvl.js,uvl.wasm,uvl-web.js} (or $UVL_DIST).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODULE=${1:-LeanlabWeb.App}
# Lake prefixes the initializer with the package name: `initialize_<pkg>_<Module>`.
INIT_SYM=${2:-initialize_leanlab_LeanlabWeb_App}
# Two jobs by default: a wide emcc of Init can exhaust a small VM.
JOBS=${JOBS:-2}
CORE_EXTRA=${CORE_EXTRA:-Std.Tactic.BVDecide.Bitblast.BoolExpr.Basic Std.Tactic.BVDecide.Bitblast.BVExpr.Basic}

PREFIX=$(lean --print-prefix)
VERSION=$(lean --version | sed -E 's/.*version ([0-9][^ ,]*).*/\1/')
CACHE=$ROOT/.lake/build/wasm/v$VERSION
DIST=${UVL_DIST:-$ROOT/web/dist}
CFLAGS="-O2 -DNDEBUG -DLEAN_EMSCRIPTEN -fwasm-exceptions -w"
mkdir -p "$CACHE" "$DIST"
cd "$ROOT"

log() { echo "==> $*"; }

UVL_PKG=$ROOT/.lake/packages/uvl
if [ ! -d "$UVL_PKG/UVL" ]; then
  log "fetching Lake dependencies"
  lake update
fi
if [ ! -f "$UVL_PKG/web/web_shell.c" ]; then
  echo "error: uvl package is missing web/web_shell.c" >&2
  exit 1
fi

# --- headers: lean.h from the toolchain, config without mimalloc -----------
INC=$CACHE/include
if [ ! -f "$INC/lean/config.h" ]; then
  mkdir -p "$INC/lean"
  cp "$PREFIX/include/lean/lean.h" "$PREFIX/include/lean/version.h" "$INC/lean/"
  printf '#pragma once\n#include <lean/version.h>\n#define LEAN_IS_STAGE0 0\n' > "$INC/lean/config.h"
  printf '#define LEAN_GITHASH ""\n' > "$INC/githash.h"
fi

# --- 1. runtime -------------------------------------------------------------
if [ ! -f "$CACHE/libleanrt.a" ]; then
  SRC=$CACHE/lean4
  if [ ! -d "$SRC/src/runtime" ]; then
    log "fetching Lean v$VERSION runtime sources"
    git clone -q --depth 1 --filter=blob:none --sparse --branch "v$VERSION" \
      https://github.com/leanprover/lean4.git "$SRC"
    git -C "$SRC" sparse-checkout set src/runtime src/include src/util
  fi
  UV=$CACHE/libuv
  if [ ! -d "$UV/include" ]; then
    git clone -q --depth 1 --branch v1.48.0 https://github.com/libuv/libuv.git "$UV"
  fi
  log "compiling the Lean runtime to wasm"
  OBJ=$CACHE/rt-obj
  mkdir -p "$OBJ/patched/uv"
  sed 's/lean_uv_os_get_group() {/lean_uv_os_get_group(uint64_t) {/' \
    "$SRC/src/runtime/uv/system.cpp" > "$OBJ/patched/uv/system.cpp"
  RT="debug thread mpz utf8 object apply exception interrupt memory stackinfo compact
      init_module io hash byteslice platform alloc allocprof sharecommon stack_overflow
      process object_ref mpn mutex libuv uv/net_addr uv/event_loop uv/timer uv/tcp uv/udp
      uv/dns uv/signal openssl"
  for f in $RT; do echo "$SRC/src/runtime/$f.cpp"; done > "$OBJ/list"
  echo "$OBJ/patched/uv/system.cpp" >> "$OBJ/list"
  xargs -P "$JOBS" -I{} sh -c 'f={}; o='"$OBJ"'/$(echo "$f" | md5sum | cut -c1-12).o;
    em++ -std=c++20 '"$CFLAGS"' -I'"$INC"' -I'"$SRC/src"' \
      -I'"$SRC/src/runtime"' -I'"$UV/include"' -c "$f" -o "$o"' < "$OBJ/list"
  emar rcs "$CACHE/libleanrt.a" "$OBJ"/*.o
fi

# --- 2. Init ----------------------------------------------------------------
if [ ! -f "$CACHE/libInit.a" ]; then
  log "generating and compiling Init for wasm (cached afterwards)"
  OBJ=$CACHE/init-obj
  mkdir -p "$OBJ"
  (cd "$PREFIX/src/lean" && { echo Init.lean; find Init -name '*.lean'; }) > "$OBJ/list"
  xargs -P "$JOBS" -I{} sh -c 'f={}; b='"$OBJ"'/$(echo "${f%.lean}" | tr / _);
    cd '"$PREFIX/src/lean"' && lean --root=. -c "$b.c" "$f" > /dev/null &&
    emcc '"$CFLAGS"' -I'"$INC"' -c "$b.c" -o "$b.o" && rm "$b.c"' < "$OBJ/list"
  emar rcs "$CACHE/libInit.a" "$OBJ"/*.o
fi

# --- 2b. extra core modules (those must import only Init) -------------------
EXTRA_KEY=$(echo "$CORE_EXTRA" | md5sum | cut -c1-12)
if [ ! -f "$CACHE/libExtra-$EXTRA_KEY.a" ]; then
  OBJ=$CACHE/extra-obj-$EXTRA_KEY
  mkdir -p "$OBJ"
  for m in $CORE_EXTRA; do
    f=$(echo "$m" | tr . /).lean
    b=$OBJ/$(echo "$m" | tr . _)
    (cd "$PREFIX/src/lean" && lean --root=. -c "$b.c" "$f" > /dev/null)
    emcc $CFLAGS -I"$INC" -c "$b.c" -o "$b.o"
  done
  emar rcs "$CACHE/libExtra-$EXTRA_KEY.a" "$OBJ"/*.o
fi

# --- 3. the app and the uvl modules it imports ------------------------------
log "building $MODULE (native C first, then wasm)"
lake build "$MODULE" > /dev/null
lake build "$MODULE:c" > /dev/null
APP=$CACHE/app
rm -rf "$APP" && mkdir -p "$APP"
python3 - "$MODULE" "$ROOT" "$UVL_PKG" > "$APP/list" <<'PY'
import os, sys
module, root, uvl = sys.argv[1:]
source_roots = [root, uvl]
ir_roots = [
    os.path.join(root, ".lake", "build", "ir"),
    os.path.join(uvl, ".lake", "build", "ir"),
]

def source_of(name):
    rel = name.replace(".", "/") + ".lean"
    for base in source_roots:
        path = os.path.join(base, rel)
        if os.path.isfile(path):
            return path
    return None

def c_of(name):
    rel = name.replace(".", "/") + ".c"
    for base in ir_roots:
        path = os.path.join(base, rel)
        if os.path.isfile(path):
            return path
    return None

seen, todo, missing = set(), [module], []
while todo:
    name = todo.pop()
    path = source_of(name)
    if name in seen or path is None:
        continue
    seen.add(name)
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("import "):
                todo += line.split()[1:]
for name in sorted(seen):
    c = c_of(name)
    if c is None:
        missing.append(name)
    else:
        print(c)
if missing:
    sys.stderr.write("error: no C file for:\n  " + "\n  ".join(missing) + "\n")
    sys.exit(1)
PY

xargs -P "$JOBS" -I{} sh -c 'f={}; o='"$APP"'/$(echo "$f" | sed "s|.lake/build/ir/||; s|/|_|g" | md5sum | cut -c1-16).o;
  emcc '"$CFLAGS"' -Dlean_float_of_nat=uvl_float_of_nat -I'"$INC"' -c "$f" -o "$o"' < "$APP/list"
emcc $CFLAGS -I"$INC" -DUVL_WEB_INIT="$INIT_SYM" -c "$UVL_PKG/web/web_shell.c" -o "$APP/web_shell.o"
emcc $CFLAGS -I"$INC" -c "$UVL_PKG/web/lean_stubs.c" -o "$APP/lean_stubs.o"
emcc $CFLAGS -c "$UVL_PKG/UVL/Render/glyph_table.c" -o "$APP/glyph_table.o"

EXPORTS=_uvl_init,_uvl_step,_uvl_frame_ptr,_uvl_width,_uvl_height,_uvl_target_center,_uvl_damage_ptr,_uvl_damage_count,_uvl_set_gpu,_uvl_render_cpu,_uvl_gpu_prims,_uvl_gpu_prims_len,_uvl_gpu_data,_uvl_gpu_data_len,_uvl_gpu_count,_uvl_gpu_background,_uvl_gpu_shader_source,_uvl_gpu_entry_points_source,_uvl_gpu_atlas_reset,_uvl_gpu_atlas_size,_uvl_gpu_cell_floats,_uvl_gpu_atlas_new_count,_uvl_gpu_atlas_new_glyphs,_uvl_gpu_atlas_new_data,_uvl_gpu_atlas_ack,_uvl_gpu_prim_ranges,_uvl_gpu_prim_ranges_len,_uvl_gpu_data_ranges,_uvl_gpu_data_ranges_len,_uvl_take_clipboard,_uvl_input_rect,_uvl_semantics,_malloc,_free
LINK=(em++ -O2 -fwasm-exceptions "$APP"/*.o "$CACHE/libExtra-$EXTRA_KEY.a" "$CACHE/libInit.a" "$CACHE/libleanrt.a"
      -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=8MB -sENVIRONMENT=web,node
      -sEXPORTED_FUNCTIONS=$EXPORTS -sEXPORTED_RUNTIME_METHODS=HEAPU8,HEAPF64,HEAPF32,UTF8ToString
      -sMODULARIZE=1 -sEXPORT_NAME=createUVL -Wl,--error-limit=0
      ${EXTRA_LDFLAGS:-} -o "$DIST/uvl.js")

STUBS=$APP/gen_stubs.c
: > "$STUBS"
if ! "${LINK[@]}" 2> "$APP/link1.log"; then
  grep -o 'undefined symbol: [A-Za-z0-9_]*' "$APP/link1.log" | cut -d' ' -f3 | sort -u > "$APP/undef" || true
  if [ ! -s "$APP/undef" ]; then cat "$APP/link1.log" >&2; exit 1; fi
  # `initialize_Lean_` is the compiler package. `initialize_leanlab_` is this app
  # and must not be stubbed.
  BAD=$(grep -v -E '^(l_Lean_|l_Std_|initialize_Lean_|initialize_Lean$|initialize_Std_|initialize_Std$)' "$APP/undef" || true)
  if [ -n "$BAD" ]; then
    echo "error: undefined symbols that are not compile-time-only:" >&2
    echo "$BAD" >&2
    exit 1
  fi
  { echo '#include <lean/lean.h>'
    for m in $CORE_EXTRA; do echo "lean_object *initialize_$(echo "$m" | tr . _)(uint8_t);"; done
    echo 'static lean_object *init_extra(uint8_t b) {'
    for m in $CORE_EXTRA; do
      echo "  { lean_object *r = initialize_$(echo "$m" | tr . _)(b); if (lean_io_result_is_error(r)) return r; lean_dec_ref(r); }"
    done
    echo '  return lean_io_result_mk_ok(lean_box(0));'
    echo '}'
    { grep '^initialize_' "$APP/undef" || true; } | sed 's/.*/lean_object *&(uint8_t b) { return init_extra(b); }/'
    { grep '^l_' "$APP/undef" || true; } | sed 's/.*/void &(void) { lean_internal_panic("compile-time-only symbol called: &"); }/'
  } > "$STUBS"
  log "stubbed $(wc -l < "$APP/undef") compile-time-only symbols"
  emcc $CFLAGS -I"$INC" -c "$STUBS" -o "$APP/gen_stubs.o"
  "${LINK[@]}" "$APP/gen_stubs.o" 2> "$APP/link2.log" || { cat "$APP/link2.log" >&2; exit 1; }
fi

cp "$ROOT/web/index.html" "$UVL_PKG/web/uvl-web.js" "$DIST/"
log "done: $DIST ($(du -h "$DIST/uvl.wasm" | cut -f1) wasm)"
