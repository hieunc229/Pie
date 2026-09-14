#!/bin/bash
#
# Sidebar geometry + click harness.
#
#   ./Tools/SmokeTest/run-sidebar-click.sh
#
# Proves that clicking a project row really folds its chats in a
# `NavigationSplitView` sidebar, and measures the row highlight's horizontal
# insets. Needs a GUI session (not SSH): it renders a window and clicks it.
#
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Compile against the real metrics rather than a copy of the numbers.
python3 - "$ROOT/PiCode/Features/Sidebar/SidebarView.swift" "$WORK/SidebarStyle.swift" <<'PY'
import sys
source, destination = sys.argv[1], sys.argv[2]
text = open(source).read()
start = text.index('enum SidebarStyle')
end = text.index('struct SidebarView')
open(destination, 'w').write('import SwiftUI\n\n' + text[start:end])
PY

echo "== the view wires what this harness measures =="
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
check_source "$SIDEBAR" 'state.toggleCollapsed(project: project)' \
    "clicking a project folds its chats"
check_source "$SIDEBAR" '.padding(.horizontal, SidebarStyle.rowHighlightInset)' \
    "the row highlight is inset on both sides"
if [ "$fail" -ne 0 ]; then
    echo
    echo "RESULT: the sidebar source no longer matches what this harness measures"
    exit 1
fi

echo
echo "== click a real row, and measure the pill =="
SDK="$(xcrun --show-sdk-path --sdk macosx)"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" -swift-version 5 \
    "$WORK/SidebarStyle.swift" "$ROOT/Tools/SmokeTest/WindowPixels.swift" \
    "$ROOT/Tools/SmokeTest/SidebarClickTest.swift" \
    -o "$WORK/sidebar-click" 2>&1 | grep -v "deprecated in macOS 14" || true

"$WORK/sidebar-click"
