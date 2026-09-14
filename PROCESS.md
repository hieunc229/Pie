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
| Discovery / launch / trust / session index / git | ✅ implemented |
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

The other four harnesses exist because they each caught a real bug:

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
| **`NSViewRepresentable` NSTextView composer** | Needed to decide what Return means per `PreferencesStore.SendKey` (`returnKey` vs `commandReturn`), to disable smart substitutions, and to support slash/`@path` completion without fighting SwiftUI's `TextField`. |
| **No `.keyboardShortcut(.return)` on Send** | It would double-fire with the text view's Return handling. |
| **Images via RPC `images`; text files inlined as fenced `@path` blocks** | Pi only accepts images as attachments. Other files are inlined as Markdown so the model can read them, and the fenced block names the path. `AttachmentLoader` rejects anything that is neither an image nor text with a clear message. |
| **Tree inspector is read-only** | `navigateTree` is SDK/extension-only, not RPC (§9). PiCode shows the tree, and offers Fork/Clone plus an explicit compatibility note. |
| **Terminal pane runs Pi's `bash` RPC** | It is *not* a real shell. It shows what the agent ran and lets the user run one-off commands through the same tool. For an interactive shell, "Open in Terminal" opens a real one. |
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
8. Update this file when you finish any of the above.

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
- [ ] The app launches and stays up for a few seconds with no crash report
- [ ] `git status` shows **no** changes in `~/.pi/agent` (no `trust.json`, no new
      session files, no touched settings)
- [ ] No `sh -c` / `Process` with a shell anywhere in the diff
- [ ] New RPC field names verified against Pi's `docs/rpc.md`
- [ ] Any new capability gap labeled as a compatibility fallback, not hidden
- [ ] This file updated if a decision, gotcha, or next step changed
