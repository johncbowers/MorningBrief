#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/Morning Brief.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path /tmp/morning-brief-module-cache Sources/BriefingCore.swift Sources/App.swift -o "$APP/Contents/MacOS/MorningBrief" -framework SwiftUI -framework AppKit -framework WebKit -framework JavaScriptCore -framework ServiceManagement
cp Resources/*.js Resources/*.LICENSE Resources/*.icns Resources/*.md "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
printf 'Built: %s\n' "$APP"
