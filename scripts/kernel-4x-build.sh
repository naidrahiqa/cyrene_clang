#!/usr/bin/env bash
# CyreneClang — Kernel 4.x Build Helper
# Optimized for legacy kernels (4.14, 4.19, 4.20) with modern Clang 22.
# Usage: bash scripts/kernel-4x-build.sh <kernel-dir> [options]
# NOTE: This script does NOT modify any existing CyreneClang scripts.
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
CYRENE_ROOT="${CYRENE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="$CYRENE_ROOT/clang-version.txt"

# Defaults
KERNEL_DIR=""
ARCH="${ARCH:-arm64}"
DEFCONFIG="${DEFCONFIG:-}"
JOBS="${JOBS:-$(nproc)}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"
OUT_DIR="${OUT_DIR:-}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Flags for kernel 4.x compatibility (suppress modern Clang warnings)
WARN_SUPPRESS=(
  -Wno-unused-function
  -Wno-unused-variable
  -Wno-unused-but-set-variable
  -Wno-address-of-packed-member
  -Wno-shift-negative-value
  -Wno-pointer-sign
  -Wno-misleading-indentation
  -Wno-bool-compare
  -Wno-maybe-uninitialized
  -Wno-array-bounds
  -Wno-shift-overflow
  -Wno-implicit-fallthrough
  -Wno-format
  -Wno-format-security
  -Wno-tautological-compare
  -Wno-missing-field-initializers
  -Wno-self-assign
  -Wno-pointer-sign
  -Wno-incompatible-pointer-types
  -Wno-deprecated-declarations
  -Wno-constant-conversion
  -Wno-parentheses-equality
  -Wno-empty-body
  -Wno-uninitialized
  -Wno-dangling-else
  -Wno-logical-op-parentheses
  -Wno-precedence
)

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()   { echo -e "\033[1;36m[Kernel-4x]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }

usage() {
  cat << EOF
CyreneClang — Kernel 4.x Build Helper

Usage: $0 <kernel-dir> [options]

Options:
  --arch=<arch>          Target architecture (default: arm64)
  --defconfig=<name>     Use specific defconfig (default: defconfig)
  --cross=<prefix>       Cross-compile prefix (default: aarch64-linux-gnu-)
  --jobs=<n>             Parallel jobs (default: nproc)
  --out=<dir>            Output directory (default: <kernel-dir>/out)
  --dry-run              Show commands without executing
  --verbose              Show full make output

Environment variables:
  ARCH                   Target architecture
  CROSS_COMPILE          Cross-compile prefix
  CLANG_TRIPLE           Target triple for Clang
  JOBS                   Number of parallel jobs
  OUT_DIR                Output directory
  KCFLAGS                Additional kernel C flags
  DRY_RUN                Set to 'true' to dry-run

Examples:
  $0 ~/kernel/msm-4.19
  $0 ~/kernel/msm-4.19 --defconfig=vendor/sdm845-perf_defconfig
  $0 ~/kernel/msm-4.19 --arch=arm --cross=arm-linux-gnueabi-
  DRY_RUN=true $0 ~/kernel/msm-4.19  # dry run

EOF
  exit 0
}

# ─── Parse Arguments ──────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch=*)      ARCH="${1#*=}" ;;
      --defconfig=*) DEFCONFIG="${1#*=}" ;;
      --cross=*)     CROSS_COMPILE="${1#*=}" ;;
      --jobs=*)      JOBS="${1#*=}" ;;
      --out=*)       OUT_DIR="${1#*=}" ;;
      --dry-run)     DRY_RUN=true ;;
      --verbose)     VERBOSE=true ;;
      --help|-h)     usage ;;
      -*)            die "Unknown option: $1" ;;
      *)
        if [[ -z "$KERNEL_DIR" ]]; then
          KERNEL_DIR="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  [[ -n "$KERNEL_DIR" ]] || { usage; }
  [[ -d "$KERNEL_DIR" ]] || die "Kernel directory not found: $KERNEL_DIR"
  [[ -f "$KERNEL_DIR/Makefile" ]] || die "No Makefile found in: $KERNEL_DIR"

  OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"
}

# ─── Detect Kernel Version ──────────────────────────────────────────────────
detect_kernel() {
  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
  KERNEL_V="${kv:-0}"
  KERNEL_P="${kp:-0}"
  KERNEL_FULL="$KERNEL_V.$KERNEL_P"

  info "Kernel version: $KERNEL_FULL"

  if [[ "$KERNEL_V" -lt 4 || ("$KERNEL_V" -eq 4 && "$KERNEL_P" -lt 14) ]]; then
    warn "Kernel < 4.14 may have issues with modern Clang. Proceed with caution."
  fi
  if [[ "$KERNEL_V" -ge 5 ]]; then
    warn "Kernel >= 5.x detected. Consider using kernel-lto.sh instead."
  fi
}

# ─── Detect Toolchain ──────────────────────────────────────────────────────
detect_toolchain() {
  log "Detecting CyreneClang toolchain ..."

  if ! command -v clang &>/dev/null; then
    die "clang not found in PATH. Install CyreneClang first."
  fi

  CLANG_VER=$(clang --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
  CLANG_MAJOR=$(clang --version | head -1 | grep -oP '\d+' | head -1 || echo "0")

  info "Clang version: $CLANG_VER (major: $CLANG_MAJOR)"

  # Check required tools
  local missing=()
  for tool in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing tools: ${missing[*]}"
  fi

  # Parse manifest if available
  if [[ -f "$MANIFEST" ]]; then
    CLANG_VERSION_MANIFEST=$(grep -oP 'CLANG_VERSION=\K.*' "$MANIFEST" 2>/dev/null || echo "")
    PGO_STATUS=$(grep -oP 'PGO=\K.*' "$MANIFEST" 2>/dev/null || echo "unknown")
    info "Manifest: Clang $CLANG_VERSION_MANIFEST, PGO=$PGO_STATUS"
  fi
}

# ─── Detect Defconfig ──────────────────────────────────────────────────────
detect_defconfig() {
  if [[ -n "$DEFCONFIG" ]]; then
    log "Using specified defconfig: $DEFCONFIG"
    return
  fi

  log "Auto-detecting defconfig ..."

  # Common defconfig names for Android kernels
  local candidates=(
    "defconfig"
    "vendor/${ARCH}-perf_defconfig"
    "vendor/${ARCH}-perf-gki_defconfig"
    "gki_${ARCH}_defconfig"
    "${ARCH}_defconfig"
    "msm_defconfig"
    "pixel_defconfig"
  )

  for dc in "${candidates[@]}"; do
    if [[ -f "$KERNEL_DIR/arch/$ARCH/configs/$dc" ]]; then
      DEFCONFIG="$dc"
      info "Found defconfig: $dc"
      return
    fi
  done

  # Try to find any defconfig
  local found
  found=$(find "$KERNEL_DIR/arch/$ARCH/configs" -maxdepth 1 -name "*defconfig*" -type f | head -1 || true)
  if [[ -n "$found" ]]; then
    DEFCONFIG=$(basename "$found")
    info "Using first defconfig found: $DEFCONFIG"
  else
    die "No defconfig found for ARCH=$ARCH in $KERNEL_DIR/arch/$ARCH/configs/"
  fi
}

# ─── Clean Previous Build ──────────────────────────────────────────────────
clean_build() {
  if [[ -d "$OUT_DIR" ]]; then
    log "Cleaning previous build at $OUT_DIR ..."
    rm -rf "$OUT_DIR"
  fi
  mkdir -p "$OUT_DIR"
}

# ─── Configure Kernel ──────────────────────────────────────────────────────
configure_kernel() {
  log "Configuring kernel with $DEFCONFIG ..."

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    "$DEFCONFIG"
  )

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" 2>&1 | grep -E "^\*|error|warning" || true
  fi

  info "Kernel configured successfully."
}

# ─── Build Kernel ──────────────────────────────────────────────────────────
build_kernel() {
  log "Building kernel (jobs=$JOBS) ..."

  # Build KCFLAGS string
  local kcflags=("${WARN_SUPPRESS[@]}")

  # Add user-specified KCFLAGS
  if [[ -n "${KCFLAGS:-}" ]]; then
    IFS=' ' read -ra extra_flags <<< "$KCFLAGS"
    kcflags+=("${extra_flags[@]}")
  fi

  local kcflags_str="${kcflags[*]}"

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    KCFLAGS="$kcflags_str"
    -j"$JOBS"
  )

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  log "KCFLAGS: $kcflags_str"

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    # Capture output, show only errors and progress
    local build_log="$OUT_DIR/build.log"
    "${cmd[@]}" 2>&1 | tee "$build_log" | {
      grep -E "^\*|error:|warning:|LD |OBJCOPY |CC |AR " || true
    }
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -ne 0 ]]; then
      warn "Build failed! Check log: $build_log"
      warn "Last 20 lines of build log:"
      tail -20 "$build_log" 2>/dev/null || true
      return $exit_code
    fi
  fi

  info "Build completed successfully!"
}

# ─── Generate Image ────────────────────────────────────────────────────────
generate_image() {
  log "Generating kernel image ..."

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    KCFLAGS="${WARN_SUPPRESS[*]}"
    -j"$JOBS"
    Image
  )

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" 2>&1 | grep -E "OBJCOPY|Image|error" || true
  fi

  # Check for generated image
  local image_path=""
  for path in \
    "$OUT_DIR/arch/$ARCH/boot/Image" \
    "$OUT_DIR/arch/$ARCH/boot/Image.gz" \
    "$OUT_DIR/arch/$ARCH/boot/Image.gz-dtb" \
    "$OUT_DIR/arch/$ARCH/boot/Image.bz2"; do
    if [[ -f "$path" ]]; then
      image_path="$path"
      break
    fi
  done

  if [[ -n "$image_path" ]]; then
    local size
    size=$(du -sh "$image_path" | cut -f1)
    info "Kernel image: $image_path ($size)"
  else
    warn "No kernel image found in $OUT_DIR/arch/$ARCH/boot/"
  fi
}

# ─── Build Summary ──────────────────────────────────────────────────────────
print_summary() {
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local h=$((duration / 3600))
  local m=$(((duration % 3600) / 60))
  local s=$((duration % 60))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Build Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Kernel:   $KERNEL_FULL"
  info "Arch:     $ARCH"
  info "Clang:    $CLANG_VER"
  info "Output:   $OUT_DIR"
  info "Duration: ${h}h ${m}m ${s}s"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Show final disk usage
  df -h / 2>/dev/null | tail -1 || true
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  START_TIME=$(date +%s)

  log "CyreneClang — Kernel 4.x Build Helper"
  echo ""

  parse_args "$@"
  detect_kernel
  detect_toolchain
  detect_defconfig

  log "Configuration:"
  info "  Kernel dir:  $KERNEL_DIR"
  info "  Output dir:  $OUT_DIR"
  info "  Arch:        $ARCH"
  info "  Defconfig:   $DEFCONFIG"
  info "  Jobs:        $JOBS"
  info "  Cross:       $CROSS_COMPILE"
  info "  Clang triple: $CLANG_TRIPLE"
  echo ""

  clean_build
  configure_kernel
  build_kernel
  generate_image
  print_summary
}

main "$@"
