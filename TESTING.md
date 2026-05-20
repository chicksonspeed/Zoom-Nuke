# Zoom Nuke — Testing Guide

This document describes what automated test coverage exists, how to run it
locally, and what must be verified manually before shipping a release.

---

## Quick start (automated — one command)

```zsh
# From the repo root:
swift test && bash tests/shell/run_tests.sh && ./tools/validate.sh
```

All three must exit 0 for the build to be considered safe to ship.

---

## Automated test coverage

### Swift unit tests (`tests/swift/`)

| File | What it tests |
|---|---|
| `DiagnosticLogEntryTests.swift` | `LogLevel` raw values · `formatted()` structure · timestamp format (yyyy-MM-dd HH:mm:ss, POSIX locale) · all optional fields (cmd, path, exit, duration, fix) · field ordering · unique IDs |
| `DiagnosticRedactorTests.swift` | Home path redaction · email · IPv4 · IPv6 · hardware UUID · serial numbers · 9 secret env-var keys · preserved non-sensitive content · idempotency · multi-rule composition · multiline text |

**How to run:**
```zsh
swift test                                      # all tests
swift test --filter DiagnosticLogEntryTests     # one class
swift test --filter DiagnosticRedactorTests     # one class
```

**What is NOT covered (intentional):**
- `DiagnosticLogger` — requires `@Published`, file system, and dispatch queues;
  covered by the shell tests and manual QA instead
- `DiagnosticReport` — requires `AppKit` (NSPasteboard, NSSavePanel); manual only
- `ContentView*`, `CleanupProcessManager` — UI and process management; manual only
- `CleanMode`, `RunState`, `Models` — import SwiftUI (`Color`); library target is
  Foundation-only to keep CI fast and dependency-free

### Shell unit tests (`tests/shell/`)

| File | What it tests |
|---|---|
| `test_logging.sh` | `_shared_logging.sh` sourcing · double-source guard · `_diag_open` creates/archives log · `_diag_write` format `[ts][LEVEL][comp]` · all 6 level functions · `log_step` echoes stdout, `log_debug` does not · `run_logged_command` DRY_RUN=true/false · exit-code capture · `redact_log_line` home paths/serials/non-sensitive · `write_diagnostic_summary` content · `_infer_failure` exit-code mapping · paths with spaces |
| `test_zoom_core.sh` | `_zoom_core.sh` sourcing · `run()` DRY_RUN=true/false · exit-code propagation · `check_cancel()` exits 130 / no-op when absent · `ZOOM_DATA_DIRS` safety (no system paths, all under `$HOME`) · `version_to_number` numeric ordering · `core_remove_zoom_data` DRY_RUN guard · `DRY_RUN` default value · `ZOOM_URL` HTTPS-only · `MIN_FREE_MB` > 0 |

**How to run:**
```zsh
bash tests/shell/run_tests.sh             # normal output
bash tests/shell/run_tests.sh --verbose   # show passing tests too
```

**Safety guarantees:**
- `ZOOM_NUKE_TEST_MODE=1` and `DRY_RUN=true` are exported by the runner
- All filesystem tests use `mktemp` — no real user paths are touched
- No sudo calls, no network calls, no Zoom data modification

### Static validation (`tools/validate.sh`)

Checks structure, syntax, permissions, VERSION format, CLI flags, audit mode,
preflight, diagnostic logging smoke tests, secret-pattern scan, and test
infrastructure presence.

```zsh
./tools/validate.sh           # normal
./tools/validate.sh --verbose # more detail
```

---

## CI (GitHub Actions — `.github/workflows/pr-validate.yml`)

| Job | Runner | What runs |
|---|---|---|
| `shellcheck` | ubuntu-latest | ShellCheck on all `.sh` files including test files |
| `source-guard` | ubuntu-latest | Verifies canonical files in `Sources/ZoomNukeCore/`, guards against re-addition to `app/`, checks `Package.swift` targets and sources list |
| `build-swift` | macos-latest | `swift build` — confirms app compiles |
| `test-swift` | macos-latest | `swift test --filter ZoomNukeTests` |
| `test-shell` | macos-latest | `bash tests/shell/run_tests.sh --verbose` |
| `validate` | macos-latest | `./tools/validate.sh --verbose` |
| `preflight` | macos-latest | `./tools/preflight_check.sh` (exit 2 OK) |
| `e2e-dry-run` | macos-latest | Full `zoom_nuke_overkill.sh --dry-run --force` run; asserts `[DRY RUN]` markers, summary block, `latest.log` creation, zero Zoom data dir side-effects |

All eight jobs run in parallel on every push and pull request to `main`.
The `release-bundle.yml` workflow is unchanged and runs only on published releases.

---

## Manual QA checklist

Work through this checklist before tagging a release.  Check each item off.

### 1. Fresh install

- [ ] Clone the repo to a machine that has never run Zoom Nuke
- [ ] Run `./tools/validate.sh` — all checks pass
- [ ] Run `swift build` — no compiler errors or warnings
- [ ] Open the built `.app` — window appears; mode selector shows Standard and Deep

### 2. Normal cleanup run (Standard mode)

- [ ] Zoom is installed and logged in on the test machine
- [ ] Launch Zoom Nuke, select **Standard Clean**, click **Run**
- [ ] Progress output appears in the shell panel as the script runs
- [ ] After completion, `~/Library/Logs/Zoom Nuke/latest.log` exists and is readable
- [ ] `~/Library/Logs/Zoom Nuke/` contains at least one `zoom-nuke-*.log` archive
  (if this is not the first run)
- [ ] `/Applications/zoom.us.app` is gone after the run
- [ ] Zoom data dirs (`~/Library/Application Support/zoom.us` etc.) are removed

### 3. Audit / dry-run mode

- [ ] Run `bash zoom_nuke_overkill.sh --audit` — prints a status report and exits,
  makes **zero** changes to the filesystem
- [ ] Run `bash zoom_nuke_overkill.sh --dry-run` (or `-n`) — every destructive
  command prints `[DRY RUN]` and the filesystem is unmodified afterward
- [ ] Run Zoom Nuke app with `DRY_RUN=true` set in the environment — output shows
  dry-run markers; no files deleted
- [ ] `write_diagnostic_summary` block appears in the log at the end of a dry run

### 4. Missing Zoom install

- [ ] Uninstall Zoom manually (`rm -rf /Applications/zoom.us.app` and data dirs)
- [ ] Run Zoom Nuke — script handles the missing app gracefully (no crash, logs
  appropriate warning/skip messages)
- [ ] The diagnostic summary still appears at the end

### 5. Permission failure

- [ ] On a Standard account (not admin), attempt to run a destructive operation
  that requires `sudo` without pre-warming credentials
- [ ] Script prompts for password or fails cleanly with an actionable error message
- [ ] Exit code is non-zero; `[ERROR]` entry appears in `latest.log`
- [ ] `_infer_failure` cause and fix fields are populated in the summary

### 6. Failed command behavior

- [ ] Introduce a deliberate failure: patch `zoom_nuke.sh` to run a command that
  exits non-zero (e.g. `false` after one of the `run_logged_command` calls)
- [ ] Confirm: `DIAG_RESULT=FAILED` in the summary block
- [ ] Confirm: `DIAG_FAILED_STEP` and `DIAG_EXIT_CODE` are correctly populated
- [ ] Confirm: `DIAG_FIX` contains a human-readable suggestion
- [ ] Revert the patch

### 7. Diagnostic log creation and archiving

- [ ] Run Zoom Nuke twice in a row
- [ ] After the second run, `~/Library/Logs/Zoom Nuke/` contains:
  - `latest.log` (current session)
  - `zoom-nuke-<timestamp>.log` (archived first session)
- [ ] Both files are UTF-8 readable plain text
- [ ] `latest.log` begins with the session header (`zoom-nuke diagnostic log`)

### 8. `latest.log` update behavior (Swift side)

- [ ] Open the app and trigger a run
- [ ] While the run is in progress, open `latest.log` in a text editor — output
  is being written in real time (file grows as the script runs)
- [ ] After the run, check that the Swift-generated session-end line
  (`Session ended — exit=…`) appears at the bottom

### 9. Copy log

- [ ] After a successful run, click **Copy Log** (or equivalent action)
- [ ] Paste into a text editor — the full log content appears
- [ ] Verify that `/Users/<yourname>/` is replaced with `~/` in the pasted text
- [ ] Verify no email addresses or hardware UUIDs appear in plain text

### 10. Export log (Save panel)

- [ ] Click **Export Log**
- [ ] An `NSSavePanel` appears with a default filename of `zoom-nuke-diagnostic.log`
- [ ] Save to the Desktop
- [ ] Open the saved file — matches the redacted log content
- [ ] File encoding is UTF-8

### 11. Send diagnostic report (GitHub issue)

- [ ] Click **Send Diagnostic Report**
- [ ] A GitHub new-issue page opens in the browser with a pre-filled body
- [ ] The summary block is in the pre-filled body
- [ ] An alert dialog confirms that the full log has been copied to the clipboard
- [ ] Paste clipboard into a text editor — full redacted log appears
- [ ] Dismiss the alert; click **OK**

### 12. Redaction review

Using a log that contains known-sensitive data (generated on a real machine):
- [ ] `/Users/<yourname>/` → replaced with `~` everywhere
- [ ] Any email addresses present → replaced with `[email]`
- [ ] Any IPv4 addresses (e.g. DNS server, network addresses) → replaced with `[ip]`
- [ ] Hardware UUID (if present) → replaced with `[uuid]`
- [ ] Serial number (if present via `system_profiler`) → replaced with `[redacted]`
- [ ] macOS version, architecture, exit codes, command names — **not** redacted

### 13. macOS 12+ compatibility

- [ ] Confirm minimum macOS target is 12.0 (`Package.swift`, `build_macos_app.sh`, Info.plist)
- [ ] Test on macOS 12.x if available (the minimum supported version)
- [ ] Test on the latest macOS release

### 14. Apple Silicon vs. Intel

- [ ] On Apple Silicon (arm64): `Architecture: arm64` appears in the diagnostic summary
- [ ] On Intel (x86_64): `Architecture: x86_64` appears in the diagnostic summary
- [ ] MAC spoofing may report a warning on Apple Silicon (expected; non-fatal)
- [ ] Both architectures complete the cleanup run without a hard failure

### 15. Cancellation

- [ ] Start a cleanup run in the app
- [ ] Click **Cancel** during the run
- [ ] Confirm: process is terminated; exit code 130 appears in the log
- [ ] Confirm: the summary block is still emitted (either by the shell or the Swift fallback)
- [ ] Confirm: no zombie `bash` processes remain (`ps aux | grep zoom`)

---

## Source of truth for core types

`DiagnosticLogEntry.swift` and `DiagnosticRedactor.swift` live exclusively in
`Sources/ZoomNukeCore/`.  There are **no** copies in `app/`.

Both directories are compiled together in a single `swiftc` invocation
(via `build_macos_app.sh`) and in the `ZoomNuke` executable's SPM sources list,
so all `app/` files see these types without any `import` statement.

The `source-guard` CI job fails immediately if either file is accidentally
re-added to `app/`, or if the `Package.swift` sources list no longer includes
the canonical paths.

---

## What remains manual-only

| Area | Reason |
|---|---|
| Full end-to-end cleanup run | Requires Zoom installed, real sudo, real filesystem |
| MAC spoofing success/failure | Hardware and macOS version dependent |
| NSSavePanel / NSPasteboard | AppKit UI — not testable in headless XCTest |
| NSWorkspace.open (GitHub URL) | Requires a browser and network |
| Real network connectivity | CI blocks outbound connections |
| Apple Silicon vs. Intel arch detection | Compile-time `#if arch()` — can't be unit tested |
| Admin privilege escalation | Cannot simulate without real credentials |

---

## Remaining future improvements

All three improvements from the original CR6 review are now implemented:

- **CR6-1 (source guard)** — `source-guard` CI job enforces canonical file locations
  and guards against drift in `Package.swift`.
- **CR6-2 (library refactor)** — mirrors eliminated; `Sources/ZoomNukeCore/` is the
  single source of truth compiled into both the library target and the executable.
- **CR6-3 (e2e smoke test)** — `e2e-dry-run` CI job runs the full script with
  `--dry-run --force` and asserts four observable properties.

The one remaining improvement worth pursuing is testing `CleanMode.scriptArgs` and
`RunState` — currently untestable because they import SwiftUI (`Color`). Extracting
those two enums into a Foundation-only file in `Sources/ZoomNukeCore/` (with the
`Color` properties moved to an extension in `app/`) would unlock full unit test
coverage with no new infrastructure required.
