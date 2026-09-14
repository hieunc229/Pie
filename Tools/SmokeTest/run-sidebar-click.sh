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
check_absent() {
    if grep -qF "$2" "$1"; then
        echo "  FAIL $3"
        fail=1
    else
        echo "  ok   $3"
    fi
}
SIDEBAR="$ROOT/PiCode/Features/Sidebar/SidebarView.swift"
APPSTATE="$ROOT/PiCode/App/AppState.swift"
check_source "$SIDEBAR" 'state.toggleCollapsed(project: project)' \
    "clicking a project folds its chats"
check_source "$SIDEBAR" '.padding(.horizontal, SidebarStyle.rowHighlightInset)' \
    "the row highlight is inset on both sides"
# Both row types, and only those two, must go through the shared chrome: a row
# that draws its own padding or its own `listRowBackground` is how the project
# pill grew taller than a chat's in the first place.
if [ "$(grep -cF '.sidebarRow(fill:' "$SIDEBAR")" = 2 ]; then
    echo "  ok   both rows get their highlight from the shared chrome"
else
    echo "  FAIL the two row types do not both use .sidebarRow(fill:)"
    fail=1
fi
if [ "$(grep -cE '^[[:space:]]*\.listRowBackground\(' "$SIDEBAR")" = 1 ]; then
    echo "  ok   exactly one row background is painted, and it is the shared chrome's"
else
    echo "  FAIL a row paints its own background ($(grep -cE '^[[:space:]]*\.listRowBackground\(' "$SIDEBAR") call sites, expected 1)"
    fail=1
fi
check_absent "$SIDEBAR" 'projectTopMargin' \
    "no vertical margin is left in the sidebar (every row is on one pitch)"
check_absent "$SIDEBAR" 'weight: .medium' \
    "the menu is not medium-weight"
# The fold is asked for first, and nothing about the query may come before it: a
# click that folds nothing is indistinguishable from a broken row. `showsChats`
# must be a straight `!isCollapsed` and must not mention `sidebarQuery` at all.
if grep -qF 'showsChats' "$APPSTATE"; then
    BODY="$(sed -n '/func showsChats/,/^    }/p' "$APPSTATE")"
    if printf '%s' "$BODY" | grep -qF '!isCollapsed(project: project)' \
       && ! printf '%s' "$BODY" | grep -qF 'sidebarQuery'; then
        echo "  ok   a click folds a project even while a search is running"
    else
        echo "  FAIL showsChats consults the query before the fold:"
        printf '%s\n' "$BODY" | sed 's/^/       /'
        fail=1
    fi
else
    echo "  FAIL AppState no longer has a showsChats(of:)"
    fail=1
fi
check_absent "$APPSTATE" 'isEmpty || !isCollapsed' \
    "nothing short-circuits the fold on a non-empty search query"
if [ "$fail" -ne 0 ]; then
    echo
    echo "RESULT: the sidebar source no longer matches what this harness measures"
    exit 1
fi

echo
echo "== click a real row, and measure the pills =="
SDK="$(xcrun --show-sdk-path --sdk macosx)"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" -swift-version 5 \
    "$WORK/SidebarStyle.swift" "$ROOT/Tools/SmokeTest/WindowPixels.swift" \
    "$ROOT/Tools/SmokeTest/SidebarClickTest.swift" \
    -o "$WORK/sidebar-click" 2>&1 | grep -v "deprecated in macOS 14" || true

"$WORK/sidebar-click"
