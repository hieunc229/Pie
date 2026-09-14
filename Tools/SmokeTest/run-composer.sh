#!/bin/bash
#
# Composer harness.
#
#   ./Tools/SmokeTest/run-composer.sh
#
# Two halves:
#
#   1. key handling, against the real `ComposerTextView` in a real window with
#      posted key events (Return / Shift+Return / Option+Return / Command+Return
#      / Escape, in both send-key modes, with and without the suggestion list);
#   2. the box shape, measured from a capture, against the real
#      `ComposerMetrics.cornerRadius`.
#
# Plus source checks for the things that are structure, not behaviour: where each
# control sits on the row, and that nothing else moved back in.
#
# Needs a GUI session (not SSH): it renders a window and posts key events.
#
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ROOT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The two send-key modes are compiled from a stub so `ComposerTextView` can be
# built on its own; these checks keep the stub honest.
PREFERENCES="$ROOT/PiCode/Services/PreferencesStore.swift"
COMPOSER="$ROOT/PiCode/Features/Composer/ComposerView.swift"
TEXTVIEW="$ROOT/PiCode/Features/Composer/ComposerTextView.swift"
SESSION="$ROOT/PiCode/Features/Session/SessionView.swift"

echo "== the composer is wired the way this harness measures =="
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

check_source "$PREFERENCES" 'case returnKey' "SendKey still has a Return-sends mode"
check_source "$PREFERENCES" 'case commandReturn' "SendKey still has a Command-Return-sends mode"
check_absent "$PREFERENCES" 'case shiftReturn' "SendKey has no third mode the harness would miss"

check_source "$COMPOSER" 'ComposerAccessControl(controller: controller)' "access/trust sits in the control row"
check_source "$COMPOSER" 'iconButton("paperclip"' "attach sits in the control row"
check_source "$COMPOSER" '.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: ComposerMetrics.cornerRadius' \
    "the box is the only filled shape, at ComposerMetrics.cornerRadius"
check_source "$COMPOSER" 'onFollowUp: { send(delivery: .followUp) }' "Option-Return can queue a follow-up"
check_absent "$COMPOSER" 'Send as steering message' "the steering/follow-up dropdown is gone"
check_absent "$COMPOSER" 'queued", systemImage: "list.bullet"' "the queue pill is gone"
check_absent "$COMPOSER" 'Label("Interrupt"' "the separate interrupt button is gone"
check_absent "$SESSION" '.background(.bar)' "there is no container background behind the composer"

# Order on the row: paperclip left, model/thinking right. A move is exactly the
# kind of change that leaves the code compiling and the layout wrong.
python3 - "$COMPOSER" <<'PY'
import re, sys
source = open(sys.argv[1]).read()
row = source[source.index('private var controlRow'):source.index('private func iconButton')]
order = ['iconButton("paperclip"', 'ComposerAccessControl(controller: controller)', 'modelMenu', 'thinkingMenu', 'primaryActionButton']
positions = [row.find(token) for token in order]
if all(p >= 0 for p in positions) and positions == sorted(positions):
    print("  ok   the row reads attach · access · model · thinking · send")
else:
    print("  FAIL the row order changed:", dict(zip(order, positions)))
    sys.exit(1)
PY
[ $? -ne 0 ] && fail=1
if [ "$fail" -ne 0 ]; then
    echo
    echo "RESULT: the composer source no longer matches what this harness measures"
    exit 1
fi

echo
echo "== keys and pixels =="
# The metrics enum and the send-key enum are compiled from the real sources; the
# rest is a stub because AppState and a live Pi process are not needed to answer
# what Return does.
python3 - "$COMPOSER" "$WORK/ComposerMetrics.swift" <<'PY'
import sys
source, destination = sys.argv[1], sys.argv[2]
text = open(source).read()
start = text.index('enum ComposerMetrics')
end = text.index('struct ComposerView')
open(destination, 'w').write('import SwiftUI\n\n' + text[start:end])
PY
cat > "$WORK/SendKeyStub.swift" <<'SWIFT'
import Foundation

struct PreferencesStore {
    enum SendKey: String, CaseIterable, Identifiable {
        case returnKey
        case commandReturn

        var id: String { rawValue }
    }
}
SWIFT

SDK="$(xcrun --show-sdk-path --sdk macosx)"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" -swift-version 5 \
    "$WORK/SendKeyStub.swift" "$WORK/ComposerMetrics.swift" \
    "$ROOT/PiCode/Features/Composer/ComposerTextView.swift" \
    "$ROOT/Tools/SmokeTest/WindowPixels.swift" \
    "$ROOT/Tools/SmokeTest/ComposerKeyTest.swift" \
    -o "$WORK/composer" 2>&1 | grep -v "deprecated in macOS 14" || true

"$WORK/composer"
