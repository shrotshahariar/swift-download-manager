#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/window-sizing-tests/module-cache
swiftc -parse-as-library -swift-version 5 \
  -module-cache-path build/window-sizing-tests/module-cache \
  Sources/StandardAppWindow.swift Tests/WindowSizingChecks.swift \
  -o build/window-sizing-tests/check
build/window-sizing-tests/check
