#!/bin/bash
# Builds build/StudySnap.app (needs Xcode or the Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/StudySnap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/StudySnap" -framework AppKit -framework Carbon
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP — run: open $APP"
