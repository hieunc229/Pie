#!/bin/bash
#
# Verifies the two pure steps of session naming: a completion into a title, and
# the fallback name when Pi cannot answer. No model is called and nothing is
# written — it compiles only the Foundation half of the app.
#
#   ./Tools/SmokeTest/run-title.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
TMP="${TMPDIR:-/tmp}"
OUT="${TMP%/}/picode-title-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

rm -rf "$OUT"
mkdir -p "$OUT"

# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-title" \
  Tools/SmokeTest/SessionTitleTest.swift $SOURCES

exec "$OUT/picode-title" "$@"
