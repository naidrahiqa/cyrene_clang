# CyreneClang

A custom LLVM/Clang toolchain built for Android kernel compilation — balanced between performance, compatibility, and staying bleeding-edge.

**Current version**: Clang 22.1.0 | Build #54 | Branch `llvmorg-22.1.0`

## Features

| Feature | Details |
|---|---|
| **PGO** | 2-stage IR-based Profile-Guided Optimization |
| **ThinLTO** | Applied to the toolchain itself for faster, leaner binaries |
| **BOLT** | Binary Optimization and Layout Tool for 5-15% additional speedup |
| **Polly** | Loop vectorization optimizer, usable via `-mllvm -polly` |
| **Memory-aware jobs** | Auto-detects RAM and scales parallel jobs |
| **LTO modes** | Thin (default), Full, or Off — configurable via `LTO_MODE` |
| **Ccache aggressive** | Compression + sloppiness for faster rebuilds |
| **Build profiling** | Per-stage timing in `build_metadata.json` |
| **Targets** | AArch64, ARM (32-bit), X86 (host tools) |
| **Kernel support** | 4.14 through 6.x (GKI + legacy trees) |
| **Auto-sync** | Weekly rebuild from LLVM `main` |
| **Distribution** | GitHub Releases + `clang-version.txt` + `clang_notes.txt` manifests |
| **Telegram notify** | Build status pushed to Telegram channel |

## Quick Start

### One-liner install (recommended)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/scripts/install.sh)
```

### Manual install

```bash
# Get the latest manifest
wget https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/clang-version.txt

# Download the toolchain
DOWNLOAD_URL=$(grep DOWNLOAD_URL clang-version.txt | cut -d= -f2)
wget "$DOWNLOAD_URL"

# Extract
mkdir -p $HOME/toolchains
tar -I zstd -xf cyrene-clang-*.tar.zst -C $HOME/toolchains/

# Fix ld symlink (if needed)
cd $HOME/toolchains/cyrene/bin
ln -sf $(which ld.lld) ld
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

## Kernel LTO Integration

ThinLTO can dramatically improve kernel performance. Use the helper script to set up the environment:

```bash
source scripts/kernel-lto.sh [kernel-source-dir]

# Then run your normal kernel make command
make -j$(nproc) O=out ARCH=arm64 ...
```

The script:
- Validates Clang >= 12.0 (required for ThinLTO)
- Exports `CC=clang`, `LD=ld.lld`, `AR=llvm-ar` with correct `KCFLAGS="-flto=thin"`
- Warns if kernel < 5.12 (incomplete LTO support)
- Parses `clang-version.txt` for build metadata

Works both when sourced (`.`) or executed directly.

## Repository Structure

```
cyrene-clang/
├── .github/workflows/
│   ├── build.yml               # CI/CD pipeline (build + package + release)
│   └── sync-patches.yml        # Auto-sync patches from LLVM stable
├── scripts/
│   ├── build.sh                # CMake configure + 2-stage PGO + BOLT
│   ├── install.sh              # One-liner installer
│   ├── patch.sh                # Apply patches from patches/
│   ├── package.sh              # Compress + generate manifests
│   ├── notify.sh               # Telegram notification helper
│   ├── kernel-lto.sh           # Kernel ThinLTO environment helper
│   ├── sync-patches.sh         # Auto cherry-pick from LLVM stable
│   └── check-compat.sh         # Compatibility validator
├── patches/                    # Custom LLVM patches (format-patch style)
├── docs/
│   ├── SKILL.md                # Full project reference for AI
│   ├── feature-general.md      # General feature dev prompt template
│   └── feature-specific.md     # Specific feature prompts (LTO, PGO, dll)
├── PROMPT.MD                   # OpenCode AI system prompt
├── README.MD
└── .gitignore
```

## Building from Source

```bash
git clone https://github.com/naidrahiqa/cyrene_clang
cd cyrene_clang
chmod +x scripts/*.sh
bash scripts/build.sh
```

Environment variables:
| Variable | Default | Description |
|---|---|---|
| `LLVM_BRANCH` | `llvmorg-22.1.0` | LLVM branch or tag to build |
| `ENABLE_PGO` | `true` | Enable 2-stage PGO build |
| `ENABLE_BOLT` | `true` | Enable BOLT post-build optimization |
| `PGO_WORKLOAD` | `sqlite` | PGO workload: `sqlite` (fast) or `kernel` (accurate) |
| `LTO_MODE` | `Thin` | LTO mode: `Thin`, `Full`, or `Off` |
| `ZSTD_LEVEL` | `19` | Zstd compression level (1-22) |
| `JOBS` | auto | Parallel build jobs (auto-detected from RAM) |
| `CLANG_VENDOR` | `CyreneClang` | Vendor string in clang version output |
| `INSTALL_DIR` | `~/toolchains/cyrene` | Where to install the toolchain |

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

## Telegram Notifications

The CI pipeline sends build status notifications via Telegram Bot API.

### Setup

1. Create a bot via [@BotFather](https://t.me/botfather) and get the token.
2. Get your chat/channel ID.
3. Add secrets to your GitHub repository:
   - `TELEGRAM_BOT_TOKEN` — your bot token
   - `TELEGRAM_CHAT_ID` — target chat/channel ID (e.g. `@channelname` or numeric ID)

Notifications are sent on:
- Build started
- Build success/failure
- New release published

## Manifest Format (`clang-version.txt`)

```
CLANG_VERSION=19.0.0git
LLVM_COMMIT=abc1234
BUILD_DATE=2024-11-01
BUILD_HOST=GitHub Actions
PGO=true
BOLT=true
LTO=Thin
TARGETS=AArch64;ARM;X86
TARBALL_SIZE=350M
SHA256=192f1f685d917735a9a9dc93a034293cc98ae101879c1c46f2f03842de62673b
DOWNLOAD_URL=https://github.com/naidrahiqa/cyrene_clang/releases/download/.../cyrene-clang.tar.zst
```

## Build Notes (`clang_notes.txt`)

Structured metadata file (inspired by greenforce_clang):

```
[date]
2026-06-15

[clang-ver]
Cirrus clang version 22.1.0 (https://github.com/llvm/llvm-project abc1234)

[lld-ver]
LLD 22.1.0 (https://github.com/llvm/llvm-project abc1234) (compatible with GNU linkers)

[llvm-commit]
https://github.com/llvm/llvm-project/commit/abc1234def56789

[host-glibc]
2.35

[size]
38M

[pgo]
true

[bolt]
true

[lto]
Thin

[link-rel]
https://github.com/naidrahiqa/cyrene_clang/releases/download/.../cyrene-clang.tar.zst

[shasum]
192f1f685d917735a9a9dc93a034293cc98ae101879c1c46f2f03842de62673b
```

## Auto Patch Sync

Automatically cherry-pick patches from LLVM stable branches without manual `.patch` file management.

### Config

Edit [`patches/stable-picks.txt`](patches/stable-picks.txt) — one LLVM commit hash per line:
```
# Lines starting with # are ignored
a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
```

### Manual Sync

```bash
bash scripts/sync-patches.sh
```

### Automated Sync (CI)

The workflow `.github/workflows/sync-patches.yml` runs:
- **Every Friday** (before Monday's main build)
- **On demand** via `workflow_dispatch`

It creates a PR with any new patches for review — never pushes directly.

## Compatibility Check

Validate your CyreneClang installation against a kernel tree:

```bash
# Check toolchain only
bash scripts/check-compat.sh

# Check toolchain + kernel compatibility
bash scripts/check-compat.sh ~/kernel/msm-5.15
```

The script checks:
- All LLVM tools present in PATH from the same installation
- Clang version compatibility with kernel (>= 14 for kernel 6.x, >= 12 for LTO)
- `ld.lld` version matches Clang major version
- Parses `clang-version.txt` for build metadata

Output: colored summary with **PASS** / **WARN** / **FAIL** and exit codes (0/1/2).

## Feature Development

For developers adding new features to CyreneClang:

- **[docs/feature-general.md](docs/feature-general.md)** — Template prompt for OpenCode sessions when starting a new feature
- **[docs/feature-specific.md](docs/feature-specific.md)** — Ready-to-use prompts for specific features (kernel LTO, auto patch sync, multi-stage PGO, compatibility checker)

Paste the relevant prompt into OpenCode at the start of a feature development session.

## License

LLVM is licensed under the Apache 2.0 License with LLVM exceptions.
Build scripts in this repo are MIT licensed.
