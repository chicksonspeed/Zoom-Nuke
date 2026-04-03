# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Zoom Nuke is a **macOS-only** privacy/cleanup tool (shell scripts + SwiftUI GUI app). The core product is shell scripts (`zoom_nuke.sh`, `zoom_nuke_overkill.sh`) and a native macOS SwiftUI app (`app/`). There are no backend services, databases, or Docker containers.

### What runs on the Linux Cloud VM

Only shell-script linting and syntax validation can run on the Linux VM. The Swift/SwiftUI build and all macOS runtime tests (`--version`, `--audit`, `--dry-run`, preflight) require macOS. The `tools/validate.sh` script auto-skips macOS-only sections when `uname` is not `Darwin`.

### Lint

```bash
shellcheck --severity=warning \
  zoom_nuke.sh zoom_nuke_overkill.sh "Start Zoom Nuke.command" \
  tools/_zoom_core.sh tools/mac_spoof.sh tools/zoom_protection.sh \
  tools/build_macos_app.sh tools/build_release_bundle.sh \
  tools/build_pkg_installer.sh tools/preflight_check.sh tools/validate.sh
```

There are two pre-existing SC2034 warnings in `tools/preflight_check.sh` (unused variables `MDM_ENROLLED` and `MAC_SPOOF_OK`). These are used in the `--json` output path and are false positives.

### Validate (smoke tests + syntax)

```bash
./tools/validate.sh --verbose
```

This runs repository structure checks, shell syntax (`bash -n`), and on macOS also runs CLI flag validation, `--audit` mode, and preflight checks.

### Build (macOS only)

The Swift app builds via SPM: `swift build`. The distributable `.app` bundle is built with `./tools/build_macos_app.sh`. Both require macOS with Xcode/Swift toolchain.

### CI

See `.github/workflows/pr-validate.yml` — runs shellcheck on Ubuntu, and Swift build + validate + preflight on macOS.
