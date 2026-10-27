#!/bin/zsh
set -eu
cd "${0:A:h}"
app="dist/Recolle.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build
cp Info.plist "$app/Contents/Info.plist"
xcrun swiftc -parse-as-library Sources/*.swift -o "$app/Contents/MacOS/Recolle" \
  -O -target arm64-apple-macos14.0 -module-cache-path "$PWD/.build/module-cache" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement -lsqlite3
xcrun swift -module-cache-path "$PWD/.build/module-cache" Tools/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
codesign --force --sign - --identifier fr.isaac.recolle "$app"
codesign --verify --strict "$app"
echo "Application prête : $PWD/$app"
