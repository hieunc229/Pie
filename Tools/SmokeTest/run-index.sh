#!/bin/bash
#
# Lists exactly what the sidebar will show and checks it against the filesystem,
# so "is this real or just UI?" has an answer that does not require reading code.
#
#   ./Tools/SmokeTest/run-index.sh [--verbose]
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-index-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-index" \
  Tools/SmokeTest/IndexListTest.swift $SOURCES

exec "$OUT/picode-index" "$@"
