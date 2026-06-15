# CyreneClang Toolchain — Quick Reference

## Struktur

```
cyrene-clang/
├── .github/workflows/
│   ├── build.yml              # Main build pipeline
│   └── sync-patches.yml       # Auto-sync LLVM patches
├── scripts/
│   ├── build.sh               # Core 2-stage PGO+ThinLTO build
│   ├── patch.sh               # Apply patches with fallback
│   ├── package.sh             # Compress + generate manifest
│   ├── notify.sh              # Telegram notifications
│   ├── sync-patches.sh        # Auto-find LLVM stable commits
│   ├── kernel-lto.sh          # Kernel ThinLTO env setup
│   └── check-compat.sh        # Toolchain compatibility check
├── patches/
│   └── 0001-*.patch           # Applied to LLVM before build
├── docs/
│   ├── feature-general.md     # Feature dev template
│   └── feature-specific.md    # Feature prompts
└── README.MD
```

## Build Flags

| Flag | Default | Deskripsi |
|------|---------|-----------|
| `LLVM_BRANCH` | `llvmorg-22.1.0` | LLVM branch/tag |
| `ENABLE_PGO` | `true` | 2-stage PGO build |
| `PGO_WORKLOAD` | `sqlite` | PGO workload (`sqlite`/`kernel`) |
| `LLVM_TARGETS` | `AArch64;ARM;X86` | Target architectures |
| `JOBS` | `$(nproc)` | Parallel jobs |

## Patch Workflow

1. Taruh `.patch` di `patches/`
2. Push ke `main` → build trigger otomatis
3. `patch.sh` apply via `git apply` → `--3way` → `sed` fallback

## Secrets (GitHub Actions)

- `TELEGRAM_BOT_TOKEN` — Bot token
- `TELEGRAM_CHAT_ID` — Channel notif build
- `ERROR_DUMP_CHAT_ID` — Channel error dump

## Kontribusi

- Commit style: `type: description` (e.g. `fix:`, `feat:`, `chore:`)
- Branch: `main` untuk semua
- Patch: format `NNNN-description.patch`
