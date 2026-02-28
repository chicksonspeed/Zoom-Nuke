#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TARGET_SCRIPT="$SCRIPT_DIR/Screw1132_Overkill.sh"

clear
echo "Zoom Nuke Launcher"
echo "=================="
echo

if [[ ! -f "$TARGET_SCRIPT" ]]; then
  echo "Could not find the main script:"
  echo "  $TARGET_SCRIPT"
  echo
  echo "Make sure this launcher stays in the same folder as Screw1132_Overkill.sh."
  read -r -p "Press Enter to close..."
  exit 1
fi

if [[ ! -x "$TARGET_SCRIPT" ]]; then
  chmod +x "$TARGET_SCRIPT" 2>/dev/null || true
fi

echo "This will run a full Zoom cleanup + reinstall."
echo "You may be asked for your macOS password by sudo."
echo

/usr/bin/env bash "$TARGET_SCRIPT" "$@"
EXIT_CODE=$?

echo
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "Finished successfully."
else
  echo "Finished with an error (exit code: $EXIT_CODE)."
fi
echo "Log file: $HOME/zoom_fix.log"
echo
read -r -p "Press Enter to close..."

exit "$EXIT_CODE"
