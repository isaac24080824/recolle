#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc -parse-as-library Sources/Models.swift Sources/Database.swift Tests/CoreTests.swift \
  -o .build/CoreTests -module-cache-path "$PWD/.build/module-cache" \
  -framework AppKit -lsqlite3
.build/CoreTests
xcrun swiftc -parse-as-library Sources/Models.swift Sources/Database.swift Sources/HistoryWorker.swift Sources/HistoryModel.swift Sources/InteractionTrace.swift Tests/AsyncTests.swift \
  -o .build/AsyncTests -module-cache-path "$PWD/.build/module-cache" \
  -framework AppKit -framework ServiceManagement -lsqlite3
.build/AsyncTests
