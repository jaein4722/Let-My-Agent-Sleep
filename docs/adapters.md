# Let My Agent Sleep Adapters

Adapters run after a watched command exits. They never change the command exit code and never delete run artifacts.

## `noop`

Writes `adapter.log` and leaves `resume_prompt.txt` for manual use.

```bash
packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success
```

## `opencode`

Primary prototype adapter.

Required:

```bash
export LMAS_OPENCODE_SESSION_ID=<session-id>
```

Optional:

```bash
export LMAS_OPENCODE_SERVER_URL=http://127.0.0.1:4096
export LMAS_OPENCODE_USERNAME=opencode
export LMAS_OPENCODE_PASSWORD=<basic-auth-password>
export LMAS_HTTP_CONNECT_TIMEOUT=5
export LMAS_HTTP_MAX_TIME=30
```

If `LMAS_OPENCODE_USERNAME` is not set, LMAS uses `OPENCODE_SERVER_USERNAME` or `opencode`.
If `LMAS_OPENCODE_PASSWORD` is not set, LMAS uses `OPENCODE_SERVER_PASSWORD` when present.
OpenCode HTTP injection is bounded by `LMAS_HTTP_CONNECT_TIMEOUT` and `LMAS_HTTP_MAX_TIME`. Timeout failures are recorded in `adapter.log`, and `completion_event.txt` plus `resume_prompt.txt` remain available for recovery.

On completion, the watcher posts `resume_prompt.txt` to:

```text
POST /session/:session_id/prompt_async
```

The OpenCode npm plugin provides `lmas_start`, `lmas_status`, `lmas_cancel`, and diagnostic `lmas_info`. `lmas_start` sets the session id from the OpenCode tool context.

The OpenCode plugin also installs a runtime handoff guard. While an `LMAS_HANDOFF v1` is active, reply-expecting prompt injection into the same session is treated as a no-op until `LMAS_COMPLETION_EVENT v1` arrives. A direct user request authorizes one exact-run status or cancel action without ending the handoff. This protects the handoff from loop plugins that try to continue a session because a TODO or plan item is still open. `noReply` internal notifications and LMAS completion prompts are not blocked. LMAS does not install OpenCode compaction hooks; compaction and continuation remain owned by OpenCode and other plugins, while LMAS blocks only live reply-expecting prompts for active handoffs.

The OpenCode TUI sidebar can show the current session guard state and active/finalizing LMAS runs when OpenCode loads the LMAS TUI entity. The same state is available from `lmas_info` for live doctor checks.

The server URL must be the same OpenCode server that owns the session id. The plugin uses its current OpenCode server URL automatically. For direct CLI fallback on a non-default port, export the same URL before attaching:

```bash
opencode serve --hostname 127.0.0.1 --port 45137 --print-logs
export LMAS_OPENCODE_SERVER_URL=http://127.0.0.1:45137
opencode run --attach http://127.0.0.1:45137 --dir "$PWD" --format json --agent build \
  'Use lmas_start with command: ./examples/fake_train.sh sleep 60.'
```

An `adapter.log` ending in an adapter failure line means injection failed or timed out. A 404 means the endpoint exists but the target server does not know that session id.

After completion, prefer checking quick state with:

```bash
packages/let-my-agent-sleep/bin/lmas.sh status <run_id>
```

Then inspect `stdout.log` and `stderr.log`. `metadata.txt` is intended as secondary context, not the first file to read.

## `codex`

Secondary prototype adapter.

The adapter captures the `CODEX_THREAD_ID` supplied by Codex and writes it to `metadata.txt` at job start, so parallel Codex threads resume the thread that launched each LMAS run. No manual session-id environment variable is required.

On completion, the watcher runs:

```bash
${LMAS_CODEX_BIN:-codex} exec resume --skip-git-repo-check "$codex_session_id" - < resume_prompt.txt
```

`LMAS_CODEX_BIN` can point to a working Codex executable when the first `codex` on `PATH` is missing or broken. If the session id or executable is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt`.

### Verified active-session boundary

Direct tests with the bundled Codex CLI and a Codex Desktop-created task established two separate facts:

- `codex exec resume` appends the external completion turn to the same persisted thread. Codex Desktop's thread reader can display that turn.
- An app-server or CLI TUI that was already running does not add the external turn to its in-memory model-visible context. In the Desktop test, the persisted thread displayed `APP_EXTERNAL_942`, but the next Desktop turn could only recall the pre-injection tokens. The same stale-context continuation was reproduced in the CLI TUI.

Do not send another message from a Codex view that stayed open across external completion. Reload or reopen the task first. A fresh resume reads the persisted completion history correctly. Showing the external turn in the UI is not evidence that the already-running model context was rebased.

## `claude`

Secondary prototype adapter.

The adapter captures the `CLAUDE_CODE_SESSION_ID` supplied by Claude Code and writes it to `metadata.txt` at job start. No manual session-id environment variable is required.

On completion, the watcher runs:

```bash
claude --resume "$claude_session_id" -p "$(cat resume_prompt.txt)"
```

If Claude Code does not supply a session ID, set `LMAS_CLAUDE_CONTINUE=1` to let the adapter fall back to:

```bash
claude --continue -p "$(cat resume_prompt.txt)"
```

which resumes the most recently used Claude session in the job's `cwd`. If neither is set, or the `claude` command is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt`.

### Verified live-session behavior

The following are observations from a limited set of real Claude Code sessions (a bare CLI/tmux session and the Desktop app) using a matching session ID and `cwd`; they are not an upstream compatibility guarantee:

- In those tests, `claude --resume` appended the completion turn to the session transcript whether the target session was dormant or currently open.
- An already-open, idle interactive session does **not** refresh live. The person watching that window sees nothing new until they restart/reopen it — this matches the `codex` adapter's documented behavior.
- If the user sends the originating session another message before it is restarted, the live process (unaware of the injected turn, since it never re-reads the file) appends its own next turn from the same stale parent, creating a branch in the transcript tree.
- In the tested versions, reopening/restarting displayed both branches by timestamp. Treat `resume_prompt.txt` as the durable recovery artifact if a future Claude Code version behaves differently.
- There is currently no known way to make the completion appear in an already-open, un-restarted session in real time. Real-time delivery into a live session (without requiring restart) is an open enhancement, not yet solved.
