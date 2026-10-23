#!/bin/bash
# Builds build/StudySnap.app (needs Xcode or the Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/StudySnap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/StudySnap" -framework AppKit -framework Carbon
cp Info.plist "$APP/Contents/"
# Signing with a fixed certificate keeps macOS permissions across rebuilds (see README).
if security find-certificate -c "StudySnap Dev" >/dev/null 2>&1; then
    codesign --force --sign "StudySnap Dev" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP — run: open $APP"
