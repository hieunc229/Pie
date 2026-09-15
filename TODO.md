This is a task list for PiCode, when a task is completed, moved them to the Completed section

To do tasks:

(none)

Completed:

1. for Header:
- either Bell or right nav icon is active (not both), add 6px gap between them, when active, set color to white
- when left menu is closed, set padding on the left of the content to avoid traffic lights / toggle menu buttons overlay
  — `ContentHeader` (`isSidebarVisible`, `leadingInset` 14/104, `HStack(spacing: 6)`, active = full `.primary`); `RootView` passes `isInspectorVisible && !isNotificationsVisible`.

2. for Right menu:
- set content font size (for code) smaller by 2 sizes
- decrease the header height by 1px
  — `ActionCodeBlock`'s diff well now `Typography.codeBlockCompact` (11, = `baseSize - 2`; command/read already were); `ArtifactHeader` / `NotificationsPanel.header` `.padding(.vertical, 15.5)`.

3. for the left menu:
- align traffic lights / toglge menu button / search button icon centered (horizontally)
- only show activity indicator for the running chat sessions, at the moment, looks like all of it is running
  — root cause was the window being `.unifiedCompact` (traffic centre 19pt), not `.unified` (26pt): `SidebarStyle.titlebarRowCenter = 19`, harness window switched to `.unifiedCompact` (verified 18.8pt vs 19.0pt on a live build). `AppState.isRunning` now asks the keyed controller for a path-backed session instead of falling through to the active one.

4. for the textchat
- max height adjust automatically
- minimum (start) is 2 text lines, max is 6 lines, make it scroll if > 6 lines
- remove the first chevron in the model name
- add more spacing between buttons (model name / reasoning effort vs send button)
  — min 2 / max 6 lines + scroll were already in place; removed the hand-drawn `chevron.down` in `modelThinkingMenu`; model/reasoning menu + send/stop now in `HStack(spacing: 10)`.

5. the chatbox floats over the transcript, but while a task is processing the bottom gap sometimes disappears — keep the same bottom spacing always
  — the reserved room was `padding(.bottom, 8 + bottomInset)` on the `LazyVStack`, i.e. *below* the 1pt bottom anchor, so `scrollTo(anchor: .bottom)` aligned the anchor's bottom with the viewport and scrolled the padding out of sight during auto-scroll (short transcripts showed it, long ones did not). The room now sits *above* the anchor in one `VStack(spacing: 0)` — the anchor stays 1pt so “pinned to the bottom” still means the very bottom — and `ConversationView` re-scrolls when `bottomInset` changes as the composer grows. The box also lost its top padding (`ComposerMetrics.boxTopPadding` 9 → 0), so a 2-line prompt is a 2-line box.

6. for the left menu, when a chat session is running, the activity indicator should be at the start of the session name (align with the project icon)
  — `SessionRow`'s spinner moved off the trailing edge into a reserved leading slot drawn in the folder glyph's own 11pt mark at the same `projectIconOffset`; the slot is present for every chat (empty when quiet) so a title never shifts when a chat starts or stops working. `run-sidebar-align.sh` checks the slot wiring and the align harness mirrors the new row structure.

7. for the actions:
- remove number of steps in the group label
- reduce font size (after label), like command / file name / etc, by 2 sizes
- remove duration and right sidebar icon
  — `ToolGroupView`'s header no longer draws the `"\(steps.count) steps"` summary (the run's line names the families instead), and the summary in both the header and `ToolActionRow` is now `Typography.codeBlockCompact` (11, = `baseSize - 2`) rather than `Typography.code`. The running elapsed clock and the per-step duration are gone, and the hover `sidebar.right` glyph is gone, so a step row is just its glyph, label, summary and diff stats.

8. for inline code in the content, reduce font size by 1 size
  — `MarkdownInline.attributed` now sets the `.code` runs to `Typography.codeBlock` (12, = `baseSize - 1`) instead of `Typography.code` (13), so inline code recedes from the sentence it is quoted in the same way a fenced block does. This is the one place inline spans are built, so paragraphs, headings, list items, quotes and table cells all follow.

9. for the content header, add a workspace menu beside the notification bell
  — `ContentHeader` now draws a `Menu` (`equal.square`) between the notification bell and the inspector toggle, with Show/Hide Terminal, Open in Finder and Open in VS Code. The square is always dimmed and takes full ink only on hover — a menu is an affordance, not a state light — while the Show/Hide label and the open panel below carry the terminal's state; the dimming is `.opacity(0.55)` on the `Menu` itself, because a `borderlessButton` menu drops modifiers set inside its label. `RootView` renders `TerminalPanel` under the conversation when `AppState.isTerminalVisible` (persisted as `showTerminal`); the panel is Pi's own bash surface (`TerminalPane`), not a login shell, and is resizable by dragging its top edge. The command palette's `toggleTerminal` and the new `openInVSCode` route through `RootView.perform`. The row is `HStack(spacing: 16)`, the bell carries a fixed 15pt width and its badge an `x: 5` offset, so a count can neither bridge the gap nor shift the menu beside it.
