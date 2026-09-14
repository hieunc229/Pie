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
| `swiftc -typecheck` over all 47 sources | ✅ clean |
| RPC layer vs real `pi` (v0.85.1) | ✅ `./Tools/SmokeTest/run.sh` — all checks pass |
| Discovery / launch / trust / session index / git | ✅ implemented |
| Transcript, composer, inspector (5 panes), palette, settings | ✅ implemented |
| Real end-to-end prompt against a model | ⚠️ **not yet exercised** (see §11) |
| Transcript row polish, per-row affordances | ⚠️ functional, not yet audited against the spec |
| Extension UI dialog round trip against a live extension | ⚠️ encode/decode verified; no live extension tested (§11) |
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
│   ├── SessionIndex.swift     read-only scan of ~/.pi/agent/sessions (never writes)
│   ├── ProjectTrustService.swift Pi-compatible trust.json read/write + lock + nearest ancestor
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
│   ├── Sidebar/         SidebarView: projects → sessions, search, pin/hide/delete
│   ├── Session/         PiSessionController (the brain), SessionView, TranscriptBuilder,
│   │                    TranscriptExporter
│   ├── Conversation/    ConversationView, MarkdownView, TranscriptRowView, ToolCallCard
│   ├── Composer/        ComposerView, ComposerTextView (AppKit NSTextView), TrustViews
│   ├── Inspector/       InspectorView (Changes), InspectorPanes (Files/Terminal/Tree/Context)
│   ├── Extension/       ExtensionChrome (widgets/status/notifications), ExtensionDialogHost
│   ├── Palette/         CommandPaletteView, Sheets (rename/compact/fork/delete)
│   ├── Settings/        SettingsView (General/Composer/Sessions/Pi)
│   └── Shared/          UIComponents (BannerView, StatusPill, DiffStatView, …)
└── Tools/SmokeTest/     run.sh + RPCSmokeTest.swift (see §3)
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
| **`NSViewRepresentable` NSTextView composer** | Needed to decide what Return means per `PreferencesStore.SendKey` (`returnKey` vs `commandReturn`), to disable smart substitutions, and to support slash/`@path` completion without fighting SwiftUI's `TextField`. |
| **No `.keyboardShortcut(.return)` on Send** | It would double-fire with the text view's Return handling. |
| **Images via RPC `images`; text files inlined as fenced `@path` blocks** | Pi only accepts images as attachments. Other files are inlined as Markdown so the model can read them, and the fenced block names the path. `AttachmentLoader` rejects anything that is neither an image nor text with a clear message. |
| **Tree inspector is read-only** | `navigateTree` is SDK/extension-only, not RPC (§9). PiCode shows the tree, and offers Fork/Clone plus an explicit compatibility note. |
| **Terminal pane runs Pi's `bash` RPC** | It is *not* a real shell. It shows what the agent ran and lets the user run one-off commands through the same tool. For an interactive shell, "Open in Terminal" opens a real one. |
| **Inspector → composer references via `AppState.composerInsertion`** | A stateless one-shot handoff (set string → composer consumes and clears). Avoids reaching into the composer's `@State` across the view tree. |
| **"Changes" pane excludes `.read` file touches** | A changes list that includes reads is not a changes list. Session changes and git changes are offered as two sources of the same pane. |
| **Transcript errors are always visible** | Never behind a disclosure. |
| **`PiDiagnosticsLog` is in-memory and opt-in** | It can contain file contents and prompts. Capped ring buffer, never written to disk; only rendered when `recordRPCPayloads` is on. |

---

## 7. Pi on-disk formats (as verified against v0.85.1)

### Sessions

```
~/.pi/agent/sessions/--<path with / and leading / replaced>--/<ISO8601>_<uuid>.jsonl
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
~/.pi/agent/trust.json   { "<absolute canonical path>": true|false }
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

- **Dialogs** (`select`, `confirm`, `input`, `editor`): Pi blocks until the client
  answers with `extension_ui_response` carrying the same `id` — `value` for
  `select`/`input`/`editor`, `confirmed` for `confirm`, or `cancelled: true`.
  Only **one** dialog is presented at a time; the rest queue and the dialog shows
  "N more waiting". The dim overlay is deliberately **not** click-dismissable: an
  extension question is a decision, not a tooltip. If the request carries
  `timeout`, Pi self-resolves; the client shows the note and does not track it.
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

---

## 10. Hard-won API facts (so you don't rediscover them)

- **`JSONValue` has no typed enum cases beyond** `null`, `bool`, `number`,
  `string`, `array`, `object`. There is no `.int`/`.double`/`.string(_:)` case —
  use the accessors (`string(_:)`, `int(_:)`, `double(_:)`, `bool(_:)`,
  `array(_:)`, `object(_:)`, `…Value`, `isNull`, `prettyDescription`) and build
  values as `.number(Double(x))`, `.object([...])`.
- Decoding goes through `JSONCoding.decode(_:)` / `JSONCoding.line(_:)`.
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
  `pinnedProjects`, `pinnedSessions`, `hiddenSessions`, `lastProjectPath`,
  `reducedMotionOverride`. Anything else is not persisted yet — add it here.
- `AppState.InspectorTab` is `String, CaseIterable, Identifiable` and exposes
  `label`/`systemImage` (not `title`).
- `PiDiagnosticsLog.limit` is internal so Settings can describe it in help text.
- The project uses `PBXFileSystemSynchronizedRootGroup` rooted at `PiCode/`, so
  **new files under `PiCode/` are added to the target automatically** — no
  `project.pbxproj` edit needed. Files added *outside* `PiCode/` (e.g.
  `Tools/SmokeTest/`) are correctly excluded from the app target.

---

## 11. What's next (in priority order)

1. **End-to-end run with a real prompt.** Everything up to the model call is
   verified; nothing downstream of a real `message_update` stream has been seen
   live. Pick a cheap model, send a one-line prompt in a scratch project, and
   confirm: live assistant text → durable row handoff without duplication, tool
   cards update in place, `agent_settled` reconcile is flicker-free, queued
   steer/follow-up appear, token usage bar moves. Expect to fix unknown event
   shapes here — that is the point of the exercise.
2. **Extension UI round trip.** Write a throwaway extension in a scratch project
   that calls `select`/`confirm`/`input`/`editor`, `notify`, `setStatus`,
   `setWidget`, `setTitle`, and an unsupported method (e.g. `setFooter`) to see
   the compatibility card. Verify only one dialog shows at a time, the queue
   count is right, Escape is a real cancel, and the overlay never dismisses on a
   stray click.
3. **Audit the transcript rows against the spec** (`README.md`): tool card
   affordances, collapsed-by-default long output, error always visible, copy
   buttons, timestamp semantics.
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
8. Update this file when you finish any of the above.

---

## 12. Conventions

- **Layout**: one type per file where practical; feature folders mirror the
  three-pane UI. New UI goes in the matching `Features/` folder.
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

## 13. Review checklist before you call something done

- [ ] `swiftc -typecheck` clean (§3 step 1)
- [ ] `xcodebuild` → `** BUILD SUCCEEDED **`
- [ ] `./Tools/SmokeTest/run.sh` → `RESULT: all checks passed`
- [ ] `git status` shows **no** changes in `~/.pi/agent` (no `trust.json`, no new
      session files, no touched settings)
- [ ] No `sh -c` / `Process` with a shell anywhere in the diff
- [ ] New RPC field names verified against Pi's `docs/rpc.md`
- [ ] Any new capability gap labeled as a compatibility fallback, not hidden
- [ ] This file updated if a decision, gotcha, or next step changed
