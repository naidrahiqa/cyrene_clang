---
name: planning
description: >
  Gunakan ketika user meminta bantuan merencanakan arsitektur, desain sistem,
  alur kerja, atau task planning sebelum coding dimulai. Aktif ketika user
  bilang "plan", "rancang", "arsitektur", "desain", "flow", "roadmap".
---

# Skill Planning — Arsitektur & Perencanaan

## Tujuan
Memastikan setiap pekerjaan coding dimulai dengan perencanaan yang matang:
- Pahami problem domain sebelum menulis kode
- Desain arsitektur/solusi yang maintainable
- Identifikasi risiko dan dependensi sejak awal
- Dokumenkan keputusan arsitektur

## Prosedur Planning

### Step 1: Analisis Kebutuhan
1. Baca deskripsi task dari user — apa yang sebenarnya diminta?
2. Identifikasi constraint dan batasan (OS, env, dependencies)
3. Tentukan scope: apa yang INCLUDE dan EXCLUDE
4. Cari file yang relevan di project (Read/Grep/Glob)

### Step 2: Eksplorasi Codebase
1. Pahami struktur project yang ada
2. Identifikasi pola yang sudah dipakai
3. Cari integrasi points (file yang perlu diubah)
4. Catat dependencies yang dibutuhkan

### Step 3: Desain Solusi
1. Tulis opsi-opsi pendekatan (minimal 2 opsi)
2. Evaluasi trade-off tiap opsi: complexity, maintainability, performance
3. Pilih opsi terbaik dengan alasan yang jelas
4. Buat file structure / component tree jika relevan

### Step 4: Dokumentasi Plan
Format output ke user:
```
## Plan: [Judul Task]

### Tujuan
- [deskripsi tujuan]

### File yang Terlibat
- [path/file1] — [perubahan]
- [path/file2] — [perubahan]

### Pendekatan
- **Opsi 1**: [deskripsi]
  - Pro: [alasan]
  - Kontra: [alasan]
- **Opsi 2**: [deskripsi]
  - Pro: [alasan]
  - Kontra: [alasan]

### Pilihan: [Opsi terpilih]
Alasan: [penjelasan]

### Langkah Eksekusi
1. [step-by-step]
2. [step-by-step]
3. [step-by-step]

### Risiko
- [risiko] — [mitigasi]
```

### Step 5: Validasi Plan
1. Tanya user: "Apakah plan ini OK? Mau lanjut eksekusi?"
2. Jika user setuju → mulai coding
3. Jika user revisi → update plan
4. Jika user cancel → simpan plan untuk referensi nanti

## Aturan
- JANGAN langsung coding sebelum plan disetujui user
- JANGAN buat plan yang terlalu abstrak — harus actionable
- JANGAN skip identifikasi risiko
- Prioritas: kesederhanaan > kompleksitas, maintainability > cleverness
- Jika task kecil (< 3 file), plan bisa ringkas — tidak perlu formal

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `planning` |
| **Triggers** | `new_feature`, `architecture_change`, `sprint_planning`, `manual_trigger` |
| **Dependencies** | `master-reference` (project context), `universal-audit` (current state audit) |
| **Depended By** | — (strategic skill, produces plans for execution) |
| **Workflows** | `llvm-update-check` (step 2 — impact assessment) |
| **Routing Rule** | Files changed in `.github/workflows/` or `docs/` → route to `planning` |
