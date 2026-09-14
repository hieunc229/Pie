# PiCode — build & handoff notes

> Living document. If you are a coding agent picking this up: **read this file
> first, then `README.md` (the original product spec)**. Update this file as you
> go — it is the only place where the reasoning that isn't visible in the code
> lives. Keep it current or the next agent will re-derive your mistakes.

---

## 1. What this is

PiCode is a **native macOS client for the `pi` coding agent**. It is **not a
fork**: `pi` remains the runtime, the source of truth for sessions/trust/settings,
and the only thing that talks to models. PiCode:

- launches `pi --mode rpc` as a child process (one child per active session),
- speaks Pi's documented JSONL RPC protocol over the child's stdio,
- renders the conversation in a Codex-inspired three-pane window (sidebar /
  transcript / inspector),
- reads Pi's own session files, `trust.json`, `settings.json` and git state to
  give the transcript context (file changes, usage, tree, terminal history).

Everything PiCode invents is additive and reversible. Pi never learns about
PiCode's own preferences.

### Non-negotiable rules (violating these is a bug)

1. **Never modify Pi's config silently.** No writing `~/.pi/agent/settings.json`,
   `auth.json`, `models.json`. PiCode writes exactly one Pi-owned file, and only
   as the direct result of a user action: `~/.pi/agent/trust.json`, using the
   same format Pi's `/trust` uses (§7).
2. **Never invoke `pi` through a shell.** Always `Process` with a direct
   `executableURL` (see `PiProcess.swift`). No `sh -c`, ever. This keeps the
   process tree and signals predictable and keeps user data out of shell quoting.
3. **Only use RPC surfaces Pi actually supports.** If a capability is TUI-only
   (tree navigation, `/trust`, theme listing, custom UI components…), PiCode must
   say so in the UI instead of pretending. Those cases are enumerated in §9 and
   must be surfaced through `ExtensionCompatibilityNotice` /
   `CompatibilityCard`, never silently dropped.
4. **Persist trust only through Pi's mechanism.** No bespoke trust store, no
   "remember my answer" checkbox that writes anywhere else.
5. **Never modify session files.** They are parsed read-only. Deleting a session
   is a separate, explicitly confirmed action.
6. **Only open http/https URLs from model-authored content**
   (`WorkspaceLauncher.openWebURL`). Never hand a local scheme, `file://`, or a
   path to `NSWorkspace.open` on the model's behalf.
7. **"Open in Terminal" must not require Automation permission.** It writes a
   temporary `.command` file and asks Finder to open it — no AppleScript.
8. **Use semantic macOS colors/materials and native controls.** Never hard-code
   colors from a screenshot. Respect Reduce Motion, keyboard focus, and system
   light/dark. No OpenAI branding, logos, or trade dress — the reference only
   informs the information architecture.
9. **State classes are `@Observable @MainActor`.** No Combine view models, no
   SwiftData. JSON stores instead (§6).

---

## 2. Current status

| Area | State |
| --- | --- |
| Xcode project (macOS 14 target, Swift 5 mode) | ✅ builds: `** BUILD SUCCEEDED **` |
| `swiftc -typecheck` over all sources | ✅ clean |
| RPC layer vs real `pi` (v0.85.1) | ✅ `./Tools/SmokeTest/run.sh` — all checks pass |
| JSON boundary (reads + writes) | ✅ `./Tools/SmokeTest/run-json.sh` — scanner matches Foundation on every real session line, 20k-deep nesting safe |
| Session replay over all real sessions | ✅ `./Tools/SmokeTest/run-replay.sh` — 9908 lines, 9004 transcript rows, no bad rows/ids/roles; also proves the folding rule (see the row below) |
| Resuming a real session (`--session`) | ✅ `./Tools/SmokeTest/run-open.sh` — read-only verified byte-for-byte |
| Pi config locations (relocated `PI_CODING_AGENT_DIR` etc.) | ✅ `./Tools/SmokeTest/run-paths.sh` — PiCode and Pi agree, proven against a live `pi` |
| Extension UI round trip against a live extension | ✅ `./Tools/SmokeTest/run-extension.sh` — all 35 checks pass, no model call |
| Sidebar contents are real (no hidden project DB) | ✅ `./Tools/SmokeTest/run-index.sh` — 16 session files on disk → 8 projects, every path exists |
| Providers, credentials, third-party providers | ✅ `./Tools/SmokeTest/run-providers.sh` — verified against a live `pi`, no credential of the user's is touched |
| Sidebar row layout (one size, chat titles aligned under project names) | ⚠️ `./Tools/SmokeTest/run-sidebar-align.sh` — measured on screen before the menu's second pass: 0.0pt alignment delta, glyph on the search margin. The menu then moved the glyph 6pt in (`projectIconRightShift`), dropped the row font to 13pt and removed the last vertical margin, so this needs re-measuring; the harness now expects the glyph at `sidebarMargin + projectIconRightShift` and an *exact* project→chat pitch (it was 26.5pt against chat→chat 28.0pt, the 1.5pt residual the old row padding stole — §10). |
| Sidebar rows behave (click a project to fold its chats; one pitch; highlight on the search margin) | ⚠️ `./Tools/SmokeTest/run-sidebar-click.sh` — the click half is measured from painted pills: 5 rows → 3 → 5 as a real posted click folds and unfolds a project, and a project's highlight 28.0pt tall against a chat's 28.0pt (it was 37.0pt while the row padded itself *inside* its `listRowBackground`). The rhythm half was re-written this turn for the menu's uniform-spacing change and has **not been run**: it now asserts that project→chat, chat→chat and chat→project steps are all equal, where it used to assert a 12.0pt margin above a project. |
| A click on a project wins over the search field | ✅ `./Tools/SmokeTest/run-sidebar-click.sh` — source check that `AppState.showsChats` asks `isCollapsed` first; the old `query.isEmpty \|\| !isCollapsed` made a documented click a silent no-op. |
| Discovery / launch / trust / session index / git | ✅ implemented |
| Composer: Return sends, Shift+Return is a line, box shape, two-line clamp, box width | ⚠️ `./Tools/SmokeTest/run-composer.sh` — real `ComposerTextView`, real key events: Return/Shift/Option/Command-Return in both send-key modes; box measured at 84.0pt against `ComposerMetrics.boxHeight(forEditor:)`, the editor at 22.0/40.0/40.0/40.0pt for 1/2/3/5 lines, and the box against a transcript row at two pane widths — **816.0pt from x 242.0 at 1300pt, 456.0pt from x 22.0 at 500pt** with the old 860pt cap. `maxContentWidth` is now 736 (the frame's cap is derived: 780), so the wide-pane number becomes 736.0pt and the box's left edge 282.0pt; the narrow-pane number is unchanged. Re-run to confirm — not run this turn. |
| Composer floats over the transcript, nothing below it | ⚠️ structure only: `run-composer.sh` asserts the overlay, the inset and the absence of a footer in the source. Nobody has watched a long session scroll under the box — see §11 |
| Transcript, composer, inspector (5 panes), palette, settings | ✅ implemented |
| Real end-to-end prompt against a model | ⚠️ **not yet exercised** (see §11) |
| Transcript vs README spec | ✅ audited (§11); the gaps it found are fixed |
| Quiet rows fold (thinking/command/edit/read) | ✅ rule, ⚠️ view — `./Tools/SmokeTest/run-replay.sh`, run after this change: 8132 of 8132 quiet steps folded (3190 reasoning blocks, 2809 commands, 1231 edits, 902 reads), 0 items lost, 0 non-quiet rows folded, 0 adjacent/split runs, every folded call has a command or a path (9004 rows → 1608 rows: 872 standalone, 87 folds of one step, 649 runs; titles `Run commands, thinking`×72, `Edited files, thinking`×60, `Thinking`×54, `Edited files, thinking, run commands`×48, `Edited files, thinking, run command`×41, `Run command, thinking`×40, and longer mixed forms). 153 real folded calls are failures or cancels and must keep their red pill — the harness counts them, it does not see the pill. What is **not** verified: the view itself — that a folded line looks dimmed, that clicking it opens, that the nested step rows and their diffstats render, and that reasoning opens as text rather than as a card. The lines have **no chevron** (the row is the control); `Thinking` is folded by the same rule rather than drawn by its own row, and compaction was reworked in the same area; see §11 items 12 and 13 |
| PROCESS.md | ✅ this file |

Nothing in the repo is generated or checked in from `/tmp`; the smoke test lives
in `Tools/SmokeTest/` and is meant to be run, not shipped.

---

## 3. Build, run, verify

```bash
# 1. Type-check quickly (no Xcode, seconds)
SDK=$(xcrun --show-sdk-path --sdk macosx)
swiftc -typecheck -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  $(find PiCode -name '*.swift')

# 2. Build and run the app
xcodebuild -scheme PiCode -configuration Debug -derivedDataPath /tmp/picode-dd build
open /tmp/picode-dd/Build/Products/Debug/PiCode.app

# 3. Exercise the RPC layer against the real binary (no model calls, no credits)
./Tools/SmokeTest/run.sh

# 4. The other harnesses (all read-only, no credits)
./Tools/SmokeTest/run-json.sh     # JSON scanner vs Foundation + deep nesting
./Tools/SmokeTest/run-replay.sh   # every real session file through the transcript builder
./Tools/SmokeTest/run-open.sh     # resume the biggest real session (copy) and re-read it
./Tools/SmokeTest/run-open.sh --small   # smallest session; also diffs the tree vs get_tree
./Tools/SmokeTest/run-paths.sh    # Pi's config/session locations, checked against a live pi
./Tools/SmokeTest/run-extension.sh     # the whole extension UI round trip (dialogs, status, widget)
./Tools/SmokeTest/run-providers.sh     # credential + model config files, checked against a live pi
./Tools/SmokeTest/run-index.sh    # the sidebar's projects are real files, not a hidden database
./Tools/SmokeTest/run-sidebar-align.sh  # sidebar row geometry, measured in pixels (GUI)
./Tools/SmokeTest/run-sidebar-click.sh  # clicking a project folds its chats, measured in pixels (GUI)
./Tools/SmokeTest/run-composer.sh       # the composer's keys and box shape (GUI)
```

The smoke test is the **acceptance gate for any change to `Models/`,
`Services/`, or the RPC call sites in `PiSessionController`.** It compiles the
Foundation-only half of the app together with `Tools/SmokeTest/RPCSmokeTest.swift`,
launches a real `pi --mode rpc` in a throwaway directory, and verifies:

- discovery finds a *working* `pi` (not just any executable named `pi`),
- every outgoing command encodes the documented method name and field names
  (Pi ignores unknown fields, so a typo is otherwise invisible),
- `get_state`/`get_messages`/`get_available_models`/`get_available_thinking_levels`/
  `get_commands`/`get_session_stats`/`get_tree`/`get_fork_messages` all answer and parse,
- `bash` runs through Pi's own tool and returns output,
- an unknown command produces a `success: false` response that surfaces as
  `PiRPCError.commandFailed`,
- events are delivered to `onEvent`,
- `trust.json` is **not** created,
- cleanup removes the throwaway session folder (found via the path `get_state`
  reports, so no Pi-naming-scheme reimplementation).

Why the smoke test compiles only `Models/`, `Services/`, `Shared/`: those files
are Foundation-only by design (§5) so they can be built without SwiftUI. Keep it
that way — if you need a new service, don't import SwiftUI in it.

The other harnesses exist because they each caught a real bug:

- **`run-json.sh`** cross-checks `JSONScanner` against Foundation on every line
  of every real session, plus escapes, malformed input, round trips, and 20k-deep
  nesting. It exists because `JSONDecoder` + recursive `JSONValue` crashed on
  Pi's deeply nested `get_tree` response (see §10) — do not "simplify" the
  scanner back to `JSONDecoder`.
- **`run-replay.sh`** pushes every real session file through
  `JSONLDecoder → PiSessionEntry → TranscriptBuilder` and asserts: no undecodable
  lines, no duplicate/empty row ids, no unknown roles or entry types, and every
  tool result matched to a call by `toolCallId`. It also checks the transcript's
  folding rule (`TranscriptRows.group`, imported from `Features/Conversation/`
  because it is Foundation-only): folding keeps every item reachable, only
  thinking/command/edit/read rows fold, a fold is one maximal run (no two adjacent
  groups, no run split apart), every foldable item ends up folded (reasoning
  included), and every folded call carries a command or a path to identify it.
  Nothing there draws anything — see §11 for what still needs eyes.
- **`run-open.sh`** resumes a real session exactly the way the sidebar does
  (`pi --mode rpc --session <copy>`), asserts Pi resumed *that* session, that the
  locally built tree matches Pi's `get_tree` (small sessions), that
  `get_state.messageCount == get_messages.count`, that `get_entries(since:)`
  returns exactly the entries after the cursor, and that the file is unchanged
  afterwards. It works on a **copy**, so a bug here cannot damage real history.
  With no argument it picks the largest indexed session — but never the one this
  process was spawned from (`PI_SESSION_FILE`), because an agent working in this
  repo makes its own session the largest, and a multi-megabyte file that is
  still being appended to does not page through inside the harness's 30s budget
  (`get_entries` times out, which looks like a PiCode bug and is not).
- **`run-paths.sh`** resolves `PiPaths` in a child process (environment variables
  are read once per process, so each case needs a fresh one) and then launches a
  throwaway `pi --mode rpc` in a temp config directory to confirm Pi really writes
  where PiCode claims: `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`,
  `settings.json` `sessionDir`, precedence between them, tilde expansion, and
  that a relative path is ignored rather than guessed. It exists because
  `PiPaths` was hardcoded to `~/.pi/agent` (§7), which would have made PiCode
  write trust decisions to a file Pi never reads.
- **`run-extension.sh`** drives the real `PiSessionController` against a real
  `pi --mode rpc` with a throwaway extension
  (`Fixtures/ExtensionUI/picode-ui-test.ts`) installed in a temp agent directory,
  and answers the dialogs the way a user would. It covers `select` (picking a
  non-default option), `confirm`, `input`, `editor` (prefill → draft → answer),
  client cancellation, **Pi's own dialog timeout**, `notify` (all three levels),
  `setStatus`/`setWidget` set *and* clear, `setTitle`, `setEditorText`, and the
  `unsupported` method path — then asserts `stats.assistantMessages == 0`,
  no transcript rows, no tokens, no protocol warnings, and no `trust.json`.
  **It never sends a model request**: Pi executes extension commands locally, and
  the harness refuses to send the slash command unless `get_commands` lists it
  (a `source: extension` entry) first. Note the shape of the protocol: the
  `prompt` response arrives only after the extension's handler returns, so the
  harness fires the send concurrently with the loop that answers dialogs.

Nothing above sends a model prompt. Keep it that way: PiCode's budget belongs to
the user.

- **`run-index.sh`** answers "are the projects in the sidebar real?" by listing
  every session file Pi's session directory actually contains and checking that
  each one maps to an existing project directory on disk, that pins/hidden
  sessions only *decorate* that list, and that no project or session list is
  cached in `UserDefaults`. PiCode has no database of projects: the sidebar is a
  projection of `SessionIndex.loadAllProjects()`, grouped by each session's
  canonical `cwd`. Keep it that way.
- **`run-sidebar-align.sh`** and **`run-sidebar-click.sh`** are the two harnesses
  that measure *pixels*. Both render a mock of the real row structure in a
  window, capture that window themselves (no screen-recording permission needed),
  and compile against `SidebarStyle` extracted from `SidebarView.swift` so the
  numbers under test are the shipped ones; both also grep the view for the wiring
  those numbers assume, and both need a GUI session (not SSH).
  - `run-sidebar-align.sh` checks geometry: a chat title starts at the same x as
    its project's name; the project glyph's ink lands
    `projectIconRightShift` in from `SidebarStyle.sidebarMargin` (the search
    field's left edge) at full width; and a chat sits as far below its project's
    name as below another chat — now exactly, because no row pads itself
    vertically any more. The pitch comes from ink *centres* measured in the
    project name's own x column — measuring whole lines would let the folder
    glyph into the project's span and skew it, which is exactly the false 1.5pt
    difference this used to report. It also greps the view for things a mock
    cannot: that no `.font` in the sidebar carries a weight other than
    `.regular`, that `SidebarRowChrome` adds no vertical padding, and that
    exactly one `Divider()` is left (the footer's — the rule under the search
    field is gone on purpose). It dumps `/tmp/picode-sidebar-look.png`, a mock of
    the whole column, so a human can judge the colours a machine cannot.
  - `run-sidebar-click.sh` checks behaviour and the geometry of the highlight.
    Every row in its mock paints a distinct saturated fill (red, magenta, cyan,
    green, yellow — each a different pair of bright channels), so a row can be
    found, measured and **counted by colour**: five rows, the fold, the pill
    heights and the pitch all come from rectangles, not from ink. Then it *clicks
    a row through the window's own event path* — a `NavigationSplitView` sidebar,
    `List`, `Button` and all — asserting the chats fold away and come back.
    Posted events, not delivered ones: SwiftUI runs an event-tracking loop on
    mouse-down, so `sendEvent`ing the down and the up deadlocks the harness. Its
    geometry claim is one pitch: the tops of four pills give project→chat,
    chat→chat and chat→project, and all three must agree (they used to be 28.0pt
    above a chat and 40.0pt above a project while a 12pt margin sat on the
    project row). It dumps `/tmp/picode-sidebar-click.png`.
  - Both read pixels through `Tools/SmokeTest/WindowPixels.swift`, which redraws
    the capture into a buffer with a pinned layout. Do not go back to reading
    `NSBitmapImageRep(cgImage:).bitmapData` directly: the capture comes back
    alpha-*first* on this machine, so a dark grey pixel reads as a bright red one
    and a colour test measures the wrong rectangle while reporting success.
  - Both capture the window's **content view**, not the window. See §10: a
    window-server capture of a window behind another window is solid black, and
    a harness can share the screen with the running app.
  - `run-sidebar-click.sh` paints its own flat backdrop
    (`.scrollContentBackground(.hidden)` plus one `Color` behind the whole
    split view). A sidebar `List` uses a material, materials do not appear in a
    `cacheDisplay` capture (they resolve to transparent → black), and a capture
    that holds two surfaces has no single backdrop (§10). The same capture also
    explains why this harness counts rows by colour: text drawn over a
    saturated fill comes back tinted, so counting rows by ink lost the row under
    the blue pill and reported four where five were drawn (§10).
- **`run-composer.sh`** is the composer's gate: it compiles `ComposerTextView`
  against the real source, hosts it in a real window, and posts real key events —
  Return, Shift-Return, Option-Return, Command-Return, Escape, in both
  `SendKey` modes, with and without the suggestion list — asserting what the
  composer asked the session to do *and* what the editor still contains, because
  "sent" with a stray newline in the text is still wrong. The key mapping cannot
  be guessed from selector names (§10), so the harness asserts the mapping itself.
  It then sets text of 1, 2, 3 and 5 lines in the real editor and measures the
  height SwiftUI gave it (22/40/40/40pt), because a `NSViewRepresentable` with no
  size of its own is handed its maximum height and the box was silently a
  constant 220pt tall (§10).
  It also measures the prompt box from a capture — 84pt tall, against
  `ComposerMetrics.boxHeight(forEditor:)` rather than against a literal — and the
  box's width against a painted transcript row in the same capture, at a wide
  (1300pt) and a narrow (500pt) pane, so "the box is as wide as the content" is a
  measured claim instead of a hope. It
  greps the sources for the structure that compiles either way: the row order
  (attach · access · model · thinking · send), the absence of the controls that
  were deliberately removed, no container background behind the composer, the
  composer as an `.overlay` on the transcript with its height handed to
  `ConversationView.bottomInset`, and no footer (no `ExtensionStatusBar`) under
  it. Needs a GUI session.
  What it cannot see: the overlay from the outside. Rendering the real
  `SessionView` needs a live controller, so "the last row ends above the box and
  earlier rows pass under it" rests on the code shape plus one manual look (§11).
- **`run-providers.sh`** exercises `PiProviderService` inside a throwaway
  `PI_CODING_AGENT_DIR` and then asks a live `pi` what it makes of the files:
  `0600` mode, masked fingerprints (no key ever printed), atomic writes with no
  temp leftovers, OAuth entries and unknown fields preserved across edits, the
  malformed-entry-poisoning bug and its repair, refusal to clobber an
  unparseable file, custom-provider round trips that Pi's own
  `get_available_models` then lists, that a credential is live for a running
  session but a `models.json` provider is not, and that reading the user's real
  configuration changes nothing.

### Environment (this machine)

- macOS 15.3.2, Xcode 16.4, Swift 6.1.2 (language mode 5), arm64.
- `pi` v0.85.1 at `~/.nvm/versions/node/v24.15.0/bin/pi`
  (package: `.../lib/node_modules/@earendil-works/pi-coding-agent`).
- Install commands (from Pi's docs): `npm install -g --ignore-scripts
  @earendil-works/pi-coding-agent` or `curl -fsSL https://pi.dev/install.sh | sh`.

---

## 4. Architecture map

```
PiCode/
├── PiCodeApp.swift            @main: WindowGroup(RootView) + .commands + Settings scene
├── App/
│   ├── AppState.swift         @Observable @MainActor root state: launch phase, discovery,
│   │                          project index, open session controllers, palette, sheets,
│   │                          toasts/banners, `run(_ PaletteCommand)`
│   └── PaletteCommand.swift   the single action enum (title/icon/requiresSession/group/…).
│                              Menus, shortcuts, palette, and toolbar ALL route through it.
├── Models/                    (Foundation only)
│   ├── JSONValue.swift        the JSON model + JSONCoding (decode/line encoder)
│   ├── JSONScanner.swift      iterative JSON reader/writer (stack-safe on deep
│   │                          payloads; sorted keys) — backs JSONCoding
│   ├── RPCModels.swift        RPCCommand/RPCResponse, PiModel, PiCommand, PiMessage,
│   │                          PiSessionEntry, PiTreeNode, PiForkPoint, PiSessionState,
│   │                          PiSessionStats, PiUsage, ExtensionUIRequest, compatibility notices
│   ├── PiEvent.swift          every RPC event Pi emits, as a typed enum + `typeName`
│   ├── TranscriptItem.swift   the renderable model: rows, FileChange, QueueSnapshot, tool runs
│   ├── Project.swift          Project, SessionRef, ProjectTrustState, git status types
│   └── ExtensionUI.swift      notification/status/widget/activity models
├── Services/                  (Foundation only, no SwiftUI)
│   ├── PiRPCClient.swift      child process + JSONL framing + request/response correlation
│   ├── PiProcess.swift        Process wrapper: pipes, direct exec, termination reporting
│   ├── JSONLDecoder.swift     strict LF framing (multi-byte-safe, capped buffer)
│   ├── PiDiscoveryService.swift  finds a *validated* pi; owns the launch PATH rule (§8)
│   ├── SessionIndex.swift     read-only scan of Pi's session directory (never writes);
│   │                          `PiPaths` owns the relocation rules (§7)
│   ├── ProjectTrustService.swift Pi-compatible trust.json read/write + lock + nearest ancestor
│   ├── PiProviderService.swift read/report/repair Pi's auth.json + models.json, and ask
│   │                          `pi auth check` about readiness (§7) — the one place PiCode
│   │                          writes configuration Pi owns
│   ├── GitStatusService.swift porcelain v1 -z + numstat -z via /usr/bin/git -C
│   ├── PreferencesStore.swift PiCode's own prefs (JSON in Application Support)
│   ├── DraftStore.swift       per-session composer drafts (JSON)
│   ├── PiDiagnosticsLog.swift in-memory, opt-in, capped ring buffer (never persisted)
│   └── WorkspaceLauncher.swift open/reveal/terminal/clipboard/URL rules
├── Shared/
│   ├── Utilities/FileSystem.swift, Formatters.swift
│   └── Text/ANSI.swift, Markdown.swift, SyntaxHighlighter.swift   (semantic colors only)
├── Features/
│   ├── Root/            RootView (3-pane + inspector + overlay host), SetupViews (onboarding)
│   ├── Sidebar/         SidebarView (project rows fold their chats), search, pin/hide/delete
│   ├── Session/         PiSessionController (the brain), SessionView, TranscriptBuilder,
│   │                    TranscriptExporter
│   ├── Conversation/    ConversationView, ConversationLayout (the shared content
│   │                    column), MarkdownView, TranscriptRowView, ToolCallCard
│   ├── Composer/        ComposerView, ComposerTextView (AppKit NSTextView), TrustViews
│   ├── Inspector/       InspectorView (Changes), InspectorPanes (Files/Terminal/Tree/Context)
│   ├── Extension/       ExtensionChrome (widgets/status/notifications), ExtensionDialogHost
│   ├── Palette/         CommandPaletteView, Sheets (rename/compact/fork/delete)
│   ├── Settings/        SettingsView (General/Composer/Sessions/Providers/Pi),
│   │                    ProvidersSettingsView (credentials + custom providers)
│   └── Shared/          UIComponents (BannerView, StatusPill, DiffStatView, …)
└── Tools/SmokeTest/     run*.sh + *Test.swift + Fixtures/ (see §3)
```

**`PiSessionController` is the heart.** If you are adding behaviour, the order is
usually: (1) new `RPCCommand` case, (2) refresh/`request` call in the controller,
(3) new field on the controller or a `TranscriptItem` case, (4) view. Do not put
protocol logic in views.

---

## 5. Layering rules

- `Models/`, `Services/`, `Shared/` are **Foundation-only**. This is what makes
  `Tools/SmokeTest` possible. Do not import SwiftUI/AppKit there.
- Only `App/`, `Features/`, `PiCodeApp.swift` may import SwiftUI/AppKit.
- Views read state and call controller methods; they never parse RPC, never
  touch the session file, never spawn processes.
- The controller is `@MainActor`; process I/O happens on background queues in
  `PiProcess`/`PiRPCClient` and is hopped back with the FIFO helper
  `PiSessionController.deliver { … }`.
  **Reason:** extension UI dialogs must appear in the order Pi sent them.
  `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` preserves order;
  unstructured `Task {}` does not.

---

## 6. Key decisions and why

| Decision | Rationale |
| --- | --- |
| **JSON stores instead of SwiftData** | The persisted state is tiny (preferences, drafts, pinned/hidden IDs). SwiftData adds a schema, migration surface, and an external store for no benefit — and would make the model layer unusable from the `swiftc` smoke test. `PreferencesStore`/`DraftStore` write plain JSON to Application Support. |
| **One `pi --mode rpc` child per active session** | Pi's RPC mode is single-session by design. Separate children mean a crash or abort in one project can't take the others down. `AppState.pruneControllers(limit: 4)` closes the least recently used beyond the cap. |
| **Deterministic transcript IDs** | Live streaming rows must be replaced by the durable rows that `get_messages`/`get_entries` return, without flicker or duplicate rows. IDs are derived from stable inputs (message id/role/index, tool call id), so the same content hashes to the same row. `agent_settled` triggers a full reconcile. |
| **Tool/bash execution lives in side tables (`toolRuntime`/`bashRuntime`)** | A tool call is first seen as a live event, then as durable transcript content, then possibly updated again. Keeping execution state in one place and applying it as an **overlay** over both base and live items prevents the two sources from disagreeing. |
| **Live assistant rows use the predicted base index** | So their IDs match the durable rows once they land. |
| **`--session <path>` for existing sessions, else new** | Pi's documented way to resume. |
| **Trust pinned per run with `--approve`/`--no-approve`** | Lets the user answer "trust this project?" once per launch without PiCode writing Pi's config behind their back. |
| **`NSViewRepresentable` NSTextView composer** | Needed to decide what Return means per `PreferencesStore.SendKey` (`returnKey` vs `commandReturn`), to disable smart substitutions, and to support slash/`@path` completion without fighting SwiftUI's `TextField`. The decision reads the **event's modifiers**, not the selector: a plain text view reports Shift-Return as plain `insertNewline:` and Command-Return as `noop:`, so a selector-only switch sends on Shift-Return and makes Command-Return mode unsendable (both were shipped, both are now asserted by `run-composer.sh`). Shift always means "add a line", Option always means "queue a follow-up". |
| **The composer is one box with one control row** | The editor, the attachment chips and the controls live in a single rounded shape at `ComposerMetrics.cornerRadius`, and nothing behind them draws a second one — no bar material under the composer area — so it reads as one object on the page. One row, in the order a prompt is assembled: attach · access · model · thinking · send. Everything that moved out of it is still reachable: steering and follow-ups are `Return`/`Option-Return`, queued messages are transcript rows and Stop puts them back in the editor (`interrupt()`, the documented Stop), and the hard abort is `⌘.` in the Agent menu. The access control is the one Pi actually has — project trust, explained in its popover as *project resources*, not sandboxing, because Pi always runs with the user's own permissions. |
| **No `.keyboardShortcut(.return)` on Send** | It would double-fire with the text view's Return handling. |
| **Images via RPC `images`; text files inlined as fenced `@path` blocks** | Pi only accepts images as attachments. Other files are inlined as Markdown so the model can read them, and the fenced block names the path. `AttachmentLoader` rejects anything that is neither an image nor text with a clear message. |
| **Tree inspector is read-only** | `navigateTree` is SDK/extension-only, not RPC (§9). PiCode shows the tree, and offers Fork/Clone plus an explicit compatibility note. |
| **Terminal pane runs Pi's `bash` RPC** | It is *not* a real shell. It shows what the agent ran and lets the user run one-off commands through the same tool. For an interactive shell, "Open in Terminal" opens a real one. |
| **The composer floats, and stops at two lines** | Two separate changes with the same goal: the composer should be a small object on the page, not a panel that owns the bottom of the window. (1) The editor is clamped to `ComposerMetrics.editorMaxHeight` (40pt = two lines at 18pt) and scrolls past that — measured, 1/2/3/5 lines give 22/40/40/40pt. (2) The transcript runs the full height of the column and the composer is drawn over it as an `.overlay(alignment: .bottom)`, so the last row passes *under* the box with a fade above it. Both need `ConversationView.bottomInset = composerHeight + 16`: the overlay takes no space, so without the inset the final row would be permanently hidden. The height is real, not a constant — `ComposerHeightKey` reports the measured overlay height back through a preference. |
| **One column for the transcript and the composer** | `ConversationLayout` + `ConversationColumn` hold the content column, and both the transcript's rows and the floating composer are laid out in it. The one number a person would name is the width of the *content* — 736pt, what the rows and the box measure — so that is what `maxContentWidth` holds; the frame's cap (`maxColumnWidth`, 780pt) is derived from it plus the 22pt gutter on each side. An overlay inherits nothing from the view it floats over, so the box used to be as wide as the *pane* while the rows stopped at the cap — a bar twice the width of the conversation. The padding sits *inside* the cap (`padding` then `frame(maxWidth:)`), so a wide pane stops at `maxColumnWidth` with `maxContentWidth` of text and a narrow one still gets its gutters; reversing the two is a 44pt error at every size, and putting the gutters into `maxContentWidth` is the same error one constant over — which is why the harness predicts the box from *pane minus gutters, capped*, and not from the cap itself (it would then agree with its own mistake). The box's own padding, the gap above the control row and `boxHeight(forEditor:)` live in `ComposerMetrics` for the same reason: the harness predicts the drawn box from them instead of from a literal. |
| **Nothing is rendered below the composer** | The footer status line (`ExtensionStatusBar`: runtime, model, thinking, trust, branch, context %, tool count, extension statuses) and the below-editor extension widget strip are gone. None of it was unique: the transcript has its own system rows for streaming/compacting/retrying/queue, the Context pane has model/thinking/context/tool counts/statuses/widgets, `InspectorView` shows the branch, and the window subtitle shows the model. A footer under a floating composer also re-anchors it to the bottom edge, which is the look the two-line clamp exists to avoid. Above-editor widgets, banners, trust prompts and the connection notice are kept; a widget an extension sets with placement `belowEditor` is drawn in the same stack above the box rather than dropped, since PiCode no longer has a place below it. |
| **Inspector → composer references via `AppState.composerInsertion`** | A stateless one-shot handoff (set string → composer consumes and clears). Avoids reaching into the composer's `@State` across the view tree. |
| **"Changes" pane excludes `.read` file touches** | A changes list that includes reads is not a changes list. Session changes and git changes are offered as two sources of the same pane. |
| **Transcript errors are always visible** | Never behind a disclosure. |
| **`PiDiagnosticsLog` is in-memory and opt-in** | It can contain file contents and prompts. Capped ring buffer, never written to disk; only rendered when `recordRPCPayloads` is on. |
| **The session tree is built locally, never fetched** | `get_tree` costs ~32 s on a 787-entry session and blocks Pi's request queue (so it delays the user's next prompt). The tree is pure `parentId` structure, so `PiTreeNode.buildTree` derives it from entries instantly and matches Pi's output exactly (`run-open.sh --small` proves it). |
| **Entries are read once, then followed with a cursor** | A full `get_entries` costs ~20 s and Pi does not cache it, while `get_entries(since:lastId)` costs ~0.01 s. One full read per session, incremental appends after every turn — nothing on the hot path stalls the next prompt. |
| **Hand-written iterative JSON scanner** | `JSONDecoder` + recursive `JSONValue` crashed (SIGBUS) on Pi's nested `get_tree` payload. The scanner is stack-safe at any depth and faster than the `try?`-chain decoder; it also makes outgoing payloads deterministic (sorted keys). |
| **`PiPaths` resolves Pi's own relocation rules** | Pi can be moved with `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR` or `settings.json` `sessionDir`, and PiCode launches `pi` with the inherited environment, so both must agree on where the config lives. This is a correctness issue, not cosmetics: PiCode writes `trust.json`, and if Pi reads a different file the user's answer is ignored while PiCode reports the project as trusted. |
| **Replies branch from the message that asked** | Pi forks only at user entries (`get_fork_messages`), so the spec's "each assistant message supports branch/fork" is honored by giving every assistant/thinking row the user entry that produced it. Pi gets a fork point it accepts, and the returned text is the prompt the user can edit and resend. `run-replay.sh` asserts every reply has one and that it is a user entry on the active branch. |
| **`picode://` links are provided by the transcript, not each row** | The link handler and `\.piCodeOpenFile`/`\.piCodeOpenChange` actions are set once in `ConversationView`, which is the only place that knows the project path to resolve a relative reference against. The first version of this shipped a handler nothing ever provided, so clicking a file reference silently did nothing. If you add a new transcript action, provide it there and check the click path, not just the compile. |
| **Timed extension dialogs are dismissed locally** | Pi self-resolves a dialog with a `timeout` and never tells the client, so a card left on screen invites the user to answer a question that no longer exists. PiCode mirrors the deadline (a quarter second early, so an answer can never race Pi's) and explains it in the activity timeline. There is no "expired" card state on purpose — a dead question should not look answerable. |
| **Extension commands get the patient `prompt` timeout** | Pi answers `prompt` only once the text has been handled, and an extension command is handled by its own handler, which may sit on a dialog for minutes. A normal prompt keeps the 60 s preflight budget; a slash command Pi reported as an extension command gets the same patient budget as `bash`. |
| **PiCode writes exactly two kinds of Pi file** | `trust.json` (the same document `/trust` writes) and, only on an explicit click in Settings → Providers, `auth.json` and `models.json` in the shapes Pi documents. Everything else under Pi's config directory is read-only, and no credential is ever read back into the UI. Before adding a third, ask why the user cannot do it in `pi` itself. |
| **The sidebar is a projection, not a database** | `SessionIndex.loadAllProjects()` reads Pi's session directory on every refresh; pins and "hidden" flags only decorate the result. `run-index.sh` guards this: add caching and the sidebar can start disagreeing with the terminal about what exists. |
| **A project is a row, not a section header** | A `Section` in the sidebar list style is a collapsible group with a disclosure chevron — wrong for a list that mirrors what is on disk. The row *is* the disclosure: clicking it folds its chats (`AppState.toggleCollapsed`, persisted as a decoration), and the fold wins over a search — `showsChats` asks `isCollapsed` *first*, because a query that overrides a documented click is indistinguishable from a broken one. As a row it also shares its chats' leading inset, which is what makes "a chat title starts where the project's name starts" exact instead of a two-point correction. The glyph is drawn to the left of its row so it lands beside the search field, and that shift is drawing-only, so the name — and therefore every chat title under it — does not move: `projectIconShift` (9pt) is how far left it once sat, `projectIconRightShift` (6pt) is how far the menu then asked it back in, and `projectIconOffset` (3pt) is the single name for what is actually applied. Its highlight is a `Button`'s: one `listRowBackground` pill inset by `rowHighlightInset` (`= sidebarMargin`) **on the shape, not on the row** — a `listRowBackground` fills the row's entire cell, its own insets and any padding included, so padding the row puts air *inside* the pill. Which is why the menu's second pass deleted every vertical margin instead of tuning one: a project's highlight became 37.0pt tall against a chat's 28.0pt when it carried 12pt of padding, and "equal spacing between everything" is only structural if no row pads itself at all. Both rows go through one `SidebarRowChrome`, so there is exactly one place that draws a pill, and it is the reason a project and a chat can differ only in colour. `run-sidebar-click.sh` clicks the row for real and measures the pills and the pitch. |
| **Reasoning is a step, and the quiet rows fold** | `bash`, `edit`/`write`, `read` and `thinking` are what a real session repeats: across the 16 real sessions here the calls are **all 4942** (2809 command, 1231 edit, 902 read) and there are **3190 reasoning blocks** — 8132 rows that say the same thing over and over. Every other tool name is something a person would actually want to read, so `QuietFamily.of` knows exactly those shapes and everything else keeps its card: a `grep` five times in a row is not the same shape of noise as a command five times in a row, because the point of folding is that the user already knows what the line will say. Folding is *presentation*, so it is a **pure function** of the item list (`TranscriptRows.group`) in a Foundation-only file — the replay harness imports it and checks the rule over every session that has ever run here (8132/8132 quiet steps folded, nothing lost, no non-quiet row folded, no run split). |
| **What folds, and what names the run, is one function** | `QuietFamily.of(item)` answers both questions — does this row fold, and what is the run called — so a run's members and its name can never be two different sets. `TranscriptRows.group` folds an item if and only if `of` returns a family, and `groupTitle` enumerates exactly those families; the harness asserts the two agree by requiring that *every* foldable item ends up inside a group (`foldedThinking == thinkingBlocks` is the check that caught the temptation to leave reasoning out of the run). Adding a family is therefore one case in one enum, not a new branch in the grouping. |
| **A run ends at anything that is not a neighbouring quiet step** | An assistant message, an orphaned result or a non-folding tool between two steps is a boundary, so a run is *consecutive* steps and nothing else. “Group all the edits in a turn” would draw a line under a paragraph of explanation and call it one action, which is a claim about what the agent did that PiCode cannot actually know. It also means a fold is always maximal, which is a property the harness can assert (no two adjacent groups; no two neighbouring quiet steps left in separate rows). Reasoning is *inside* the run rather than a boundary, because in Pi's output it is interleaved with the calls it reasons about: a boundary there would leave a `Thinking` line above almost every group, which is the same noise in a different arrangement. |
| **The folded line is keyed by its *first* item** | `.group`'s id is `group-<first item id>`. A turn streams: the group grows from one call to six while the user reads it, and if the id followed the contents, every appended call would give the row a new identity and SwiftUI would rebuild it — folding the line back up under the user's cursor. Keyed by the head, the row keeps its identity and its `@State isExpanded` while it grows. |
| **A folded line keeps its status, a failed call keeps a pill** | The whole point of collapsing is that the user is not reading the calls, so anything they would need to act on has to survive on the line: a running call keeps its spinner and elapsed time, and a run containing a failure or a cancellation shows `Failed`/`Cancelled` even though its content is closed. 150 real folded calls in the sessions here are failures or cancels. The same rule applies inside a run — `ToolActionRow` marks the call that failed and colours its icon, because "which one broke" is the question the expanded list exists to answer. This is also why the failure sentence ("This tool reported a failure without output") is part of `ToolCallContent` and not of the card's header: a card may be collapsed, a folded row may be expanded, and the sentence has to be present in both. |
| **Two disclosure levels, one indent step** | A run opens to a list, and a step inside it opens to its content. One click cannot open six outputs — that is the noise being removed — and one click must not be needed for a *single* step, so a one-step group skips the intermediate list and opens its content directly (`ToolGroupView` branches on `items.count == 1`). Every nested thing — a step inside its run, a call's output under its own summary, reasoning under its own line — is indented by the one constant `ConversationLayout.nestedIndent` (15pt), because two steps of indentation inside a 736pt column leaves the output at the width of a postcard. |
| **The transcript has no chevrons; the line is the control** | Every folded line — the run header, a `Thinking` step inside it, a nested `ToolActionRow` — is one dimmed line the user clicks. A column of little arrows down the left of the conversation is more furniture than the fold is worth, so the affordance is the line itself: the whole row is a `.contentShape(Rectangle())` inside a `.plain` button, hovering lifts the dimming, and a tooltip names what a click will do. Never a `DisclosureGroup`: the system style draws a chevron in the leading gutter *and* shifts the row's glyph out of line with every other row's icon. The one row that still shows a chevron is the transient "Pi is working" line in `ConversationView`, whose disclosure is what the spec asks for; if it is ever changed, this is the paragraph that says the rest of the transcript already gave its chevron up. |
| **A compaction is a fact, not a document** | `.compaction` rows draw one line — `[icon] Compact context`, or `Branch summary` for the entry Pi writes when the user switches branches — and nothing else. The old row printed a badge plus the whole summary in a tinted box in the middle of the conversation, which is exactly the noise the transcript's folding exists to remove, and the summary text is a compression of the turns that were just replaced rather than something anyone reads. Pi's two summaries are different facts (one folded the context away, the other describes a path that was left behind), so the builder maps the message *role* onto `SummaryKind` and the row takes the label and the glyph from it — the glyphs are the same ones `PiSessionEntry` uses in the session tree, so the tree and the transcript name one event the same way. The text is not dropped: it is on the row's context menu and, in full, under the same heading in the exported transcript. |
| **The shared content moved out of the card** | `ToolCallContent` draws arguments, file changes, output, truncation notice, failure sentence and structured result; `ToolCallCard` (non-quiet tools) and `QuietStepContent` (folded ones, drawn by both `ToolGroupView` and `ToolActionRow`) share it. An `edit`'s diffstat and a `read`'s file chip must not be able to disagree between the two shapes, and the card lost ~140 lines by it. The card keeps its own chrome (icon, name, status pill, chevrons, copy button); the folded row keeps its own header. `QuietStepContent` is also where the *other* shape lives: a reasoning step draws its text rather than a call's card, so its line and its body are chosen in one place instead of in each of the two views that can open a single step. |

---

## 7. Pi on-disk formats (as verified against v0.85.1)

### Where Pi's files live

Never hardcode `~/.pi/agent`. Pi relocates itself, and PiCode launches `pi` with
the inherited environment, so it must resolve the same paths Pi's `config.js`
does:

| Priority | Agent directory | Session directory |
| --- | --- | --- |
| 1 | `PI_CODING_AGENT_DIR` | `PI_CODING_AGENT_SESSION_DIR` |
| 2 | `~/.pi/agent` | `sessionDir` in `settings.json` |
| 3 | — | `<agent dir>/sessions` |

Tilde paths, `file://` URLs and absolute paths are accepted; a *relative*
`sessionDir` is ignored rather than guessed, because Pi resolves it against the
working directory and that changes per project. All of this lives in `PiPaths`
(`SessionIndex.swift`) and is checked against a live `pi` by
`./Tools/SmokeTest/run-paths.sh`.

Known gap: Pi merges a project's `.pi/settings.json` over the global one, so a
project can set its *own* `sessionDir`. PiCode indexes one global directory, so
that project's sessions would not appear in the sidebar. Nobody has hit it; if
you do, the fix is per-project session discovery, not a global `sessionDir`.

### Providers (the only config PiCode writes)

Two files decide which models a session can use, and both belong to Pi:

| File | Shape | Written by |
| --- | --- | --- |
| `<agent dir>/auth.json` | `{ "<provider>": { "type": "api_key", "key": … } }` or `{ "type": "oauth", "access", "refresh", "expires" }` | Pi's `/login`; PiCode's Settings → Providers |
| `<agent dir>/models.json` | `{ "providers": { "<name>": { "baseUrl", "api", "apiKey", "models": [ … ] } } }` | Pi's `/setup-custom-providers`, or hand-editing; PiCode's Settings → Providers |

Facts proven by `./Tools/SmokeTest/run-providers.sh` against a live `pi`:

* `auth.json` is read **as a whole**. One entry that Pi cannot parse (for
  example a provider-shaped entry missing `"type"`) makes *every* provider
  report `invalid_state`. Repairing means removing that entry, never guessing
  at it.
* A credential added while a session is running **is** picked up (Pi checks the
  file revision), within about half a second — no restart needed.
* A provider added to `models.json` is **not** live until the process restarts:
  `get_available_models` keeps the old catalog. That is why the Settings pane
  offers "Restart Sessions to Apply Changes".
* `apiKey` may be a literal, `$ENV_VAR`, or `!command`. PiCode keeps references
  visible and never expands them.
* Pi validates the file on read but PiCode refuses to overwrite a file it cannot
  parse, and preserves fields it does not edit (`compat`, `headers`,
  `samplingParams`, `thinkingLevelMap`) so an edit here cannot quietly drop
  someone's customisation.
* `pi auth check --provider <id> --json --no-refresh` answers readiness without a
  network call. `pi auth print-api-key` / `print-bearer-token` and `--credentials`
  exist and are off-limits: credentials stay Pi-owned.

`enabledModels` in `settings.json` is only Ctrl+P's cycling scope and Pi
maintains it itself, so PiCode leaves it alone.

### Sessions

```
<session dir>/--<path with / and leading / replaced>--/<ISO8601>_<uuid>.jsonl
```

- One JSON object per line, LF-terminated.
- Header line carries `type`, `id`, `cwd`, timestamp; later entries are a **v3
  tree** linked by `id`/`parentId`.
- Directory names are `--private-var-…--` style: leading `/` becomes `--`, inner
  `/` becomes `-`, and the name ends with `--`. `SessionIndex.decodeDirectoryName`
  inverts this and is **lossy** — it is only a fallback when the header's `cwd`
  is unavailable.
- PiCode reads these files; it never rewrites them.

### Trust

```
<agent dir>/trust.json   { "<absolute canonical path>": true|false }
```

- Sorted keys, 2-space indent, trailing newline — byte-compatible with Pi's writer.
- Lookup walks **nearest ancestor**: a decision on `/a/b` covers `/a/b/c`.
- Pi's lockfile is `<file>.lock` **as a directory** (created with `mkdir`).
  `ProjectTrustService` mirrors that, with stale-lock recovery after 15s.
- Resources that require trust: `.pi/settings.json`, `.pi/extensions`,
  `.pi/skills`, `.pi/prompts`, `.pi/themes`, `.pi/SYSTEM.md`,
  `.pi/APPEND_SYSTEM.md`, project `.agents/skills`.
- As of this writing `~/.pi/agent/trust.json` **does not exist** on this machine
  and the smoke test asserts PiCode never creates it as a side effect.
- Because PiCode *does* write this one file (only after an explicit user
  decision), the agent directory must be Pi's real one — see
  `run-paths.sh` above.

### Git (used by the Changes pane)

- `git -C <path> status --porcelain=v1 -z`: `<XY> <path>\0`; for renames the
  **next** NUL-delimited token is the source path.
- `git -C <path> diff --numstat -z`: `<added>\t<deleted>\t<path>\0`.
- Invoked as `/usr/bin/git` with `-C`, never a shell.

---

## 8. Environment gotcha you will hit again (fixed — don't regress it)

`pi` ships as a Node script (`#!/usr/bin/env node`). Two things break discovery
on real machines:

1. **A different program named `pi` shadows it.** On this machine
   `/opt/homebrew/bin/pi` is a 2023 Python script that fails with
   `ModuleNotFoundError: No module named 'pi'`, and it comes **first** on the
   login-shell PATH. `command -v pi` therefore returns the wrong program.
2. **An old `node` shadows the right one.** `/usr/local/bin/node` here is
   Node 18.16.0 while Pi needs a modern Node; with `/usr/local/bin` ahead of the
   nvm bin directory, `pi --version` dies inside Pi's bundle.

Consequences, both implemented:

- `PiDiscoveryService` **validates** every candidate by running `pi --version`
  and only returns a working installation. It tries the login-shell hit first,
  then a static candidate list, then every `~/.nvm/versions/node/*/bin/pi`,
  newest first. The failure message records why the login-shell hit was rejected.
- `PiDiscoveryService.launchEnvironment(executable:shellPath:)` returns a PATH
  with **the executable's own directory first**, then the login-shell PATH with
  that entry removed. Both discovery (`--version`) and the app's RPC launch
  (`PiSessionController`, and the smoke test) go through it, so `pi` always runs
  under the Node it was installed with.

If discovery fails on a new machine, print the `.missing(searched:shellPath:detail:)`
payload — it names every path tried and the reason the login-shell hit failed.
`SetupViews.swift` renders that same information to the user.

---

- **Writing a file with `open(path, 'w').write(...)` truncates it first.** If the
  write then raises — a tuple where a string was meant is enough — the file is
  left at **0 bytes**, and `git status` shows it as merely "modified". This has
  already cost one recovery of this very file. Write to a temporary path and
  `os.replace()` it, or assert the replacements matched before writing, and check
  the line count afterwards.

## 9. RPC protocol notes

Framing: one JSON object per line, **LF only**; CRLF tolerated by stripping a
trailing CR. `JSONLDecoder` never treats U+2028/U+2029 as a delimiter and decodes
UTF-8 only after a whole record is available (multi-byte-safe). Records are
capped at 32 MiB.

Correlation: every request sends an `id`; the response echoes it. `PiRPCClient`
keeps `pending[id] → continuation` plus a timeout work item
(`defaultTimeout = 60s`). `sendAwaitingResponse(_:timeout:)` is the raw path used
by the smoke test to probe the wire format; the app uses typed `send(_:)`.

Response failures throw `PiRPCError.commandFailed(command:message:)`, which the
controller turns into a visible transcript error.

Commands implemented (`RPCCommand`, names verified against `docs/rpc.md` **and**
the installed bundle): `get_state`, `get_messages`, `get_available_models`,
`get_available_thinking_levels`, `get_commands`, `get_session_stats`,
`get_entries(since:)`, `get_tree`, `get_fork_messages`, `get_last_assistant_text`,
`set_model`, `cycle_model`, `set_thinking_level`, `cycle_thinking_level`,
`set_steering_mode`, `set_follow_up_mode`, `set_auto_compaction`, `set_auto_retry`,
`set_session_name`, `prompt`, `steer`, `follow_up`, `abort`, `abort_retry`,
`abort_bash`, `clear_queue`, `new_session(parentSession:)`,
`switch_session(path:)`, `fork(entryId:)`, `clone`, `compact(customInstructions:)`,
`export_html(outputPath:)`, `bash(command:)`.

Notes that cost time to learn:

- During streaming, `prompt` **must** carry `streamingBehavior`
  (`steer`/`followUp`) or Pi returns an error. PiCode routes queued sends through
  `steer`/`follow_up` instead.
- Absent optionals must stay **absent**, not `null` (`compact`, `new_session`,
  `export_html`, `get_entries`). The smoke test pins this.
- Pi silently ignores unknown fields and unknown *values* in some places — which
  is why the wire-format assertions exist.

Events (`PiEvent`, `Models/PiEvent.swift`): `agent_start`, `agent_end`,
`agent_settled`, `turn_start`, `turn_end`, `message_start`, `message_update`,
`message_end`, `bash_execution_update`, `tool_execution_start/update/end`,
`queue_update`, `compaction_start/end`, `auto_retry_start/end`,
`summarization_retry_*`, `extension_error`, `extension_ui_request`, and
`unknown(type:)` which must be preserved rather than dropped. Use `typeName` for
logging; there is no `name` property.

`message_update` carries deltas; **`message_end.message` is authoritative.** Live
partial content is assembled from `message_start` + deltas and reconciled on
`agent_settled`.

### Extension UI

> **Verified end to end** by `./Tools/SmokeTest/run-extension.sh` against a live
> `pi` and a throwaway extension. Two real bugs came out of it — read these
> before touching the extension path:
>
> 1. **`timeout` is in milliseconds.** It is the only duration on the wire that
>    is, and `Format.duration` takes seconds, so passing it through printed
>    "25m 0s" for a 1.5 s timeout. Use `ExtensionUIRequest.timeoutSeconds` and
>    never the raw field.
> 2. **Pi resolves a timed dialog without telling us.** The client had no timer
>    of its own, so the card stayed on screen after Pi had already continued with
>    the default answer — inviting the user to answer a question that no longer
>    existed. `PiSessionController.scheduleDialogTimeout` now mirrors the deadline
>    (a quarter second early, so an answer can never race Pi's own) and records
>    "Extension request expired" in the activity timeline. There is deliberately
>    no "expired" dialog state: the card is gone, and the timeline explains why.
>
> Also: the **`prompt` response arrives only after an extension command's handler
> returns**, which can be as long as its slowest dialog. `promptTimeout(for:)`
> therefore gives extension commands the patient budget `bash` uses, so a long
> dialog cannot fake a "prompt failed" error.

- **Dialogs** (`select`, `confirm`, `input`, `editor`): Pi blocks until the client
  answers with `extension_ui_response` carrying the same `id` — `value` for
  `select`/`input`/`editor`, `confirmed` for `confirm`, or `cancelled: true`.
  Only **one** dialog is presented at a time; the rest queue and the dialog shows
  "N more waiting". The dim overlay is deliberately **not** click-dismissable: an
  extension question is a decision, not a tooltip.
- **Fire-and-forget** (`notify`, `setStatus`, `setWidget`, `setTitle`,
  `set_editor_text`): displayed (notifications / status bar / widget strips / window
  title / composer prefill) or logged, never answered.
- **TUI-only, degraded in RPC mode** — surface as compatibility notices:
  `custom()` returns undefined; `setWorkingMessage`, `setWorkingIndicator`,
  `setFooter`, `setHeader`, `setEditorComponent`, `setToolsExpanded` are no-ops;
  `getEditorText()` returns `""`; `getToolsExpanded()` returns `false`;
  `pasteToEditor()` degrades to `setEditorText()`; `getAllThemes()` returns `[]`;
  `getTheme()` returns `undefined`.
- **`navigateTree` is not available over RPC at all** (SDK/extension only), and
  `/tree` and `/trust` are TUI commands. The Tree inspector is therefore
  read-only and offers Fork/Clone; `/trust` is mirrored by PiCode's own trust UI
  writing Pi's `trust.json`.

### Read-path costs (measured on this machine, v0.85.1)

Pi answers one request at a time, so a slow read does not just stall the pane
that asked for it — it delays the user's next prompt. Measured on a real 5.5 MB
session with 787 entries / 144 messages in context:

| Command | Cost | How PiCode uses it |
| --- | --- | --- |
| `get_tree` | **~32 s** | **Never called.** The tree is built locally from entries. |
| `get_entries` (full) | **~20 s**, no caching | Once per session, and last in `refreshAll()` so the transcript paints first. |
| `get_entries(since: <id>)` | **0.00–0.01 s** | After every settled turn and after compaction. |
| `get_messages` | ~0.25 s | Every refresh. |
| `get_fork_messages` | ~0.00 s | With the tree/fork UI. |
| `get_session_stats` | ~0.00 s | Usage pane. |

Consequences baked into the controller:

- `PiTreeNode.buildTree(from:leafId:)` derives the tree from entries in `parentId`
  order. It is verified against Pi's own `get_tree` on small sessions by
  `run-open.sh --small`. Never reintroduce a `get_tree` call.
- `PiSessionController.refreshEntries()` keeps `lastEntryId` as a durable cursor:
  one full read per session, then `since:` appends forever. If the cursor is
  rejected (Pi restarted on a different session), it falls back to a full read.
  `isLoadingEntries` guards against two concurrent full walks and drives the tree
  pane's progress state.
- A first load on a long session therefore takes ~20 s of *background* time. That
  is Pi's cost, not a PiCode bug; the tree pane says so instead of looking stuck.

---

## 10. Hard-won API facts (so you don't rediscover them)

- **`JSONValue` has no typed enum cases beyond** `null`, `bool`, `number`,
  `string`, `array`, `object`. There is no `.int`/`.double`/`.string(_:)` case —
  use the accessors (`string(_:)`, `int(_:)`, `double(_:)`, `bool(_:)`,
  `array(_:)`, `object(_:)`, `…Value`, `isNull`, `prettyDescription`) and build
  values as `.number(Double(x))`, `.object([...])`.
- Decoding goes through `JSONCoding.decode(_:)` / `JSONCoding.line(_:)`, which are
  backed by **`JSONScanner`** (iterative, hand-written). `JSONDecoder`/
  `JSONEncoder` with `JSONValue` **overflows the stack** on deeply nested payloads:
  `get_tree` nests one level per session entry, and a 145-entry session crashed a
  smoke test with SIGBUS inside `_CodingPathNode.path`. Keep the `Codable`
  conformance for small typed stores only (§5) and never route RPC or session
  data through it. The scanner also gives deterministic sorted keys on the wire.
- Two deliberate scanner differences from `JSONSerialization`, both harmless for
  Pi's output and safer than failing: duplicate object keys keep the last value,
  and lone UTF-16 surrogates become U+FFFD instead of rejecting the record.
- `get_session_stats` totals cover the **whole session history** (every branch,
  including compacted-away messages) while `get_state.messageCount` is the
  **active branch**. On the test session: 780 total vs 144 in context, 23 user vs
  4 user. Show them as different things; only `contextUsage` describes the live
  context window.
- `PiSessionState` fields: `model`, `thinkingLevel`, `isStreaming`, `isCompacting`,
  `steeringMode`, `followUpMode`, `sessionFile`, `sessionId`, `sessionName`,
  `autoCompactionEnabled`, `autoRetryEnabled`, `messageCount`,
  `pendingMessageCount`. There is **no** `error` field.
- `FileChange` = `{ id, path, kind, additions, deletions }` with
  `Kind ∈ {created, modified, deleted, read}` and **no `count`** — occurrences are
  computed. `FileChange.Kind.gitStatus` maps to `GitFileChange.Status`.
- `QueueSnapshot` = `{ steering, followUp }` of `QueuedMessage { id, text }` with
  `isEmpty` / `update(steering:followUp:)`. `clearQueue()` on the controller drops
  them locally and tells Pi.
- `ActivityEntry` = `{ id, kind, title, detail, timestamp, isError }` with
  `Kind ∈ {…, .extensionRequest, .notify}`.
- `PreferencesStore` owns: `appearance`, `sendKey`, `showInspector`, `showSidebar`,
  `defaultThinkingLevel`, `defaultModelQualifiedID`, `confirmBeforeDeletingSessions`,
  `notificationsEnabled`, `recordRPCPayloads`, `extraLaunchArguments`,
  `pinnedProjects`, `pinnedSessions`, `hiddenSessions`, `collapsedProjects`,
  `lastProjectPath`, `reducedMotionOverride`. Anything else is not persisted
  yet — add it here. `PreferencesStore` is **not** observable, so anything the UI
  must redraw on is mirrored into `AppState` (`collapsedProjects` is seeded in
  `AppState.init` and written back on every toggle; `isInspectorVisible` is the
  older computed-property style and is the reason a "did the pane redraw?" bug is
  possible there).
- `AppState.InspectorTab` is `String, CaseIterable, Identifiable` and exposes
  `label`/`systemImage` (not `title`).
- `PiDiagnosticsLog.limit` is internal so Settings can describe it in help text.
- `SettingsTab` (`general`, `composer`, `sessions`, `providers`, `pi`) is the
  `TabView` selection; `AppState.openSettings(tab:)` sets it and the *view* raises
  the window (`AppState` stays AppKit-free). `SettingsTab` lives in
  `SettingsView.swift` next to the `TabView`.
- `WorkspaceLauncher.openTerminal(at:)` takes a directory and returns `URL?`.
  Putting it (or anything else non-`Void`) directly in a `Button` action inside a
  `Form` `Section` produces a *bogus* SwiftUI error — "return type of property
  requires that 'TableHeaderRowContent<…>' conform to 'View'" — pointing at the
  section, not the line. Discard the value (`_ = …`) and recompile before you
  start rewriting the view.
- **AppKit's Return family, measured** (a real text view, real key events; asserted
  by `run-composer.sh`):

  | key | selector | `modifierFlags` |
  | --- | --- | --- |
  | Return | `insertNewline:` | none |
  | Shift-Return | `insertNewline:` | `.shift` |
  | Option-Return | `insertNewlineIgnoringFieldEditor:` | `.option` |
  | Command-Return | `noop:` | `.command` |

  Two traps: Shift-Return is *not* `insertNewlineIgnoringFieldEditor:` (so a
  selector-only switch sends the prompt), and Command-Return is `noop:` — an
  undeclared selector (`Selector(("noop:"))`), which a selector-only switch never
  matches (so the Command-Return-sends mode could never send). Read
  `NSApp.currentEvent?.modifierFlags` instead.
- **An overlay is not part of what it floats over.** `SessionView` draws the
  composer with `.overlay(alignment: .bottom)`, which is what lets the transcript
  keep the pane's full height — and it also means the composer inherits *none* of
  the transcript's layout: not its insets, not its width cap, not its gutter.
  Anything that must line up with the rows has to be put in the same column by
  hand (`ConversationColumn`). The same asymmetry is why
  `ConversationView.bottomInset` exists: an overlay reserves no space, so the
  transcript has to be *told* how tall the thing over it is, or the last row lives
  underneath it forever.
- **`padding` then `frame(maxWidth:)`, never the reverse.** In
  `ConversationColumn` the gutter is applied *before* the cap, so a wide pane
  stops at `maxColumnWidth` (780pt, its gutters included) and a narrow one still
  gets them. The other
  order caps the content at `maxWidth` and *then* pads it, which makes everything
  44pt wider than the rows it is meant to match — a mistake that looks right in
  code and is only visible as a measured width (`run-composer.sh` compares the box
  against a painted row at two pane widths).
- **A `NSViewRepresentable` with no size of its own is handed its maximum
  height.** `ComposerTextView` wrapped an `NSScrollView`, which reports no
  intrinsic size, so the `.frame(minHeight: 26, maxHeight: 220)` was not a
  *range* the editor grew through — it was a constant 220pt box with a 26pt
  editor floating in it. The user's complaint ("make it shorter") had this as its
  root cause, and it is invisible in code review because the modifier reads like
  a clamp. Fix: implement
  `sizeThatFits(_:nsView:context:)`, lay out the container, and return
  `min(max(usedRect.height + insets, height(forLines: 1)), height(forLines: visibleLines))`.
  `run-composer.sh` now measures the editor at 1/2/3/5 lines, so a regression
  shows up as a number rather than as "the box looks tall again".
- **Do not resize the text container inside `sizeThatFits`.** The obvious
  "make sure the width is current" line —
  `container.containerSize = NSSize(width: proposal.width ?? …, height: .greatestFiniteMagnitude)`
  — invalidates layout *while* SwiftUI is asking for a size, and the answers come
  back stale and oscillating: measured, 1 and 2 lines were right (22pt, 40pt) and
  then 3 and 5 lines reported **22pt** again, so the box collapsed as you typed.
  `widthTracksTextView` already keeps the container as wide as the view; leave it
  alone. (The probe that isolated this instrumented the scroll view's frame *and*
  the text view's `usedRect`; seeing `used 54pt` inside a `22pt` box is what
  identified the stale answer.)
- **SwiftUI's `.continuous` corner is not a circle** (measured, asserted by
  `run-composer.sh`): the flat span at a rounded rect's top row is narrower than
  `width - 2r`, so pixel-measuring the corner does not give the radius back.
  Measured for a 300pt box, through `WindowPixels.capture(_ view:)`: radius 10 →
  11.0pt inset, 14 → 16.0pt, 18 → 21.0pt, 22 → 26.0pt, corner height ≈ radius + 1.5
  (`.circular` at 18 → 17.0pt, off the line). The harness converts a measurement
  back with `1.25 * radius - 1.5`, tolerance 1.5pt — **calibrated for that capture
  path**; a window-server capture of the same box reads 3.5pt wider.
- **A material does not survive a `cacheDisplay` capture, and a two-surface
  capture has no single backdrop.** `WindowPixels` picks "ink" by comparing a
  pixel to the capture's most common brightness. Two ways that quietly breaks:
  (1) a sidebar `List`'s material draws as transparent offscreen and resolves to
  black, so *every* pixel looks darker than the backdrop — one harness read a
  whole column as a single 428pt "line of text"; (2) when the capture holds a
  sidebar and a detail column with different colours, the modal brightness is
  whichever covers more pixels, and the other surface becomes all-ink. Fixes,
  both applied: paint a flat backdrop in a mock instead of relying on a material
  (`.scrollContentBackground(.hidden)` + one `Color` behind the split view), and
  measure ink against `background(in:yRange:)` — the modal brightness of the
  region under test — rather than the whole image. The failure looked like a
  behaviour bug ("clicking the project does not bring the chats back"); it was a
  capture bug.
- **Do not photograph an occluded window**: `CGWindowListCreateImage` hands back
  whatever the window server last composited, so a harness window that ends up
  behind the real app captures **solid black** — and then an assertion like "the
  box fill is visible" reports content missing rather than capture broken. All
  three visual harnesses therefore draw the view instead
  (`WindowPixels.capture(_ view:)`), which cannot be occluded and conveniently
  leaves the title bar and toolbar out of the picture. Two consequences: the
  composer's corner calibration is 3.5pt narrower than a window capture would
  read, and a capture's y now starts at the content view's top edge — which is
  also where a posted mouse event's coordinates start at the bottom, so a click
  point is `contentHeight - distanceFromTop` (the title bar is in neither).
- **Sidebar list layout, measured** (`run-sidebar-align.sh` / `run-sidebar-click.sh`,
  macOS 15, `.listStyle(.sidebar)`):
  - a `listRowBackground` fills the **whole column** — 0 to 140pt in a 140pt
    column, no inset of its own — so a highlight pill has to be inset by hand if
    it should not run edge to edge;
  - and it fills the row's whole **cell**, its own insets and any padding
    included: a project row that padded itself 12pt top and bottom came out
    **37.0pt** tall against a chat's 28.0pt, its extra air ended up *inside* the
    pill, and the padding also changed the rhythm — so the menu's second pass
    deleted every vertical margin instead of tuning one (§12). (Also measured:
    `listRowInsets(top: 12)` moved the pill to ~29pt with *no gap at all*,
    `listRowInsets(EdgeInsets())` still spans the column, and a 12pt spacer row
    produced a 28pt gap — see the next item.)
  - a row's content is floored at **20pt** (`.defaultMinListRowHeight` is ignored
    by `.listStyle(.sidebar)`: a 40pt spacer still produced a 48pt cell), so a
    pill's height is `max(20, content) + 8` — which is why 17pt of content and
    20pt of content are both a 28.0pt pill, and what the shared chrome's
    `rowMinHeight` relies on;
  - **text drawn over a saturated fill comes back tinted**: white over pure blue
    lands at (229,229,255), 26 off neutral — past the ±24 `WindowPixels.isText`
    uses to keep coloured fills out of a count of ink — so a harness that counts
    rows by ink silently loses the row under a blue pill. It did: five rows were
    painted and four counted. Count painted rows by colour instead;
  - list **rows** are inset ~2pt further than section **headers**, and the system
    row inset is ~19pt from the sidebar edge while the search field sits at 10pt
    (hence `projectIconShift = 9`, and `projectIconRightShift = 6` on top of it);
  - a sidebar list row has a **minimum height** of ~27.5pt, and row *padding* does
    not add what it says: 12pt of `.padding(.top)` shows up as ~9.8pt of
    separation and *steals 1.5pt from the gap below the padded row*, which is the
    whole of the project→chat/chat→chat difference (26.5 vs 28.0). A spacer row
    (`Color.clear.frame(height:)`) keeps the rhythm exact but is floored at the
    27.5pt minimum; `.listRowInsets` is worse (it stole 5.5pt);
    `.listSectionSpacing` is **unavailable on macOS**, so per-*group* spacing
    cannot be expressed directly. Conclusion, now shipped: the only rhythm that is
    exactly equal everywhere is the list's own, so no row insets or pads itself
    vertically and no group is separated at all;
  - `Color.accentColor` follows the *window's* focus: macOS draws an inactive
    window's accent as grey, so an accent-tinted row background changes colour when
    the sidebar is not the key view. A neutral `Color.primary.opacity(0.08)` does
    not — hence one grey for both hover and the active row, which also says the two
    are the same statement rather than two different ones;
  - `Image(systemName: "folder")` at `font(size: 15)` renders 16.5pt of ink, so a
    fixed 15pt frame does not clip it;
  - **a posted mouse event is not always delivered.** With several clicks in one
    run, one now and then lands nowhere — the fold-then-unfold pair in
    `run-sidebar-click.sh` is where it shows ("3 row(s) on screen" when five were
    expected). It is the harness, not the app: the mock's row is a `Button`
    toggling `@State`, a delivered click always toggles it, and re-running passes.
    Two things follow. Do not "fix" this by retrying silently — a retry hides the
    one regression the harness exists for, and adding `makeKeyAndOrderFront` +
    `NSApp.activate` before each click made delivery *worse*, not better (measured:
    7 of 8 clean before, 1 of 4 clicks delivered after). And read a lone fold
    failure as "re-run me", not as a result; §11 item 10 is the human check that
    settles it.
  - a window capture's bitmap comes back **alpha-first**, so read pixels through
    `WindowPixels` and never through `NSBitmapImageRep.bitmapData` (§3).
- **The transcript's folding identity is a SwiftUI fact, not a cosmetic one.** A
  `ForEach` over `TranscriptRows.group(items)` keys each row by its `id`, and
  `@State` — including a folded row's `isExpanded` — is thrown away when that id
  changes. A group's id is therefore `group-<first item id>`, never a hash of its
  contents: a streaming turn appends calls to a run every second or two, and an
  id that followed the contents would fold the line back up under the user's
  cursor mid-read. The same reasoning applies to any future row whose contents
  grow.
- **A folded row is not always a tool call.** Once `thinking` joined the fold, an
  assumption that held for three families stopped holding for the fourth: a
  reasoning item has no `toolArguments`, so `foldedSummary` is empty for it *by
  construction* (`toolInputSummary` returns `""` when there is nothing to
  summarise) and a folded line whose identity comes from its summary would come
  out blank. The replay harness's “every folded call has a line to identify it”
  check had to be narrowed to `item.kind == .toolCall` for the same reason —
  reasoning is identified by its family name, deliberately, because a
  middle-truncated fragment of a first draft says nothing. Anything that walks a
  group and assumes a tool name, an output or a diffstat has to ask
  `QuietFamily.of(item)` first; there are now four families and only three of them
  are tools.
- **An empty view still costs its `HStack`'s spacing.** `DiffStatView` draws
  nothing when both counts are `nil` or zero, which is every `read` — but the
  `ForEach` that produced it still took part in the row, so a read's line came out
  with a 6pt gap in front of nothing. Guard the *spacing* (here: filter to the
  changes that actually have numbers) rather than trusting a view that renders
  empty to render nothing at all.
- The project uses `PBXFileSystemSynchronizedRootGroup` rooted at `PiCode/`, so
  **new files under `PiCode/` are added to the target automatically** — no
  `project.pbxproj` edit needed. Files added *outside* `PiCode/` (e.g.
  `Tools/SmokeTest/`) are correctly excluded from the app target.

---

## 11. What's next (in priority order)

0. **Auth is still only half-addressed.** Credentials and third-party
   providers can now be configured in Settings → Providers (`run-providers.sh`,
   §7), but Pi's *failure* messages are still shown as bare error rows. Pi says
   things like `No API key for anthropic/claude-sonnet-4` and
   `Run '/login anthropic' to re-authenticate.`; those should render as a
   guidance card with a button that opens Terminal at `pi`, instead of text the
   user has to interpret. Readiness already exists (`pi auth check --no-refresh`
   from the same pane) — reuse it for the card's wording. Never call
   `pi auth print-api-key`, `print-bearer-token`, or `--credentials`.
1. **End-to-end run with a real prompt.** Everything up to the model call is
   verified; nothing downstream of a real `message_update` stream has been seen
   live. Pick a cheap model, send a one-line prompt in a scratch project, and
   confirm: live assistant text → durable row handoff without duplication, tool
   cards update in place, `agent_settled` reconcile is flicker-free, queued
   steer/follow-up appear, token usage bar moves. Expect to fix unknown event
   shapes here — that is the point of the exercise.
2. ~~**Extension UI round trip.**~~ **Done** —
   `./Tools/SmokeTest/run-extension.sh` drives the real controller against a live
   extension: every dialog kind, client cancel, Pi's own timeout, notifications,
   status and widget set/clear, title and composer prefill, and the unsupported
   method path. It is credit-free (Pi runs extension commands locally) and the
   two bugs it found are fixed (§9). Still to eyeball in the GUI: the dialog card
   layering, the "N more waiting" queue count, and that Escape is a real cancel
   rather than a dismiss — the harness covers the logic, not the pixels.
3. ~~**Audit the transcript rows against the spec** (`README.md`).~~ **Done** —
   found and fixed: file references were dead links (the environment action was
   never provided), change chips could not open the diff the spec says they
   should, replies had no branch action, and the running turn was not the
   compact elapsed-time disclosure the spec asks for. User prompts are now the
   trailing bubble too. Not covered by a harness: scroll-position stability while
   streaming upward, and ANSI color in the bash log — check both by eye during
   the live run in item 1.
4. **Trust flow polish.** `TrustViews` + `ProjectTrustService` exist but a full
   manual pass (untrusted project with `.pi/settings.json` → approve → relaunch →
   badge) hasn't been done, and `trust.json` shouldn't be left behind after
   testing.
5. **Interrupt/abort paths under load**: `abort` mid-stream, `abort_bash` while a
   command runs, `interrupt()` vs `abortRetry()`, and process death
   (`onExit`) mid-turn.
6. **Session lifecycle**: `new_session`, `switch_session`, `fork`, `clone`,
   `compact`, `export_html` are implemented but only lightly used. Verify each
   updates `sessionFile`/`sessionId` and the sidebar/ephemeral-row behaviour.
7. **Accessibility pass**: keyboard focus visibility, VoiceOver labels on
   transcript rows and tool cards, Reduce Motion honored.
8. **Paste an attachment into the composer.** `README.md` promises paste of
   images and text files (twice: the composer section and the parity table), and
   only the file picker and drag-and-drop exist. The editor is a plain
   `NSTextView`, so this means overriding `paste(_:)`/`readSelection(from:)` in a
   subclass: an image on the pasteboard becomes an `Attachment`, a string stays
   text. Do not intercept plain text paste — `@path` references are typed, not
   pasted, and a paste that silently becomes an attachment would surprise.
9. **The floating composer, seen once by a human.** The structure is asserted
   but the overlay has never been looked at on screen (no screen-recording
   permission here, and rendering the real `SessionView` needs a live
   controller). Open a session long enough to scroll and check: the last row ends
   above the box, earlier rows pass *behind* it and fade, the fade matches the
   transcript background in both light and dark appearance, the box does not jump
   as the editor grows from one line to two, the box's edges line up with the text
   above it (measured from two pane widths in `run-composer.sh`, but never against
   a real transcript row), and its distance from the bottom edge reads as a
   deliberate margin rather than a cropped box.
10. **The sidebar, both halves of the check — and this one is urgent.** The menu's
   second pass (no rule under the search field, one uniform row pitch, the folder
   glyph 6pt in, one grey hover/active highlight, 13pt regular type) was made on an
   explicit instruction to stop running harnesses, so **none of it is measured**:
   the status table's numbers are the old ones plus arithmetic, and both sidebar
   harnesses were rewritten without being run. First run
   `./Tools/SmokeTest/run-sidebar-align.sh` and
   `./Tools/SmokeTest/run-sidebar-click.sh` — they now assert a glyph at
   `sidebarMargin + projectIconRightShift`, an exact pitch (project→chat =
   chat→chat = chat→project) from four painted pills, no `.font` in the file with a
   weight other than `.regular`, no vertical padding in `SidebarRowChrome`, and
   exactly one `Divider()` left — and replace the ⚠️ rows in §2 with what they
   print. Then the human half, which no harness here can see: that the fold
   survives a relaunch, that a grey highlight on a *project* row looks right (it
   had none before — only chats hovered) in both appearances, that a fold made
   *while* a search is running reads as deliberate rather than as missing results,
   that folding the project whose session is open does not disturb the open
   session, that 13pt rows against the 11pt caption still read as one menu, and
   that the search field's own fill separates it well enough now that the rule
   under it is gone.
11. Update this file when you finish any of the above.
12. **The folded rows, seen once by a human.** The folding *rule* is proved
    over every real session by `run-replay.sh` (see §2), but nothing has drawn a
    folded line: there is no harness for it, and none was run — this landed on an
    explicit instruction to stop the verify loop. Open a real session and check:
    that a run of steps reads as *one* dimmed line and not as a card, that the
    content opens on a click anywhere along the line (the whole row is
    `.contentShape(Rectangle())` inside a `.plain` button) and that nothing looks
    *un*clickable now that there is no chevron (the hover lift and the tooltip are
    the whole affordance), that a one-step group opens its content directly while a
    many-step group opens a list, that the command or path in `foldedSummary` is
    truncated in the *middle* and stays one line, that a running call's spinner and
    elapsed time tick, that one of the 153 folded failures shows its red `Failed`
    pill while collapsed, that the nested step rows' diffstats line up with the
    one-step rows' output, and that the empty-state and long-output paths still
    look right in both appearances. Also check the grouped title on a real run —
    `Thinking, edited files, run commands` is generated, and the words are the one
    part of this that no test can judge: in particular that a run of **reasoning**
    reads correctly now that it is folded with the calls, is not mistaken for a
    call, and that a `Thinking` step inside an opened run draws the reasoning text
    (selectable, no output box, `Copy Reasoning` on the menu) rather than an empty
    card. The one behaviour this pass *removed* is deliberate: a `Thinking` row no
    longer opens itself while the reasoning streams — the folded line shows a
    spinner and the text is one click away — so if watching reasoning arrive turns
    out to be worth the movement, that is the thing to ask for back.
13. **A compaction row, seen once.** There is no compaction row to look at in the
    16 sessions on disk — Pi writes 51 `compaction` *entries*, but a compaction
    reaches the transcript only as a `compactionSummary` *message* from
    `get_messages`, and none of these sessions' active branches has one (the
    builder reads the file, and a compaction entry carries no `message`). So the
    new one-line row (`[icon] Compact context`) is unverified end to end; the
    mapping from message role to `SummaryKind` is checked by `run-open.sh` on the
    first session that happens to have a summary message (unrun, like everything
    else this turn), but *nobody has seen the row*. Open a compacted session and
    check: one dimmed line, the glyph matching the tree inspector's for the same
    event, no box, no summary text, and `Copy Summary` still on the context menu.

Already closed by the harnesses (kept here so nobody re-opens them):

- ~~Reloaded sessions lose compaction/branch markers~~ — verified against a real
  compacted session: `get_messages` includes the summary, and the transcript
  renders a compaction row after resume (`run-open.sh`).
- ~~Timed extension dialogs lingered after Pi had resolved them~~ — dismissed by
  a local deadline that mirrors Pi's, and the activity timeline says why
  (`run-extension.sh`).
- ~~A 1.5 s dialog timeout displayed as "25m 0s"~~ — the wire sends milliseconds;
  `ExtensionUIRequest.timeoutSeconds` converts once (`run-extension.sh`).
- ~~`SessionReplayTest` orphan check was vacuous~~ — it now matches `toolResult`
  messages to calls by `toolCallId` (3754 of 3754 matched).
- ~~Deeply nested RPC payloads crash the app~~ — the iterative scanner replaced
  `JSONDecoder` on that path (§10).
- ~~`get_tree` stalls the app on long sessions~~ — the tree is built locally, and
  entries are followed with a cursor instead of re-read (§9).

---

## 12. Conventions

- **Layout**: one type per file where practical; feature folders mirror the
  three-pane UI. New UI goes in the matching `Features/` folder.
- **Sidebar rows**: a project and its chats are the same rank, so they share
  `SidebarStyle.rowFont` — 13pt, `.regular`, and *nothing* in the menu is medium,
  semibold or bold (the semantic styles are avoided here because they drag a
  weight along with their size; `run-sidebar-align.sh` greps the file for a
  heavier one) — and the primary text colour. A chat has no glyph; it is indented
  by `SidebarStyle.titleIndent` so its title starts where the project's name
  starts. A project is a **row**, never a `Section`: the sidebar list style turns
  a section header into a collapsible group with a disclosure chevron, and a
  project is folded by clicking the row instead. Rows also share the leading inset
  a section header does not, which is why the indent no longer needs a correction
  — measure it with `run-sidebar-align.sh` after changing the sidebar. The folder
  glyph is positioned by an `.offset` (`projectIconOffset`) rather than by padding,
  because a shift that is drawing-only leaves the name — and every chat title
  aligned to it — exactly where it was. The search field carries no rule beneath
  it: its own recessed fill is the separation, and one `Divider()` (the footer's)
  is all that is left in this view.
- **The composer is one shape and one row**: the editor, its attachment chips and
  its controls share a single rounded box (`ComposerMetrics.cornerRadius`) and
  nothing behind them fills anything — no bar material under the composer area.
  A new control goes on that row, left of the model picker if it is an *input*,
  right of it if it configures the *run*; a new row is a design change, not an
  addition. Every control there must earn its space: the send button doubles as
  Stop rather than sitting next to one.
- **The composer's numbers live in `ComposerMetrics`, its width in
  `ConversationColumn`**: the box's padding, the gap above the control row and
  `boxHeight(forEditor:)` are metrics the view *uses* and the harness *predicts
  from*, so a padding change shows up as a measured number instead of a silent
  drift from a hard-coded expectation. The box must stay in the transcript's
  column; a second floating element goes in `ConversationColumn` too, or it will
  be pane-wide.
- **The composer stays small and stays an overlay**: two lines, then it scrolls;
  it is drawn over the transcript, and the transcript is told
  (`ConversationView.bottomInset`) because an overlay reserves no space. Nothing
  is added *below* the composer — that was a deliberate removal, and any new
  session state belongs in the transcript's system rows or the inspector, not in
  a footer. If you change the composer's height or padding, change
  `ComposerHeightKey`'s consumer too, and re-run `run-composer.sh`: the box's
  height is asserted against `ComposerMetrics.editorMaxHeight`, not a magic
  number.
- **Return-family keys are decided from the event, never the selector**: Shift
  means "add a line", Option means "queue a follow-up", and the send chord comes
  from `PreferencesStore.SendKey`. The selector alone is not enough (§10) — and
  because the mapping is invisible in a diff, `run-composer.sh` asserts it.
- **Vertical rhythm in the sidebar**: every row is on the list's own pitch — a
  chat sits as far below the previous chat as below its project's name, and a
  project sits as far below the chat above it as a chat does. Nothing gets an
  extra margin to say "this is a heading": the folder glyph is what separates two
  projects. Neither a margin nor row padding is a free way to add breathing room —
  a row's padding changes the row's pitch *and* grows the pill, because
  `listRowBackground` fills the whole cell — so if a gap is ever needed here, cut
  it out of the *shape* (as `rowHighlightInset` does horizontally), do not pad the
  row, and measure it with `run-sidebar-click.sh`. The project glyph gets a fixed
  *height* as well as width so a 15pt folder cannot make its row taller than a text
  row.
- **The row highlight sits on the sidebar's horizontal margin, and is one
  colour**: hover and the active row draw the same rounded pill
  (`rowHighlightRadius`) filled with `rowHighlightFill` — a neutral grey, not
  `accentColor`, which macOS draws grey anyway once the window is not key, so an
  accent-tinted background changes colour under the pointer and says something
  different about hover than about selection. The pill is inset by
  `rowHighlightInset` (which is `sidebarMargin`) so it starts and ends where the
  search field does; `listRowBackground` fills the whole column by itself, so
  without that inset it would run edge to edge while every other element sits on a
  margin. Both rows paint through one `SidebarRowChrome`
  (`View.sidebarRow(fill:)`), which is what makes a project's pill the same height
  as a chat's — one place to change and one place to measure: if you touch
  `rowMinHeight`, `rowHighlightInset` or the chrome, run `run-sidebar-click.sh`,
  which measures the pills and the steps between them.
- **The transcript folds four quiet shapes, and folding is a pure function**: a
  tool call with a card is the default; only `thinking`, `bash`, `edit`/`write`
  and `read` become a folded line, and the list lives in `QuietFamily.of(_ item:)`
  — one place, with the words (`label`/`pluralLabel`/`listed(count:)`) and the
  icon beside it. Adding a fifth family means adding a case and accepting that the
  user will stop reading those rows. The same function decides membership *and*
  the title, so the two cannot disagree. The *rule* stays in `TranscriptRows.group`:
  pure, Foundation-only, no SwiftUI, because that is what lets `run-replay.sh`
  prove it over every real session instead of over an example. Don't move that
  decision into the view, and don't give a group an id that depends on its contents
  — a streaming turn would re-key the row and fold it up again (§10). Reasoning is
  not a tool: a step's shape comes from `QuietFamily.of(item)`, never from
  `toolName` alone (§10).
- **A tool call's content is drawn in one place**: `ToolCallContent` renders
  arguments, file changes, output, the truncation notice, the failure sentence and
  the structured result; `QuietStepContent` chooses between that and a reasoning
  step's text, and both the card and the folded rows add only their own headers.
  Change a tool's presentation there, once. Anything a user must not be able to
  miss stays *outside* the disclosure — that is why the failure sentence is part
  of the content and the running/failed pill is on the collapsed line — and any
  new tool-shaped row has to keep that rule: no state that matters only behind a
  click.
- **A folded row has no chevron, and its line says what opens**: the transcript has
  one way of saying "there is more under this" — a dimmed line, a `.plain` button
  over the whole row, a hover that lifts the dimming, and a tooltip naming the
  action (`ToolGroupView`, `ToolActionRow`). Do not add a disclosure glyph to a row,
  and do not use `DisclosureGroup` for one: its chevron lands in the leading
  gutter, which both re-introduces the arrows and pushes the row's icon out of line
  with every other icon in the column. System rows that *are* a fact rather than a
  fold — a compaction, a retry — are a single line built from the model
  (`SummaryKind`), never a badge plus a paragraph.
- **Recessed controls on the sidebar**: the search field's fill has to be darker
  than the sidebar material in *both* appearances, so it is a translucent black
  with a per-appearance alpha (`SidebarStyle.searchFieldFill`) — `.quaternary`
  goes the wrong way in dark mode. A custom fill also removes AppKit's focus
  ring, so the field draws its own: keyboard focus must stay visible.
- **Adding a command**: add the `RPCCommand` case (verify the wire name in Pi's
  `docs/rpc.md` *and* the installed bundle), add it to the wire-format case list
  in `Tools/SmokeTest/RPCSmokeTest.swift`, add a `PaletteCommand` case if it is
  user-invocable, then wire it in `AppState.run(_:)` and/or the controller. Menus
  and shortcuts come for free because they all dispatch through `PaletteCommand`.
- **Adding an inspector pane**: add the `AppState.InspectorTab` case (it must
  supply `label` + `systemImage`), then the pane view in `InspectorPanes.swift`
  and one line in `InspectorView.pane(controller:)`.
- **Writing large Swift files**: split them. A single `write` of >~200 lines hits
  the output token limit; append in chunks with `bash cat >> … << 'PICODE_APPEND_EOF'`.
- **Comments**: explain *why* (protocol quirks, Pi semantics, macOS constraints),
  not *what*. The protocol facts in §9/§10 belong in comments next to the code
  that depends on them.
- **Never** leave a `TODO` that hides a compatibility problem; surface it in the
  UI as a compatibility card.
- **Never** hardcode a path inside Pi's config directory. Ask `PiPaths` (§7) —
  Pi can be relocated, and PiCode must agree with it.

## 13. Review checklist before you call something done

- [ ] `swiftc -typecheck` clean (§3 step 1)
- [ ] `xcodebuild` → `** BUILD SUCCEEDED **`
- [ ] `./Tools/SmokeTest/run.sh` → `RESULT: all checks passed`
- [ ] `./Tools/SmokeTest/run-json.sh` → `RESULT: all checks passed`
- [ ] `./Tools/SmokeTest/run-replay.sh` → `RESULT: all checks passed`, including
      the folding checks. If you touched `TranscriptRows`, `QuietFamily`,
      `ToolCallContent`, `ToolGroupView`, `QuietStepContent` or `ToolCallCard`,
      read its `folding:` line: `0` items lost, `0` folded rows from another tool,
      `0` adjacent/split runs, and the `families` list must add up to every quiet
      step in the session — the `reasoning folds with the steps it belongs to`
      check is what proves the last one (3190 of 3190 here, 8132 steps in total).
      A `watched:` count above zero means there are real folded failures on disk —
      those need `ToolGroupView`'s red pill, so they are the rows to look at when
      you open the app
- [ ] `./Tools/SmokeTest/run-open.sh --small` → `RESULT: all checks passed`
- [ ] `./Tools/SmokeTest/run-paths.sh` → `RESULT: all checks passed` (only if you
      touched `PiPaths`, trust, session discovery, or process launching)
- [ ] `./Tools/SmokeTest/run-extension.sh` → `RESULT: all checks passed` (only if
      you touched extension UI, dialogs, or the prompt send path)
- [ ] `./Tools/SmokeTest/run-providers.sh` → `RESULT: all checks passed` (only if
      you touched `PiProviderService`, settings, or Pi's config paths)
- [ ] `./Tools/SmokeTest/run-index.sh` → `RESULT: all checks passed` (only if you
      touched session discovery, the sidebar, or preferences)
- [ ] `./Tools/SmokeTest/run-sidebar-align.sh` → `RESULT: all checks passed`
      (only if you touched the sidebar layout; needs a GUI session)
- [ ] `./Tools/SmokeTest/run-sidebar-click.sh` → `RESULT: all checks passed`
      (only if you touched the sidebar's rows or highlights; needs a GUI session).
      It measures the pills, so if you touched `rowMinHeight`,
      `rowHighlightInset` or `SidebarRowChrome`, check that a project's highlight
      is still the height of a chat's (28.0pt) and that the three steps —
      project→chat, chat→chat, chat→project — still agree (28.0pt each; a row that
      pads itself vertically breaks the second number, and pads *inside* its pill
      to break the first)
- [ ] `./Tools/SmokeTest/run-composer.sh` → `RESULT: all checks passed`
      (only if you touched the composer, the Return key, `PreferencesStore.SendKey`,
      `SessionView`'s bottom area, or the transcript's bottom inset; needs a GUI
      session). If you changed the composer's height or padding, check that the
      measured editor heights are still 22/40/40/40pt, that the box still
      matches `ComposerMetrics.boxHeight(forEditor:)`, and that the box and a
      transcript row are still the same width at both 1300pt and 500pt — a wrong
      height means a `NSViewRepresentable` is taking its maximum height again, and
      a wrong width means the padding and the width cap were swapped (§10)
- [ ] The app launches and stays up for a few seconds with no crash report
- [ ] Folded rows opened by eye: a run of steps reads as one dimmed line,
      clicking it (anywhere along it) opens, a one-step group opens its content
      directly while a many-step group opens a list, a running call keeps its
      spinner, a folded failure keeps its red pill, no chevron is drawn on any
      folded line (a `Thinking` step included), a `Thinking` line opened shows
      reasoning text rather than an empty card, and a compaction is one
      `Compact context` line and nothing else (§11 items 12–13)
- [ ] `git status` shows **no** changes in `~/.pi/agent` (no `trust.json`, no new
      session files, no touched settings)
- [ ] No `sh -c` / `Process` with a shell anywhere in the diff
- [ ] New RPC field names verified against Pi's `docs/rpc.md`
- [ ] Any new capability gap labeled as a compatibility fallback, not hidden
- [ ] This file updated if a decision, gotcha, or next step changed
