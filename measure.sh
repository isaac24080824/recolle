#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build
fixture=$(mktemp -d "$PWD/.build/performance-XXXXXX")
trap 'rm -rf "$fixture"' EXIT
xcrun swiftc -O -parse-as-library Sources/Models.swift Sources/Database.swift Tools/MeasurePerformance.swift \
  -o .build/MeasurePerformance -module-cache-path "$PWD/.build/module-cache" \
  -framework AppKit -lsqlite3
.build/MeasurePerformance "$fixture"
