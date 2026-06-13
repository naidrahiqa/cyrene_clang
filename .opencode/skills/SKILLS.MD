# CyreneClang Toolchain — AI Skill

## Project Overview
CyreneClang is a custom LLVM/Clang-based Android kernel toolchain built for balance:
- Maximum performance via PGO + ThinLTO + Polly
- Broad compatibility across Android kernel versions (4.x–6.x)
- Bleeding-edge LLVM base with cherry-picked stable patches
- Automated CI/CD via GitHub Actions
- Distribution via GitHub Releases + `clang-version.txt` manifest

## Repository Structure
```
cyrene-clang/
├── .github/
│   └── workflows/
│       └── build.yml          # Main CI build workflow
├── scripts/
│   ├── build.sh               # Core build script
│   ├── patch.sh               # Apply custom LLVM patches
│   └── package.sh             # Package + generate manifest
├── patches/                   # Custom LLVM patches (git format-patch)
├── docs/
│   └── SKILL.md               # This file
├── clang-version.txt          # Latest release manifest (auto-generated)
└── README.md
```

## Build System
- **Build host**: Ubuntu (GitHub Actions `ubuntu-latest` or `ubuntu-latest-8-core`)
- **Build tool**: CMake + Ninja
- **Source**: `https://github.com/llvm/llvm-project.git`
- **Default branch**: `main` (bleeding edge), pinnable to tags like `llvmorg-18.1.0`

## CMake Configuration (Key Flags)
```cmake
-DCMAKE_BUILD_TYPE=Release
-DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86"
-DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt;polly"
-DLLVM_ENABLE_LTO=Thin
-DLLVM_INCLUDE_TESTS=OFF
-DLLVM_INCLUDE_EXAMPLES=OFF
-DLLVM_INCLUDE_BENCHMARKS=OFF
-DPOLLY_ENABLE_GPGPU_CODEGEN=OFF
-DLLVM_ENABLE_BINDINGS=OFF
-DLLVM_BUILD_DOCS=OFF
```

## PGO Build Flow
CyreneClang uses a 2-stage PGO build:
1. **Stage 1**: Build instrumented Clang with `-DLLVM_BUILD_INSTRUMENTED=IR`
2. **Collect profiles**: Build a sample project (e.g., Linux kernel or SPEC workload) using stage-1 Clang to generate `.profraw` files
3. **Merge profiles**: `llvm-profdata merge -output=pgo.prof *.profraw`
4. **Stage 2**: Rebuild Clang with `-DLLVM_PROFDATA_FILE=pgo.prof`

In GitHub Actions, step 2 is approximated by building a lightweight C workload (e.g., compiling a dummy kernel tree) to get meaningful profile data without requiring a real device.

## Features
| Feature | Status | Notes |
|---|---|---|
| PGO (Profile-Guided Optimization) | ✅ | 2-stage build, IR-based |
| ThinLTO | ✅ | Enabled on toolchain itself |
| Polly Loop Optimizer | ✅ | Available as `-mllvm -polly` |
| Multi-target (AArch64/ARM/x86) | ✅ | All three compiled in |
| Kernel 4.x–6.x support | ✅ | Tested against GKI + older trees |
| Auto-release to GitHub Releases | ✅ | On every successful build |
| `clang-version.txt` manifest | ✅ | Auto-generated post-build |
| Custom patch support | ✅ | Drop `.patch` files in `patches/` |
| Bleeding-edge LLVM sync | ✅ | Weekly scheduled workflow |

## clang-version.txt Format
```
CLANG_VERSION=19.0.0git
LLVM_COMMIT=abc1234def5678
BUILD_DATE=2024-11-01
BUILD_HOST=GitHub Actions
PGO=true
LTO=Thin
TARGETS=AArch64;ARM;X86
DOWNLOAD_URL=https://github.com/USER/cyrene-clang/releases/download/TAG/cyrene-clang.tar.zst
```

## Kernel Integration
To use CyreneClang in a kernel build:
```bash
# Download and extract
wget <DOWNLOAD_URL>
tar -I zstd -xf cyrene-clang.tar.zst -C $HOME/toolchains/cyrene

# Set PATH
export PATH="$HOME/toolchains/cyrene/bin:$PATH"

# Build kernel
make -j$(nproc) \
  O=out ARCH=arm64 \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu-
```

## Patch System
- Patches live in `patches/` as `.patch` files (git format-patch compatible)
- `scripts/patch.sh` applies them in alphabetical order before cmake configure
- Naming convention: `NNNN-description.patch` (e.g., `0001-fix-arm64-abi.patch`)
- To add a new patch: `git format-patch -1 HEAD` inside llvm-project, then drop in `patches/`

## GitHub Actions Workflow Triggers
| Trigger | Action |
|---|---|
| `workflow_dispatch` | Manual build with configurable LLVM branch |
| `schedule: cron` | Weekly auto-sync from LLVM main |
| `push` to `patches/` | Rebuild with updated patches |

## Common AI Tasks in This Project
- **Modify CMake flags**: Edit the `-DFLAG=VALUE` lines in `scripts/build.sh` configure step
- **Add a patch**: Create `.patch` file in `patches/`, update `scripts/patch.sh` if needed
- **Update workflow**: Edit `.github/workflows/build.yml`
- **Debug build failure**: Check CMake configure output first, then ninja error logs
- **Change LLVM version**: Update `LLVM_BRANCH` env var in workflow or pass via `workflow_dispatch` input
- **Tune PGO workload**: Edit the "Collect PGO profiles" step in `build.sh`

## Dependencies (Build Host)
```bash
sudo apt-get install -y \
  cmake ninja-build python3 git \
  clang lld \
  libxml2-dev libedit-dev libncurses5-dev \
  zstd build-essential ca-certificates \
  binutils-aarch64-linux-gnu
```

## Important Notes
- Always use `--depth=1` when cloning LLVM unless bisecting bugs
- LTO on the toolchain itself is `Thin` (not `Full`) to keep RAM usage manageable on 16GB runners
- `zstd` compression is preferred over `gz` for final tarball — significantly smaller + faster
- The `X86` target is included so the toolchain can compile host tools natively
- Never commit generated files (`build/`, `toolchain/`, `*.profraw`, `*.prof`) to the repo