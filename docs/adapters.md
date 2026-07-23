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

On completion, the watcher first connects to Codex's same-user app-server Unix socket and asks that active thread owner to start a turn with `resume_prompt.txt`. A CLI TUI attached to the server receives the prompt and response immediately. The watcher then tries the active Codex Desktop IPC owner as a secondary live route.

For remote/SSH use, the live path needs no LMAS-installed daemon, wrapper, or alternate binary. Start and supervise Codex's own built-in server exactly as you would an OpenCode server, then attach the TUI:

```bash
codex app-server --listen unix://
codex --remote unix://
```

Both commands use `$CODEX_HOME/app-server-control/app-server-control.sock` by default. LMAS only discovers and connects to that same-user socket; it never installs, bootstraps, or starts the app server. If the server must outlive an SSH connection, keep the first command in the host's existing tmux/systemd process setup.

The result is handled as follows:

- App-server or Desktop owner acknowledgment: live wake succeeded, so no CLI fallback or reload warning is added.
- Missing socket, incompatible owner, or another definite non-delivery result: run the existing fallback.
- Timeout, disconnect, or another ambiguous result after dispatch: retain `resume_prompt.txt` and suppress the fallback to avoid a duplicate completion turn.

The separate-process fallback remains:

```bash
${LMAS_CODEX_BIN:-codex} exec resume --skip-git-repo-check "$codex_session_id" - < resume_prompt.txt
```

Set `LMAS_CODEX_LIVE_WAKE=0` to skip all live attempts, or `LMAS_CODEX_APP_SERVER_WAKE=0` to skip only the app-server socket. `LMAS_CODEX_APP_SERVER_SOCKET` overrides the default Unix socket for an explicitly configured server. `LMAS_CODEX_BIN` can point to a working Codex executable when the first `codex` on `PATH` is missing or broken. If the session id or fallback executable is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt`.

### Verified active-session boundary

Direct tests with the bundled Codex CLI established three separate facts:

- `codex exec resume` appends the external completion turn to the same persisted thread. Codex Desktop's thread reader can display that turn.
- An app-server or CLI TUI that was already running does not add the external turn to its in-memory model-visible context. In the Desktop test, the persisted thread displayed `APP_EXTERNAL_942`, but the next Desktop turn could only recall the pre-injection tokens. The same stale-context continuation was reproduced in the CLI TUI.
- When the TUI is attached to a shared Codex app server with `codex --remote unix://`, an external `turn/start` is rendered in that already-running TUI and enters the owner's live model context without a restart.

This stale-context boundary applies to the `codex exec resume` fallback. When `adapter.log` says `codex live wake succeeded`, the active app-server or Desktop owner itself started the turn and does not need to be reloaded. When the fallback was used, do not send another message from a Codex view that stayed open across completion; reload or reopen the task first. A fresh resume reads the persisted completion history correctly. Showing the external turn in the UI is not evidence that an external-process fallback rebased the already-running model context.

## `claude`

Experimental adapter.

The adapter captures the `CLAUDE_CODE_SESSION_ID` supplied by Claude Code and writes it to `metadata.txt` at job start. The installed Claude command uses two steps:

```bash
lmas.sh start --adapter claude -- <command...>
# After LMAS_HANDOFF v1, launch this with Bash run_in_background: true:
lmas.sh await <run_id>
```

The first command hands the real job to LMAS and tmux. The second command is a lightweight receiver owned by Claude's native background-task harness; it waits without LLM polling and never owns, kills, or supervises the real command. When the completion event appears, `await` atomically claims native delivery, emits `LMAS_COMPLETION_EVENT v1`, and exits successfully regardless of whether the job status is `SUCCEEDED`, `FAILED`, or `CANCELLED`. Claude's task notification then wakes the same live session. Read the notification's `<output-file>` directly because a completed task may no longer be available through `TaskOutput`.

If Claude exits, the tmux job continues. Its background Bash child may terminate with Claude or briefly survive as an orphan, so the ready marker records both the waiter and the exact owning Claude process, including process start identities to reject PID reuse. At completion, LMAS waits briefly for a native claim. It runs the separate-process fallback only when the waiter was never registered, the waiter is dead, or that recorded Claude owner is dead:

```bash
claude --resume "$claude_session_id" -p "$(cat resume_prompt.txt)"
```

If Claude Code does not supply a session ID, set `LMAS_CLAUDE_CONTINUE=1` to let the adapter fall back to:

```bash
claude --continue -p "$(cat resume_prompt.txt)"
```

which resumes the most recently used Claude session in the job's `cwd`. If neither is set, or the `claude` command is missing, the adapter writes the reason to `adapter.log` and leaves `resume_prompt.txt` without claiming delivery.

Native and fallback paths share one atomic `delivery.claim` directory. A native claim suppresses fallback even if the task notification later becomes ambiguous; Claude exposes no receipt that could distinguish a lost notification from one queued but not yet processed. A native delivery path whose waiter and owner are still live but has not claimed within the grace period is also ambiguous and suppresses fallback. LMAS never treats a timeout, missing model response, or missing acknowledgement as proof of delivery failure. `resume_prompt.txt` remains available in every case.

Set `LMAS_CLAUDE_NATIVE_GRACE_SECONDS` to change how long LMAS waits for the registered native waiter to claim completion before deciding whether fallback is safe. The default is 5 seconds.

### Verified live-session behavior

The following are observations from isolated real Claude Code CLI sessions; they are not an upstream compatibility guarantee:

- A Bash tool command started with `run_in_background: true` kept running across turns and automatically re-invoked the same idle session when it exited.
- An actual LMAS/tmux job completed while `lmas.sh await` was the background task; the task notification woke the same session without user input, and its output file contained the expected completion event.
- The completed task was no longer available through `TaskOutput`, while reading the notification's output-file path recovered the payload correctly.
- If no native waiter can deliver, `claude --resume` remains the durable fallback. That separate process does not provide live synchronization to an already-open interface, so reopening or resuming the session may still be required.
