#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

OUTPUT_DIR="${1:-$REPO_ROOT/dist}"
APP_NAME="Zoom Nuke.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
APP_SCRIPT_SOURCE="$REPO_ROOT/app/Zoom Nuke.applescript"
MAIN_SCRIPT_SOURCE="$REPO_ROOT/Screw1132_Overkill.sh"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This build step requires macOS (osacompile)." >&2
  exit 1
fi

for required_file in "$APP_SCRIPT_SOURCE" "$MAIN_SCRIPT_SOURCE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required file: $required_file" >&2
    exit 1
  fi
done

if ! command -v osacompile >/dev/null 2>&1; then
  echo "osacompile is required but not available." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"

osacompile -o "$APP_PATH" "$APP_SCRIPT_SOURCE"
cp "$MAIN_SCRIPT_SOURCE" "$APP_PATH/Contents/Resources/Screw1132_Overkill.sh"
chmod +x "$APP_PATH/Contents/Resources/Screw1132_Overkill.sh"

echo "Created app bundle:"
echo "  $APP_PATH"
