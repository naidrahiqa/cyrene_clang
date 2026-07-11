---
name: opencode-dom-debug-mode
description: >
  Gunakan skill ini ketika user ingin membuat mode di OpenCode supaya AI bisa menggerakkan browser secara mandiri — mengklik elemen, membaca console error, inspect DOM, mencari bug di halaman web tanpa bantuan manusia. Trigger ketika user menyebut: "DOM mode opencode", "AI gerakin browser", "debugging browser di opencode", "chrome devtools opencode", "AI mandiri nyari bug di browser", "browser automation opencode", "opencode bisa klik browser", atau ingin meniru fitur browser agent seperti di Antigravity. Skill ini mencakup setup chrome-devtools-mcp di OpenCode plus cara membuat custom agent/mode khusus untuk DOM debugging.
---

# OpenCode DOM Debug Mode (Browser Agent)

Skill ini memandu cara membuat **DOM debugging mode** di OpenCode — di mana AI bisa **menggerakkan browser secara mandiri**: klik elemen, baca console error, inspect DOM, screenshot, cek network request, semua otomatis.

Ini mirip seperti fitur browser agent di Antigravity — di OpenCode kita pakai **`chrome-devtools-mcp`** sebagai jembatan antara AI dan Chrome.

---

## Cara Kerja

```
OpenCode AI
    ↓  (MCP protocol)
chrome-devtools-mcp
    ↓  (Chrome DevTools Protocol / CDP)
Chrome Browser (port 9222)
    ↓
Halaman web kamu
```

AI bisa: screenshot, klik elemen, isi form, baca DOM, lihat console error, cek network request, jalankan JS di halaman, audit Lighthouse.

---

## Setup: 3 Langkah

### Langkah 1 — Jalankan Chrome dengan remote debugging aktif

Chrome harus dijalankan khusus dengan flag remote debugging. Gunakan profil terpisah supaya tidak bentrok dengan Chrome biasa.

**macOS:**
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-debug-profile
```

**Linux:**
```bash
google-chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-debug-profile
```

**Windows:**
```cmd
"C:\Program Files\Google\Chrome\Application\chrome.exe" ^
  --remote-debugging-port=9222 ^
  --user-data-dir=C:\tmp\chrome-debug-profile
```

> Kalau pakai **Antigravity IDE**, cukup klik ikon Chrome di pojok kanan atas — otomatis jalan di port 9222.

---

### Langkah 2 — Tambahkan chrome-devtools-mcp ke OpenCode config

Edit `opencode.json` di root project (atau `~/.config/opencode/opencode.json` untuk global):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "command": ["npx", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222", "-y"]
    }
  }
}
```

> **Catatan format OpenCode:** `command` harus berupa **array of strings**, bukan string tunggal. `type` harus `"local"` untuk server yang dijalankan lewat stdio.

Tidak perlu install global — `npx` akan download otomatis saat OpenCode pertama kali jalan.

---

### Langkah 3 — Buat custom DOM debug mode

Buat file `.opencode/modes/dom-debug.md` di dalam project:

```markdown
---
temperature: 0.2
tools:
  bash: true
  read: true
  grep: true
  glob: true
  list: true
  write: false
  edit: false
---

Kamu dalam **DOM Debug Mode**. Kamu punya akses ke browser Chrome yang sedang berjalan via chrome-devtools MCP tools.

Saat menginvestigasi bug, ikuti urutan ini:
1. Screenshot halaman — lihat kondisi visual saat ini
2. Baca console browser — cari error atau warning JS
3. Inspect elemen yang bermasalah — periksa DOM, atribut, CSS
4. Cek network request — lihat yang gagal (4xx/5xx)
5. Jalankan JS di browser jika perlu untuk test hipotesis
6. Laporkan temuan: file apa, penyebabnya apa, cara fixnya

Jangan ubah file source code. Hanya investigasi dan laporkan.
```

---

## Cara Pakai

1. Jalankan Chrome dengan remote debugging (langkah 1)
2. Buka halaman yang mau di-debug di Chrome tersebut
3. Jalankan `opencode` di terminal
4. Tekan **Tab** untuk switch ke mode `dom-debug`
5. Kasih perintah ke AI — dia yang kerjain sendiri

### Contoh prompt:

```
Screenshot halaman sekarang, lalu cek apakah ada error di console
```
```
Klik tombol "Submit" dan lihat network request apa yang dikirim
```
```
Inspect elemen dengan class .navbar dan ceritakan strukturnya
```
```
Jalankan document.querySelectorAll('button') di browser dan hitung ada berapa
```
```
Cari kenapa form validasi tidak muncul setelah submit
```

---

## Verifikasi Koneksi

Setelah setup selesai, test dengan prompt ini di OpenCode:

```
Buka https://example.com, ambil screenshot, dan ceritakan apa yang terlihat
```

Kalau AI berhasil screenshot dan describe halamannya — setup sudah berhasil ✅

---

## Tools yang Tersedia via chrome-devtools-mcp

| Tool              | Kemampuan                                              |
|-------------------|--------------------------------------------------------|
| Screenshot        | Foto kondisi halaman saat ini                          |
| Console logs      | Baca error, warning, log dari JS console               |
| DOM query         | Cari elemen, baca atribut, struktur HTML               |
| JS execution      | Jalankan kode JS langsung di halaman                   |
| Network capture   | Monitor HTTP request/response                          |
| Click / type      | Klik elemen, isi input, submit form                    |
| Navigate          | Buka URL, back/forward, reload                         |
| Lighthouse        | Audit performa, aksesibilitas, SEO                     |
| Performance trace | Rekam dan analisis bottleneck rendering                |

---

## Troubleshooting

**Error "cannot connect to browser":**
- Pastikan Chrome sudah jalan dengan `--remote-debugging-port=9222`
- Cek port tidak terpakai: `lsof -i :9222` (Mac/Linux)
- Coba buka `http://localhost:9222/json` di browser lain — harus muncul JSON daftar tab

**MCP tidak terdeteksi OpenCode:**
- Restart OpenCode setelah edit `opencode.json`
- Pastikan format `command` berupa array: `["npx", "chrome-devtools-mcp@latest", ...]`
- Cek Node.js tersedia: `node --version`

**Mode `dom-debug` tidak muncul di Tab switcher:**
- Pastikan file ada di `.opencode/modes/dom-debug.md` (di dalam project)
- Atau `~/.config/opencode/modes/dom-debug.md` untuk global

---

## Referensi

- chrome-devtools-mcp: https://github.com/ChromeDevTools/chrome-devtools-mcp
- OpenCode MCP config: https://opencode.ai/docs/mcp-servers
- OpenCode modes: https://opencode.ai/docs/modes

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `opencode-dom-debug-mode` |
| **Triggers** | `dom_debug_requested`, `browser_issue`, `frontend_debug`, `manual_trigger` |
| **Dependencies** | Chrome DevTools MCP (external agent) |
| **Depended By** | — (standalone debugging tool) |
| **Workflows** | Not part of automated workflows (manual trigger only) |
| **Routing Rule** | User requests browser/DOM debugging → load this skill |