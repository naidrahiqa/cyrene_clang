---
name: refactoring
description: >
  Gunakan ketika user meminta refactoring, code cleanup, optimasi kode,
  mengurangi tech debt, atau memperbaiki code quality. Aktif jika user
  bilang "refactor", "cleanup", "bersihin", "rapihin", "tech debt",
  "code quality", "duplikasi", "dead code".
---

# Skill Refactoring — Code Cleanup & Quality Improvement

## Prinsip Refactoring
1. **Jangan ubah behavior** — refactoring = restruktur, bukan fitur baru
2. **Satu langkah sekali** — refactor bertahap, jangan overhaul total
3. **Test coverage needed** — jangan refactor kode tanpa test
4. **Boy scout rule** — tinggalkan kode lebih bersih dari sebelumnya
5. **YAGNI** — jangan over-engineering untuk skenario yang belum ada

## Area Refactoring

### 1. Duplikasi Kode (DRY)
Cari:
- Blok kode yang hampir sama di > 1 tempat
- Logic yang bisa di-extract ke function/method
- Magic string/number yang dipakai berulang
- Copy-paste code dari file lain

### 2. Complexitas (KISS)
Cari:
- Function terlalu panjang (> 30 lines)
- Nesting terlalu dalam (> 3 level)
- Multiple responsibility (SRP violation)
- Boolean parameter yang bikin branching
- Nested ternary / ternary chain

### 3. Naming & Readability
Cari:
- Nama fungsi/variabel yang misleading
- Singkatan tidak jelas (`tmp`, `data`, `val`, `foo`)
- Nama yang terlalu generik (`process()`, `handle()`, `doStuff()`)
- Inconsistent naming style (camelCase vs snake_case)
- Magic number tanpa named constant

### 4. Dead Code
Cari:
- Comment-out code (tapi jangan dihapus tanpa izin)
- Function tidak dipanggil
- Import/variable tidak terpakai
- Condition yang selalu true/false
- Code yang di-deadcode karena perubahan flow

### 5. Structure & Organization
Cari:
- File terlalu besar (> 500 lines)
- Class/module punya terlalu banyak tanggung jawab
- Circular dependency
- Global state yang bisa dihindari
- Mix of concerns (UI + logic + data dalam satu file)

### 6. Error Handling
Cari:
- Silent catch (`catch {}` / `except: pass`)
- Error swallowed tanpa logging
- Missing error handling untuk edge cases
- Return code yang diabaikan

## Prosedur Refactoring

### Step 1: Identifikasi
1. Gunakan tools (lint, grep) untuk cari code smell
2. Prioritaskan: duplikasi > kompleksitas > naming > dead code > struktur
3. Buat daftar item refactoring

### Step 2: Analisis Dampak
1. Cari semua referensi ke kode yang akan di-refactor
2. Pastikan behavior tidak berubah
3. Identifikasi test yang perlu diupdate
4. Jika tidak ada test → peringatkan user: "Refactor tanpa test riskan"

### Step 3: Eksekusi
1. Satu refactor per commit/change
2. Ekstrak → rename → simplify → restructure (urutan ini)
3. Jangan campur refactor dengan fix bug atau fitur baru
4. Ikuti gaya kode yang sudah ada di project

### Step 4: Verifikasi
1. Jalankan test suite (jika ada)
2. Jalankan lint & typecheck
3. Bandingkan output sebelum & sesudah (untuk logic refactor)
4. Pastikan tidak ada regression

## Aturan
- JANGAN refactor kode production tanpa test — risiko regression tinggi
- JANGAN hapus comment-out code tanpa tanya user dulu
- JANGAN ganti API signature tanpa update semua caller
- JANGAN refactor > 5 file dalam satu sesi tanpa plan
- JANGAN buat perfect code — cukup better dari sebelumnya
- Jika user bilang "refactor all", tanya scope yang spesifik dulu
- Catat refactoring yang dilakukan di dokumentasi (AGENTS.md)

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `refactoring-engine` |
| **Triggers** | `pr_opened`, `code_review_completed`, `tech_debt_sprint`, `manual_trigger` |
| **Dependencies** | `security-auditor` (run after refactoring to verify security) |
| **Depended By** | — |
| **Workflows** | `pr-review` (step 4), `full-audit` (step 3) |
| **Routing Rule** | Runs after audit + security pass in PR workflow |
