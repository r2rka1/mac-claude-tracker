#!/bin/bash
# Builds build/ClaudeTracker.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeTracker"
APP="build/ClaudeTracker.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/ClaudeTracker.app"
    pkill -x ClaudeTracker 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed and launched $DEST"
fi
