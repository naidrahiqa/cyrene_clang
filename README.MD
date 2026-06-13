# CyreneClang

A custom LLVM/Clang toolchain built for Android kernel compilation — balanced between performance, compatibility, and staying bleeding-edge.

## Features

| Feature | Details |
|---|---|
| **PGO** | 2-stage IR-based Profile-Guided Optimization |
| **ThinLTO** | Applied to the toolchain itself for faster, leaner binaries |
| **Polly** | Loop vectorization optimizer, usable via `-mllvm -polly` |
| **Targets** | AArch64, ARM (32-bit), X86 (host tools) |
| **Kernel support** | 4.x through 6.x (GKI + legacy trees) |
| **Auto-sync** | Weekly rebuild from LLVM `main` |
| **Distribution** | GitHub Releases + `clang-version.txt` manifest |

## Quick Start

```bash
# Get the latest manifest
wget https://raw.githubusercontent.com/YOUR_USER/cyrene-clang/main/clang-version.txt

# Download the toolchain
DOWNLOAD_URL=$(grep DOWNLOAD_URL clang-version.txt | cut -d= -f2)
wget "$DOWNLOAD_URL"

# Extract
mkdir -p $HOME/toolchains
tar -I zstd -xf cyrene-clang-*.tar.zst -C $HOME/toolchains/
```

## Kernel Integration

```bash
export PATH="$HOME/toolchains/cyrene/bin:$PATH"

make -j$(nproc) \
  O=out \
  ARCH=arm64 \
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

### Optional: Enable Polly in your kernel

Add to your kernel `Makefile` or build script:
```bash
KCFLAGS="-mllvm -polly -mllvm -polly-vectorizer=stripmine"
```

## Building from Source

```bash
git clone https://github.com/YOUR_USER/cyrene-clang
cd cyrene-clang
chmod +x scripts/*.sh
bash scripts/build.sh
```

Environment variables:
| Variable | Default | Description |
|---|---|---|
| `LLVM_BRANCH` | `main` | LLVM branch or tag to build |
| `ENABLE_PGO` | `true` | Enable 2-stage PGO build |
| `INSTALL_DIR` | `~/toolchains/cyrene` | Where to install the toolchain |
| `JOBS` | `nproc` | Parallel build jobs |

## Adding Custom Patches

1. Generate a patch from your LLVM working tree:
   ```bash
   git -C llvm-project format-patch -1 HEAD
   ```
2. Move it to `patches/` with a descriptive name:
   ```
   patches/0001-fix-arm64-inline-asm.patch
   ```
3. Push — the workflow auto-triggers on changes to `patches/`.

## Manifest Format (`clang-version.txt`)

```
CLANG_VERSION=19.0.0git
LLVM_COMMIT=abc1234
BUILD_DATE=2024-11-01
BUILD_HOST=GitHub Actions
PGO=true
LTO=Thin
TARGETS=AArch64;ARM;X86
TARBALL_SIZE=350M
DOWNLOAD_URL=https://github.com/YOUR_USER/cyrene-clang/releases/download/.../cyrene-clang.tar.zst
```

## License

LLVM is licensed under the Apache 2.0 License with LLVM exceptions.  
Build scripts in this repo are MIT licensed.