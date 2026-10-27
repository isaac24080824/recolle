#!/bin/zsh
set -eu
cd "${0:A:h}"

./build.sh
app="dist/Recolle.app"
archive="dist/Recolle-macOS-AppleSilicon.zip"
codesign --verify --strict "$app"
xcrun lipo "$app/Contents/MacOS/Recolle" -verify_arch arm64

if [ -e "$archive" ]; then rm "$archive"; fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(
  cd dist
  shasum -a 256 Recolle-macOS-AppleSilicon.zip > SHA256SUMS.txt
)
echo "Téléchargement prêt : $PWD/$archive"
