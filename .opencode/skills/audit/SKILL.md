---
name: universal-audit
description: >
  UNIVERSAL project auditor — ANY language, ANY framework, ANY path.
  Use when user says "audit ai", "audit", "cek code", "scan project",
  "review code", "bug hunt", "code review", "cek bug", or asks to
  analyze any project. Auto-detects project type from file signatures
  and applies tailored audit rules. Falls back if customrom-fix matches.
---

# Universal Audit Skill v2

> Audit otomatis untuk SEMUA jenis project. Gak peduli bahasa, framework,
> atau stack — ngedeteksi sendiri jenisnya dari file yang ada, milah aturan
> audit yang sesuai, dan lapor objektif tanpa basa-basi.

---

## CARA DETEKSI PROJECT TYPE (Auto)

Kalo dikasih path project (atau pake CWD), jalanin deteksi ini:

### 1. Cek File Signature (Priority Order)

Berdasarkan file yang ADA di root project (bukan extension doang):

| Signature File(s) | Project Type |
|---|---|
| `KernelSU/` + `Makefile` + `*.c` + `Kconfig` | Android Kernel Module (GKI) |
| `module.prop` + `service.sh` + `customize.sh` | KernelSU / Magisk Module |
| `Cargo.toml` | Rust (Cargo) |
| `go.mod` | Go (Golang) |
| `package.json` + `next.config.*` | Next.js |
| `package.json` + `vite.config.*` + `react` in deps | React + Vite |
| `package.json` + `vite.config.*` | Vite (Vanilla/Vue/Svelte) |
| `package.json` + `nuxt.config.*` | Nuxt.js |
| `package.json` + `angular.json` | Angular |
| `package.json` + `svelte.config.*` | SvelteKit |
| `package.json` + `expo/` or `react-native` in deps | React Native |
| `package.json` (standalone) | Node.js / npm project |
| `composer.json` | PHP + Composer / Laravel |
| `pom.xml` | Java Maven |
| `build.gradle` (`.kts` / `.groovy`) | Java/Android Gradle |
| `gradlew` + `build.gradle` | Android / Java Gradle Wrapper |
| `requirements.txt` or `pyproject.toml` or `setup.py` | Python |
| `Cargo.toml` + `esp-rs` or `no_std` | Embedded Rust |
| `CMakeLists.txt` | C/C++ CMake |
| `Makefile` + `*.c` | C / Kernel / Makefile project |
| `*.csproj` or `*.sln` | C# .NET |
| `Package.swift` | Swift Package Manager |
| `mix.exs` | Elixir / Phoenix |
| `rebar.config` or `mix.exs` | Erlang / Elixir |
| `Gemfile` | Ruby on Rails / Ruby |
| `Cargo.toml` | Rust |
| `index.html` + `*.js` + `*.css` | Vanilla HTML/JS/CSS |
| `docker-compose.yml` + `Dockerfile` | Docker Project |
| `pubspec.yaml` | Dart / Flutter |
| `*.sql` + no other config | SQL / Database Project |
| `.github/workflows/` | GitHub Actions (CI/CD) |
| `*.tf` + `terraform` | Terraform / IaC |
| `*.py` + `*.ipynb` | Jupyter Notebook / Data Science |
| `*.zig` + `build.zig` | Zig |
| `*.dart` (standalone) | Dart CLI |

### 2. Fallback: Extension-Based Detection

Kalo gak ada signature file, detek dari extension dominan di project:

| Dominant Extension | Assumed Type |
|---|---|
| `.py` | Python |
| `.js` / `.jsx` | JavaScript |
| `.ts` / `.tsx` | TypeScript |
| `.java` | Java |
| `.c` / `.h` | C |
| `.cpp` / `.hpp` / `.cc` | C++ |
| `.rs` | Rust |
| `.go` | Go |
| `.rb` | Ruby |
| `.php` | PHP |
| `.swift` | Swift |
| `.kt` / `.kts` | Kotlin |
| `.cs` | C# |
| `.vue` | Vue |
| `.svelte` | Svelte |
| `.r` / `.R` | R |
| `.lua` | Lua |
| `.ex` / `.exs` | Elixir |
| `.zig` | Zig |
| `.dart` | Dart |
| `.sql` | SQL |
| `.sh` / `.bash` | Shell Script |
| `.ps1` | PowerShell |
| `.yml` / `.yaml` | YAML Config |
| `.toml` | TOML Config |
| `.json` | JSON Config |
| `.md` | Documentation |
| `.html` | HTML |
| `.css` / `.scss` / `.less` | Stylesheet |
| `.tf` | Terraform |

### 3. Final Fallback

Kalo masih gak ketemu, scan `ls` root project dan lapor ke user:
"Project di `<path>` gak bisa dideteksi otomatis. Isinya: <list file>. Mau audit pake aturan umum aja?"

---

## TAHAP AUDIT (Universal)

6 tahap yang jalan untuk SEMUA jenis project:

### Tahap 1: Struktur & Completeness
- Semua file yang dibutuhkan sesuai jenis project exist?
- `package.json` / `go.mod` / `Cargo.toml` / `requirements.txt` — dependencies proper?
- Ada file duplikat, kosong, atau gak kepake?
- `.gitignore` proper buat jenis project ini?
- Entry point ada? (main.go, main.py, index.js, main.rs, dll)
- Config files valid? (tsconfig, vite.config, next.config, dll)

### Tahap 2: Kontradiksi & Dokumentasi
- Kode bilang A, README/docs bilang B?
- Comment bilang X, implementasi Y?
- Version number di config vs actual release?
- Nama fungsi/variabel misleading?
- Changelog ngaku fix tapi kode masih sama?

### Tahap 3: Security & Best Practices
- **Web (JS/TS):** XSS, CSRF, SQL injection, hardcoded API keys/tokens, dependency vuln
- **Go:** Error ignored, goroutine leak, race condition, context not propagated
- **Rust:** Unsafe block justification, unwrap() spam, panic paths, soundness issue
- **Python:** eval/exec, pickle deserialize, path traversal, bare except
- **C/C++:** Buffer overflow, use-after-free, integer overflow, no bounds check
- **Java/Kotlin:** Null safety, insecure deserialization, exposed credentials
- **C# .NET:** SQL injection (EF raw), insecure deserialization, hardcoded secrets
- **PHP/Laravel:** SQL injection (raw queries), XSS (blade), .env exposure
- **Swift:** Force unwrap, memory safety, keychain exposure
- **Kotlin:** Null safety, coroutine leak, implicit intent
- **Shell:** Command injection, unsafe temp, missing quotes, no error handling
- **Ruby/Rails:** Mass assignment, SQL injection, secret exposure
- **Dart/Flutter:** Hardcoded keys, insecure storage, deep link hijack
- **Terraform:** Hardcoded secrets in tfvars, public S3, no state locking
- **Docker:** Root user, exposed ports, massive image size, credentials in layer
- **Dasar:** Hardcoded secrets di source code, credentials in git history

### Tahap 4: Error Handling
- Returned errors diabaikan? (ignored error return)
- Kalo network call gagal, apa yang terjadi?
- Kalo file I/O gagal, apa yang terjadi?
- Kalo input user invalid, crash atau graceful?
- Ada panic/unwrap/throw yang gak di-handle?
- Fallback strategy exist atau asumsi "pasti berhasil"?
- Timeout handling?

### Tahap 5: Performance
- O(n²) loops yang gak perlu?
- API call di dalam loop?
- Memory leak potential (event listener gak di-remove, goroutine leak, dll)?
- I/O blocking di main thread (web)?
- Large file loaded entirely ke memory?
- N+1 query (database)?
- Bundle size issue (web)?
- Unnecessary dependency / bloat?
- Caching strategy lemah?

### Tahap 6: Side Effects & Maintainability
- Modifikasi di luar scope project? (write ke /sys, /proc, registry, dll)
- Network call tanpa sepengetahuan user?
- Process spawn / kill?
- Dead code (gak dipanggil)?
- Magic numbers / hardcoded constants?
- Complex function yang gak di-split?
- Tech debt: workaround yang jadi permanent?

---

## ATURAN PER JENIS PROJECT (Specific)

### Web Frontend (React, Next.js, Vue, Svelte, Angular)
- `useEffect` dep array correctness (React)
- Component props validation (TypeScript/PropTypes)
- State management pattern (redundant state?)
- API route security (Next.js server actions / API routes)
- Client-side data exposure
- Missing key prop (React list)
- Unused imports / components
- Tailwind / CSS class consistency
- Build output check (`npm run build` works?)
- Bundle size: code splitting, lazy loading

### Web Backend (Express, Fastify, Fiber, Laravel, Rails, Django, Phoenix)
- Input validation / sanitization di semua endpoint
- Auth middleware di route yang butuh proteksi
- Rate limiting?
- Session / JWT security
- CORS configuration (too permissive?)
- ORM vs raw SQL (injection risk)
- File upload validation
- Logging sensitive data?

### Go
- `go vet` / `go mod tidy` check
- `errcheck` — errors ignored?
- Goroutine: WaitGroup, mutex, or channel sync?
- Context: propagated ke semua call?
- Race detector findings
- Interface vs concrete type (testability)
- `defer` usage (resource leak?)

### Rust
- `cargo check` / `cargo clippy` findings
- `unsafe` — justification + soundness
- `unwrap()` / `expect()` — crash points
- Error handling: `Result` vs `panic`
- Lifetime annotations correctness
- Trait bounds / generics complexity
- `Arc` / `Mutex` usage (deadlock potential?)
- `#[derive]` completeness

### C / C++ / Kernel
- Buffer overflow (gets, strcpy, sprintf, scanf tanpa limit)
- Use-after-free / double free
- Integer overflow / underflow
- Format string vuln (printf with user input)
- Off-by-one errors
- Locking: mutex deadlock, double lock, unlock without lock
- Inline assembly safety
- Memory allocation failure check (NULL return)
- Signed/unsigned mismatch
- Device tree binding correctness (kernel)

### Python
- `requirements.txt` / `pyproject.toml` completeness
- Virtual environment / pip freeze?
- Exception handling specific (not bare `except:`)
- Path handling: `os.path.join` vs string concat
- Thread safety (lock usage)
- Context manager (`with` statement) for resources
- Type hints completeness?
- Pickle / eval / exec usage?
- SQL injection (raw queries)?

### Java / Kotlin (Android)
- Null safety (Kotlin `?` / Java `Optional`)
- Activity/Fragment lifecycle handling
- Coroutine / RxJava disposal
- Implicit intent exposure
- Content provider security
- SharedPreferences / DataStore sensitive data
- ProGuard / R8 rules?
- Gradle dependency vulnerabilities
- Serializable/Parcelable correctness

### PHP / Laravel
- Route auth middleware
- SQL injection via raw queries
- Blade template XSS (`{!! $var !!}`)
- `.env` exposure in debug mode
- Composer outdated / vulnerable deps
- Artisan command safety
- Mass assignment protection

### Dart / Flutter
- `const` constructor usage
- `BuildContext` usage after async gap
- Hardcoded API keys / secrets
- `SharedPreferences` for sensitive data
- Deep link validation
- Platform channel security
- `pubspec.yaml` dependency audit

### Swift / iOS
- Force unwrap (`!`) — crash points
- Keychain vs UserDefaults for sensitive data
- URL scheme / universal link validation
- Main thread blocking
- Delegate retain cycle
- `Codable` vs manual parsing safety
- App Transport Security config

### Shell Script
- Command injection (variables in `eval` / backtick)
- Unsafe temp file creation (race condition)
- Missing quotes around variables
- `set -e` / error handling?
- `trap` for cleanup?
- Hardcoded paths that may not exist
- Missing shebang / permission

### C# .NET
- SQL injection (Entity Framework raw SQL)
- Insecure deserialization (BinaryFormatter, Json.NET)
- Hardcoded connection strings / secrets
- Async/await deadlock (`.Result` / `.Wait()`)
- XSS in Blazor / Razor
- Overposting / mass assignment (ASP.NET)

### Ruby / Rails
- Mass assignment (no `attr_accessible` / strong params)
- SQL injection (`.where("... #{...}")`)
- XSS (`.html_safe` without sanitization)
- Secret exposure (credentials, env)
- N+1 queries
- Gem vulnerabilities

### Terraform / IaC
- Hardcoded secrets / access keys in `.tfvars`
- Public S3 bucket / overly permissive IAM
- Missing state locking (DynamoDB)
- No remote state backend
- Provider version pinning
- `lifecycle` / `prevent_destroy` usage

### Docker
- Root user running container
- Exposed ports unnecessarily
- Multi-stage build usage?
- Secrets in build args / layers
- Massive image (no .dockerignore)
- `latest` tag usage
- Health check missing

---

## PROSEDUR AUDIT

Kalo user minta audit:

### Step 1: Tentukan Target
1. Kalo user kasih path → pake itu
2. Kalo user nyebut nama path → cocokin
3. Kalo user nyebut nama project → cocokin
4. Kalo gak ada → tanya "Mau audit project mana? Path atau nama?"

### Step 2: Auto-Deteksi
1. Cek file signature di root target
2. Kalo ketemu → pake aturan khusus + 6 tahap universal
3. Kalo gak ketemu → extension-based detection
4. Kalo masih gak ketemu → tanya user

### Step 3: Jalanin Audit
1. Baca SEMUA file penting (config, entry point, main logic)
2. Jalanin 6 tahap universal + aturan khusus
3. Catat temuan: Critical, Warning, Info

### Step 4: Output Report

```
╔══════════════════════════════════════════════════════════╗
║              UNIVERSAL AUDIT REPORT v2                   ║
║  Project: <nama project>                                ║
║  Path: <full path>                                      ║
║  Detected: <project type>                               ║
║  Method: <file signature / extension / manual>          ║
╠══════════════════════════════════════════════════════════╣
║  Files Scanned: <jumlah>                                ║
║  Total Lines: <jumlah>                                  ║
╚══════════════════════════════════════════════════════════╝

[1] STRUKTUR & COMPLETENESS
    ● <Critical/Warning/Info> — <file:line> — <temuan>

[2] KONTRADIKSI & DOKUMENTASI
    ● <Critical/Warning/Info> — <file:line> — <temuan>

[3] SECURITY & BEST PRACTICES
    ● <Critical/Warning/Info> — <file:line> — <temuan>

[4] ERROR HANDLING
    ● <Critical/Warning/Info> — <file:line> — <temuan>

[5] PERFORMANCE
    ● <Critical/Warning/Info> — <file:line> — <temuan>

[6] SIDE EFFECTS & MAINTAINABILITY
    ● <Critical/Warning/Info> — <file:line> — <temuan>

────────────────────────────────────────────────────────
RINGKASAN:
● Critical: <jumlah>
● Warning: <jumlah>
● Info: <jumlah>

VERDICT: LULUS / LULUS BERSYARAT / GAGAL
Alasan: <1-2 kalimat>
Prioritas fix: <top 3>
────────────────────────────────────────────────────────
```

---

## ATURAN MAIN

1. **JANGAN pernah pake asumsi.** Deteksi dari file, bukan dari nama project.
2. **JANGAN percaya comment/docs.** Yang penting kode beneran ngapain.
3. **JANGAN ngefix apapun sebelum lapor.** Audit dulu, baru tanya.
4. **Kalo gak yakin jenis projectnya, tanya user.** Jangan nebak.
5. **Kalo ada yang aneh di kode, SPEAK UP.** Gak perlu sopan.
6. **Prioritas report: Critical > Warning > Info.** Jangan timpuk semua level.
7. **Kalo project kosong atau cuma generated files, bilang doang.**
8. **Untuk CustomROM-Fix, delegasi ke skill `customrom-fix`.**
9. **Selalu catat jumlah file dan baris yang di-scan.**
10. **Verifikasi temuan dengan baca kode langsung, jangan dari log/comment.**

---

## 🔗 Orchestration

| Aspek | Detail |
|-------|--------|
| **Master Orchestrator** | `.opencode/AGENTS.md` — routing, workflows, event triggers |
| **Skill ID** | `universal-audit` |
| **Triggers** | `pr_opened`, `code_review_requested`, `scheduled_weekly`, `manual_trigger` |
| **Dependencies** | `master-reference` (project context) |
| **Depended By** | `planning` (current state audit) |
| **Workflows** | `pr-review` (step 2), `full-audit` (step 1) |
| **Routing Rule** | New `*.c`, `*.h`, `*.S` files → `universal-audit` + `security-auditor` |
| **Data Flow** | Report → consolidated PR comment |
