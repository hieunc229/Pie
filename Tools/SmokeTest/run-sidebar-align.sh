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
python3 - "$ROOT/PiCode/Features/Sidebar/SidebarView.swift" "$ROOT/PiCode/Shared/UI/Typography.swift" "$WORK/SidebarStyle.swift" <<'PY'
import sys
source, typography, destination = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(source).read()
start = text.index('enum SidebarStyle')
end = text.index('struct SidebarView')
shared = open(typography).read()
open(destination, 'w').write('import SwiftUI\n\n' + shared + '\n' + text[start:end])
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
check_source "$SIDEBAR" '.frame(width: SidebarStyle.projectIconSize' \
    "the project glyph has a fixed width, so the indent is exact"
check_source "$SIDEBAR" '.padding(.leading, SidebarStyle.titleIndent)' \
    "the empty-state line is indented past the glyph"
# A running chat's spinner is the *leading* mark, sharing the folder glyph's exact
# slot (the same 11pt frame at the same `projectIconOffset`), so it lines up with
# the project icon above it and a quiet chat's title keeps the same x.
if grep -A12 'if state.isRunning(session)' "$SIDEBAR" | grep -qF 'width: SidebarStyle.projectIconSize'; then
    echo "  ok   a running chat's spinner is drawn in the project glyph's own slot"
else
    echo "  FAIL a running chat's spinner is not in the project glyph's slot"
    fail=1
fi
check_source "$SIDEBAR" '.font(SidebarStyle.rowFont)' \
    "the shared row font is what both use"
check_source "$SIDEBAR" '.sidebarRow(fill: isNewChatHovering' \
    "New chat is a list row, drawn with the project rows' own chrome"
check_source "$SIDEBAR" 'state.newChatInCurrentProject' \
    "the New chat row starts in the project the user is already in"
check_source "$SIDEBAR" 'onOpenPalette' \
    "the search icon raises the command palette"
check_source "$SIDEBAR" '.overlay(alignment: .topTrailing) { searchButton }' \
    "search is an overlay on the sidebar's trailing edge"
check_source "$SIDEBAR" '.padding(.top, SidebarStyle.topBarTopInset)' \
    "the search icon is drawn on the titlebar row"
check_source "$SIDEBAR" '.ignoresSafeArea(.container, edges: .top)' \
    "the search icon leaves the sidebar's safe area for the titlebar row"
check_source "$SIDEBAR" 'state.toggleCollapsed(project: project)' \
    "clicking a project folds its chats (no chevron to click)"
check_source "$SIDEBAR" 'state.showsChats(of: project)' \
    "a folded project hides its chats"
check_source "$SIDEBAR" '.offset(x: -SidebarStyle.projectIconOffset)' \
    "the project glyph is shifted to its own mark beside the search field"
# The menu is one weight: normal. Anything heavier in this file is a regression —
# a heading shouts, and the whole design is that a project is not a heading.
if grep -qE 'weight: \.(medium|semibold|bold|heavy|black|ultraLight|thin|light)|\\.bold\(\)|fontWeight\(' "$SIDEBAR"; then
    echo "  FAIL the sidebar uses a weight other than regular:"
    grep -nE 'weight: \.(medium|semibold|bold|heavy|black|ultraLight|thin|light)|\\.bold\(\)|fontWeight\(' "$SIDEBAR" | sed 's/^/       /'
    fail=1
else
    echo "  ok   every text style in the sidebar is regular weight"
fi
# The rhythm is the list's: a row may not pad itself vertically (that also grows
# its highlight, because `listRowBackground` fills the whole cell). The one
# allowed exception is the half-point on the highlight shape itself, which shrinks
# the pill instead of growing the cell and so leaves a one-point gap between rows.
CHROME="$(sed -n '/struct SidebarRowChrome/,/^}/p' "$SIDEBAR")"
OFFENDERS="$(printf '%s' "$CHROME" | grep -E '\.padding\(\.(top|bottom|vertical)' | grep -vF '.padding(.vertical, 0.5)' || true)"
if [ -n "$OFFENDERS" ]; then
    echo "  FAIL the shared row chrome pads its row vertically, so the rhythm is not uniform"
    printf '%s\n' "$OFFENDERS" | sed 's/^/       /'
    fail=1
else
    echo "  ok   the shared chrome only trims the highlight, so every row is on one pitch"
fi
# The rule above the footer is gone on purpose: the list and the footer share the
# column's background, and the gap is the separation. No Divider is expected in
# the column. Only the SidebarView *column* counts — a row's context menu draws
# its own rules, and those are the menu's, not the column's.
COLUMN="$(sed -n '/^struct SidebarView/,/^\/\/ MARK: - Project row/p' "$SIDEBAR")"
DIVIDERS="$(printf '%s\n' "$COLUMN" | grep -cE '^[[:space:]]*Divider\(\)' || true)"
if [ "$DIVIDERS" = 0 ]; then
    echo "  ok   the column draws no rules; the background is the only separation"
else
    echo "  FAIL the column draws $DIVIDERS Divider(s); none is expected"
    fail=1
fi
if grep -qE 'Section[ ({]' "$SIDEBAR"; then
    echo "  FAIL a project is still a Section (the sidebar turns those into a collapsible group with a chevron)"
    fail=1
else
    echo "  ok   projects are rows, so there is no disclosure chevron"
fi
if grep -qF 'Text("\(project.sessions.count)")' "$SIDEBAR"; then
    echo "  FAIL a project row still shows its session count"
    fail=1
else
    echo "  ok   the session count is gone from the project row"
fi
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
    "$WORK/SidebarStyle.swift" "$ROOT/Tools/SmokeTest/WindowPixels.swift" \
    "$ROOT/Tools/SmokeTest/SidebarAlignTest.swift" \
    -o "$WORK/sidebar-align" 2>&1 | grep -v "deprecated in macOS 14" || true

"$WORK/sidebar-align"
