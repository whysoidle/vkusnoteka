#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcodebuild -checkFirstLaunchStatus
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
cd "$TASK_ROOT/app"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build macos --release --no-pub
APP_PATH="$TASK_ROOT/app/build/macos/Build/Products/Release/RecipeVault.app"
"$TASK_ROOT/scripts/package-macos.sh" "$APP_PATH"
