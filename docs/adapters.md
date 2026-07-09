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

The OpenCode plugin also installs a runtime handoff guard. While an `LMAS_HANDOFF v1` is active, reply-expecting prompt injection into the same session is treated as a no-op until `LMAS_COMPLETION_EVENT v1` arrives or the user explicitly asks for status/cancel. This protects the handoff from loop plugins that try to continue a session because a TODO or plan item is still open. `noReply` internal notifications and LMAS completion prompts are not blocked.

The server URL must be the same OpenCode server that owns the session id. When testing with a non-default port, attach the run to that server and pass the same URL to `lmas_start`:

```bash
opencode serve --hostname 127.0.0.1 --port 45137 --print-logs
opencode run --attach http://127.0.0.1:45137 --dir "$PWD" --format json --agent build \
  'Use lmas_start with command: ./examples/fake_train.sh sleep 60 and server_url: http://127.0.0.1:45137.'
```

An `adapter.log` ending in an adapter failure line means injection failed or timed out. A 404 means the endpoint exists but the target server does not know that session id.

After completion, prefer checking quick state with:

```bash
packages/let-my-agent-sleep/bin/lmas.sh status <run_id>
```

Then inspect `stdout.log` and `stderr.log`. `metadata.txt` is intended as secondary context, not the first file to read.

## `codex`

Secondary prototype adapter.

Preferred:

```bash
export LMAS_CODEX_SESSION_ID=<session-id>
```

If `LMAS_CODEX_SESSION_ID` is empty, the adapter uses `CODEX_THREAD_ID` when Codex exposes it. The resolved id is written to `metadata.txt` at job start, so parallel Codex threads resume the thread that launched each LMAS run.

On completion, the watcher runs:

```bash
codex exec resume "$codex_session_id" - < resume_prompt.txt
```

If the session id or `codex` command is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt`.

## `claude`

Secondary prototype adapter.

Preferred:

```bash
export LMAS_CLAUDE_SESSION_ID=<session-id>
```

On completion, the watcher runs:

```bash
claude --resume "$LMAS_CLAUDE_SESSION_ID" -p "$(cat resume_prompt.txt)"
```

If `LMAS_CLAUDE_SESSION_ID` is empty, set `LMAS_CLAUDE_CONTINUE=1` to let the adapter fall back to:

```bash
claude --continue -p "$(cat resume_prompt.txt)"
```

which resumes the most recently used Claude session in the job's `cwd`. If neither is set, or the `claude` command is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt`.

### Verified live-session behavior

Tested directly against real Claude Code sessions (both a bare CLI/tmux session and the actual Desktop app), targeting an explicit, correct session ID with a matching `cwd`:

- The append to the session transcript always succeeds — `claude --resume` reliably attaches the completion turn to the session file with the correct parent, whether the target session is dormant or currently open.
- An already-open, idle interactive session does **not** refresh live. The person watching that window sees nothing new until they restart/reopen it — this matches the `codex` adapter's documented behavior.
- If the user sends the originating session another message before it is restarted, the live process (unaware of the injected turn, since it never re-reads the file) appends its own next turn from the same stale parent, creating a branch in the transcript tree.
- This branching does not lose data and does not require picking a winner: reopening/restarting the session merges all branches by timestamp and displays them in correct chronological order. Restart is therefore a reliable recovery path even after a branch occurs.
- There is currently no known way to make the completion appear in an already-open, un-restarted session in real time. Real-time delivery into a live session (without requiring restart) is an open enhancement, not yet solved.
