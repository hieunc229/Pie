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
| Session replay over all real sessions | ✅ `./Tools/SmokeTest/run-replay.sh` — 7.4k lines, no bad rows/ids/roles |
| Resuming a real session (`--session`) | ✅ `./Tools/SmokeTest/run-open.sh` — read-only verified byte-for-byte |
| Pi config locations (relocated `PI_CODING_AGENT_DIR` etc.) | ✅ `./Tools/SmokeTest/run-paths.sh` — PiCode and Pi agree, proven against a live `pi` |
| Extension UI round trip against a live extension | ✅ `./Tools/SmokeTest/run-extension.sh` — all 35 checks pass, no model call |
| Sidebar contents are real (no hidden project DB) | ✅ `./Tools/SmokeTest/run-index.sh` — 16 session files on disk → 8 projects, every path exists |
| Providers, credentials, third-party providers | ✅ `./Tools/SmokeTest/run-providers.sh` — verified against a live `pi`, no credential of the user's is touched |
| Sidebar row layout (one size, chat titles aligned under project names) | ✅ `./Tools/SmokeTest/run-sidebar-align.sh` — measured on screen: 0.0pt alignment delta, glyph on the search margin, project→chat pitch 26.5pt against chat→chat 28.0pt (the 1.5pt residual is the list's, see §10) |
| Sidebar rows behave (click a project to fold its chats; highlight on the search margin) | ✅ `./Tools/SmokeTest/run-sidebar-click.sh` — clicks a real row through the window's event path: 3 rows → 1 → 3; highlight 10.0pt in from both edges of a 268pt column. (Its row counting broke once for a reason that had nothing to do with the sidebar: a material is invisible to a `cacheDisplay` capture — §10.) |
| Discovery / launch / trust / session index / git | ✅ implemented |
| Composer: Return sends, Shift+Return is a line, box shape and the two-line clamp | ✅ `./Tools/SmokeTest/run-composer.sh` — real `ComposerTextView`, real key events: Return/Shift/Option/Command-Return in both send-key modes; box measured at 76.0pt (two lines plus the control row) and the editor measured at 22.0/40.0/40.0/40.0pt for 1/2/3/5 lines |
| Composer floats over the transcript, nothing below it | ⚠️ structure only: `run-composer.sh` asserts the overlay, the inset and the absence of a footer in the source. Nobody has watched a long session scroll under the box — see §11 |
| Transcript, composer, inspector (5 panes), palette, settings | ✅ implemented |
| Real end-to-end prompt against a model | ⚠️ **not yet exercised** (see §11) |
| Transcript vs README spec | ✅ audited (§11); the gaps it found are fixed |
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
  tool result matched to a call by `toolCallId`.
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
    its project's name; the project glyph's ink lands on
    `SidebarStyle.sidebarMargin` (the search field's left edge) at full width; and
    a chat sits as far below its project's name as below another chat. The last
    comes from ink *centres* measured in the project name's own x column —
    measuring whole lines would let the taller folder glyph into the project's
    span and skew it, which is exactly the false 1.5pt difference this used to
    report. It dumps `/tmp/picode-sidebar-look.png`, a mock of the whole column,
    so a human can judge the colours a machine cannot.
  - `run-sidebar-click.sh` checks behaviour and the horizontal margin. It paints
    one row's background red, measures that rectangle against the search field's
    margins, and then *clicks a row through the window's own event path* — a
    `NavigationSplitView` sidebar, `List`, `Button` and all — asserting the chats
    fold away and come back. Posted events, not delivered ones: SwiftUI runs an
    event-tracking loop on mouse-down, so `sendEvent`ing the down and the up
    deadlocks the harness. It dumps `/tmp/picode-sidebar-click.png`.
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
    split view) and measures `isText` against the modal brightness *inside the
    column*. A sidebar `List` uses a material, materials do not appear in a
    `cacheDisplay` capture (they resolve to transparent → black), and a capture
    that holds two surfaces has no single backdrop — the harness reported
    "three rows → found 1" for exactly that reason, having counted the whole
    column as one band of ink (§10).
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
  It also measures the prompt box from a capture — 372×76pt, against
  `ComposerMetrics.cornerRadius` and against two lines plus the control row — and
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
│   ├── Conversation/    ConversationView, MarkdownView, TranscriptRowView, ToolCallCard
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
| **A project is a row, not a section header** | A `Section` in the sidebar list style is a collapsible group with a disclosure chevron — wrong for a list that mirrors what is on disk. The row *is* the disclosure: clicking it folds its chats (`AppState.toggleCollapsed`, persisted as a decoration; a running search always wins so a match is never hidden inside a fold). As a row it also shares its chats' leading inset, which is what makes "a chat title starts where the project's name starts" exact instead of a two-point correction. The glyph is drawn `projectIconShift` (9pt, measured) to the left of its row so it lands on the search field's margin, and that shift is drawing-only, so the name — and therefore every chat title under it — does not move. Its highlight is a `Button`'s: a `listRowBackground` pill inset by `rowHighlightInset`, which is `sidebarMargin`, because the background fills the whole column on its own (measured). `run-sidebar-click.sh` clicks the row for real. |

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
  - list **rows** are inset ~2pt further than section **headers**, and the system
    row inset is ~19pt from the sidebar edge while the search field sits at 10pt
    (hence `projectIconShift = 9`);
  - a sidebar list row has a **minimum height** of ~27.5pt, and row *padding* does
    not add what it says: 12pt of `.padding(.top)` shows up as ~9.8pt of
    separation and *steals 1.5pt from the gap below the padded row*, which is the
    whole of the project→chat/chat→chat difference (26.5 vs 28.0). A spacer row
    (`Color.clear.frame(height:)`) keeps the rhythm exact but is floored at the
    27.5pt minimum; `.listRowInsets` is worse (it stole 5.5pt);
    `.listSectionSpacing` is **unavailable on macOS**, so per-*group* spacing
    cannot be expressed directly;
  - `Image(systemName: "folder")` at `font(size: 15)` renders 16.5pt of ink, so a
    fixed 15pt frame does not clip it;
  - a window capture's bitmap comes back **alpha-first**, so read pixels through
    `WindowPixels` and never through `NSBitmapImageRep.bitmapData` (§3).
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
   controller). Open a session long enough to scroll and check four things: the
   last row ends above the box, earlier rows pass *behind* it and fade, the fade
   matches the transcript background in both light and dark appearance, and the
   box does not jump as the editor grows from one line to two.
10. **Click-to-fold a project by hand.** `run-sidebar-click.sh` now clicks a real
   row through the window's event path (3 rows → 1 → 3) in a
   `NavigationSplitView` sidebar, so the hit-testing half is proven. What is left
   is the human half: that the fold survives a relaunch, that the hover highlight
   looks right, that a running search un-folds a match instead of hiding it, and
   that folding the project whose session is open does not disturb the open
   session.
11. Update this file when you finish any of the above.

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
  `SidebarStyle.rowFont` (regular, no bold header) and the primary text colour.
  A chat has no glyph; it is indented by `SidebarStyle.titleIndent` so its title
  starts where the project's name starts. A project is a **row**, never a
  `Section`: the sidebar list style turns a section header into a collapsible
  group with a disclosure chevron, and a project is folded by clicking the row
  instead. Rows also share the leading inset a section header does not, which is
  why the indent no longer needs a correction — measure it with
  `run-sidebar-align.sh` after changing the sidebar.
- **The composer is one shape and one row**: the editor, its attachment chips and
  its controls share a single rounded box (`ComposerMetrics.cornerRadius`) and
  nothing behind them fills anything — no bar material under the composer area.
  A new control goes on that row, left of the model picker if it is an *input*,
  right of it if it configures the *run*; a new row is a design change, not an
  addition. Every control there must earn its space: the send button doubles as
  Stop rather than sitting next to one.
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
- **Vertical rhythm in the sidebar**: one chat sits as far below the previous
  chat as below its project's name (within 1.5pt — the list's own quirk, §10).
  Nothing gets an extra bottom margin to say "this is a heading": only
  `projectTopMargin` separates two projects, and the project glyph gets a fixed
  *height* as well as width so a 15pt folder cannot make its row taller than a
  text row. Row padding is not a free way to add breathing room — it changes the
  row's pitch; ask for the margin you want and measure it.
- **The row highlight sits on the sidebar's horizontal margin**: hover and
  selection draw a rounded pill, and that pill is inset by `rowHighlightInset`
  (which is `sidebarMargin`) so it starts and ends where the search field does.
  `listRowBackground` fills the whole column by itself, so without the inset the
  pill runs edge to edge while every other element sits on a margin. Verify with
  `run-sidebar-click.sh`, which measures the pill's rectangle.
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
- [ ] `./Tools/SmokeTest/run-replay.sh` → `RESULT: all checks passed`
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
      (only if you touched the sidebar's rows or highlights; needs a GUI session)
- [ ] `./Tools/SmokeTest/run-composer.sh` → `RESULT: all checks passed`
      (only if you touched the composer, the Return key, `PreferencesStore.SendKey`,
      `SessionView`'s bottom area, or the transcript's bottom inset; needs a GUI
      session). If you changed the composer's height or padding, check that the
      measured editor heights are still 22/40/40/40pt and that the box still
      measures `editorMaxHeight + 36` — a wrong number there means a
      `NSViewRepresentable` is taking its maximum height again (§10)
- [ ] The app launches and stays up for a few seconds with no crash report
- [ ] `git status` shows **no** changes in `~/.pi/agent` (no `trust.json`, no new
      session files, no touched settings)
- [ ] No `sh -c` / `Process` with a shell anywhere in the diff
- [ ] New RPC field names verified against Pi's `docs/rpc.md`
- [ ] Any new capability gap labeled as a compatibility fallback, not hidden
- [ ] This file updated if a decision, gotcha, or next step changed
