#!/usr/bin/env bash
# Cyrene Clang — Benchmark Script
# Measures compile time, binary size, and memory usage.
# Output: benchmark/results.json + benchmark/chart.svg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BENCH_DIR="$REPO_DIR/benchmark"
RESULTS="$BENCH_DIR/results.json"

# Config
CYRENE_DIR="${CYRENE_DIR:-$HOME/toolchains/cyrene}"
KERNEL_SOURCE="${KERNEL_SOURCE:-}"
RUNS="${RUNS:-3}"
ARCH="${ARCH:-arm64}"

log() { echo -e "\033[1;36m[Benchmark]\033[0m $*"; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

mkdir -p "$BENCH_DIR"

# ─── Validate ────────────────────────────────────────────────────────────────
[[ -x "$CYRENE_DIR/bin/clang" ]] || die "Cyrene Clang not found at $CYRENE_DIR/bin/clang"

if [[ -z "$KERNEL_SOURCE" ]]; then
  # Auto-clone minimal kernel for benchmark
  KERNEL_SOURCE="$BENCH_DIR/kernel-test"
  if [[ ! -d "$KERNEL_SOURCE" ]]; then
    log "Cloning android-mainline kernel (shallow) for benchmark ..."
    git clone --depth=1 --filter=blob:none \
      https://android.googlesource.com/kernel/common \
      "$KERNEL_SOURCE" 2>&1 || die "Failed to clone kernel"
  fi
fi

[[ -d "$KERNEL_SOURCE" ]] || die "Kernel source not found at $KERNEL_SOURCE"

# ─── Detect toolchain version ───────────────────────────────────────────────
CLANG_BIN="$CYRENE_DIR/bin/clang"
CLANG_VERSION=$("$CLANG_BIN" --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
VENDOR=$("$CLANG_BIN" --version | head -1 | awk '{print $1}')
log "Toolchain: $VENDOR $CLANG_VERSION"

# ─── Benchmark function ─────────────────────────────────────────────────────
run_benchmark() {
  local name="$1"
  local cc="$2"
  local lto="${3:-off}"
  local out_dir="$BENCH_DIR/out-$name"
  local log_file="$BENCH_DIR/log-$name.txt"

  log "Running benchmark: $name (LTO=$lto, runs=$RUNS)"

  local total_time=0
  local total_size=0
  local peak_mem=0
  local success=0

  for ((i=1; i<=RUNS; i++)); do
    log "  Run $i/$RUNS ..."

    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    # Build with timing + memory tracking
    local start_time end_time elapsed
    start_time=$(date +%s%N)

    # Use /usr/bin/time for memory tracking if available
    local time_cmd=""
    if command -v /usr/bin/time &>/dev/null; then
      time_cmd="/usr/bin/time -v"
    fi

    local make_args=(
      -C "$KERNEL_SOURCE"
      O="$out_dir"
      ARCH="$ARCH"
      CC="$cc"
      LD=ld.lld
      AR=llvm-ar
      NM=llvm-nm
      STRIP=llvm-strip
      OBJCOPY=llvm-objcopy
      OBJDUMP=llvm-objdump
      CLANG_TRIPLE=aarch64-linux-gnu-
      CROSS_COMPILE=aarch64-linux-gnu-
      -j"$(nproc)"
    )

    # Add LTO flags if enabled
    if [[ "$lto" != "off" ]]; then
      make_args+=(LTO=$lto)
    fi

    # Run defconfig + build
    make "${make_args[@]}" defconfig 2>/dev/null
    $time_cmd make "${make_args[@]}" 2>&1 | tee "$log_file" || true

    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))  # ms

    # Get binary size
    local vmlinux="$out_dir/arch/arm64/boot/Image.gz"
    local size=0
    if [[ -f "$vmlinux" ]]; then
      size=$(stat -c%s "$vmlinux" 2>/dev/null || stat -f%z "$vmlinux" 2>/dev/null || echo 0)
    fi

    # Extract peak memory from /usr/bin/time output
    local mem_kb=0
    if [[ -f "$log_file" ]]; then
      mem_kb=$(grep -oP 'Maximum resident set size \(kbytes\): \K\d+' "$log_file" 2>/dev/null || echo 0)
    fi

    log "    Time: ${elapsed}ms | Size: $(( size / 1024 ))KB | Mem: ${mem_kb}KB"

    total_time=$((total_time + elapsed))
    total_size=$((total_size + size))
    [[ "$mem_kb" -gt "$peak_mem" ]] && peak_mem=$mem_kb
    ((success++)) || true

    # Cleanup between runs
    rm -rf "$out_dir"
  done

  # Calculate averages
  local avg_time=0 avg_size=0
  if [[ $success -gt 0 ]]; then
    avg_time=$((total_time / success))
    avg_size=$((total_size / success))
  fi

  log "  Result: avg_time=${avg_time}ms avg_size=$(( avg_size / 1024 ))KB peak_mem=${peak_mem}KB"

  # Return via global results
  echo "{\"name\":\"$name\",\"version\":\"$CLANG_VERSION\",\"vendor\":\"$VENDOR\",\"lto\":\"$lto\",\"avg_time_ms\":$avg_time,\"avg_size_bytes\":$avg_size,\"peak_mem_kb\":$peak_mem,\"runs\":$success}"
}

# ─── Run benchmarks ─────────────────────────────────────────────────────────
log "=== Cyrene Clang Benchmark ==="
log "Kernel: $KERNEL_SOURCE"
log "Runs per config: $RUNS"
echo ""

RESULTS_ARRAY=()

# Benchmark 1: No LTO (baseline)
RESULTS_ARRAY+=($(run_benchmark "no-lto" "$CLANG_BIN" "off"))

# Benchmark 2: ThinLTO
RESULTS_ARRAY+=($(run_benchmark "thin-lto" "$CLANG_BIN" "thin"))

# Build results JSON
echo "[" > "$RESULTS"
for i in "${!RESULTS_ARRAY[@]}"; do
  echo "  ${RESULTS_ARRAY[$i]}" >> "$RESULTS"
  if [[ $i -lt $((${#RESULTS_ARRAY[@]} - 1)) ]]; then
    echo "," >> "$RESULTS"
  fi
done
echo "]" >> "$RESULTS"

log ""
log "Results saved to: $RESULTS"
log ""

# ─── Generate chart ─────────────────────────────────────────────────────────
log "Generating chart ..."
if command -v python3 &>/dev/null; then
  python3 "$SCRIPT_DIR/generate-chart.py" "$RESULTS" "$BENCH_DIR/chart.svg"
  log "Chart saved to: $BENCH_DIR/chart.svg"
elif command -v python &>/dev/null; then
  python "$SCRIPT_DIR/generate-chart.py" "$RESULTS" "$BENCH_DIR/chart.svg"
  log "Chart saved to: $BENCH_DIR/chart.svg"
else
  log "Python not found, skipping chart generation"
fi

log ""
log "Benchmark complete!"
