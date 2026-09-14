#!/bin/bash
#
# Drives the real PiSessionController against a real `pi --mode rpc` and a
# throwaway extension, exercising the whole extension UI sub-protocol. No model
# request is sent: Pi runs extension commands locally, so this costs nothing.
#
# Everything, including Pi's agent directory, lives in a temporary directory.
#
#   ./Tools/SmokeTest/run-extension.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
TMP="${TMPDIR:-/tmp}"
OUT="${TMP%/}/picode-extension-test"

SDK="$(xcrun --show-sdk-path --sdk macosx)"

rm -rf "$OUT"
mkdir -p "$OUT/agent"
# Pi must load the test extension from a temporary agent directory. PiCode reads
# this variable too (PiPaths), so the harness verifies it agrees with Pi.
export PI_CODING_AGENT_DIR="$OUT/agent"

# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-extension" \
  Tools/SmokeTest/ExtensionUITest.swift \
  "$APP/Features/Session/PiSessionController.swift" \
  "$APP/Features/Session/TranscriptBuilder.swift" \
  $SOURCES

"$OUT/picode-extension" --root "$OUT"
