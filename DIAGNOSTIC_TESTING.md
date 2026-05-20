# Zoom Nuke — Diagnostic System Manual Testing Checklist

Run these checks after any change to the diagnostic logging system.
Most automated checks are in `tools/validate.sh` (run `./tools/validate.sh`).
This file covers integration and UI tests that require a real macOS session.

---

## 1. Log Directory and File Creation

**How to test:**
1. Delete `~/Library/Logs/Zoom Nuke/` if it exists:
   ```bash
   rm -rf ~/Library/Logs/Zoom\ Nuke/
   ```
2. Open Zoom Nuke.app and click **Run Cleanup** (any mode).

**Expected:**
- `~/Library/Logs/Zoom Nuke/` is created.
- `~/Library/Logs/Zoom Nuke/latest.log` is created and non-empty while the script runs.
- The log contains a session header line with a timestamp.
- The footer in the app shows `~/Library/Logs/Zoom Nuke/latest.log`.

---

## 2. `latest.log` Archive on New Session

**How to test:**
1. Run cleanup once — confirm `latest.log` is created.
2. Note the content of `latest.log`.
3. Run cleanup a second time.

**Expected:**
- On the second run, the previous `latest.log` is renamed to `zoom-nuke-YYYYMMDD-HHMMSS.log`.
- A new `latest.log` is created for the current session.
- Both files are present in `~/Library/Logs/Zoom Nuke/`.

---

## 3. Structured Shell Log Entries

**How to test:**
```bash
cat ~/Library/Logs/Zoom\ Nuke/latest.log
```

**Expected:**
- Lines matching `[YYYY-MM-DD HH:MM:SS] [LEVEL] [component] message`.
- At least one `[INFO]`, `[STEP]`, and `[SUCCESS]` entry from `_zoom_core.sh` hooks.
- A `========== Diagnostic Summary ==========` block at the end of a completed run.

---

## 4. Diagnostic Summary Block

**How to test:**
Run a cleanup (any mode) to completion or failure.

**Expected:**
- `latest.log` contains:
  ```
  ========== Diagnostic Summary ==========
  Result:         SUCCESS   (or FAILED / CANCELLED)
  ...
  Log Path:       ~/Library/Logs/Zoom Nuke/latest.log
  =======================================
  ```
- The Swift app detects the block and stores it in `DiagnosticLogger.shared.latestSummary`.
- (Verify via Xcode debugger / print statement if needed.)

---

## 5. Failed Command — Exit Code and Suggested Fix in Log

**How to test:**
Simulate a network failure by setting `ZOOM_URL` to an invalid URL:
```bash
ZOOM_URL="https://invalid.invalid/Zoom.pkg" ./zoom_nuke_overkill.sh --dry-run
```
Or force a failure by temporarily pointing `ZOOM_URL` to a non-existent server in a test run.

**Expected:**
- `latest.log` contains an `[ERROR]` line with `exit=` and `cause=` fields.
- `DIAG_RESULT=FAILED` appears in the summary block.
- `Suggested Fix:` has a human-readable hint (e.g. "Check your internet connection...").

---

## 6. Redaction

**How to test (shell-side):**
```bash
bash -c '
  . tools/_shared_logging.sh
  redact_log_line "/Users/yourname/Library/Logs/zoom.log"
'
```
**Expected:** Output shows `~/Library/Logs/zoom.log` (home path replaced with `~`).

**How to test (Swift-side):**
In Swift REPL or a unit test:
```swift
let raw = "Error at /Users/hampus/Library/Logs/zoom.log (serial: C02XK12345)"
let redacted = DiagnosticRedactor.redact(raw)
// Expected: "Error at ~/Library/Logs/zoom.log (serial: [redacted])"
```

---

## 7. Copy Log Action

**How to test:**
1. Run cleanup to completion.
2. Click **Copy Log** in the Diagnostic Report row.
3. Paste into a text editor.

**Expected:**
- Clipboard contains the report header + `latest.log` content.
- Home directory paths appear as `~` (redacted).
- No privacy warning alert is shown (Copy uses automatic redaction).
- Serial numbers, if any appeared in output, are masked as `[redacted]`.

---

## 8. Export Log Action

**How to test:**
1. Run cleanup to completion.
2. Click **Export Log**.
3. Confirm the privacy warning alert appears.
4. Click **Continue** → choose a save location.

**Expected:**
- `NSSavePanel` opens with default name `zoom-nuke-diagnostic.log`.
- File type options include `.log` and plain text.
- Saved file contains redacted content matching what **Copy Log** would produce.
- Clicking **Cancel** on the alert does not save any file.

---

## 9. Send Report Action

**How to test:**
1. Run cleanup.
2. Click **Send Report**.
3. Confirm privacy warning appears.
4. Click **Continue**.

**Expected:**
- Default Mail app opens with subject `Zoom Nuke Diagnostic Report` and body pre-filled.
- OR: if Mail is not configured, a fallback alert says "report has been copied to clipboard."
- In either case, no log is silently transmitted anywhere.

---

## 10. Privacy Warning Gate

**How to test:**
1. Click **Export Log** or **Send Report**.
2. Click **Cancel** on the privacy warning.

**Expected:**
- No file is saved and Mail does not open.
- `pendingDiagAction` is cleared (clicking Run Cleanup still works normally).

---

## 11. Diagnostic Buttons Visibility

**How to test:**
- Open the app; do NOT run cleanup.

**Expected:** Diagnostic row (`Copy Log / Export Log / Send Report`) is NOT visible.

- Run cleanup to completion (success, failure, or cancel).

**Expected:** Diagnostic row appears with all three buttons enabled.

---

## 12. Exported Log Matches Live Log

**How to test:**
1. Run cleanup.
2. Click **Export Log** → save to a file.
3. Compare with `cat ~/Library/Logs/Zoom\ Nuke/latest.log`.

**Expected:**
- Exported file content is the redacted version of `latest.log`.
- The structure (header, entries, summary) is preserved.

---

## 13. Audit Mode Output

**How to test:**
```bash
./zoom_nuke_overkill.sh --audit
```

**Expected report includes:**
- Running Zoom processes (or "none")
- Installed Zoom version and size
- Each data directory: PRESENT with size, or absent
- LaunchAgents / LaunchDaemons
- Package receipts with version
- Cache/database findings
- Network interface state and MAC address
- Backup directories with sizes
- Hardware fingerprint (model only; serial/UUID redacted inline)

---

## 14. validate.sh Passes All Diagnostic Checks

```bash
./tools/validate.sh --verbose
```

**Expected:**
- Section "6. Diagnostic logging (_shared_logging.sh)" shows all green:
  - `tools/_shared_logging.sh` exists and sources cleanly
  - Diagnostic log file created by `_diag_open`
  - Structured INFO and ERROR entries written
  - `redact_log_line` correctly masks home paths
  - `write_diagnostic_summary` produces expected output

---

## Quick Regression Checklist

After any change, run in order:

```bash
# 1. Automated checks
./tools/validate.sh

# 2. Shell logging smoke test
bash -c '
  . tools/_shared_logging.sh
  TMPDIR_TEST=$(mktemp -d)
  _diag_open "$TMPDIR_TEST" "3.2.1"
  log_info  "hello" "test"
  log_error "fail"  "test" "exit=99"
  DIAG_RESULT=FAILED DIAG_FAILED_STEP="Download" DIAG_EXIT_CODE=99
  write_diagnostic_summary
  _diag_close
  echo "--- log contents ---"
  cat "$TMPDIR_TEST/latest.log"
  rm -rf "$TMPDIR_TEST"
'

# 3. Redaction test
bash -c '
  . tools/_shared_logging.sh
  out=$(redact_log_line "/Users/hampus/Library secret_token=abc123")
  echo "$out"
  [[ "$out" != *"hampus"* ]] && echo "PASS: path redacted" || echo "FAIL: path NOT redacted"
'

# 4. Build check (macOS only)
./tools/build_macos_app.sh /tmp/test-build && rm -rf /tmp/test-build
```
