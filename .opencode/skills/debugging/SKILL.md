---
name: debugging
description: >
  Gunakan ketika user melaporkan error, bug, crash, unexpected behavior,
  atau ketika build/test gagal. Aktif jika user bilang "error", "bug",
  "crash", "gagal", "fail", "broken", "tidak jalan", "wrong output".
---

# Skill Debugging — Error Resolution & Bug Fixing

## Prinsip Debugging
1. **Reproduce dulu** — pahami error sebelum menyentuh kode
2. **Baca log/error message** — seringkali jawabannya ada di sana
3. **Isolasi masalah** — cari variable mana yang menyebabkan
4. **Satu perubahan sekali** — jangan ubah banyak hal sekaligus
5. **Verifikasi fix** — pastikan error benar-benar hilang

## Prosedur Debugging

### Step 1: Kumpulkan Informasi
1. Baca error message / stack trace dengan seksama
2. Cek file:line yang disebut di error
3. Tanyakan (atau cari): kapan terakhir berfungsi? Apa yang berubah?
4. Cek environment: OS, versi tools, dependencies

### Step 2: Reproduksi
1. Jalankan command yang menghasilkan error
2. Catat output lengkap (jangan dipotong)
3. Jika intermittent, cari pattern (kondisi tertentu?)
4. Jika tidak bisa direproduksi → tanya user langkah detail

### Step 3: Diagnosa
1. Baca kode di lokasi error (Read)
2. Cari akar masalah:
   - **Syntax/compile error**: typo, import salah, versi tidak cocok
   - **Runtime error**: null pointer, undefined variable, type mismatch
   - **Logic error**: kondisi salah, off-by-one, infinite loop
   - **Dependency error**: library version mismatch, missing package
   - **Environment error**: PATH, permission, port conflict
3. Trace alur data dari input ke titik error
4. Jika perlu, tambahkan logging sementara untuk memverifikasi

### Step 4: Perbaiki
1. Tulis fix minimal — hanya ubah apa yang perlu
2. Ikuti konvensi kode yang ada
3. Jangan tambah fitur baru saat debugging
4. Jika fix butuh perubahan besar → plan dulu

### Step 5: Verifikasi
1. Jalankan ulang command yang tadinya error
2. Jalankan test yang relevan
3. Jalankan lint/typecheck
4. Pastikan tidak ada regression di bagian lain

## Checklist Debugging Cepat

| Gejala | Cek Pertama |
|--------|-------------|
| Build error | Compiler error message, missing import |
| Runtime crash | Stack trace, null check, type check |
| Wrong output | Logic trace, edge cases, test cases |
| Performance | Loop analysis, query count, memory |
| Network | API response, timeout, auth token |
| Database | Query syntax, schema, connection |
| Dependency | Version mismatch, lockfile, install |

## Aturan
- JANGAN tebak-nebak fix. Baca kode dulu.
- JANGAN ubah banyak file sekaligus — sulit di-rollback.
- JANGAN ignore error message — itu petunjuk utama.
- Jika stuck > 10 menit, cari pattern berbeda atau tanya user.
- Jika fix melibatkan perubahan > 3 file, buat plan dulu.

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `debugging` |
| **Triggers** | `build_failure`, `test_failure`, `crash_report`, `ci_failure`, `manual_trigger` |
| **Dependencies** | `master-reference` (known issues), `compiler-build-optimizer` (build context) |
| **Depended By** | — (consumer skill, triggered on failures) |
| **Workflows** | `pr-review` (step 6 — fallback if others fail) |
| **Routing Rule** | `build_failure` → route to `debugging` with `compiler-build-optimizer` + `llvm-runtimes-fixer` context |
| **Data Flow** | Receives build logs from `compiler-build-optimizer`; routes to `llvm-runtimes-fixer` if error matches known signature |
