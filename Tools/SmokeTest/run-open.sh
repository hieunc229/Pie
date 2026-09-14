#!/bin/bash
#
# Resumes a real session through the same path the sidebar uses. Works on a copy
# and asserts the copy is untouched afterwards.
#
#   ./Tools/SmokeTest/run-open.sh [path/to/session.jsonl]
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-open-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-open" \
  Tools/SmokeTest/SessionOpenTest.swift "$APP/Features/Session/TranscriptBuilder.swift" $SOURCES

exec "$OUT/picode-open" "$@"
