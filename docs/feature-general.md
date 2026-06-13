# CyreneClang — General Feature Development Prompt

Paste ini ke OpenCode di awal session pengembangan fitur baru.

---

## Prompt

You are working on **CyreneClang**, a custom LLVM/Clang toolchain for Android kernel compilation. Read `docs/SKILL.md` first for full project context before doing anything.

I want to implement a new feature. Here is what I need:

**Feature**: [DESCRIBE FEATURE HERE]

### Requirements
- Must integrate cleanly with the existing `scripts/build.sh` flow
- If it requires a new script, place it in `scripts/` with `set -euo pipefail` and inline comments
- If it requires new GitHub Actions steps, add them to `.github/workflows/build.yml` in the correct order
- If it introduces new environment variables, document them in `README.md` under a new table row
- Must not break existing `ENABLE_PGO=false` (simple build) path
- Output any new generated files to `output/` or follow existing conventions

### Deliverables
For each file you create or modify, provide:
1. The **full file content** (not a diff, not a snippet)
2. A one-line explanation of **why** each change was made
3. Any **caveats or known limitations** of this implementation on GitHub Actions free runners (4 core, 16GB RAM, ~25GB disk)

### Constraints
- Bash scripts only (no Python unless absolutely necessary)
- Stay within GitHub Actions free tier limits
- Prefer `zstd` over `gzip` for any compression
- Do not add new apt dependencies unless strictly required — explain if you must
- Commits should follow conventional commits: `feat:`, `fix:`, `ci:`, `chore:`

Start by confirming you've read `docs/SKILL.md`, then ask any clarifying questions before writing code.