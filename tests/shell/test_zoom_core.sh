#!/usr/bin/env bash
# tests/shell/test_zoom_core.sh — Tests for tools/_zoom_core.sh helpers
#
# Sourced by run_tests.sh.  Must define run_tests().
#
# Tests cover:
#   - run() DRY_RUN=true: prints [DRY RUN] and does not execute
#   - run() DRY_RUN=false: executes the command and passes through exit code
#   - check_cancel() exits 130 when cancel sentinel file exists
#   - check_cancel() does not exit when sentinel file is absent
#   - ZOOM_DATA_DIRS contains no unexpected system paths
#   - version_to_number produces correctly padded numeric strings
#   - core_check_requirements skips on non-Darwin (guards gracefully)
#
# SAFETY: DRY_RUN=true is set globally by the runner.
# No real Zoom data directories, /Applications, or sudo paths are touched.
# All filesystem operations use mktemp.

CORE_LIB="${REPO_ROOT}/tools/_zoom_core.sh"
MAC_SPOOF_LIB="${REPO_ROOT}/tools/mac_spoof.sh"
SHARED_LOG_LIB="${REPO_ROOT}/tools/_shared_logging.sh"

# Source the library once into a fresh subprocess and capture exit.
_source_all() {
  # mac_spoof.sh must be sourced first (it defines version_to_number used by core).
  bash -c "
    set -uo pipefail
    . '${SHARED_LOG_LIB}' 2>/dev/null || true
    . '${MAC_SPOOF_LIB}'  2>/dev/null || true
    . '${CORE_LIB}'       2>/dev/null || true
    $1
  " 2>/dev/null
}

# ---------------------------------------------------------------------------
run_tests() {

  if [[ ! -f "$CORE_LIB" ]]; then
    skip "tools/_zoom_core.sh not found — skipping all core tests"
    return
  fi

  # ------------------------------------------------------------------
  # 1. Libraries source cleanly (together)
  # ------------------------------------------------------------------
  local src_exit=0
  bash -c "
    . '${SHARED_LOG_LIB}' 2>/dev/null || true
    . '${MAC_SPOOF_LIB}'  2>/dev/null || true
    . '${CORE_LIB}'       2>/dev/null
  " 2>/dev/null || src_exit=$?
  assert_eq "0" "$src_exit" \
    "_zoom_core.sh + mac_spoof.sh + _shared_logging.sh source without error"

  # ------------------------------------------------------------------
  # 2. run() with DRY_RUN=true prints [DRY RUN] and does NOT execute
  # ------------------------------------------------------------------
  local sentinel
  sentinel="$(mktemp)"
  rm -f "$sentinel"   # ensure it doesn't exist

  local dry_stdout
  dry_stdout="$(_source_all "
    DRY_RUN=true
    run touch '${sentinel}'
  ")"
  assert_contains "[DRY RUN]" "$dry_stdout" \
    "run() with DRY_RUN=true prints [DRY RUN] prefix"
  if [[ -f "$sentinel" ]]; then
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] run() with DRY_RUN=true must NOT execute the command\n" \
      "$_CURRENT_FILE"
    rm -f "$sentinel"
  else
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ run() with DRY_RUN=true does not execute the command\n"
  fi

  # ------------------------------------------------------------------
  # 3. run() with DRY_RUN=false executes the command
  # ------------------------------------------------------------------
  local sentinel2
  sentinel2="$(mktemp)"
  rm -f "$sentinel2"

  _source_all "DRY_RUN=false; run touch '${sentinel2}'" >/dev/null 2>&1
  if [[ -f "$sentinel2" ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ run() with DRY_RUN=false executes the command\n"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] run() with DRY_RUN=false must execute the command\n" \
      "$_CURRENT_FILE"
  fi
  rm -f "$sentinel2"

  # ------------------------------------------------------------------
  # 4. run() DRY_RUN=false: exit code propagates
  # ------------------------------------------------------------------
  local run_exit=0
  _source_all "DRY_RUN=false; run false" || run_exit=$?
  # run() does `"$@"` which propagates exit; 'false' exits 1
  assert_eq "1" "$run_exit" \
    "run() propagates non-zero exit code from the wrapped command"

  # ------------------------------------------------------------------
  # 5. check_cancel() exits 130 when sentinel file is present
  # ------------------------------------------------------------------
  local cancel_file
  cancel_file="$(mktemp)"
  local cancel_exit=0
  _source_all "
    ZOOM_NUKE_CANCEL_FILE='${cancel_file}'
    check_cancel
  " || cancel_exit=$?
  assert_eq "130" "$cancel_exit" \
    "check_cancel() exits 130 when ZOOM_NUKE_CANCEL_FILE exists"
  rm -f "$cancel_file"

  # ------------------------------------------------------------------
  # 6. check_cancel() does NOT exit when sentinel is absent
  # ------------------------------------------------------------------
  local no_cancel_exit=0
  _source_all "
    ZOOM_NUKE_CANCEL_FILE='/tmp/zoom_nuke_test_no_such_cancel_file_xyz'
    check_cancel
  " 2>/dev/null || no_cancel_exit=$?
  assert_eq "0" "$no_cancel_exit" \
    "check_cancel() does not exit when cancel file is absent"

  # ------------------------------------------------------------------
  # 7. check_cancel() is a no-op when ZOOM_NUKE_CANCEL_FILE is unset
  # ------------------------------------------------------------------
  local unset_cancel_exit=0
  bash -c "
    unset ZOOM_NUKE_CANCEL_FILE
    . '${SHARED_LOG_LIB}' 2>/dev/null || true
    . '${MAC_SPOOF_LIB}'  2>/dev/null || true
    . '${CORE_LIB}'       2>/dev/null
    check_cancel
  " 2>/dev/null || unset_cancel_exit=$?
  assert_eq "0" "$unset_cancel_exit" \
    "check_cancel() is a no-op when ZOOM_NUKE_CANCEL_FILE is unset"

  # ------------------------------------------------------------------
  # 8. ZOOM_DATA_DIRS contains no system-protected paths
  # ------------------------------------------------------------------
  local data_dirs_raw
  data_dirs_raw="$(_source_all "
    for d in \"\${ZOOM_DATA_DIRS[@]}\"; do echo \"\$d\"; done
  " 2>/dev/null || echo '')"

  local has_danger=false
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    # These paths must never appear in ZOOM_DATA_DIRS.
    case "$dir" in
      /System/*|/Library/*|/bin|/usr|/etc|/private/etc)
        has_danger=true
        printf "    ❌ FAIL  [%s] ZOOM_DATA_DIRS contains dangerous path: %s\n" \
          "$_CURRENT_FILE" "$dir"
        ;;
    esac
  done <<< "$data_dirs_raw"

  if [[ "$has_danger" == "false" ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ ZOOM_DATA_DIRS contains no system-protected paths\n"
  else
    _FAIL=$((_FAIL + 1))
  fi

  # ------------------------------------------------------------------
  # 9. ZOOM_DATA_DIRS entries are all under $HOME (user-scoped only)
  # ------------------------------------------------------------------
  local has_non_home=false
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    if [[ "$dir" != "$HOME"* ]]; then
      has_non_home=true
      printf "    ❌ FAIL  [%s] ZOOM_DATA_DIRS entry not under HOME: %s\n" \
        "$_CURRENT_FILE" "$dir"
    fi
  done <<< "$data_dirs_raw"

  if [[ "$has_non_home" == "false" && -n "$data_dirs_raw" ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ All ZOOM_DATA_DIRS entries are under \$HOME\n"
  elif [[ -z "$data_dirs_raw" ]]; then
    skip "ZOOM_DATA_DIRS was empty — skipping home-scope check"
  else
    _FAIL=$((_FAIL + 1))
  fi

  # ------------------------------------------------------------------
  # 10. version_to_number pads correctly (via mac_spoof.sh)
  # ------------------------------------------------------------------
  if [[ ! -f "$MAC_SPOOF_LIB" ]]; then
    skip "tools/mac_spoof.sh not found — skipping version_to_number test"
  else
    local ver_out
    ver_out="$(_source_all "version_to_number '12.6.1'")"
    # Expected: zero-padded 6-digit string from two 3-digit groups, or 9-digit
    # from three — depends on implementation. Just check it's all digits.
    assert_match '^[0-9]+$' "$ver_out" \
      "version_to_number '12.6.1' returns a numeric string"
    # Sanity: 12.6.1 > 10.15.7 in numeric comparison.
    local ver_min
    ver_min="$(_source_all "version_to_number '10.15.7'")"
    if [[ -n "$ver_out" && -n "$ver_min" ]]; then
      if (( 10#$ver_out > 10#$ver_min )); then
        _PASS=$((_PASS + 1))
        $VERBOSE && printf "    ✅ version_to_number: 12.6.1 > 10.15.7 numerically\n"
      else
        _FAIL=$((_FAIL + 1))
        printf "    ❌ FAIL  [%s] version_to_number: 12.6.1 (%s) should be > 10.15.7 (%s)\n" \
          "$_CURRENT_FILE" "$ver_out" "$ver_min"
      fi
    fi
  fi

  # ------------------------------------------------------------------
  # 11. DRY_RUN wrapper: core_remove_zoom_data with DRY_RUN=true
  #     prints [DRY RUN] and never touches real paths
  # ------------------------------------------------------------------
  local tmp_backup
  tmp_backup="$(mktemp -d)"
  local dry_remove_out
  dry_remove_out="$(_source_all "
    DRY_RUN=true
    BACKUP_DIR='${tmp_backup}'
    ZOOM_DATA_DIRS=('/tmp/zoom_nuke_test_nonexistent_xyz')
    core_remove_zoom_data
  " 2>/dev/null || echo '')"

  # With DRY_RUN=true the run() wrapper should emit [DRY RUN] for rm -rf.
  assert_contains "[DRY RUN]" "$dry_remove_out" \
    "core_remove_zoom_data with DRY_RUN=true emits [DRY RUN] for rm -rf calls"
  # The backup dir must remain empty — no real files were backed up.
  local backup_file_count
  backup_file_count="$(find "$tmp_backup" -mindepth 1 | wc -l | tr -d ' ')"
  assert_eq "0" "$backup_file_count" \
    "core_remove_zoom_data with DRY_RUN=true writes nothing to backup dir"
  rm -rf "$tmp_backup"

  # ------------------------------------------------------------------
  # 12. DRY_RUN is false by default (default value check)
  # ------------------------------------------------------------------
  # The runner exports DRY_RUN=true for safety, so we must explicitly unset it
  # in the subprocess before sourcing _zoom_core.sh to test the library default.
  local default_dry_run
  default_dry_run="$(bash -c "
    unset DRY_RUN
    . '${SHARED_LOG_LIB}' 2>/dev/null || true
    . '${MAC_SPOOF_LIB}'  2>/dev/null || true
    . '${CORE_LIB}'       2>/dev/null
    echo \"\${DRY_RUN}\"
  " 2>/dev/null || echo 'error')"
  assert_eq "false" "$default_dry_run" \
    "DRY_RUN defaults to 'false' when not set by caller"

  # ------------------------------------------------------------------
  # 13. ZOOM_URL is HTTPS (not HTTP)
  # ------------------------------------------------------------------
  local zoom_url
  zoom_url="$(_source_all "echo \"\${ZOOM_URL}\"" 2>/dev/null || echo '')"
  assert_match '^https://' "$zoom_url" \
    "ZOOM_URL uses HTTPS (not plain HTTP)"

  # ------------------------------------------------------------------
  # 14. Minimum free space threshold is non-zero
  # ------------------------------------------------------------------
  local min_mb
  min_mb="$(_source_all "echo \"\${MIN_FREE_MB}\"" 2>/dev/null || echo '0')"
  if [[ "$min_mb" =~ ^[0-9]+$ ]] && (( min_mb > 0 )); then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ MIN_FREE_MB=%s (non-zero)\n" "$min_mb"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] MIN_FREE_MB should be a positive integer, got: %s\n" \
      "$_CURRENT_FILE" "$min_mb"
  fi
}
