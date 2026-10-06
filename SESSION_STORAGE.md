# Session storage

PiCode uses a shared metadata catalog over the native harness stores. The harness
remains responsible for writing transcripts and resuming its own conversations.
There is no second transcript database to synchronize or migrate.

| Harness | Discovery | Resume |
| --- | --- | --- |
| Pi | Existing configured Pi session directory | Native session file |
| Oh My Pi | Agent directory's `sessions` JSONL files | Native session file |
| Claude Code | `CLAUDE_CONFIG_DIR/projects`, default `~/.claude/projects` | Native session ID |
| Codex | `CODEX_HOME/sessions`, default `~/.codex/sessions` | Native thread ID |
| DeepSeek | `DSH_HOME/storages/session_projcache/sessions`, default `~/.dsh` | Currently unavailable through the installed JSON-RPC server |
| OpenCode | Not indexed until a runtime/session adapter exists | Unavailable |

Non-Pi sidebar identities are namespaced by harness. Resume IDs and storage paths
are separate: an opaque thread ID must never be used as a path for deletion.
The sidebar groups sessions by canonical project directory, independent of harness.
Missing harness installations do not hide their saved histories.

PiCode stores only presentation overrides (pins, hidden rows, and titles) in its
own preferences. Native title changes are used for Pi/OMP; other renamed sessions
receive a local title override. Discovery reads bounded head/tail regions of JSONL
files; message counts are therefore estimates for long histories. Claude/Codex
history is loaded when opening a conversation, with text history normalized into
PiCode's display format. This does not reproduce every native tool/event type.

DeepSeek's `session/prompt` calls `agents.create`, not `agents.resume`. Saved
DeepSeek sessions appear in the catalog, but opening one reports this limitation
instead of creating a fresh conversation. Implementing native resume requires a
DeepSeek server protocol extension; adding a local transcript database cannot
solve that runtime limitation. New PiCode DeepSeek sessions use unique IDs.

A rebuildable SQLite metadata/search cache can be added if scanning becomes slow.
It should cache file path, harness, native ID, modification time, and search fields;
native stores should still remain authoritative. Harness profile-specific roots
beyond the environment/default paths need explicit discovery configuration.
