#!/usr/bin/env bash
#
# Measures the sidebar's one visual promise: a session title starts where its
# project's name starts. Renders the real layout in a window and captures that
# window itself, so it needs a GUI session (not SSH) but no screen-recording
# permission.
#
# Run: ./Tools/SmokeTest/run-sidebar-align.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

WORK="${TMPDIR:-/tmp%/}/picode-sidebar-align"
rm -rf "$WORK"
mkdir -p "$WORK"

# Compile against the real metrics rather than a copy of the numbers.
python3 - "$ROOT/PiCode/Features/Sidebar/SidebarView.swift" "$WORK/SidebarMetrics.swift" <<'PY'
import sys
source, destination = sys.argv[1], sys.argv[2]
text = open(source).read()
start = text.index('enum SidebarMetrics')
end = text.index('struct SidebarView')
open(destination, 'w').write('import SwiftUI\n\n' + text[start:end])
PY

echo "== the view wires the metrics the way the measurement assumes =="
fail=0
check_source() {
    if grep -qF "$2" "$1"; then
        echo "  ok   $3"
    else
        echo "  FAIL $3"
        fail=1
    fi
}
SIDEBAR="$ROOT/PiCode/Features/Sidebar/SidebarView.swift"
check_source "$SIDEBAR" '.frame(width: SidebarMetrics.projectIconSize' \
    "the project glyph has a fixed width, so the indent is exact"
check_source "$SIDEBAR" '.padding(.leading, SidebarMetrics.titleIndent)' \
    "a session title is indented past the glyph"
check_source "$SIDEBAR" '.font(SidebarMetrics.rowFont)' \
    "the shared row font is what both use"
if grep -q 'bubble.left' "$SIDEBAR"; then
    echo "  FAIL a session row still draws a chat glyph"
    fail=1
else
    echo "  ok   session rows draw no chat glyph"
fi
if grep -q 'messageCount) messages' "$SIDEBAR"; then
    echo "  FAIL a session row still shows a message count"
    fail=1
else
    echo "  ok   the timestamp and message count are gone from the row"
fi
if [ "$fail" -ne 0 ]; then
    echo
    echo "RESULT: the sidebar source no longer matches what this harness measures"
    exit 1
fi

echo
echo "== measure what macOS actually renders =="
SDK="$(xcrun --show-sdk-path --sdk macosx)"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" -swift-version 5 \
    "$WORK/SidebarMetrics.swift" "$ROOT/Tools/SmokeTest/SidebarAlignTest.swift" \
    -o "$WORK/sidebar-align" 2>&1 | grep -v "deprecated in macOS 14" || true

"$WORK/sidebar-align"
