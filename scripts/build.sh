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
PGO_WORKLOAD="${PGO_WORKLOAD:-sqlite}"  # "sqlite" (fast) or "kernel" (accurate)

# Targets: AArch64 (Android), ARM (32-bit compat), X86 (host tools)
LLVM_TARGETS="AArch64;ARM;X86"

# Projects to build — polly for loop vectorization, bolt for binary optimization
LLVM_PROJECTS="clang;lld;compiler-rt;polly;bolt"

# Vendor string — appended to clang version (e.g. "CyreneClang 22.1.0")
CLANG_VENDOR="${CLANG_VENDOR:-CyreneClang}"

# ─── Host Compiler Detection ──────────────────────────────────────────────
detect_host_compiler() {
  if command -v clang &>/dev/null; then
    HOST_CC="clang"
    HOST_CXX="clang++"
    HOST_HAS_CLANG=true
  else
    HOST_CC="cc"
    HOST_CXX="c++"
    HOST_HAS_CLANG=false
  fi
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "\n\033[1;36m[CyreneClang]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"

START_EPOCH=$(date +%s)

notify() {
  local type="$1"
  export BUILD_STAGE="${2:-}"
  [[ -x "$NOTIFY_SCRIPT" ]] && bash "$NOTIFY_SCRIPT" "$type" || true
}

build_duration() {
  local now end elapsed h m s
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  h=$((elapsed / 3600))
  m=$(((elapsed % 3600) / 60))
  s=$((elapsed % 60))
  printf "%dh %dm %ds" "$h" "$m" "$s"
}

gen_changelog() {
  local cl="$BUILD_DIR/changelog.txt"
  {
    echo "*Date:* $BUILD_DATE"
    echo "*Branch:* \`$LLVM_BRANCH\`"
    echo "*LLVM Commit:* \`$LLVM_COMMIT\`"
    echo "*PGO:* $ENABLE_PGO | *LTO:* $LTO_MODE"

    local patch_files=("$(dirname "$SCRIPT_DIR")/patches"/*.patch)
    if ls "$(dirname "$SCRIPT_DIR")/patches/"*.patch &>/dev/null 2>&1; then
      echo ""
      echo "*Applied Patches:*"
      for pf in "$(dirname "$SCRIPT_DIR")/patches/"*.patch; do
        local name
        name=$(basename "$pf")
        local subj
        subj=$(grep -m1 '^Subject: ' "$pf" 2>/dev/null | sed 's/^Subject: //' || echo "")
        local BULLET=$'\xE2\x80\xA2' DASH=$'\xE2\x80\x94'
        echo "  $BULLET \`$name\`${subj:+ $DASH $subj}"
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
    -DLLVM_ENABLE_LIBCXX=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCLANG_VENDOR="$CLANG_VENDOR" \
    "$@"
}

# ─── Stage 1: Instrumented Build (PGO profiling) ──────────────────────────────
stage1_build() {
  log "Stage 1: Building instrumented Clang for PGO ..."
  local s1_build="$BUILD_DIR/stage1"
  local s1_install="$BUILD_DIR/stage1-install"

  cmake_configure "$LLVM_DIR" "$s1_build" "$s1_install" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_BUILD_INSTRUMENTED=IR

  cmake --build "$s1_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  cmake --install "$s1_build" 2>&1 | tee -a "$BUILD_DIR/build.log"

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

  # Verify profiles were generated
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

  # Check if any .profraw files were actually generated
  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob

  if (( ${#profiles[@]} == 0 )); then
    warn "No .profraw profile files were generated in $profile_dir."
    return 1
  fi

  # Merge raw profiles into a single .prof file
  log "Merging PGO profiles ..."
  if ! "$BUILD_DIR/stage1-install/bin/llvm-profdata" merge \
    -output="$BUILD_DIR/pgo.prof" \
    "${profiles[@]}"; then
    warn "llvm-profdata merge failed"
    return 1
  fi

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
    -DCOMPILER_RT_ENABLE_LTO=OFF \
    -DLLVM_PROFDATA_FILE="$PGO_PROF" \
    -DLLVM_ENABLE_PLUGINS=ON

  cmake --build "$s2_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  cmake --install "$s2_build" 2>&1 | tee -a "$BUILD_DIR/build.log"
}

# ─── BOLT Post-Build Optimization ────────────────────────────────────────────
# Binary Optimization and Layout Tool — reorders functions/data for better
# cache locality. Typically yields 5-15% speedup on top of PGO + ThinLTO.
apply_bolt() {
  if [[ "$ENABLE_BOLT" != "true" ]]; then
    return 0
  fi

  local clang_bin="$INSTALL_DIR/bin/clang"
  local llvm_bolt="$INSTALL_DIR/bin/llvm-bolt"
  local perf2bolt="$INSTALL_DIR/bin/perf2bolt"

  # Check prerequisites
  if [[ ! -x "$clang_bin" ]]; then
    warn "clang binary not found, skipping BOLT"
    return 0
  fi
  if [[ ! -x "$llvm_bolt" ]]; then
    warn "llvm-bolt not found, skipping BOLT (build llvm-bolt first)"
    return 0
  fi
  if ! command -v perf &>/dev/null; then
    warn "perf not found, skipping BOLT (install linux-tools-generic)"
    return 0
  fi

  log "Applying BOLT optimization to clang ..."

  local bolt_dir="$BUILD_DIR/bolt"
  mkdir -p "$bolt_dir"

  # Step 1: Collect perf profile (run clang on a small workload)
  log "  BOLT: Collecting perf profile ..."
  local perf_data="$bolt_dir/clang.perf.data"

  # Create a minimal C file to compile for profiling
  local test_c="$bolt_dir/test.c"
  cat > "$test_c" <<'TESTEOF'
int main(void) { return 0; }
TESTEOF

  # Record perf events while compiling the test file
  perf record -e cycles:u -j any,u -o "$perf_data" \
    "$clang_bin" -c -O2 -o /dev/null "$test_c" 2>/dev/null || {
    warn "BOLT: perf record failed, skipping"
    return 0
  }

  if [[ ! -s "$perf_data" ]]; then
    warn "BOLT: no perf data collected, skipping"
    return 0
  fi

  # Step 2: Convert perf data to BOLT format
  log "  BOLT: Converting perf data ..."
  local fdata="$bolt_dir/clang.fdata"

  if [[ -x "$perf2bolt" ]]; then
    "$perf2bolt" -p "$perf_data" -o "$fdata" "$clang_bin" 2>/dev/null || {
      warn "BOLT: perf2bolt conversion failed, skipping"
      return 0
    }
  else
    # Fallback: use llvm-bolt's built-in perf conversion
    "$llvm_bolt" -perfdata="$perf_data" -read-only -o /dev/null "$clang_bin" 2>/dev/null || true
    # If that doesn't work, skip BOLT
    warn "BOLT: perf2bolt not found, skipping"
    return 0
  fi

  # Step 3: Apply BOLT optimization
  log "  BOLT: Optimizing clang binary ..."
  local bolted_bin="$bolt_dir/clang.bolt"

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
    local original_size
    original_size=$(stat -c%s "$clang_bin" 2>/dev/null || stat -f%z "$clang_bin" 2>/dev/null || echo 0)
    local bolted_size
    bolted_size=$(stat -c%s "$bolted_bin" 2>/dev/null || stat -f%z "$bolted_bin" 2>/dev/null || echo 0)

    cp "$bolted_bin" "$clang_bin"
    chmod +x "$clang_bin"

    local saved_pct=0
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

  # Use Stage 1 Clang (supports ThinLTO) if available; fall back to system Clang
  local cc="${STAGE1_CC:-}"
  local cxx="${STAGE1_CXX:-}"

  if [[ -z "$cc" || ! -f "$cc" ]]; then
    if [[ "$HOST_HAS_CLANG" == "true" ]]; then
      cc="$HOST_CC"; cxx="$HOST_CXX"
    fi
  fi

  if [[ -n "$cc" && -f "$cc" ]]; then
    cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" \
      -DCMAKE_C_COMPILER="$cc" \
      -DCMAKE_CXX_COMPILER="$cxx" \
      -DLLVM_ENABLE_LTO=Thin \
      -DCOMPILER_RT_ENABLE_LTO=OFF
  else
    warn "No Clang host compiler found — building without ThinLTO"
    LTO_MODE="Off"
    cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" \
      -DLLVM_ENABLE_LTO=OFF
  fi

  cmake --build "$build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  cmake --install "$build" 2>&1 | tee -a "$BUILD_DIR/build.log"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  detect_host_compiler
  BUILD_DATE=$(date -u +%Y-%m-%d)
  LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  LTO_MODE="Thin"
  PATCH_COUNT=0
  if ls "$(dirname "$SCRIPT_DIR")/patches/"*.patch &>/dev/null 2>&1; then
    PATCH_COUNT=$(ls -1 "$(dirname "$SCRIPT_DIR")/patches/"*.patch 2>/dev/null | wc -l)
  fi

  export LLVM_BRANCH BUILD_DATE LLVM_COMMIT LTO_MODE PATCH_COUNT
  export GITHUB_RUN_NUMBER="${GITHUB_RUN_NUMBER:-}"
  export GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
  export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

  # Note: notify started is called by GitHub Actions workflow, not here

  log "Starting CyreneClang build (PGO=$ENABLE_PGO) ..."
  mkdir -p "$BUILD_DIR"

  clone_llvm
  apply_patches

  # Refresh commit after patching
  LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  export LLVM_COMMIT

  BUILD_SUCCESS=false
  if [[ "$ENABLE_PGO" == "true" ]]; then
    stage1_build
    if collect_profiles; then
      stage2_build
      apply_bolt
      BUILD_SUCCESS=true
    else
      warn "PGO profile collection failed. Falling back to non-PGO (simple) build."
      ENABLE_PGO="false"
      export ENABLE_PGO
      simple_build
      BUILD_SUCCESS=true
    fi
  else
    simple_build
    BUILD_SUCCESS=true
  fi

  if [[ "$BUILD_SUCCESS" == "true" ]]; then
    CLANG_VERSION=$("$INSTALL_DIR/bin/clang" --version | head -1 | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
    BUILD_DURATION=$(build_duration)
    export CLANG_VERSION BUILD_DURATION
    export CHANGELOG_FILE=$(gen_changelog)

    log "Build complete! Toolchain installed to: $INSTALL_DIR"
    log "Clang version: $CLANG_VERSION"
    notify success
  fi
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
    BUILD_DURATION=$(build_duration 2>/dev/null || echo "unknown")
    export BUILD_DURATION ERROR_LOG="${ERROR_LOG:-}" BUILD_STAGE="Build Failed"
    export ERROR_DUMP_CHAT_ID="${ERROR_DUMP_CHAT_ID:-}"
    export ERROR_DUMP_FILE="${ERROR_DUMP_FILE:-$BUILD_DIR/build.log}"
    bash "$NOTIFY_SCRIPT" failure || true
    bash "$NOTIFY_SCRIPT" error_dump || true
  fi
}
trap cleanup EXIT

main "$@"