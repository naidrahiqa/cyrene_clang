# Cara Pakai CyreneClang

Dokumentasi lengkap cara install & pakai CyreneClang buat build kernel Android.

---

## Daftar Isi

1. [Prasyarat](#prasyarat)
2. [Install](#install)
3. [Verifikasi](#verifikasi)
4. [Build Kernel (Modern 5.x/6.x)](#build-kernel-modern)
5. [Build Kernel dengan ThinLTO](#build-kernel-dengan-thinlto)
6. [Build Kernel Legacy (4.x)](#build-kernel-legacy)
7. [Optimasi Polly](#optimasi-polly)
8. [Cek Kompatibilitas](#cek-kompatibilitas)
9. [Troubleshooting](#troubleshooting)

---

## Prasyarat

### Wajib

- **zstd** — CyreneClang pakai format `.tar.zst` (bukan `.tar.gz` seperti Zyc Clang)

```bash
# Ubuntu/Debian
sudo apt install zstd

# Arch
sudo pacman -S zstd

# macOS
brew install zstd
```

### Build Kernel

- `make`, `gcc`/`clang` (host), `bc`, `flex`, `bison`, `libssl-dev`
- Cross-compile toolchain: `aarch64-linux-gnu-gcc` (atau pakai clang sebagai cross-compiler)

---

## Install

### Metode 1: One-liner (Paling Gampang)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/scripts/install.sh)
```

Script ini otomatis:
1. Fetch release terbaru dari GitHub
2. Download & extract ke `./cyrene-clang/`
3. Buat symlink `ld -> ld.lld`
4. Verifikasi installation

Setelah selesai, tambahkan ke PATH:

```bash
export PATH="$(pwd)/cyrene-clang/bin:$PATH"
```

Buat permanent, tambahkan ke `~/.bashrc` atau `~/.zshrc`:

```bash
echo 'export PATH="$HOME/cyrene-clang/bin:$PATH"' >> ~/.bashrc
```

### Metode 2: Manual

```bash
# 1. Download manifest
wget https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/clang-version.txt

# 2. Ambil URL download
DOWNLOAD_URL=$(grep DOWNLOAD_URL clang-version.txt | cut -d= -f2)

# 3. Download tarball
wget "$DOWNLOAD_URL"

# 4. Extract (PERHATIKAN: pakai zstd, bukan gzip)
mkdir -p ~/toolchains
tar -I zstd -xf cyrene-clang-*.tar.zst -C ~/toolchains/

# 5. Fix symlink
cd ~/toolchains/cyrene/bin
ln -sf ld.lld ld

# 6. Tambah PATH
export PATH="$HOME/toolchains/cyrene/bin:$PATH"
```

### Metode 3: Build dari Source

```bash
git clone https://github.com/naidrahiqa/cyrene_clang
cd cyrene_clang
bash scripts/build.sh
```

**WARNING**: Build dari source butuh waktu lama (~3 jam dengan PGO enabled). Pakai `ENABLE_PGO=false` buat build cepat (single-pass).

---

## Verifikasi

Setelah install, cek apakah semuanya benar:

```bash
# Cek versi clang
clang --version

# Output harusnya:
# CyreneClang version 22.1.0 (....)
# Target: aarch64-unknown-linux-gnu

# Cek tools lainnya
ld.lld --version
llvm-ar --version
llvm-nm --version
```

Atau pakai script bawaan:

```bash
bash scripts/check-compat.sh
```

---

## Build Kernel (Modern 5.x/6.x)

### Setup PATH

```bash
export PATH="$HOME/toolchains/cyrene/bin:$PATH"
```

### Basic Kernel Build

```bash
# Set variabel
KERNEL_DIR=/path/to/kernel
OUT_DIR=$KERNEL_DIR/out
ARCH=arm64

# Clean previous build
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

# Configure
make -C $KERNEL_DIR \
  O=$OUT_DIR \
  ARCH=$ARCH \
  CC=clang \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu- \
  defconfig

# Build
make -C $KERNEL_DIR \
  O=$OUT_DIR \
  ARCH=$ARCH \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu- \
  -j$(nproc)
```

### One-liner (Copy-Paste)

```bash
export PATH="$HOME/toolchains/cyrene/bin:$PATH" && \
make -j$(nproc) O=out ARCH=arm64 \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  STRIP=llvm-strip OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu-
```

---

## Build Kernel dengan ThinLTO

ThinLTO bisa meningkatkan performa kernel sampai 10-15%. Pakai helper script:

```bash
# Source script LTO
source scripts/kernel-lto.sh /path/to/kernel

# Lalu build seperti biasa
make -j$(nproc) O=out ARCH=arm64
```

Script ini otomatis:
- Set `CC=clang`, `LD=ld.lld`, `AR=llvm-ar`
- Tambahkan `KCFLAGS="-flto=thin"` dan `KLDFLAGS="-flto=thin"`
- Validasi versi Clang (minimum 12.0)
- Warning kalau kernel < 5.12 (LTO support belum lengkap)

### Manual Tanpa Script

Kalau mau set manual:

```bash
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export KCFLAGS="-flto=thin"
export KLDFLAGS="-flto=thin"

make -j$(nproc) O=out ARCH=arm64 \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu-
```

---

## Build Kernel Legacy (4.14 - 4.20)

Kernel legacy sering punya masalah warning kalau dipakai sama Clang modern. Pakai script khusus:

```bash
bash scripts/kernel-4x-build.sh /path/to/kernel \
  --defconfig=vendor/sdm845-perf_defconfig
```

### Opsi

| Flag | Default | Deskripsi |
|------|---------|-----------|
| `--arch=<arch>` | `arm64` | Target architecture |
| `--defconfig=<name>` | auto-detect | Defconfig yang dipakai |
| `--cross=<prefix>` | `aarch64-linux-gnu-` | Cross-compile prefix |
| `--jobs=<n>` | `nproc` | Parallel jobs |
| `--out=<dir>` | `<kernel>/out` | Output directory |
| `--dry-run` | false | Tampilkan command tanpa eksekusi |
| `--verbose` | false | Tampilkan full output |

### Contoh

```bash
# Samsung kernel 4.19
bash scripts/kernel-4x-build.sh ~/kernel/msm-4.19 \
  --defconfig=vendor/sdm845-perf_defconfig

# Kernel 4.14 ARM (32-bit)
bash scripts/kernel-4x-build.sh ~/kernel/msm-4.14 \
  --arch=arm \
  --cross=arm-linux-gnueabi- \
  --defconfig=vendor/crosshatch_defconfig

# Dry run (lihat command tanpa jalan)
DRY_RUN=true bash scripts/kernel-4x-build.sh ~/kernel/msm-4.19
```

Script ini otomatis menambahkan flag `-Wno-*` buat suppress warning yang muncul di kernel legacy.

---

## Optimasi Polly

Polly adalah loop vectorizer optimizer yang bisa meningkatkan performa kernel. Untuk mengaktifkannya:

```bash
KCFLAGS="-mllvm -polly -mllvm -polly-vectorizer=stripmine" make -j$(nproc) O=out ARCH=arm64 \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  STRIP=llvm-strip OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu-
```

### Flag Polly Tambahan

| Flag | Deskripsi |
|------|-----------|
| `-mllvm -polly` | Aktifkan Polly |
| `-mllvm -polly-vectorizer=stripmine` | Vectorizer strategy |
| `-mllvm -polly-position=early` | Jalankan Polly di awan compilation |
| `-mllvm -polly-register-tiling` | Register tiling optimization |

**Note**: Polly bisa memperlambat compile time. Untuk生产 build, test dulu di environment kamu.

---

## Cek Kompatibilitas

```bash
# Cek toolchain saja
bash scripts/check-compat.sh

# Cek toolchain + kernel
bash scripts/check-compat.sh /path/to/kernel
```

Script ini mengecek:
- Semua LLVM tools ada di PATH dari instalasi yang sama
- Kompatibilitas versi Clang dengan kernel
- Versi `ld.lld` match dengan Clang major version
- Parse `clang-version.txt` untuk metadata

**Exit codes:**
- `0` = PASS — semua check berhasil
- `1` = FAIL — ada error
- `2` = WARN — ada warning tapi tidak fatal

---

## Troubleshooting

### "zstd: command not found"

```bash
sudo apt install zstd
```

### "ld: cannot find -lc" atau linker error

```bash
# Pastikan ld symlink ke ld.lld
cd $HOME/toolchains/cyrene/bin
ln -sf ld.lld ld
``

### Warning banyak di kernel legacy

Pakai `kernel-4x-build.sh` yang otomatis suppress warning:

```bash
bash scripts/kernel-4x-build.sh /path/to/kernel --defconfig=<your_defconfig>
``

### "error: undefined reference" saat ThinLTO

Pastikan pakai `ld.lld` (bukan `ld` GNU):

```bash
export LD=ld.lld
```

### Build lambat

Kalau build pertama lambat, itu normal karena PGO profile collection. Untuk build cepat tanpa PGO:

```bash
ENABLE_PGO=false bash scripts/build.sh
```

### "clang: error: unsupported option '-flto=thin'"

Clang version terlalu lama. CyreneClang 22.1.0 sudah support ThinLTO. Pastikan PATH benar:

```bash
which clang
# Harusnya: /home/user/toolchains/cyrene/bin/clang
```

### Kernel 6.x tidak bisa build

Pastikan Clang >= 14:

```bash
clang --version | head -1
# Harusnya: CyreneClang version 22.1.0
```

---

## Perbedaan dengan Clang Lain

| | CyreneClang | Zyc Clang | Proton Clang |
|---|---|---|---|
| **Versi** | 22.1.0 (bleeding-edge) | 16.0.6 | 17.0.6 |
| **Format** | `.tar.zst` | `.tar.gz` | `.tar.zst` |
| **PGO** | ✓ (2-stage) | ✓ | ✓ |
| **BOLT** | ✓ | ✗ | ✗ |
| **ThinLTO** | ✓ | ✓ | ✓ |
| **Polly** | ✓ | ✓ | ✓ |
| **Target** | Android kernel | Android kernel | Android kernel |
| **Kernel support** | 4.14 - 6.x | 4.14 - 6.x | 4.14 - 6.x |

---

## Referensi Cepat

```bash
# Install
bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/scripts/install.sh)

# Set PATH
export PATH="$HOME/cyrene-clang/bin:$PATH"

# Build kernel
make -j$(nproc) O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm STRIP=llvm-strip OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-

# Build dengan ThinLTO
source scripts/kernel-lto.sh /path/to/kernel && make -j$(nproc) O=out ARCH=arm64

# Build kernel legacy
bash scripts/kernel-4x-build.sh /path/to/kernel --defconfig=<defconfig>

# Cek kompatibilitas
bash scripts/check-compat.sh /path/to/kernel
```
