#!/usr/bin/env bash
# CyreneClang — Core Build Script
# Performs a 2-stage PGO + ThinLTO Clang build targeting Android kernels.
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
LLVM_BRANCH="${LLVM_BRANCH:-llvmorg-22.1.0}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cyrene}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build}"
LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
JOBS="${JOBS:-$(nproc)}"
ENABLE_PGO="${ENABLE_PGO:-true}"
ENABLE_BOLT="${ENABLE_BOLT:-true}"
PGO_WORKLOAD="${PGO_WORKLOAD:-sqlite}"

LLVM_TARGETS="AArch64;ARM;X86"
LLVM_PROJECTS="clang;lld;compiler-rt;polly"
CLANG_VENDOR="${CLANG_VENDOR:-CyreneClang}"

# ─── Host Compiler Detection ──────────────────────────────────────────────
detect_host_compiler() {
  HOST_CC="${HOST_CC:-}"
  HOST_CXX="${HOST_CXX:-}"

  if [[ -z "$HOST_CC" ]]; then
    if command -v clang &>/dev/null; then
      HOST_CC="clang"
      HOST_CXX="clang++"
    else
      HOST_CC="cc"
      HOST_CXX="c++"
    fi
  fi

  HOST_PROFDATA=""
  if [[ "$HOST_CC" == *clang* ]]; then
    HOST_HAS_CLANG=true
    local resolved_cc
    resolved_cc=$(command -v "$HOST_CC" || echo "$HOST_CC")
    if [[ -L "$resolved_cc" ]]; then
      resolved_cc=$(readlink -f "$resolved_cc")
    fi
    local host_dir
    host_dir=$(dirname "$resolved_cc")

    local suffix=""
    if [[ "$HOST_CC" =~ clang(-[0-9]+) ]]; then
      suffix="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$suffix" && -x "$host_dir/llvm-profdata$suffix" ]]; then
      HOST_PROFDATA="$host_dir/llvm-profdata$suffix"
    elif [[ -x "$host_dir/llvm-profdata" ]]; then
      HOST_PROFDATA="$host_dir/llvm-profdata"
    elif [[ -n "$suffix" ]] && command -v "llvm-profdata$suffix" &>/dev/null; then
      HOST_PROFDATA=$(command -v "llvm-profdata$suffix")
    elif command -v llvm-profdata &>/dev/null; then
      HOST_PROFDATA=$(command -v llvm-profdata)
    fi
  else
    HOST_HAS_CLANG=false
  fi
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "\n\033[1;36m[CyreneClang]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
START_EPOCH=$(date +%s)

notify() {
  local type="$1"
  export BUILD_STAGE="${2:-}"
  [[ -x "$NOTIFY_SCRIPT" ]] && bash "$NOTIFY_SCRIPT" "$type" || true
}

build_duration() {
  local now elapsed h m s
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  h=$((elapsed / 3600))
  m=$(((elapsed % 3600) / 60))
  s=$((elapsed % 60))
  printf "%dh %dm %ds" "$h" "$m" "$s"
}

gen_changelog() {
  local cl="$BUILD_DIR/changelog.txt"
  local patches_dir="$REPO_DIR/patches"

  {
    echo "*Date:* $BUILD_DATE"
    echo "*Branch:* \`$LLVM_BRANCH\`"
    echo "*LLVM Commit:* \`$LLVM_COMMIT\`"
    echo "*PGO:* $ENABLE_PGO | *LTO:* $LTO_MODE"

    if ls "$patches_dir"/*.patch &>/dev/null 2>&1; then
      echo ""
      echo "*Applied Patches:*"
      for pf in "$patches_dir"/*.patch; do
        local name subj
        name=$(basename "$pf")
        subj=$(grep -m1 '^Subject: ' "$pf" 2>/dev/null | sed 's/^Subject: //' || echo "")
        echo "  • \`$name\`${subj:+ — $subj}"
      done
    fi
  } > "$cl"
  echo "$cl"
}

# ─── Stage 0: Clone LLVM ──────────────────────────────────────────────────────
clone_llvm() {
  if [[ -d "$LLVM_DIR" ]]; then
    log "LLVM already cloned, skipping."
    return
  fi
  log "Cloning LLVM (branch: $LLVM_BRANCH) ..."
  git clone https://github.com/llvm/llvm-project.git \
    --depth=1 --branch "$LLVM_BRANCH" "$LLVM_DIR"
}

# ─── Apply Custom Patches ─────────────────────────────────────────────────────
apply_patches() {
  log "Applying custom patches ..."
  bash "$SCRIPT_DIR/patch.sh" "$LLVM_DIR"
}

# ─── CMake Configure Helper ───────────────────────────────────────────────────
cmake_configure() {
  local src="$1" build="$2" install="$3" projects="$4" targets="${5:-$LLVM_TARGETS}"
  shift 5

  local cmake_extra_args=()

  # Warn about stale system gold plugin (version mismatch with LTO)
  if [[ -f /usr/lib/bfd-plugins/LLVMgold.so ]]; then
    warn "System gold plugin detected at /usr/lib/bfd-plugins/LLVMgold.so"
    warn "This may cause LTO errors if the plugin LLVM version differs from the build."
    warn "Consider: sudo apt remove llvm-*-linker-tools  or  remove it manually."
  fi
  if [[ -f /usr/lib/llvm-16/lib/LLVMgold.so ]]; then
    warn "LLVM 16 gold plugin detected — remove with: sudo apt remove llvm-16-linker-tools"
  fi

  # Disable gold plugin build (not needed; we use LLD for ThinLTO)
  cmake_extra_args+=("-DLLVM_BINUTILS_INCDIR=")

  # Enable ccache if available
  if command -v ccache &>/dev/null; then
    cmake_extra_args+=("-DLLVM_CCACHE_BUILD=ON")
  fi

  # Limit parallel link jobs to 1 to avoid OOM / disk explosion during ThinLTO linking
  cmake_extra_args+=("-DLLVM_PARALLEL_LINK_JOBS=1")

  # Use shared ThinLTO cache across targets to save disk + time
  cmake_extra_args+=("-DLLVM_THIN_LTO_CACHE_DIR=$BUILD_DIR/lto-cache")

  # Skip appending git hash to version string (saves rebuilds + disk)
  cmake_extra_args+=("-DLLVM_APPEND_VC_REV=OFF")

  # Use LLD as the linker if available (much faster than GNU ld)
  local lld_path=""
  for lld_name in ld.lld ld.lld-18 ld.lld-17 ld.lld-16 ld.lld-15 ld.lld-14 lld; do
    if command -v "$lld_name" &>/dev/null; then
      lld_path=$(command -v "$lld_name")
      cmake_extra_args+=("-DLLVM_USE_LINKER=lld" "-DCMAKE_LINKER=$lld_path")
      break
    fi
  done
  if [[ -z "$lld_path" ]]; then
    warn "LLD not found — ThinLTO cache flags disabled (GNU ld does not support them)"
  fi

  # Use llvm-ar / llvm-ranlib to avoid triggering the system's gold plugin
  for ar_name in llvm-ar llvm-ar-18 llvm-ar-17 llvm-ar-16 llvm-ar-15 llvm-ar-14; do
    if command -v "$ar_name" &>/dev/null; then
      cmake_extra_args+=("-DCMAKE_AR=$(command -v "$ar_name")")
      break
    fi
  done
  for ranlib_name in llvm-ranlib llvm-ranlib-18 llvm-ranlib-17 llvm-ranlib-16 llvm-ranlib-15 llvm-ranlib-14; do
    if command -v "$ranlib_name" &>/dev/null; then
      cmake_extra_args+=("-DCMAKE_RANLIB=$(command -v "$ranlib_name")")
      break
    fi
  done

  # ThinLTO cache flags — only pass when LLD is available (GNU ld rejects them)
  local thinlto_cache_flags=()
  if [[ -n "$lld_path" ]]; then
    thinlto_cache_flags=(
      "-DCMAKE_SHARED_LINKER_FLAGS=-lc++ -lc++abi -lm -Wl,--thinlto-cache-policy=cache_size_bytes=2g"
      "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--thinlto-cache-policy=cache_size_bytes=2g"
      "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--thinlto-cache-policy=cache_size_bytes=2g"
    )
  else
    thinlto_cache_flags=(
      "-DCMAKE_SHARED_LINKER_FLAGS=-lc++ -lc++abi -lm"
    )
  fi

  cmake -S "$src/llvm" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DLLVM_TARGETS_TO_BUILD="$targets" \
    -DLLVM_ENABLE_PROJECTS="$projects" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_BUILD_DOCS=OFF \
    -DPOLLY_ENABLE_GPGPU_CODEGEN=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCOMPILER_RT_USE_LIBCXX=ON \
    -DCOMPILER_RT_LINK_CXX_LIBRARY=ON \
    -DCOMPILER_RT_ENABLE_PIC=ON \
    "${thinlto_cache_flags[@]}" \
    -DCLANG_VENDOR="$CLANG_VENDOR" \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DLLVM_ENABLE_WARNINGS=OFF \
    "${cmake_extra_args[@]}" \
    "$@"
}

# ─── Stage 1: Instrumented Build (PGO profiling) ──────────────────────────────
stage1_build() {
  log "Stage 1: Building instrumented Clang for PGO ..."
  local s1_build="$BUILD_DIR/stage1"
  local s1_install="$BUILD_DIR/stage1-install"

  # Include lld and compiler-rt (without sanitizers/xray/libfuzzer) so Stage 1 Clang
  # has a modern LTO-compatible linker and builtins to pass CMake compiler checks.
  local stage1_projects="clang;lld;compiler-rt"

  cmake_configure "$LLVM_DIR" "$s1_build" "$s1_install" "$stage1_projects" "X86" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_CRT=OFF

  cmake --build "$s1_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  cmake --install "$s1_build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  export STAGE1_CC="$s1_install/bin/clang"
  export STAGE1_CXX="$s1_install/bin/clang++"

  # Remove Stage 1 build directory completely (keep stage1-install which contains the compiler)
  log "Removing Stage 1 build directory to free disk space ..."
  rm -rf "$s1_build"
  df -h / 2>/dev/null | tail -1 || true
}

# ─── PGO Profile Collection: SQLite ───────────────────────────────────────────
collect_sqlite() {
  log "Collecting PGO profiles via SQLite workload ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/cyrene-%p.profraw"

  local workload_dir="$BUILD_DIR/workload"
  mkdir -p "$workload_dir"

  log "Downloading SQLite amalgamation ..."
  if ! curl -sSL https://www.sqlite.org/2024/sqlite-amalgamation-3460000.zip \
    -o "$workload_dir/sqlite.zip"; then
    warn "SQLite download failed"
    return 1
  fi

  log "Extracting SQLite amalgamation ..."
  if ! unzip -q "$workload_dir/sqlite.zip" -d "$workload_dir"; then
    warn "SQLite unzip failed"
    return 1
  fi

  log "Compiling SQLite workload with Stage 1 Clang ..."
  if ! "$STAGE1_CC" -c -O2 -o /dev/null \
    "$workload_dir/sqlite-amalgamation-3460000/sqlite3.c"; then
    warn "SQLite compilation failed"
    return 1
  fi

  log "SQLite workload completed successfully."
}

# ─── PGO Profile Collection: Real Kernel ─────────────────────────────────────
collect_kernel() {
  log "Collecting PGO profiles via real Android kernel build ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/cyrene-%p.profraw"

  local kernel_dir="$BUILD_DIR/kernel-workload"
  log "Cloning android-mainline kernel (--depth=1) ..."
  if ! git clone --depth=1 \
    https://android.googlesource.com/kernel/common "$kernel_dir"; then
    warn "Kernel clone failed"
    return 1
  fi

  pushd "$kernel_dir" > /dev/null
  log "Configuring kernel (defconfig ARCH=arm64) ..."
  if ! make defconfig ARCH=arm64 CC="$STAGE1_CC"; then
    warn "Kernel defconfig failed"
    popd > /dev/null
    rm -rf "$kernel_dir"
    return 1
  fi

  log "Building kernel subsystems (drivers/gpu + kernel/) ..."
  make -j"$JOBS" ARCH=arm64 CC="$STAGE1_CC" drivers/gpu/ kernel/ || warn "Kernel partial build had errors/warnings"
  popd > /dev/null

  log "Cleaning up kernel source (saves ~2GB) ..."
  rm -rf "$kernel_dir"

  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob
  if (( ${#profiles[@]} == 0 )); then
    warn "Kernel workload generated no profiles."
    return 1
  fi
  log "Kernel workload completed successfully."
}

# ─── PGO Profile Collection ───────────────────────────────────────────────────
collect_profiles() {
  local workload="${PGO_WORKLOAD:-sqlite}"
  log "Collecting PGO profiles (workload: $workload) ..."

  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  if [[ "$workload" == "kernel" ]]; then
    collect_kernel || { warn "Kernel workload failed, falling back to SQLite workload..."; collect_sqlite; } || return 1
  else
    collect_sqlite || return 1
  fi

  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob

  if (( ${#profiles[@]} == 0 )); then
    warn "No .profraw profile files were generated in $profile_dir."
    return 1
  fi

  log "Merging PGO profiles ..."
  local profdata_bin="$STAGE1_INSTALL/bin/llvm-profdata"
  if [[ -n "${HOST_PROFDATA:-}" && -x "$HOST_PROFDATA" ]]; then
    log "Using host llvm-profdata ($HOST_PROFDATA) to match host compiler instrumentation..."
    profdata_bin="$HOST_PROFDATA"
  fi

  if ! "$profdata_bin" merge \
    -output="$BUILD_DIR/pgo.prof" \
    "${profiles[@]}"; then
    warn "llvm-profdata merge failed"
    return 1
  fi

  export PGO_PROF="$BUILD_DIR/pgo.prof"
  log "PGO profile ready: $PGO_PROF"
}

# ─── Intermediate Cleanup ─────────────────────────────────────────────────────
cleanup_stage1_artifacts() {
  log "Cleaning up Stage 1 artifacts to free disk space ..."
  local s1_build="$BUILD_DIR/stage1"

  # Remove Stage 1 build tree (keep stage1-install/bin/clang needed for Stage 2)
  if [[ -d "$s1_build" ]]; then
    local before
    before=$(du -sh "$s1_build" 2>/dev/null | cut -f1)
    rm -rf "$s1_build"
    log "Removed Stage 1 build dir: $before"
  fi

  # Remove raw .profraw files (already merged into pgo.prof)
  if [[ -d "$BUILD_DIR/profiles" ]]; then
    local before
    before=$(du -sh "$BUILD_DIR/profiles" 2>/dev/null | cut -f1)
    rm -rf "$BUILD_DIR/profiles"
    log "Removed raw profile data: $before"
  fi

  # Remove SQLite workload download
  if [[ -d "$BUILD_DIR/workload" ]]; then
    local before
    before=$(du -sh "$BUILD_DIR/workload" 2>/dev/null | cut -f1)
    rm -rf "$BUILD_DIR/workload"
    log "Removed workload files: $before"
  fi

  # Remove ccache stats (regenerated on demand)
  rm -f "$BUILD_DIR/.ccache_stats" 2>/dev/null || true

  # Remove unnecessary files from stage1-install to save space
  local s1_install="$BUILD_DIR/stage1-install"
  if [[ -d "$s1_install" ]]; then
    # Remove docs, examples, cmake files from stage1-install (not needed for stage2)
    rm -rf "$s1_install/lib/cmake" 2>/dev/null || true
    rm -rf "$s1_install/share" 2>/dev/null || true
    rm -rf "$s1_install/include" 2>/dev/null || true
    # Remove static libraries from stage1 (lib/*.a) — saves ~1GB, not needed for stage2
    find "$s1_install/lib" -name "*.a" -delete 2>/dev/null || true
    # Remove unnecessary stage1 binaries (keep only clang, clang++, lld, llvm-profdata)
    for tool in "$s1_install/bin/"*; do
      local name
      name=$(basename "$tool")
      case "$name" in
        clang*|lld*|ld.lld*|llvm-profdata*|llvm-ar*|llvm-nm*|llvm-objcopy*|llvm-objdump*|llvm-strip*)
          ;; # Keep these and versioned variants (e.g., clang-22)
        *)
          rm -f "$tool" 2>/dev/null || true
          ;;
      esac
    done
    log "Cleaned up stage1-install"
  fi

  # Prune LLVM git aggressively (saves ~1GB)
  if [[ -d "$LLVM_DIR/.git" ]]; then
    log "Pruning LLVM git objects ..."
    git -C "$LLVM_DIR" gc --aggressive --prune=now 2>/dev/null || true
    git -C "$LLVM_DIR" repack -a -d --window=250 --depth=1 2>/dev/null || true
    # Remove reflog + stash to free more space
    git -C "$LLVM_DIR" reflog expire --expire=now --all 2>/dev/null || true
  fi

  # Clear ccache stats cache
  rm -f "$BUILD_DIR/.ccache_stats" 2>/dev/null || true

  # Remove ThinLTO cache from stage1 (not needed for stage2)
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true

  df -h / 2>/dev/null | tail -1 || true
  log "Disk cleanup complete"
}

# ─── Stage 2: Optimized Final Build ───────────────────────────────────────────
stage2_build() {
  log "Stage 2: Building optimized CyreneClang ..."
  local s2_build="$BUILD_DIR/stage2"

  # Prepend Stage 1 bin to PATH so that CMake and Clang find lld, llvm-profdata, etc.
  local old_path="$PATH"
  export PATH="$STAGE1_INSTALL/bin:$PATH"

  cmake_configure "$LLVM_DIR" "$s2_build" "$INSTALL_DIR" "$LLVM_PROJECTS" "" \
    -DCMAKE_C_COMPILER="$STAGE1_CC" \
    -DCMAKE_CXX_COMPILER="$STAGE1_CXX" \
    -DLLVM_ENABLE_LTO=Thin \
    -DCOMPILER_RT_ENABLE_LTO=OFF \
    -DLLVM_PROFDATA_FILE="$PGO_PROF" \
    -DLLVM_ENABLE_PLUGINS=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CRT=OFF

  cmake --build "$s2_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"

  # Free disk BEFORE install: remove object files
  log "Stage 2 build done. Cleaning object files before install ..."
  find "$s2_build" -name "*.o" -delete 2>/dev/null || true
  find "$s2_build" -name "*.obj" -delete 2>/dev/null || true
  rm -rf "$s2_build/lib" 2>/dev/null || true
  # Remove ThinLTO cache after build (no longer needed)
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  cmake --install "$s2_build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  # Wipe entire stage2 build dir after install (saves ~15GB before BOLT)
  log "Removing Stage 2 build directory ..."
  rm -rf "$s2_build" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  export PATH="$old_path"
}

# ─── BOLT Post-Build Optimization ────────────────────────────────────────────
apply_bolt() {
  [[ "$ENABLE_BOLT" == "true" ]] || return 0

  local clang_bin="$INSTALL_DIR/bin/clang"
  local llvm_bolt="${INSTALL_DIR}/bin/llvm-bolt"
  local perf2bolt="${INSTALL_DIR}/bin/perf2bolt"

  # Check prerequisites
  [[ -x "$clang_bin" ]] || { warn "clang binary not found, skipping BOLT"; return 0; }
  [[ -x "$llvm_bolt" ]] || { warn "llvm-bolt not found, skipping BOLT"; return 0; }
  command -v perf &>/dev/null || { warn "perf not found, skipping BOLT"; return 0; }

  log "Applying BOLT optimization to clang ..."
  local bolt_dir="$BUILD_DIR/bolt"
  mkdir -p "$bolt_dir"

  # Step 1: Collect perf profile
  local perf_data="$bolt_dir/clang.perf.data"
  local test_c="$bolt_dir/test.c"
  echo 'int main(void) { return 0; }' > "$test_c"

  log "  BOLT: Collecting perf profile ..."
  perf record -e cycles:u -j any,u -o "$perf_data" \
    "$clang_bin" -c -O2 -o /dev/null "$test_c" 2>/dev/null || {
    warn "BOLT: perf record failed, skipping"
    return 0
  }

  [[ -s "$perf_data" ]] || { warn "BOLT: no perf data collected, skipping"; return 0; }

  # Step 2: Convert perf data to BOLT format
  local fdata="$bolt_dir/clang.fdata"
  log "  BOLT: Converting perf data ..."

  if [[ -x "$perf2bolt" ]]; then
    "$perf2bolt" -p "$perf_data" -o "$fdata" "$clang_bin" 2>/dev/null || {
      warn "BOLT: perf2bolt conversion failed, skipping"
      return 0
    }
  else
    warn "BOLT: perf2bolt not found, skipping"
    return 0
  fi

  # Step 3: Apply BOLT optimization
  local bolted_bin="$bolt_dir/clang.bolt"
  log "  BOLT: Optimizing clang binary ..."

  "$llvm_bolt" "$clang_bin" \
    -data="$fdata" \
    -o "$bolted_bin" \
    -reorder-blocks=ext-tsp \
    -reorder-functions=hfsort+ \
    -split-functions \
    -split-all-cold \
    -dyno-stats \
    -icf=1 \
    -use-gnu-stack \
    2>&1 | tee -a "$BUILD_DIR/build.log" || {
    warn "BOLT: optimization failed, skipping"
    return 0
  }

  # Step 4: Replace original binary
  if [[ -s "$bolted_bin" ]]; then
    local original_size bolted_size saved_pct=0
    original_size=$(stat -c%s "$clang_bin" 2>/dev/null || stat -f%z "$clang_bin" 2>/dev/null || echo 0)
    bolted_size=$(stat -c%s "$bolted_bin" 2>/dev/null || stat -f%z "$bolted_bin" 2>/dev/null || echo 0)

    cp "$bolted_bin" "$clang_bin"
    chmod +x "$clang_bin"

    if [[ "$original_size" -gt 0 ]]; then
      saved_pct=$(( (original_size - bolted_size) * 100 / original_size ))
    fi

    log "  BOLT: Done! Size: ${original_size} → ${bolted_size} bytes (${saved_pct}% smaller)"
  else
    warn "BOLT: bolted binary is empty, skipping"
    return 0
  fi
}

# ─── Simple Build (no PGO) ────────────────────────────────────────────────────
simple_build() {
  log "Building CyreneClang (no PGO) ..."
  local build="$BUILD_DIR/simple"
  local cc="" cxx=""
  local lto_mode="Thin"
  local old_path="$PATH"

  # Use Stage 1 Clang if available, else host Clang, else no LTO
  if [[ -n "${STAGE1_CC:-}" && -x "${STAGE1_CC:-}" ]]; then
    cc="$STAGE1_CC"; cxx="$STAGE1_CXX"
    export PATH="$STAGE1_INSTALL/bin:$PATH"
  elif [[ "$HOST_HAS_CLANG" == "true" ]]; then
    cc="$HOST_CC"; cxx="$HOST_CXX"
  else
    lto_mode="Off"
  fi

  local cmake_args=()
  if [[ -n "$cc" && -f "$cc" ]]; then
    cmake_args+=(-DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" -DLLVM_ENABLE_LTO="$lto_mode")
  else
    warn "No Clang host compiler found — building without ThinLTO"
    cmake_args+=(-DLLVM_ENABLE_LTO=Off)
  fi

  cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" "$LLVM_PROJECTS" "" "${cmake_args[@]}"
  cmake --build "$build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  cmake --install "$build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  export PATH="$old_path"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  detect_host_compiler
  BUILD_DATE=$(date -u +%Y-%m-%d)
  LTO_MODE="Thin"
  PATCH_COUNT=0

  if ls "$REPO_DIR/patches/"*.patch &>/dev/null 2>&1; then
    PATCH_COUNT=$(ls -1 "$REPO_DIR/patches/"*.patch 2>/dev/null | wc -l)
  fi

  export LLVM_BRANCH BUILD_DATE LTO_MODE PATCH_COUNT
  export GITHUB_RUN_NUMBER="${GITHUB_RUN_NUMBER:-}"
  export GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
  export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

  log "Starting CyreneClang build (PGO=$ENABLE_PGO) ..."
  mkdir -p "$BUILD_DIR"

  # Clone LLVM first — set commit AFTER clone so notification has correct info
  BUILD_STAGE="Cloning LLVM"
  export BUILD_STAGE
  clone_llvm

  # Now we can get the actual commit
  LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  export LLVM_COMMIT

  BUILD_STAGE="Applying patches"
  export BUILD_STAGE
  apply_patches

  # Refresh commit after patching
  LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  LLVM_COMMIT_FULL=$(git -C "$LLVM_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
  export LLVM_COMMIT LLVM_COMMIT_FULL

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "LLVM_COMMIT=$LLVM_COMMIT" >> "$GITHUB_ENV"
    echo "LLVM_COMMIT_FULL=$LLVM_COMMIT_FULL" >> "$GITHUB_ENV"
  fi

  # Remove .git directory from LLVM source tree to free space (~1.5GB)
  log "Removing LLVM .git directory to save space ..."
  rm -rf "$LLVM_DIR/.git"

  BUILD_SUCCESS=false
  if [[ "$ENABLE_PGO" == "true" ]]; then
    export STAGE1_INSTALL="$BUILD_DIR/stage1-install"

    BUILD_STAGE="Stage 1: Instrumented build"
    export BUILD_STAGE
    stage1_build

    log "Available disk after Stage 1: $(df -h / | tail -1 | awk '{print $4}')"

    BUILD_STAGE="PGO profile collection"
    export BUILD_STAGE
    if collect_profiles; then
      cleanup_stage1_artifacts

      log "Available disk before Stage 2: $(df -h / | tail -1 | awk '{print $4}')"
      BUILD_STAGE="Stage 2: Optimized build"
      export BUILD_STAGE
      stage2_build

      BUILD_STAGE="BOLT optimization"
      export BUILD_STAGE
      apply_bolt
      BUILD_SUCCESS=true
    else
      warn "PGO profile collection failed. Falling back to non-PGO build."
      ENABLE_PGO="false"
      export ENABLE_PGO
      BUILD_STAGE="Simple build (no PGO fallback)"
      export BUILD_STAGE
      simple_build
      BUILD_SUCCESS=true
    fi
  else
    BUILD_STAGE="Simple build"
    export BUILD_STAGE
    simple_build
    BUILD_SUCCESS=true
  fi

  if [[ "$BUILD_SUCCESS" == "true" ]]; then
    BUILD_STAGE="Packaging"
    CLANG_VERSION=$("$INSTALL_DIR/bin/clang" --version | head -1 | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
    BUILD_DURATION=$(build_duration)
    CHANGELOG_FILE=$(gen_changelog)
    export BUILD_STAGE CLANG_VERSION BUILD_DURATION CHANGELOG_FILE

    if [[ -n "${GITHUB_ENV:-}" ]]; then
      echo "BUILD_STAGE=$BUILD_STAGE" >> "$GITHUB_ENV"
      echo "CLANG_VERSION=$CLANG_VERSION" >> "$GITHUB_ENV"
      echo "BUILD_DURATION=$BUILD_DURATION" >> "$GITHUB_ENV"
      echo "CHANGELOG_FILE=$CHANGELOG_FILE" >> "$GITHUB_ENV"
    fi

    # Final cleanup: remove LLVM source tree to free disk space for packaging
    log "Cleaning up LLVM source tree ..."
    rm -rf "$LLVM_DIR"
    df -h / 2>/dev/null | tail -1 || true

    log "Build complete! Toolchain installed to: $INSTALL_DIR"
    log "Clang version: $CLANG_VERSION"
    notify success
  fi
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
    BUILD_DURATION=$(build_duration 2>/dev/null || echo "unknown")

    # Capture error from build.log if it exists
    local error_log=""
    if [[ -f "$BUILD_DIR/build.log" && -s "$BUILD_DIR/build.log" ]]; then
      error_log=$(tail -c 4000 "$BUILD_DIR/build.log" 2>/dev/null || true)
    fi

    export BUILD_DURATION
    export ERROR_LOG="${error_log:-${ERROR_LOG:-}}"
    export BUILD_STAGE="${BUILD_STAGE:-Build Failed}"
    export ERROR_DUMP_CHAT_ID="${ERROR_DUMP_CHAT_ID:-}"
    export ERROR_DUMP_FILE="${ERROR_DUMP_FILE:-$BUILD_DIR/build.log}"
    bash "$NOTIFY_SCRIPT" failure || true
    bash "$NOTIFY_SCRIPT" error_dump || true

    if [[ -n "${GITHUB_ENV:-}" ]]; then
      echo "NOTIFIED_FAILURE=true" >> "$GITHUB_ENV"
    fi
  fi
}
trap cleanup EXIT

main "$@"
