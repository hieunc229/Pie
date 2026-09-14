#!/bin/bash
#
# Verifies the provider/credential configuration PiCode writes is the
# configuration Pi actually reads. Runs entirely in a throwaway agent directory,
# so the user's own credentials are never touched and no model is called.
#
#   ./Tools/SmokeTest/run-providers.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
TMP="${TMPDIR:-/tmp}"
OUT="${TMP%/}/picode-provider-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
PI="/Users/mac/.nvm/versions/node/v24.15.0/bin/pi"

rm -rf "$OUT"
mkdir -p "$OUT/agent"
# PiCode resolves Pi's configuration through this variable, and the child pi
# processes inherit it, so the harness configures its own throwaway Pi.
export PI_CODING_AGENT_DIR="$OUT/agent"
export PICODE_TEST_PI="$PI"

# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-providers" \
  Tools/SmokeTest/ProviderConfigTest.swift $SOURCES

exec "$OUT/picode-providers" "$@"
