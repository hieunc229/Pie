# PiCode

PiCode is a native macOS GUI for [Pi Coding Agent](https://pi.dev/). It keeps Pi as the agent runtime and presents its capabilities in a focused, ChatGPT Codex-inspired desktop interface: projects and sessions in a sidebar, a readable live transcript in the center, and contextual code, diff, terminal, and session details on demand.

This document is the product and implementation specification for the first production version of the app.

> [!IMPORTANT]
> PiCode is a client for Pi, not a fork or reimplementation of Pi. When Pi adds a provider, model, command, event, or session capability to its RPC interface, PiCode should expose it with minimal app-specific logic.

## Product goals

- Make Pi approachable without removing the control that makes the TUI powerful.
- Preserve the behavior and session data of the installed Pi version.
- Make long agent runs easy to read, steer, stop, resume, branch, and review.
- Put file changes and tool activity next to the conversation instead of hiding them in raw logs.
- Feel like a polished native Mac app with familiar keyboard navigation, window behavior, accessibility, and system integrations.
- Keep the interface quiet by default while making advanced Pi features discoverable.

## Non-goals

- Reimplementing Pi's agent loop, provider adapters, model catalog, tool execution, session format, compaction, or extension system.
- Adding built-in plan mode, sub-agents, MCP, to-dos, background shell execution, or mandatory permission prompts. Pi deliberately leaves these to extensions, packages, containers, or external tools.
- Silently changing Pi configuration or editing files under `~/.pi/agent/` behind the user's back.
- Claiming full compatibility with TUI-only extension APIs. RPC-supported extension UI is required; terminal-only custom components need a clearly labeled compatibility fallback.
- Copying OpenAI branding, logos, product names, or pixel-level trade dress. The reference informs information architecture and interaction quality, not identity.

## Design principles

1. **Conversation first.** The current task and its state dominate the window.
2. **Progressive disclosure.** Common controls stay visible; advanced controls live in menus, command search, and the inspector.
3. **Every agent action is legible.** Tool calls, output, errors, retries, compaction, queued messages, and file changes have explicit states.
4. **The UI reflects Pi.** Avoid inventing client state when Pi already provides authoritative state or events.
5. **Safe by clarity.** Show the working directory and trust state before a task starts. Never imply that project trust is a sandbox.
6. **Local first.** Sessions remain in Pi's storage, credentials remain owned by Pi, and the app works without a PiCode account.

## Visual direction

The supplied ChatGPT Codex screenshot establishes the visual hierarchy:

- A dark, restrained window with a persistent project/session sidebar.
- A compact title bar with the current session name and secondary actions.
- A wide transcript column with generous spacing and clear user/assistant separation.
- Collapsible work-duration and activity sections instead of a permanently noisy console.
- File-change cards with additions/deletions and a direct path into review.
- A large, rounded composer floating over the bottom of the transcript with attachment, access/trust, model, thinking, and send/stop controls.

PiCode should also support the system light appearance. Use semantic macOS colors and materials rather than hard-coded screenshot colors. Prefer native controls, SF Symbols, system typography, reduced-motion support, and visible keyboard focus.

### Main window

Use a three-column `NavigationSplitView`:

```text
┌──────────────────┬──────────────────────────────────────┬─────────────────────┐
│ Projects         │ Session title                 Actions│ Inspector           │
│                  ├──────────────────────────────────────┤                     │
│ + New session    │                                      │ Files changed       │
│ Search           │ Transcript                           │ Diff / file preview │
│                  │ - user prompts                       │ Terminal output     │
│ Project A        │ - assistant streaming                │ Session tree        │
│   Session 1      │ - tool and status cards              │ Context & usage     │
│   Session 2      │ - errors and extension UI            │                     │
│ Project B        │                                      │                     │
│                  ├──────────────────────────────────────┤                     │
│ Settings         │ ╭─ composer floats over transcript ─╮ │                     │
└──────────────────┴──────────────────────────────────────┴─────────────────────┘
```

The composer floats over the transcript: rows scroll behind it and fade under the box, and nothing is drawn below it. The inspector is optional and closed by default on smaller windows. The transcript must remain usable when both sidebars are hidden.

### Sidebar

- **New session** opens a native folder picker, then creates a Pi RPC process with that folder as its working directory.
- Group sessions by canonical working directory, using the project folder name as the group title.
- Sort sessions by most recently active; allow pinning without changing Pi's session files.
- Show session name, activity state, and a subtle relative timestamp.
- Support search across project names, session names, and locally indexed prompt/response text.
- Context menu: rename, reveal session file, duplicate current branch, export, and remove from PiCode's recent list.
- Deleting a Pi session file must be a separate, explicit destructive action with confirmation. Removing a sidebar item is not deletion.
- The bottom area provides Settings, Pi version/update state, and diagnostics.

### Session header

- Editable session name.
- Canonical working directory with Reveal in Finder and Copy Path actions.
- Overflow menu for new, resume/switch, clone, fork, compact, export, share, reload resources, and session diagnostics.
- Inspector toggle and sidebar toggle.
- Connection/agent state: starting, idle, working, compacting, retrying, stopping, disconnected, or failed.

### Transcript

Render a chronological, virtualized conversation from Pi messages and events:

- User prompts use a compact tinted bubble aligned to the trailing edge.
- Assistant text uses full-width Markdown with selectable text, tables, lists, links, and syntax-highlighted fenced code.
- Stream text in place without changing scroll position when the user has scrolled upward.
- Tool calls appear as collapsible cards with tool name, concise input summary, duration, status, and expandable raw input/output.
- Bash output uses a monospaced, selectable log view with ANSI color support and a maximum collapsed height.
- File writes/edits use change cards showing path and available line counts. Selecting a card opens the inspector diff.
- Thinking/reasoning content is collapsed and labeled according to what the provider actually exposes. Never fabricate hidden reasoning.
- Retries, compaction, summaries, extension errors, and cancellation appear as lightweight system rows.
- A running task has a compact elapsed-time disclosure that expands to the activity timeline.
- Each completed assistant message supports copy and branch/fork actions. Feedback controls are optional and local-only unless a backend is deliberately added later.
- Provide a jump-to-latest button when new content arrives off-screen.

### Composer

- Multiline editor that grows to two lines and then scrolls, so the composer stays a small object floating over the transcript.
- `Return` sends; `Shift+Return` inserts a newline. Allow the mapping to be changed in Settings.
- `@` opens fuzzy file search for the current project and inserts file attachments/references.
- `/` opens command completion populated by Pi's `get_commands`, including extension commands, prompt templates, and `/skill:*` commands.
- Attachment button supports images and text files using the system file picker, drag and drop, and paste.
- Model picker is populated by `get_available_models`; never ship a hard-coded catalog.
- Thinking picker exposes only levels supported by the current model.
- While idle, the primary action sends a prompt. While working, it becomes Stop.
- While working, `Return` steers the running turn and `Option+Return` queues a follow-up; both are also reachable from the Agent menu. Queued messages appear at the end of the transcript as their own rows, and Stop clears the queue, puts it back in the editor, and then aborts — `Command+.` is the hard stop that leaves the queue to Pi.
- The box is the only filled shape in the composer: attachment, access/trust, model, thinking, and send/stop share one compact row under the editor, so the composer is two lines plus that row — measured, 76pt tall.
- The composer floats over the transcript rather than sitting under it: nothing is rendered below it, and the transcript keeps the full height behind it, fading out beneath the box. Live session state that used to be repeated in a footer is in the transcript's own system rows; everything else (model, thinking, context usage, tool counts, git branch, extension status) is in the inspector's Context pane.
- Show the current project trust/access state beside the attachment control. Its popover must explain that Pi runs with the permissions of the current macOS user.
- Drafts are stored by session in PiCode app storage, never injected into the Pi session until sent.

### Inspector

Use tabs or a segmented control for:

- **Changes** — git working-tree summary and unified diff for the active project. This is a presentation feature; Pi remains responsible for agent edits.
- **Files** — searchable project tree and read-only preview, with Open in Editor and Reveal in Finder.
- **Terminal** — structured bash/tool output for the session, not an unrelated background shell.
- **Tree** — Pi's append-only session tree, current branch, labels/bookmarks when present, pre-compaction history, and abandoned branches.
- **Context** — model, thinking level, token/cache usage, reported cost, context utilization, session ID/file, loaded resources, and available commands.

## Pi feature parity

The current parity baseline follows Pi's official documentation as of 2026-09-14. “Supported” means the GUI exposes the behavior without changing its semantics.

| Pi capability | PiCode experience | Priority |
| --- | --- | --- |
| Streaming agent loop | Live assistant text, tool cards, statuses, and errors | P0 |
| `read`, `write`, `edit`, `bash` and optional built-in tools | Structured tool activity and expandable results | P0 |
| Images and file references | Paste, drag/drop, picker, and `@` file search | P0 |
| Multiple providers and hundreds of models | Runtime model picker backed by Pi | P0 |
| OAuth/subscription and API-key authentication | Native setup guidance that launches Pi's supported login flow; credentials remain Pi-owned | P0 |
| Model switching and thinking levels | Header/composer pickers using RPC commands | P0 |
| Automatic session persistence | Project-grouped recent sessions and resume/switch | P0 |
| Named and ephemeral sessions | New-session options and editable title | P0 |
| Abort | Stop action with correct queue handling | P0 |
| Steering and follow-up queues | Explicit delivery choice, queue chips, edit/clear | P0 |
| Automatic and manual compaction | Context meter, compact action, progress and result summary | P0 |
| Automatic retry | Retry status, countdown when available, and cancel retry | P0 |
| Session tree, fork, and clone | Tree inspector and branch actions | P1 |
| HTML/JSONL export and session import | Share/export/import menu flows | P1 |
| Skills and prompt templates | Searchable slash-command completion | P0 |
| TypeScript extensions and extension commands | Discover through Pi and invoke through prompts | P0 |
| RPC extension dialogs | Native select, confirm, input, and multiline editor sheets | P0 |
| Extension notifications/status/widgets/title/editor text | Native banners, inspector status and widgets, title, and draft updates | P1 |
| Pi packages from npm, git, or local paths | Package manager UI with source and full-access warning | P1 |
| Themes | PiCode light/dark/system appearance; document that TUI theme rendering is not transferable over RPC | P2 |
| Custom providers and models | Reflect whatever the Pi runtime reports | P0 |
| `AGENTS.md`, `CLAUDE.md`, `SYSTEM.md`, and appended system prompts | Show loaded context/resources and reload action | P1 |
| Project trust | First-run trust decision and persistent trust status | P0 |
| Print/JSON modes | Not duplicated in the primary GUI; available through Pi itself | N/A |
| SDK mode | Not used by the Swift client | N/A |

### Compatibility boundary

Pi RPC supports extension dialogs (`select`, `confirm`, `input`, and `editor`) and fire-and-forget UI requests such as notifications, status, widgets, title, and editor text. Implement these before calling extension support complete.

Some extension APIs require direct TUI access and are degraded or unavailable in RPC mode, including arbitrary `custom()` components, TUI header/footer replacement, custom editor components, tool-expansion state, and TUI theme control. PiCode must:

1. Continue the session without crashing.
2. Explain the unsupported TUI-only surface in an extension compatibility card.
3. Offer **Open in Terminal** to resume the same session with Pi when practical.
4. Never claim that an ignored RPC no-op was displayed successfully.

## Key user flows

### First launch

1. Locate `pi` in the user's login shell environment and show the detected path and version.
2. If Pi is missing, provide copyable installation instructions from the current Pi quickstart. Do not install it silently.
3. Let the user choose a project folder.
4. Evaluate project trust before loading project-local settings, packages, extensions, skills, prompts, themes, or system-prompt files.
5. Start `pi --mode rpc` in that working directory.
6. If no model/authentication is available, guide the user through a supported Pi login or API-key setup without storing secrets in SwiftData or logs.
7. Create the first session and focus the composer.

### Start or resume work

1. Select a project and an existing session, or choose New session.
2. Spawn one isolated Pi RPC process per active session.
3. Fetch state, messages, entries, available models, and commands.
4. Reconcile the transcript before accepting input.
5. Preserve a per-session draft and scroll position when switching sessions.

### Send, steer, follow up, and stop

- Idle send uses `prompt` with optional image payloads.
- A send while streaming must explicitly use steering or follow-up behavior.
- Stop first clears queued messages, restores them to the draft area, then aborts. This mirrors Pi's interactive Escape behavior and prevents queued work from unexpectedly continuing.
- UI state changes only after the correlated RPC response or authoritative event arrives.

### Review changes

1. Detect changed files in the session's working directory using read-only git commands.
2. Group transcript change cards by assistant turn.
3. Open the unified diff in the inspector when a card is selected.
4. Support copy, open in editor, and reveal in Finder.
5. Any future discard/revert action must be explicit, scoped to selected hunks/files, and confirmed.

### Branch history

- Use Pi entry IDs as durable cursors.
- The Tree inspector visualizes parent/child relationships and identifies the current leaf.
- Fork starts a new session from a selected prior user message.
- Clone duplicates the active branch into a new session.
- Abandoned branches remain discoverable; PiCode must not flatten the tree into a linear chat history.

## Architecture

### Runtime boundary

The Swift app launches the user's installed Pi executable as a child process:

```text
SwiftUI views
    ↕ observable view models
PiCode domain services
    ↕ typed async commands/events
Pi RPC client
    ↕ stdin/stdout JSONL
pi --mode rpc
    ↕
providers · agent loop · tools · sessions · extensions
```

Use `Foundation.Process` with pipes for stdin, stdout, and stderr. Set the process current directory to the selected project. Never invoke through `sh -c`; pass executable and arguments directly.

RPC records are strict JSONL delimited by LF. The stream decoder must:

- Decode incrementally as UTF-8 across arbitrary byte boundaries.
- Split only on `\n`, optionally removing a trailing `\r`.
- Preserve Unicode line and paragraph separators inside JSON strings.
- Correlate command responses by request ID.
- Route unsolicited events independently of responses.
- Treat stderr as diagnostics, not protocol data.
- Enforce one writer/serialization actor for stdin.
- Survive unknown event fields and surface unknown event types in diagnostics.

### Suggested modules

Keep views, behavior, and data contracts separated. Functions should live in focused service/helper files and shared type definitions in dedicated model files.

```text
PiCode/
├── App/
│   ├── PiCodeApp.swift
│   └── AppState.swift
├── Models/
│   ├── Project.swift
│   ├── Session.swift
│   ├── TranscriptItem.swift
│   └── RPCModels.swift
├── Services/
│   ├── PiDiscoveryService.swift
│   ├── PiProcess.swift
│   ├── PiRPCClient.swift
│   ├── JSONLDecoder.swift
│   ├── SessionIndex.swift
│   ├── ProjectTrustService.swift
│   ├── GitStatusService.swift
│   └── DraftStore.swift
├── Features/
│   ├── Sidebar/
│   ├── Conversation/
│   ├── Composer/
│   ├── Inspector/
│   ├── SessionTree/
│   ├── Extensions/
│   ├── Packages/
│   └── Settings/
└── Shared/
    ├── Components/
    ├── Markdown/
    └── Utilities/
```

Use actors for process and stream ownership. Deliver observable UI state on `@MainActor`. Keep raw RPC models separate from presentation models so protocol changes do not ripple through every view.

### State ownership

- **Pi owns:** messages, agent state, model selection, thinking level, queues, compaction, retries, session tree, session persistence, commands, extension behavior, and authentication.
- **PiCode owns:** project recents, pins, window layout, inspector selection, local search index, drafts, transcript scroll position, and UI preferences.
- **Git owns:** repository status and diffs.
- **Keychain/Pi owns secrets:** PiCode must not mirror API keys or OAuth tokens into its own database.

SwiftData may store PiCode-owned metadata keyed by canonical project path and Pi session ID. It must not duplicate whole Pi JSONL sessions as a competing source of truth.

### Process lifecycle

- Starting a session creates one process supervisor and one RPC client.
- Switching away may keep a working process alive; idle processes can be suspended by policy after saving UI state.
- Window close must not abruptly orphan a child process. If work is active, explain whether closing will stop it.
- Unexpected exit produces a recoverable disconnected state with stderr diagnostics and Restart/Open in Terminal actions.
- On restart, request current state and entries after the last durable entry ID before rendering the session as synchronized.
- Multiple windows must not write to the same session from separate Pi processes.

## Security and privacy

Pi runs locally with the permissions of the user account that launched it. Project trust controls whether project-local configuration and executable extensions are loaded; it is not a sandbox and does not constrain ordinary model tool calls.

- Always display the canonical working directory before a new session starts.
- Reproduce Pi's trust semantics instead of inventing a broader promise.
- Do not auto-trust projects. Persist decisions only through Pi's supported trust mechanism.
- Warn that Pi packages and extensions can execute arbitrary code with full user access. Show source, scope, and version before installation.
- Avoid logging prompts, tool outputs, environment variables, credentials, or complete RPC payloads by default.
- Redact likely secrets from diagnostics exports and let the user preview the export.
- Do not send telemetry, crash transcripts, or session data without a separate opt-in.
- Clearly label `/share` as an upload to a private GitHub gist and require an explicit user action.
- Recommend a container or another OS-level isolation method for untrusted or unmonitored work.

## Native macOS behavior

- SwiftUI-first, with AppKit bridges only where SwiftUI does not provide production-quality text editing, code selection, diff rendering, or window control.
- Standard menu commands for New Session, Open Project, Search, Send, Stop, Toggle Sidebar, Toggle Inspector, and Settings.
- Command palette accessible from the keyboard, combining Pi commands and PiCode navigation actions with distinct labels.
- Multiwindow support, with a guard against opening the same Pi session for writing twice.
- Restore window size, column visibility, selected project/session, and unsent drafts.
- Support system appearance, Increase/Decrease Text Size, high contrast, Reduce Motion, and Reduce Transparency.
- Full keyboard navigation and VoiceOver labels for every icon-only control, status change, tool card, queue item, and diff annotation.
- Use notifications only for user-enabled completion or attention events.

## Performance requirements

- Launch to usable sidebar in under one second on a warm start, independent of Pi process startup.
- Keep scrolling smooth with at least 10,000 transcript items by using lazy/virtualized rendering.
- Coalesce streaming deltas to UI-friendly updates without delaying visible output noticeably.
- Parse RPC off the main actor.
- Load large tool outputs, files, and diffs lazily with truncation plus an explicit Show All action.
- Incrementally index session text and project files; never block the composer on indexing.
- Apply backpressure to logs and cap retained in-memory raw event history.

## Error states

Every failure should state what failed, what remains safe, and the next action:

- Pi executable not found or incompatible.
- No provider credentials or no available model.
- Project not trusted.
- RPC startup, framing, decode, timeout, or unsupported-command error.
- Provider authentication, rate limit, overload, or network failure.
- Tool failure or extension error.
- Session file missing, unreadable, moved, or already open for writing.
- Project folder moved or access revoked.
- Extension UI request unsupported by RPC.

Errors tied to a turn stay in the transcript; app/runtime errors use a persistent banner and diagnostics panel. Never discard a draft because sending failed.

## Delivery plan

### Phase 1 — usable agent client

- Replace the starter SwiftData item UI with the main split-view shell.
- Discover the Pi executable and launch `pi --mode rpc`.
- Implement strict JSONL framing, typed responses/events, and reconnection diagnostics.
- New project/session, session resume/switch, transcript streaming, Markdown, tool cards, model/thinking pickers, attachments, send, stop, steer, follow-up, and queue restoration.
- First-run/trust/authentication guidance.

### Phase 2 — review and history

- Project/session sidebar persistence and search.
- Change cards, git diff inspector, file preview, and terminal output.
- Session tree, fork, clone, compaction controls, usage/cost context, import, and export.
- Native extension UI request handling and command palette.

### Phase 3 — customization and polish

- Pi package management with full-access warnings.
- Loaded resource inspection and reload.
- Multiwindow lifecycle, large-session optimization, accessibility audit, notification preferences, and diagnostics export.
- Open-in-Terminal compatibility handoff for TUI-only extensions.

## Definition of done

The first production release is complete when:

- A user with Pi installed can choose a folder, resolve trust/authentication, start a session, send a prompt, watch streaming output and tool execution, attach a file/image, steer or queue a follow-up, stop safely, and resume the same session after relaunch.
- Model and thinking controls reflect the connected Pi runtime rather than a bundled list.
- The transcript remains synchronized through tool calls, retries, errors, compaction, and process restart.
- Session names, trees, forks, clones, imports, and exports preserve Pi semantics and files.
- RPC-supported extension dialogs work as native sheets and unsupported TUI-only surfaces fail visibly and safely.
- The user can inspect changed files and diffs without PiCode modifying them.
- PiCode never stores provider secrets or represents project trust as sandboxing.
- The app is fully usable from the keyboard and with VoiceOver in light and dark appearances.

## Source of truth

The implementation should be checked against the installed Pi version and the latest official documentation, especially when RPC types change:

- [Pi overview](https://pi.dev/)
- [Pi documentation](https://pi.dev/docs/latest)
- [Using Pi](https://pi.dev/docs/latest/usage)
- [RPC mode](https://pi.dev/docs/latest/rpc)
- [Sessions](https://pi.dev/docs/latest/sessions)
- [Providers](https://pi.dev/docs/latest/providers)
- [Extensions](https://pi.dev/docs/latest/extensions)
- [Pi packages](https://pi.dev/docs/latest/packages)
- [Security](https://pi.dev/docs/latest/security)
- [Official OpenAI Codex use cases](https://learn.chatgpt.com/use-cases)

The attached ChatGPT Codex screenshot is the design reference for this repository. It is inspiration for layout and interaction only; Pi's documentation and runtime are authoritative for functionality.
