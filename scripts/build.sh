#!/usr/bin/env bash
# CyreneClang — Core Build Script
# Performs a 2-stage PGO + ThinLTO Clang build targeting Android kernels.
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
LLVM_BRANCH="${LLVM_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cyrene}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build}"
LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
JOBS="${JOBS:-$(nproc)}"
ENABLE_PGO="${ENABLE_PGO:-true}"
PGO_WORKLOAD="${PGO_WORKLOAD:-sqlite}"  # "sqlite" (fast) or "kernel" (accurate)

# Targets: AArch64 (Android), ARM (32-bit compat), X86 (host tools)
LLVM_TARGETS="AArch64;ARM;X86"

# Projects to build — polly for loop vectorization
LLVM_PROJECTS="clang;lld;compiler-rt;polly"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "\n\033[1;36m[CyreneClang]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

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
  bash "$(dirname "$0")/patch.sh" "$LLVM_DIR"
}

# ─── CMake Configure Helper ───────────────────────────────────────────────────
cmake_configure() {
  local src="$1" build="$2" install="$3"
  shift 3
  cmake -S "$src/llvm" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DLLVM_TARGETS_TO_BUILD="$LLVM_TARGETS" \
    -DLLVM_ENABLE_PROJECTS="$LLVM_PROJECTS" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_BUILD_DOCS=OFF \
    -DPOLLY_ENABLE_GPGPU_CODEGEN=OFF \
    "$@"
}

# ─── Stage 1: Instrumented Build (PGO profiling) ──────────────────────────────
stage1_build() {
  log "Stage 1: Building instrumented Clang for PGO ..."
  local s1_build="$BUILD_DIR/stage1"
  local s1_install="$BUILD_DIR/stage1-install"

  cmake_configure "$LLVM_DIR" "$s1_build" "$s1_install" \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DLLVM_VP_COUNTERS_PER_SITE=6

  cmake --build "$s1_build" -j"$JOBS"
  cmake --install "$s1_build"

  export STAGE1_CC="$s1_install/bin/clang"
  export STAGE1_CXX="$s1_install/bin/clang++"
}

# ─── PGO Profile Collection: SQLite ───────────────────────────────────────────
collect_sqlite() {
  log "Collecting PGO profiles via SQLite workload ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/cyrene-%p.profraw"

  local workload_dir="$BUILD_DIR/workload"
  mkdir -p "$workload_dir"
  curl -sSL https://www.sqlite.org/2024/sqlite-amalgamation-3460000.zip \
    -o "$workload_dir/sqlite.zip" 2>/dev/null || { warn "SQLite download failed"; return 1; }
  unzip -q "$workload_dir/sqlite.zip" -d "$workload_dir" 2>/dev/null || { warn "SQLite unzip failed"; return 1; }

  "$STAGE1_CC" -O2 -o /dev/null \
    "$workload_dir/sqlite-amalgamation-3460000/sqlite3.c" \
    -lpthread -ldl 2>/dev/null || true
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
    https://android.googlesource.com/kernel/common "$kernel_dir" 2>/dev/null; then
    warn "Kernel clone failed — falling back to SQLite workload"
    return 1
  fi

  pushd "$kernel_dir" > /dev/null
  log "Configuring kernel (defconfig ARCH=arm64) ..."
  make defconfig ARCH=arm64 CC="$STAGE1_CC" 2>/dev/null || { warn "Kernel defconfig failed"; popd > /dev/null; return 1; }

  log "Building kernel subsystems (drivers/gpu + kernel/) ..."
  make -j"$JOBS" ARCH=arm64 CC="$STAGE1_CC" \
    drivers/gpu/ kernel/ 2>/dev/null || \
    warn "Kernel partial build had warnings (profiles may still be valid)"
  popd > /dev/null

  log "Cleaning up kernel source (saves ~2GB) ..."
  rm -rf "$kernel_dir"
}

# ─── PGO Profile Collection ───────────────────────────────────────────────────
collect_profiles() {
  local workload="${PGO_WORKLOAD:-sqlite}"
  log "Collecting PGO profiles (workload: $workload) ..."

  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  if [[ "$workload" == "kernel" ]]; then
    collect_kernel || collect_sqlite
  else
    collect_sqlite
  fi

  # Merge raw profiles into a single .prof file
  log "Merging PGO profiles ..."
  "$BUILD_DIR/stage1-install/bin/llvm-profdata" merge \
    -output="$BUILD_DIR/pgo.prof" \
    "$profile_dir"/*.profraw

  export PGO_PROF="$BUILD_DIR/pgo.prof"
  log "PGO profile ready: $PGO_PROF"
}

# ─── Stage 2: Optimized Final Build ───────────────────────────────────────────
stage2_build() {
  log "Stage 2: Building optimized CyreneClang ..."
  local s2_build="$BUILD_DIR/stage2"

  cmake_configure "$LLVM_DIR" "$s2_build" "$INSTALL_DIR" \
    -DCMAKE_C_COMPILER="$STAGE1_CC" \
    -DCMAKE_CXX_COMPILER="$STAGE1_CXX" \
    -DLLVM_ENABLE_LTO=Thin \
    -DLLVM_PROFDATA_FILE="$PGO_PROF" \
    -DLLVM_ENABLE_PLUGINS=ON

  cmake --build "$s2_build" -j"$JOBS"
  cmake --install "$s2_build"
}

# ─── Simple Build (no PGO) ────────────────────────────────────────────────────
simple_build() {
  log "Building CyreneClang (no PGO) ..."
  local build="$BUILD_DIR/simple"

  cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" \
    -DLLVM_ENABLE_LTO=Thin

  cmake --build "$build" -j"$JOBS"
  cmake --install "$build"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "Starting CyreneClang build (PGO=$ENABLE_PGO) ..."
  mkdir -p "$BUILD_DIR"

  clone_llvm
  apply_patches

  if [[ "$ENABLE_PGO" == "true" ]]; then
    stage1_build
    collect_profiles
    stage2_build
  else
    simple_build
  fi

  log "Build complete! Toolchain installed to: $INSTALL_DIR"
  log "Clang version: $("$INSTALL_DIR/bin/clang" --version | head -1)"
}

main "$@"