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

10. for the left menu:
- don't show the harness
- for the actions of project / chat session: only show when hover (otherwise hide it and not taking the space)
  — `SessionRow` no longer draws the harness caption beside the title; the runtime a chat resumes on is still the row's own field and `AppState.open(session:)` already explains the one harness whose adapter cannot resume a saved session, so nothing a user needs was lost with the label. The trailing controls on both row types were already drawn only on hover, but each row reserved their width permanently, so a quiet title stopped one (chat) or two (project) buttons short of the row's trailing edge: the room is now `isHovering ? SidebarStyle.topBarButtonSize * 2 : 0` on `ProjectRow` and `isHovering ? SidebarStyle.topBarButtonSize : 0` on `SessionRow`, so a quiet row's title and its pin run to the row's own edge and the buttons take the space back only while they are visible.

11. for the left menu:
- the hover actions on project / chat rows should be dim, then white when the control itself is hovered
- add a trash (or archive) action to a chat session
- every item in the 3-dots dropdown must have an icon
  — both rows' trailing controls now take their ink from `.foregroundStyle(.primary)` and their dim from `SidebarStyle.actionIdleOpacity` (0.55) applied as an `.opacity` on the control itself: a `borderlessButton` menu snapshots its label as a template image, and the literal `NSColor` these glyphs used resolved against the wrong appearance, which is why they drew black on the dark sidebar (measured on a live build: dim 151-159, full 248-255, against 33/49 surfaces). A chat row now carries a trash button beside its menu, wired to the same confirmed path as the menu's own item (`sessionPendingDeletion` + `.deleteSession`, which raises the confirmation sheet unless the preference is off) and not drawn at all for a chat with nothing on disk, and the row reserves both buttons' width only while they are drawn. Both dropdowns already carried a `Label(_:systemImage:)` on every item; what was invisible was the *menu button* itself — a sidebar `List` draws a `borderlessButton` menu by snapshotting its label, and an image-only label comes back empty there, so the ellipsis is now `Text(Image(systemName: "ellipsis"))` (render lab: image label 0 ink where the text-wrapped one draws).

12. for the left menu:
- when a project has more than 10 chat sessions, show only the last 10, and a 'Show more...' text button below them; clicking it shows all, and folding the project and reopening it shows the first 10 again
- the same for Projects / Pinned Projects: the 10 latest projects, then a show more button
  — one limit (`SidebarStyle.visibleRowLimit`, 10) and one helper (`SidebarView.capped(_:showingAll:)`) give a project's chats and both project headings the same rule: the first ten rows of a list `AppState.sort` has already put newest-first (pinned first, then by `updatedAt` / `mostRecentActivity`), plus a `ShowMoreRow` while the rest are hidden. A project's expansion is view state — `expandedChatLists`, a set of project paths — and the `list`'s `onChange(of: state.expandedProjects)` intersects it with the expanded set, so a fold forgets the expansion and reopening a project shows its ten most recent chats again; the two headings have no fold, so theirs (`showsAllProjects`, `showsAllPinnedProjects`) lasts the session. `ShowMoreRow` is a row, not a footer: same pitch, same hover pill, its text on the names' column (`SidebarStyle.titleIndent`), dimmed (measured 157 peak ink against 223-232 for a name), with the hidden count in its tooltip.

13. when deleting a chat session, it starts in the background instead of freezing the UI:
- the confirmation sheet closes on the answer, and the session leaves the left menu at the same moment; the file is unlinked and the index is rescanned behind the window
  — `AppState.delete(session:)` is no longer `async throws`: it drops the session from `projects` (`dropFromIndex`, which keeps the project's row because its folder is still there) and unlinks the file on the main actor, then runs `refreshIndex()` in a `Task`. Unlinking before the rescan is what stops a rescan that runs in between from putting the row back. `DeleteSessionSheet` lost its `isDeleting`/`error` state: it calls `state.delete(session:)` and `onFinish()` in the same click, so there is no "Deleting…" title to sit through, and the palette's no-confirmation path calls the same method directly. Failures go to the window's banner (`present(error:)`) and the row returns on the next rescan, which is the authority on what still exists. Measured on a 304-file fixture: the sheet and row were gone 420-476 ms after the press (the sheet's own dismissal animation) while the rescan took 1617 ms, with an AX round trip staying at 13 ms through it; a read-only folder produced the banner 12 ms after the press and the row came back.

14. move the "jump to latest" button to the top centre, above the chatbox
  — `ConversationView`'s pill went from `.overlay(alignment: .bottomTrailing)` with a flat `.padding(16)` to `.overlay(alignment: .bottom)` resting on `.padding(.bottom, bottomInset)`: `bottomInset` is exactly the room the transcript reserves for the floating box (its height plus 16pt of chrome, passed down by `SessionView`), so the pill's bottom edge lands on the composer's top padding and clears the box at every prompt size. The corner anchor was the wrong place for it — the pane's trailing edge is *outside* the centred content column, so on a wide window the pill drifted away from the text it scrolls to, and on a narrow one it was drawn behind the composer's gradient (that overlay sits above `ConversationView`). Centring it keeps the scroll proxy and `isPinnedToBottom` in the view that owns them; the pill's visibility rule and its `.easeOut(duration: 0.2)` scroll to `bottomAnchor` are unchanged.
