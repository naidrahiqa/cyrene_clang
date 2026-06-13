# CyreneClang — Feature-Specific Prompts

Pilih prompt yang sesuai fitur yang mau lo kerjain. Semua prompt ini
diasumsikan lo udah load `docs/SKILL.md` sebagai context di OpenCode.

---

## 1. Bolt-on LTO untuk Kernel (CONFIG_LTO_CLANG)

```
You are working on CyreneClang. Read docs/SKILL.md first.

Implement kernel-side ThinLTO support as a bolt-on feature. This is separate
from the toolchain's own ThinLTO — this is about enabling CONFIG_LTO_CLANG
in the kernel build that USES CyreneClang.

Requirements:
- Create scripts/kernel-lto.sh: a helper script users can source or call
  before their kernel make invocation to set up the correct KCFLAGS, KLDFLAGS,
  and environment for ThinLTO kernel builds
- The script must:
  - Detect CyreneClang version from clang-version.txt (if present)
  - Validate that the detected Clang version supports ThinLTO (>= 12.0)
  - Export: CC=clang, LD=ld.lld, AR=llvm-ar, plus KCFLAGS with -flto=thin
  - Warn (not fail) if kernel version < 5.12 where LTO support is incomplete
  - Print a summary of what was set and why
- Add a section to README.md: "## Kernel LTO Integration" with usage example
- Do NOT modify build.sh — this is purely a user-facing helper

Constraints:
- Must work when sourced (.) or executed directly
- No kernel source tree modifications
- Compatible with bash 4.x+

Provide: scripts/kernel-lto.sh (full), README.md addition (the new section only).
```

---

## 2. Auto Cherry-Pick Patches dari LLVM Stable

```
You are working on CyreneClang. Read docs/SKILL.md first.

Implement an automated system to cherry-pick relevant patches from LLVM stable
branches into our build, without requiring manual .patch file management.

Requirements:
- Create scripts/sync-patches.sh that:
  - Accepts a list of LLVM commit hashes via a config file: patches/stable-picks.txt
    (one commit hash per line, comments with #)
  - For each hash: fetches only that commit from llvm-project remote (git fetch
    origin <hash> — shallow), then runs git format-patch to create the .patch file
    in patches/ with naming: NNNN-<short-hash>-<subject>.patch
  - Skips hashes that already have a matching patch file
  - Prints a clear log of: skipped / applied / failed
- Add a GitHub Actions workflow: .github/workflows/sync-patches.yml
  - Triggered by: workflow_dispatch (manual) and weekly schedule (Friday 00:00 UTC,
    one day before the main build on Monday)
  - After sync, opens a PR (not a direct push) with the new patch files so changes
    can be reviewed before the next build
  - Uses gh CLI for PR creation (available on ubuntu-latest)
- patches/stable-picks.txt should be created with 3 example placeholder hashes
  and comments explaining the format

Constraints:
- git fetch of individual commits requires the remote to support partial fetch —
  handle the case where it doesn't gracefully (fallback: warn + skip)
- PR body should list which commits were added

Provide: scripts/sync-patches.sh, .github/workflows/sync-patches.yml,
patches/stable-picks.txt — all complete files.
```

---

## 3. Multi-Stage PGO dengan Real Kernel Workload

```
You are working on CyreneClang. Read docs/SKILL.md first.

The current PGO workload in scripts/build.sh uses SQLite as a proxy workload.
Replace it with a real Android kernel compilation workload for more representative
profiles.

Requirements:
- Modify the collect_profiles() function in scripts/build.sh to:
  - Clone a minimal, well-known Android kernel (use
    https://github.com/kdrag0n/proton-clang-build as reference for which kernel
    is conventionally used, or default to android-mainline from
    kernel.googlesource.com with --depth=1)
  - Configure it with a generic arm64 defconfig (make defconfig ARCH=arm64)
  - Run a partial build (just enough to generate rich compiler profiles — building
    drivers/gpu and kernel/ directories is sufficient, no need for full vmlinux)
  - Use the stage-1 instrumented clang as CC for this kernel build
  - Set LLVM_PROFILE_FILE so profiles land in $BUILD_DIR/profiles/
  - Clean up the kernel clone after profile collection (saves ~2GB disk)
- Add a workflow_dispatch input to build.yml: pgo_workload with options
  "sqlite" (fast, default) and "kernel" (slower, more accurate) so users can
  choose
- The kernel workload path must complete within ~30 minutes on a 4-core runner
  or emit a warning that it may timeout

Constraints:
- Kernel source clone must use --depth=1
- Do not store the kernel source as part of the final toolchain
- If kernel workload fetch fails (network issue), fall back to SQLite workload
  automatically with a warning — never fail the entire build for this

Provide: modified scripts/build.sh (full file), modified .github/workflows/build.yml
(full file).
```

---

## 4. Clang Version Checker / Compatibility Validator

```
You are working on CyreneClang. Read docs/SKILL.md first.

Create a standalone compatibility checker that kernel developers can run to
validate that their CyreneClang installation is correct and compatible with
their kernel tree.

Requirements:
- Create scripts/check-compat.sh:
  - Checks that clang, ld.lld, llvm-ar, llvm-nm, llvm-objcopy are all present
    in PATH and from the same CyreneClang installation (same prefix)
  - Parses clang-version.txt (from current dir or $CYRENE_ROOT) and prints a
    formatted summary: version, build date, PGO status, LTO mode
  - Detects the kernel version from the user-provided kernel source path
    (first argument to the script, e.g.: ./check-compat.sh ~/kernel/msm-5.15)
    by reading Makefile VERSION/PATCHLEVEL
  - Validates compatibility matrix:
    - Clang >= 14 required for kernel >= 6.0
    - Clang >= 12 required for kernel >= 5.12 LTO
    - Clang >= 11 for anything older
  - Checks if ld.lld version matches clang major version (mismatch = warning)
  - Exits 0 if all checks pass, 1 if any hard requirement fails, 2 if only
    warnings
  - Output: colored terminal output (green ✓, yellow ⚠, red ✗) with a final
    PASS / WARN / FAIL summary line
- Add usage to README.md under "## Compatibility Check" section

Constraints:
- Must work without a kernel source tree (skip kernel checks gracefully if no
  path provided)
- No external dependencies beyond standard coreutils + grep + awk
- Must work on both the user's local machine AND inside GitHub Actions

Provide: scripts/check-compat.sh (full), README.md addition (new section only).
```

---

## Tips Penggunaan

- Untuk fitur yang saling bergantung (misal PGO workload + LTO), kerjain dulu
  **PGO workload** baru **LTO** karena LTO bergantung pada toolchain yang sudah
  selesai dibangun
- Setelah tiap fitur selesai, jalankan `scripts/check-compat.sh` sebagai
  smoke test
- Commit tiap fitur terpisah dengan conventional commit message yang jelas