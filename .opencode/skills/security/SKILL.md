---
name: security
description: >
  Gunakan ketika user meminta security review, vulnerability assessment,
  hardening, atau audit keamanan. Aktif jika user bilang "security",
  "vulnerability", "CVE", "hardening", "audit", "hack", "secure".
---

# Skill Security — Security Review & Hardening

## Prinsip Keamanan
1. **Defense in depth** — jangan bergantung pada satu lapisan keamanan
2. **Least privilege** — beri akses minimal yang diperlukan
3. **Never trust user input** — validasi, sanitasi, escape
4. **Keep secrets secret** — no hardcoded keys, tokens, passwords
5. **Fail securely** — default-deny, jangan bocorkan info di error

## Area Cek Keamanan

### 1. Hardcoded Secrets
Cari pola:
- API keys, tokens (`sk-...`, `ghp_...`, `AKIA...`, dll)
- Password / connection strings
- Private keys (`-----BEGIN...`)
- Yang harus ada di env var / vault, bukan di source code

### 2. Input Validation
- SQL injection (`$query = "SELECT * FROM users WHERE id = $input"`)
- Command injection (`exec("rm $filename")`)
- Path traversal (`open("/var/" + userInput)`)
- XSS (`innerHTML = userInput`, `dangerouslySetInnerHTML`)
- SSRF (user-controlled URL di server-side request)
- File upload (ekstensi, size, content-type validation?)

### 3. Authentication & Authorization
- Password storage (hash + salt? bcrypt/argon2?)
- Session management (secure cookies, httpOnly, sameSite)
- JWT (signature verification, expiry, alg=none?)
- Rate limiting di login endpoint?
- Role-based access control (RBAC) sudah benar?

### 4. Dependency Security
- Cek `package.json`, `requirements.txt`, `go.mod`, `Cargo.toml` untuk:
  - Known CVEs (gunakan npm audit / safety / cargo audit)
  - Versi lawas dengan known vuln
  - Dependency yang tidak terpakai (bloat + attack surface)

### 5. Data Protection
- HTTPS everywhere?
- Sensitive data di client-side?
- Logging: apakah log mengandung password/token?
- Error handling: jangan expose stack trace ke user
- Local storage / SharedPreferences untuk data sensitif?

### 6. Environment & Config
- Debug mode aktif di production?
- CORS terlalu permisif (`Access-Control-Allow-Origin: *`)?
- Security headers: CSP, HSTS, X-Frame-Options, X-Content-Type-Options
- Docker: root user? exposed ports? secrets di image layer?

## Prosedur Security Review

### Step 1: Scope
1. Tentukan apa yang di-review (full project atau feature tertentu)
2. Fokus pada: input handling, auth, data flow, dependency

### Step 2: Scan
1. Cari hardcoded secrets (Grep pattern)
2. Cek input validation di setiap endpoint/function
3. Cek dependency dengan versi dan known vuln
4. Cek konfigurasi security

### Step 3: Report
Format output:
```
## Security Review: [Scope]

### CRITICAL
- [findings] — [file:line] — [impact] — [fix]

### HIGH
- [findings] — [file:line] — [impact] — [fix]

### MEDIUM
- [findings] — [file:line] — [impact] — [fix]

### LOW / INFO
- [findings] — [file:line] — [saran]

### Summary
- Critical: [n]
- High: [n]
- Medium: [n]
- Low/Info: [n]
- Risk Level: [Low/Medium/High/Critical]
```

### Step 4: Fix
1. Prioritaskan Critical > High > Medium
2. Jangan ubah logic bisnis — hanya perbaiki security
3. Verifikasi setiap fix tidak break fungsionalitas
4. Jangan commit secrets ke git history

## Aturan
- JANGAN merasa aman hanya karena "small project" — small project juga kena hack
- JANGAN bilang "ini aman" tanpa bukti — validasi dengan check
- JANGAN skip dependency check — supply chain attack itu nyata
- Jika menemukan hardcoded secret di commit history, laporkan segera
- Jika tidak yakin dengan severity, tanya user

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `security-auditor` |
| **Triggers** | `code_push`, `dependency_update`, `pr_opened`, `scheduled_weekly`, `tag_created` |
| **Dependencies** | `master-reference` (project context) |
| **Depended By** | `refactoring-engine` (post-security verification) |
| **Workflows** | `pr-review` (step 3), `release-build` (step 3), `daily-build` (step 2), `full-audit` (step 2) |
| **Routing Rule** | `dependency_update` → `security-auditor` strict mode |
| **Severity Actions** | CRITICAL → block merge + Telegram; HIGH → GitHub issue |
