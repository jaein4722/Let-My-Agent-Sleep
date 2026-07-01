# Let My Agent Sleep Adapters

Adapters run after a watched command exits. They never change the command exit code and never delete run artifacts.

## `noop`

Writes `adapter.log` and leaves `resume_prompt.txt` for manual use.

```bash
bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success
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
export LMAS_OPENCODE_PASSWORD=<basic-auth-password>
```

On completion, the watcher posts `resume_prompt.txt` to:

```text
POST /session/:session_id/prompt_async
```

The OpenCode custom tool `.opencode/tools/lmas_start.ts` sets the session id from tool context.

The server URL must be the same OpenCode server that owns the session id. When testing with a non-default port, attach the run to that server and pass the same URL to `lmas_start`:

```bash
opencode serve --hostname 127.0.0.1 --port 45137 --print-logs
opencode run --attach http://127.0.0.1:45137 --dir "$PWD" --format json --agent build \
  'Use lmas_start with command: ./examples/fake_train.sh sleep 60 and server_url: http://127.0.0.1:45137.'
```

An empty `adapter.log` means `curl -fsS` received a successful 2xx response. A 404 means the endpoint exists but the target server does not know that session id.

After completion, prefer checking quick state with:

```bash
bin/lmas.sh status <run_id>
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
