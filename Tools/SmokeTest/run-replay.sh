#!/bin/bash
#
# Replays every real session file through PiCode's parsers. Read-only: it never
# writes to ~/.pi/agent.
#
#   ./Tools/SmokeTest/run-replay.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-replay-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-replay" \
  Tools/SmokeTest/SessionReplayTest.swift "$APP/Features/Session/TranscriptBuilder.swift" $SOURCES

exec "$OUT/picode-replay"
