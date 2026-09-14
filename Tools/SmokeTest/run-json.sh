#!/bin/bash
#
# Cross-checks the iterative JSON scanner against Foundation on real data.
#
#   ./Tools/SmokeTest/run-json.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-json-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-json" \
  Tools/SmokeTest/JSONScannerTest.swift $SOURCES

exec "$OUT/picode-json" "$@"
