#!/bin/bash
#
# Checks that PiCode resolves Pi's config locations exactly like Pi does, and
# that Pi really writes where PiCode claims. Everything happens in a temporary
# directory; nothing in ~/.pi is read for writing and no model request is sent.
#
#   ./Tools/SmokeTest/run-paths.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-paths-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-paths" \
  Tools/SmokeTest/PiPathsTest.swift $SOURCES

exec "$OUT/picode-paths"
