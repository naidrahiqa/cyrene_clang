# CyreneClang Toolchain — AI Skill

> Lihat file lengkap di `.opencode/skills/SKILLS.MD` (source of truth).
> File ini adalah alias agar `docs/SKILL.md` bisa diakses dari prompt manapun.

## Ringkasan

CyreneClang adalah custom LLVM/Clang toolchain untuk Android kernel:
- PGO 2-stage + ThinLTO + Polly
- Target: AArch64, ARM, X86
- Kernel 4.x–6.x support
- Weekly auto-sync dari LLVM main
- Distribusi via GitHub Releases + `clang-version.txt`

## Struktur

```
cyrene-clang/
├── .github/workflows/build.yml
├── scripts/
│   ├── build.sh
│   ├── patch.sh
│   ├── package.sh
│   └── notify.sh
├── patches/
├── docs/
│   ├── SKILL.md
│   ├── feature-general.md
│   └── feature-specific.md
├── PROMPT.MD
└── README.MD
```

## Panduan Cepat
- **Build flags** → edit `scripts/build.sh` (CMake flags)
- **Patch baru** → taruh `.patch` di `patches/`
- **CI** → `.github/workflows/build.yml`
- **Token/secret** → GitHub Secrets, jangan hardcode:
  - `TELEGRAM_BOT_TOKEN` — bot token (wajib)
  - `TELEGRAM_CHAT_ID` — channel buat notif build (`@naiprojectupdate`)
  - `ERROR_DUMP_CHAT_ID` — channel buat error dump (`@naierrordump`)
- **JANGAN hardcode secret apapun** — chat ID, token, API key harus dari env var, fallback ke kosong (`:-}`) biar aman kalo gak di-set
- **Kompresi** → selalu `zstd`
- **Clone LLVM** → selalu `--depth=1`
