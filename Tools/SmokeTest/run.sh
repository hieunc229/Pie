#!/bin/bash
#
# PiCode RPC smoke test.
#
# Compiles the Foundation-only half of the app (Models, Services, Shared) with
# Tools/SmokeTest/RPCSmokeTest.swift and runs it against the real `pi` binary.
# This is the fastest way to prove the RPC layer still works after a change,
# without launching the GUI.
#
#   ./Tools/SmokeTest/run.sh
#
# It never sends a model prompt, so it does not spend API credits, and it
# removes the throwaway session it creates.
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-smoke-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-smoke" \
  Tools/SmokeTest/RPCSmokeTest.swift $SOURCES

exec "$OUT/picode-smoke"
