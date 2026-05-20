#!/usr/bin/env bash
# tools/_shared_logging.sh — Shared diagnostic logging helpers for Zoom Nuke scripts.
#
# SOURCED, never executed directly.  Compatible with bash 3.2+ (macOS default).
#
# Usage in a caller script:
#
#   TOOLS_DIR="$(cd "$(dirname "$0")/tools" && pwd -P)"
#   . "$TOOLS_DIR/_shared_logging.sh"
#   _diag_open "$HOME/Library/Logs/Zoom Nuke" "$VERSION"
#
#   log_info    "Checking requirements..."          "requirements"
#   log_step    "Killing Zoom processes"            "zoom_kill"
#   log_success "Zoom removed"                     "zoom_kill"
#   log_warn    "MAC spoof not supported on M1"    "mac_spoof"
#   log_error   "Download failed"                  "download" "exit=1"
#
#   run_logged_command "Download Zoom" curl -L ...
#
#   write_diagnostic_summary
#   _diag_close
#
# Structured lines are written to FD 3 (the diagnostic log file).
# Human-readable (emoji-prefixed) lines go to stdout as usual.
# Do NOT log passwords, sudo credentials, session tokens, or cookies.

# ---------------------------------------------------------------------------
# Guard against double-sourcing
# ---------------------------------------------------------------------------
if [[ "${_SHARED_LOGGING_LOADED:-}" == "1" ]]; then return 0; fi
_SHARED_LOGGING_LOADED=1

# ---------------------------------------------------------------------------
# Diagnostic log state (set by _diag_open; used by all log_ functions)
# ---------------------------------------------------------------------------
_DIAG_DIR=""       # ~/Library/Logs/Zoom Nuke
_DIAG_LOG=""       # full path to latest.log (written via FD 3)
_DIAG_FD_OPEN=0    # 1 once FD 3 is connected to a file

# Summary variables — set by run_logged_command and callers on failure.
DIAG_RESULT="SUCCESS"
DIAG_FAILED_STEP=""
DIAG_FAILED_COMMAND=""
DIAG_EXIT_CODE="0"
DIAG_CAUSE=""
DIAG_FIX=""
DIAG_RUN_MODE="standard"

# ---------------------------------------------------------------------------
# _diag_open DIR [SCRIPT_VERSION]
# Creates the log directory, opens latest.log on FD 3, writes a session header.
# Call once from setup_logging() or equivalent, after argument parsing.
# ---------------------------------------------------------------------------
_diag_open() {
  local dir="${1:-$HOME/Library/Logs/Zoom Nuke}"
  local script_ver="${2:-unknown}"

  _DIAG_DIR="$dir"
  _DIAG_LOG="$dir/latest.log"

  # Create directory if missing (non-fatal if it fails).
  mkdir -p "$_DIAG_DIR" 2>/dev/null || true

  # Archive existing latest.log before overwriting.
  if [[ -f "$_DIAG_LOG" ]]; then
    local stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"
    mv "$_DIAG_LOG" "$_DIAG_DIR/zoom-nuke-${stamp}.log" 2>/dev/null || true
  fi

  # Open FD 3 for writing to latest.log.
  exec 3>"$_DIAG_LOG" 2>/dev/null && _DIAG_FD_OPEN=1 || true

  # Write header to the diagnostic file.
  _diag_raw "zoom-nuke diagnostic log"
  _diag_raw "Started:        $(date)"
  _diag_raw "Script version: $script_ver"
  _diag_raw "macOS:          $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  _diag_raw "Architecture:   $(uname -m 2>/dev/null || echo unknown)"
  _diag_raw "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _diag_raw ""
}

# ---------------------------------------------------------------------------
# _diag_close
# Close FD 3.  Call after write_diagnostic_summary.
# ---------------------------------------------------------------------------
_diag_close() {
  if [[ "$_DIAG_FD_OPEN" == "1" ]]; then
    exec 3>&- 2>/dev/null || true
    _DIAG_FD_OPEN=0
  fi
}

# ---------------------------------------------------------------------------
# _diag_raw TEXT
# Write TEXT directly to FD 3 (no timestamp/level prefix).
# ---------------------------------------------------------------------------
_diag_raw() {
  if [[ "$_DIAG_FD_OPEN" == "1" ]]; then
    printf '%s\n' "$1" >&3 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# _diag_write LEVEL COMPONENT MESSAGE [EXTRAS...]
# Write one structured line to FD 3.
# Format: [YYYY-MM-DD HH:MM:SS] [LEVEL] [component] message | extra...
# ---------------------------------------------------------------------------
_diag_write() {
  local level="$1" component="$2" message="$3"
  shift 3
  local ts extras="" e
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  for e in "$@"; do
    extras="$extras | $e"
  done
  _diag_raw "[$ts] [$level] [$component] $message$extras"
}

# ---------------------------------------------------------------------------
# Public log functions
# All accept: MESSAGE COMPONENT [EXTRAS...]
# ---------------------------------------------------------------------------

log_info() {
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "INFO" "$comp" "$msg" "$@"
}

log_step() {
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "STEP" "$comp" "$msg" "$@"
  echo "▶  $msg"
}

log_success() {
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "SUCCESS" "$comp" "$msg" "$@"
}

log_warn() {
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "WARNING" "$comp" "$msg" "$@"
}

log_error() {
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "ERROR" "$comp" "$msg" "$@"
}

log_debug() {
  # Only written to the diagnostic file; not echoed to stdout.
  local msg="$1" comp="${2:-general}"; shift 2 || shift "$#"
  _diag_write "DEBUG" "$comp" "$msg" "$@"
}

# ---------------------------------------------------------------------------
# log_progress STEP TOTAL LABEL
#
# Emits a machine-parseable progress marker to BOTH stdout and FD 3 so the
# Swift UI can drive a determinate progress bar without shell surgery.
#
# Format (stdout): [PROGRESS] <step>/<total> <label>
# The Swift parser splits on the first space after the ratio to get label.
# ---------------------------------------------------------------------------
log_progress() {
  local step="$1" total="$2" label="$3"
  printf '[PROGRESS] %s/%s %s\n' "$step" "$total" "$label"
  _diag_write "PROGRESS" "progress" "$label" "step=$step" "total=$total"
}

# ---------------------------------------------------------------------------
# run_logged_command STEP_NAME CMD [ARGS...]
#
# Runs CMD with ARGS, respecting DRY_RUN.  Logs:
#   - The step name and exact command
#   - Exit code and duration
#   - Likely failure reason and suggested fix when exit != 0
#   - Sets DIAG_FAILED_STEP / DIAG_FAILED_COMMAND / DIAG_EXIT_CODE /
#     DIAG_CAUSE / DIAG_FIX on failure
#
# Stdout/stderr from the command flow normally (already tee'd to log files by
# the caller's setup_logging()).  This function does NOT swallow them.
# ---------------------------------------------------------------------------
run_logged_command() {
  local step_name="$1"; shift
  local cmd_str="$*"

  log_step "$step_name" "cmd_runner" "cmd=$cmd_str"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY RUN] Would run: $cmd_str" "cmd_runner"
    return 0
  fi

  local start_ts exit_code duration
  start_ts="$(date +%s)"
  exit_code=0
  "$@" || exit_code=$?
  duration=$(( $(date +%s) - start_ts ))

  if [[ "$exit_code" -eq 0 ]]; then
    log_success "$step_name" "cmd_runner" "exit=0" "duration=${duration}s"
  else
    _infer_failure "$step_name" "$exit_code" "$1"
    DIAG_FAILED_STEP="$step_name"
    DIAG_FAILED_COMMAND="$cmd_str"
    DIAG_EXIT_CODE="$exit_code"
    DIAG_CAUSE="$_INFER_CAUSE"
    DIAG_FIX="$_INFER_FIX"
    DIAG_RESULT="FAILED"
    log_error "$step_name failed" "cmd_runner" \
      "exit=$exit_code" "duration=${duration}s" "cause=$_INFER_CAUSE"
    _diag_raw "   fix: $_INFER_FIX"
  fi

  return "$exit_code"
}

# ---------------------------------------------------------------------------
# _infer_failure STEP EXIT_CODE CMD
# Sets _INFER_CAUSE and _INFER_FIX based on common failure patterns.
# Compatible with bash 3.2 — no namerefs.
# ---------------------------------------------------------------------------
_INFER_CAUSE=""
_INFER_FIX=""

_infer_failure() {
  local step="$1" code="$2" cmd="$3"

  _INFER_CAUSE="Unexpected failure (exit $code)"
  _INFER_FIX="Check the full log at: ${_DIAG_LOG:-\~/Library/Logs/Zoom Nuke/latest.log}"

  case "$code" in
    126)
      _INFER_CAUSE="Permission denied — command not executable"
      _INFER_FIX="Run: chmod +x $(basename "$cmd" 2>/dev/null || echo "$cmd")"
      ;;
    127)
      _INFER_CAUSE="Command not found: $cmd"
      _INFER_FIX="Ensure the required tool is installed and on PATH"
      ;;
    130)
      _INFER_CAUSE="Interrupted by user (SIGINT)"
      _INFER_FIX="Run again and allow the process to complete"
      ;;
    *)
      # Match on step name keywords (bash 3.2 compatible — no ${var,,}).
      case "$step" in
        *[Dd]ownload*|*[Cc]url*|*[Nn]etwork*)
          _INFER_CAUSE="Network failure or DNS resolution error"
          _INFER_FIX="Check your internet connection and try again"
          ;;
        *[Ii]nstall*|*[Pp]kg*|*[Ii]nstaller*)
          _INFER_CAUSE="Installation failed — possible disk space or permission issue"
          _INFER_FIX="Ensure at least 500 MB free space and that you have admin rights"
          ;;
        *[Ss]ignature*|*[Vv]erif*)
          _INFER_CAUSE="Package signature verification failed"
          _INFER_FIX="Retry — may be a partial or corrupted download"
          ;;
        *[Ss]udo*)
          _INFER_CAUSE="sudo access denied or credential timeout"
          _INFER_FIX="Run from a Terminal window with admin rights"
          ;;
        *[Kk]ill*|*[Pp]rocess*)
          _INFER_CAUSE="Could not terminate Zoom processes"
          _INFER_FIX="Manually quit Zoom and retry, or restart your Mac"
          ;;
        *[Dd][Nn][Ss]*|*[Ff]lush*)
          _INFER_CAUSE="DNS cache flush failed"
          _INFER_FIX="Retry with admin rights; DNS flush is non-critical"
          ;;
        *)
          _INFER_CAUSE="Unexpected failure at step: $step"
          _INFER_FIX="Export the diagnostic log (Copy Log / Export Log in the app) and review it"
          ;;
      esac
      ;;
  esac
}

# ---------------------------------------------------------------------------
# redact_log_line LINE
# Returns a lightly redacted version of LINE (stdout).
# Replaces home path with ~ and serial-number patterns.
# Heavy redaction (email, UUID, IP) is handled on the Swift side at export.
# ---------------------------------------------------------------------------
redact_log_line() {
  local line="$1"
  # Redact any /Users/<name>[/rest] pattern with ~[/rest] using sed.
  # This catches all usernames, not just the current $HOME.
  # Also masks hardware serial-number patterns.
  line="$(printf '%s' "$line" | sed \
    -e 's|/Users/[^/[:space:]]*|~|g' \
    -e 's/Serial Number[^:]*: [A-Z0-9][A-Z0-9]*/Serial Number: [redacted]/g' \
    2>/dev/null || printf '%s' "$line")"
  printf '%s\n' "$line"
}

# ---------------------------------------------------------------------------
# write_diagnostic_summary
# Prints the structured summary block to BOTH stdout (UI / tee log) and FD 3.
# Call at the very end of main(), including from ERR traps.
# ---------------------------------------------------------------------------
write_diagnostic_summary() {
  local mac_ver arch ts
  mac_ver="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"

  local log_path="${_DIAG_LOG:-${LOG:-~/zoom_fix.log}}"

  # Emit to stdout so the Swift UI captures it for latestSummary detection.
  printf '\n'
  printf '%s\n' "========== Diagnostic Summary =========="
  printf 'Generated:      %s\n' "$ts"
  printf 'Result:         %s\n' "${DIAG_RESULT:-UNKNOWN}"
  printf 'Failed Step:    %s\n' "${DIAG_FAILED_STEP:-(none)}"
  printf 'Failed Command: %s\n' "${DIAG_FAILED_COMMAND:-(none)}"
  printf 'Exit Code:      %s\n' "${DIAG_EXIT_CODE:-0}"
  printf 'Likely Cause:   %s\n' "${DIAG_CAUSE:-(none)}"
  printf 'Suggested Fix:  %s\n' "${DIAG_FIX:-(none)}"
  printf 'Script Version: %s\n' "${VERSION:-unknown}"
  printf 'macOS Version:  %s\n' "$mac_ver"
  printf 'Architecture:   %s\n' "$arch"
  printf 'Run Mode:       %s\n' "${DIAG_RUN_MODE:-standard}"
  printf 'Log Path:       %s\n' "$log_path"
  printf '%s\n' "======================================="
  printf '\n'
}
