#!/usr/bin/env bash
# tests/shell/test_logging.sh — Tests for tools/_shared_logging.sh
#
# Sourced by run_tests.sh.  Must define run_tests().
#
# Tests cover:
#   - _diag_open creates latest.log in a temp dir
#   - _diag_open archives an existing latest.log
#   - _diag_write produces the expected [ts][LEVEL][comp] format
#   - log_info / log_step / log_success / log_warn / log_error / log_debug
#     each write the correct level tag
#   - log_step echoes to stdout; log_debug does NOT echo to stdout
#   - redact_log_line replaces /Users/<name> with ~
#   - redact_log_line masks serial-number patterns
#   - write_diagnostic_summary emits the required header and result
#   - write_diagnostic_summary includes DIAG_FAILED_STEP and DIAG_EXIT_CODE
#   - Double-sourcing guard (_SHARED_LOGGING_LOADED) prevents re-init
#   - Paths with spaces work for _diag_open
#
# SAFETY: all file I/O uses mktemp; no real user paths are touched.
# DRY_RUN=true is set by the runner, preventing any destructive operations.

SHARED_LOG_LIB="${REPO_ROOT}/tools/_shared_logging.sh"

# ---------------------------------------------------------------------------
# Helper: source _shared_logging.sh into a fresh bash subprocess and return
# its stdout.  We use a subprocess per test to avoid state bleed from the
# _DIAG_FD_OPEN / _DIAG_DIR globals.
# ---------------------------------------------------------------------------
_run_logging() {
  # $1 = bash code to run after sourcing the library
  bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null
    $1
  " 2>/dev/null
}

_run_logging_with_open() {
  # $1 = dir, $2 = bash code to run after _diag_open
  local dir="$1" code="$2"
  bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null
    _diag_open '${dir}' 'test-1.0'
    ${code}
    _diag_close
  " 2>/dev/null
}

# ---------------------------------------------------------------------------
run_tests() {

  # Skip entire file if library is missing.
  if [[ ! -f "$SHARED_LOG_LIB" ]]; then
    skip "tools/_shared_logging.sh not found — skipping all logging tests"
    return
  fi

  # Skip tests that require macOS tools if not on Darwin.
  local is_macos=false
  [[ "$(uname 2>/dev/null)" == "Darwin" ]] && is_macos=true

  # ------------------------------------------------------------------
  # 1. Library sources cleanly
  # ------------------------------------------------------------------
  local source_exit=0
  bash -c ". '${SHARED_LOG_LIB}'" 2>/dev/null || source_exit=$?
  assert_eq "0" "$source_exit" \
    "_shared_logging.sh sources without error"

  # ------------------------------------------------------------------
  # 2. Double-sourcing guard
  # ------------------------------------------------------------------
  local double_source_out
  double_source_out="$(bash -c "
    . '${SHARED_LOG_LIB}'
    first_state=\${_SHARED_LOGGING_LOADED:-}
    . '${SHARED_LOG_LIB}'
    second_state=\${_SHARED_LOGGING_LOADED:-}
    echo \"\${first_state}:\${second_state}\"
  " 2>/dev/null)"
  assert_eq "1:1" "$double_source_out" \
    "Double-sourcing guard: _SHARED_LOGGING_LOADED stays 1 on re-source"

  # ------------------------------------------------------------------
  # 3. _diag_open creates latest.log
  # ------------------------------------------------------------------
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  _run_logging_with_open "$tmp_dir" "" >/dev/null 2>&1
  assert_file_exists "${tmp_dir}/latest.log" \
    "_diag_open creates latest.log in temp dir"
  rm -rf "$tmp_dir"

  # ------------------------------------------------------------------
  # 4. _diag_open archives existing latest.log
  # ------------------------------------------------------------------
  local tmp_dir2
  tmp_dir2="$(mktemp -d)"
  touch "${tmp_dir2}/latest.log"
  echo "old session" > "${tmp_dir2}/latest.log"
  _run_logging_with_open "$tmp_dir2" "" >/dev/null 2>&1
  # Should have: latest.log (new) AND at least one zoom-nuke-*.log (archive)
  local archive_count
  archive_count="$(find "$tmp_dir2" -name 'zoom-nuke-*.log' | wc -l | tr -d ' ')"
  assert_eq "1" "$archive_count" \
    "_diag_open archives previous latest.log to zoom-nuke-<stamp>.log"
  rm -rf "$tmp_dir2"

  # ------------------------------------------------------------------
  # 5. _diag_write structured line format: [ts] [LEVEL] [comp] message
  # ------------------------------------------------------------------
  local tmp_dir3
  tmp_dir3="$(mktemp -d)"
  _run_logging_with_open "$tmp_dir3" \
    "log_info 'hello world' 'test_comp'" >/dev/null 2>&1
  local log_contents
  log_contents="$(cat "${tmp_dir3}/latest.log" 2>/dev/null || echo '')"
  assert_match \
    '^\[2[0-9]{3}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[INFO\] \[test_comp\] hello world$' \
    "$(echo "$log_contents" | grep 'hello world')" \
    "_diag_write format: [YYYY-MM-DD HH:MM:SS] [INFO] [comp] message"
  rm -rf "$tmp_dir3"

  # ------------------------------------------------------------------
  # 6. Each public log function writes its level tag
  # ------------------------------------------------------------------
  local levels=("INFO" "STEP" "SUCCESS" "WARNING" "ERROR" "DEBUG")
  local functions=("log_info" "log_step" "log_success" "log_warn" "log_error" "log_debug")
  for i in "${!levels[@]}"; do
    local level="${levels[$i]}" fn="${functions[$i]}"
    local tmp_fn
    tmp_fn="$(mktemp -d)"
    _run_logging_with_open "$tmp_fn" "${fn} 'test entry' 'suite'" >/dev/null 2>&1
    local fn_log
    fn_log="$(cat "${tmp_fn}/latest.log" 2>/dev/null || echo '')"
    assert_contains "[${level}]" "$fn_log" \
      "${fn} writes [${level}] tag to log"
    rm -rf "$tmp_fn"
  done

  # ------------------------------------------------------------------
  # 7. log_step echoes to stdout; log_debug does NOT
  # ------------------------------------------------------------------
  local tmp_step; tmp_step="$(mktemp -d)"
  local step_stdout
  step_stdout="$(_run_logging_with_open "$tmp_step" "log_step 'visible step' 'ui'")"
  assert_contains "visible step" "$step_stdout" \
    "log_step echoes human-readable output to stdout"
  rm -rf "$tmp_step"

  local tmp_debug; tmp_debug="$(mktemp -d)"
  local debug_stdout
  debug_stdout="$(_run_logging_with_open "$tmp_debug" "log_debug 'silent debug' 'ui'")"
  assert_not_contains "silent debug" "$debug_stdout" \
    "log_debug does NOT echo to stdout (log file only)"
  rm -rf "$tmp_debug"

  # ------------------------------------------------------------------
  # 8. run_logged_command with DRY_RUN=true logs without executing
  # ------------------------------------------------------------------
  # NOTE: log_info writes to FD 3 (the log file), not stdout.
  # The "[DRY RUN] Would run:" message must be checked in the log file, not in
  # the captured stdout of the subprocess.
  local tmp_dry; tmp_dry="$(mktemp -d)"
  local dry_stdout
  dry_stdout="$(bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null
    DRY_RUN=true
    _diag_open '${tmp_dry}' 'test'
    run_logged_command 'test step' echo THIS_SHOULD_NOT_APPEAR
    _diag_close
  " 2>/dev/null)"
  assert_not_contains "THIS_SHOULD_NOT_APPEAR" "$dry_stdout" \
    "run_logged_command with DRY_RUN=true does not execute the command"
  # The [DRY RUN] marker is emitted via log_info → FD 3 (log file), not stdout.
  local dry_log_content
  dry_log_content="$(cat "${tmp_dry}/latest.log" 2>/dev/null || echo '')"
  assert_contains "DRY RUN" "$dry_log_content" \
    "run_logged_command with DRY_RUN=true writes [DRY RUN] to the diagnostic log file"
  rm -rf "$tmp_dry"

  # ------------------------------------------------------------------
  # 9. run_logged_command with DRY_RUN=false executes the command
  # ------------------------------------------------------------------
  local tmp_real; tmp_real="$(mktemp -d)"
  local sentinel_file="${tmp_real}/sentinel"
  bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null
    DRY_RUN=false
    _diag_open '${tmp_real}' 'test'
    run_logged_command 'create sentinel' touch '${sentinel_file}'
    _diag_close
  " >/dev/null 2>&1
  assert_file_exists "$sentinel_file" \
    "run_logged_command with DRY_RUN=false executes the command"
  rm -rf "$tmp_real"

  # ------------------------------------------------------------------
  # 10. run_logged_command captures non-zero exit code
  # ------------------------------------------------------------------
  # We must NOT call _diag_close after the failing command, because _diag_close
  # exits 0 and would shadow the exit code.  We explicitly exit with $? instead.
  local tmp_fail; tmp_fail="$(mktemp -d)"
  local cmd_exit=0
  bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null
    DRY_RUN=false
    _diag_open '${tmp_fail}' 'test'
    run_logged_command 'intentional failure' false; exit \$?
  " >/dev/null 2>&1 || cmd_exit=$?
  # run_logged_command returns the command's exit code ('false' exits 1)
  assert_eq "1" "$cmd_exit" \
    "run_logged_command propagates non-zero exit code"
  local fail_log
  fail_log="$(cat "${tmp_fail}/latest.log" 2>/dev/null || echo '')"
  assert_contains "[ERROR]" "$fail_log" \
    "run_logged_command writes [ERROR] to log on failure"
  rm -rf "$tmp_fail"

  # ------------------------------------------------------------------
  # 11. redact_log_line: home path replaced with ~
  # ------------------------------------------------------------------
  local redact_home
  redact_home="$(_run_logging "redact_log_line '/Users/testuser/secret.txt'")"
  assert_not_contains "testuser" "$redact_home" \
    "redact_log_line removes username from /Users/<name>/..."
  assert_contains "~" "$redact_home" \
    "redact_log_line replaces home path with tilde"

  # ------------------------------------------------------------------
  # 12. redact_log_line: serial number masked
  # ------------------------------------------------------------------
  local redact_serial
  redact_serial="$(_run_logging "redact_log_line 'Serial Number: XYZABC12345678'")"
  assert_not_contains "XYZABC12345678" "$redact_serial" \
    "redact_log_line masks hardware serial number"
  assert_contains "[redacted]" "$redact_serial" \
    "redact_log_line replaces serial with [redacted]"

  # ------------------------------------------------------------------
  # 13. redact_log_line: non-sensitive path passes through unchanged
  # ------------------------------------------------------------------
  local redact_app
  redact_app="$(_run_logging "redact_log_line '/Applications/zoom.us.app'")"
  assert_contains "/Applications/zoom.us.app" "$redact_app" \
    "redact_log_line does not alter /Applications paths"

  # ------------------------------------------------------------------
  # 14. redact_log_line: path with spaces handled correctly
  # ------------------------------------------------------------------
  local redact_spaces
  redact_spaces="$(_run_logging "redact_log_line '/Users/test user/My Documents/file.log'")"
  # /Users/test is matched (stops at the first space in the username pattern
  # which uses [^/[:space:]]*). Verify no crash and username is removed.
  assert_not_contains "test user" "$redact_spaces" \
    "redact_log_line handles paths with spaces without crashing"

  # ------------------------------------------------------------------
  # 15. write_diagnostic_summary emits the summary header
  # ------------------------------------------------------------------
  local summary_out
  summary_out="$(_run_logging "
    DIAG_RESULT='SUCCESS'
    DIAG_FAILED_STEP=''
    DIAG_FAILED_COMMAND=''
    DIAG_EXIT_CODE='0'
    DIAG_CAUSE=''
    DIAG_FIX=''
    write_diagnostic_summary
  ")"
  assert_contains "Diagnostic Summary" "$summary_out" \
    "write_diagnostic_summary emits '========== Diagnostic Summary =========='"

  # ------------------------------------------------------------------
  # 16. write_diagnostic_summary includes DIAG_RESULT
  # ------------------------------------------------------------------
  local summary_fail
  summary_fail="$(_run_logging "
    DIAG_RESULT='FAILED'
    DIAG_EXIT_CODE='42'
    DIAG_FAILED_STEP='Download Zoom'
    write_diagnostic_summary
  ")"
  assert_contains "FAILED" "$summary_fail" \
    "write_diagnostic_summary includes DIAG_RESULT=FAILED"

  # ------------------------------------------------------------------
  # 17. write_diagnostic_summary includes exit code
  # ------------------------------------------------------------------
  assert_contains "42" "$summary_fail" \
    "write_diagnostic_summary includes DIAG_EXIT_CODE=42"

  # ------------------------------------------------------------------
  # 18. write_diagnostic_summary includes failed step
  # ------------------------------------------------------------------
  assert_contains "Download Zoom" "$summary_fail" \
    "write_diagnostic_summary includes DIAG_FAILED_STEP"

  # ------------------------------------------------------------------
  # 19. write_diagnostic_summary closes with the separator line
  # ------------------------------------------------------------------
  assert_contains "=======================================" "$summary_out" \
    "write_diagnostic_summary ends with ======================================="

  # ------------------------------------------------------------------
  # 20. _infer_failure sets correct cause for exit 126
  # ------------------------------------------------------------------
  local infer_126
  infer_126="$(_run_logging "
    _infer_failure 'Run cleanup' 126 '/some/script.sh'
    echo \"cause:\$_INFER_CAUSE\"
  ")"
  assert_contains "Permission denied" "$infer_126" \
    "_infer_failure exit 126 → Permission denied cause"

  # ------------------------------------------------------------------
  # 21. _infer_failure sets correct cause for exit 127
  # ------------------------------------------------------------------
  local infer_127
  infer_127="$(_run_logging "
    _infer_failure 'Run cleanup' 127 'missingtool'
    echo \"cause:\$_INFER_CAUSE\"
  ")"
  assert_contains "not found" "$infer_127" \
    "_infer_failure exit 127 → Command not found cause"

  # ------------------------------------------------------------------
  # 22. _infer_failure: download step triggers network cause
  # ------------------------------------------------------------------
  local infer_download
  infer_download="$(_run_logging "
    _infer_failure 'Download Zoom' 1 'curl'
    echo \"cause:\$_INFER_CAUSE\"
  ")"
  assert_contains "Network" "$infer_download" \
    "_infer_failure Download step → Network failure cause"

  # ------------------------------------------------------------------
  # 23. Path with spaces: _diag_open works when dir has spaces
  # ------------------------------------------------------------------
  local tmp_spaces
  tmp_spaces="$(mktemp -d)/dir with spaces"
  mkdir -p "$tmp_spaces"
  _run_logging_with_open "$tmp_spaces" "log_info 'spaced path test' 'test'" >/dev/null 2>&1
  assert_file_exists "${tmp_spaces}/latest.log" \
    "_diag_open works when the log directory path contains spaces"
  rm -rf "$(dirname "$tmp_spaces")"

  # ------------------------------------------------------------------
  # 24. Missing Zoom path: scripts do not crash when /Applications/zoom.us.app
  #     is absent (this tests the guard-rail pattern in _zoom_core.sh)
  # ------------------------------------------------------------------
  local core_lib="${REPO_ROOT}/tools/_zoom_core.sh"
  if [[ -f "$core_lib" ]]; then
    local no_zoom_exit=0
    bash -c "
      set -uo pipefail
      . '${REPO_ROOT}/tools/_shared_logging.sh' 2>/dev/null
      . '${REPO_ROOT}/tools/mac_spoof.sh' 2>/dev/null || true
      . '${core_lib}' 2>/dev/null
      # core_remove_zoom_data uses 'run rm -rf' but DRY_RUN=true so nothing executes.
      DRY_RUN=true
      # Override ZOOM_DATA_DIRS to a nonexistent temp path.
      ZOOM_DATA_DIRS=('/tmp/zoom_nuke_test_nonexistent_path')
      core_remove_zoom_data
    " 2>/dev/null || no_zoom_exit=$?
    assert_eq "0" "$no_zoom_exit" \
      "core_remove_zoom_data with DRY_RUN=true exits 0 when Zoom not installed"
  else
    skip "tools/_zoom_core.sh not found — skipping DRY_RUN core test"
  fi
}
