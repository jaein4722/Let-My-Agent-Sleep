# Let My Agent Sleep

Let My Agent Sleep is a lightweight handoff protocol for long-running agent jobs.

It lets an agent start training, evaluation, preprocessing, or batch work without staying alive to poll. The agent prints `LMAS_HANDOFF v1`, exits the loop, and a watcher later writes or injects `LMAS_COMPLETION_EVENT v1`.

## Quick Start

```bash
chmod +x bin/lmas.sh examples/fake_train.sh tests/smoke/*.sh codex/let-my-agent-sleep/skills/let-my-agent-sleep/scripts/lmas.sh
bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success
```

Run artifacts are written to `.lmas/runs/<run_id>/`.

Inspect a run:

```bash
bin/lmas.sh status <run_id>
bin/lmas.sh list
```

## Path Policy

LMAS keeps run state workspace-local by default.

- Run metadata and logs: `.lmas/runs/<run_id>/`
- Task artifacts and reproducible helper scripts: `.lmas/artifacts/<task-or-timestamp>/`

Use `/tmp` only when the workspace is not writable or a system temporary path is explicitly requested.

## OpenCode Prototype

OpenCode is the primary target.

Project-local files:

- `.opencode/tools/lmas_start.ts`
- `.opencode/tools/lmas_status.ts`
- `.opencode/skills/let-my-agent-sleep/SKILL.md`

Start OpenCode from this repo and use the `let-my-agent-sleep` skill. For long jobs, the agent should call the `lmas_start` tool instead of the normal bash tool.

Set the server URL if needed:

```bash
export LMAS_OPENCODE_SERVER_URL=http://127.0.0.1:4096
```

The custom tool sets `LMAS_OPENCODE_SESSION_ID` from the OpenCode tool context.

For automatic completion injection, the session must belong to the same OpenCode server URL that Let My Agent Sleep calls. A reliable local test is:

```bash
opencode serve --hostname 127.0.0.1 --port 45137 --print-logs
opencode run --attach http://127.0.0.1:45137 --dir "$PWD" --format json --agent build \
  'Use the let-my-agent-sleep skill. Call lmas_start with command: ./examples/fake_train.sh sleep 60 and server_url: http://127.0.0.1:45137. Stop after LMAS_HANDOFF v1.'
```

After 60 seconds, `adapter.log` should be empty and `completion_event.txt` should exist. A `404` in `adapter.log` usually means the server URL does not own that session id.

On completion, agents should inspect stdout/stderr first and use `lmas_status` for a concise run summary. `metadata.txt` is secondary context.

## npm Package

The distributable package lives in `packages/let-my-agent-sleep` and publishes as `let-my-agent-sleep`.

```bash
npm_config_cache=/private/tmp/lmas-npm-cache npm pack --workspace let-my-agent-sleep --dry-run
node packages/let-my-agent-sleep/bin/lmas-install.js install --agent detected --dry-run --yes
```

When published, users can install with:

```bash
npx let-my-agent-sleep install
```

The installed CLI alias is:

```bash
lmas install
```

The installer detects OpenCode and Codex, lists installed agents first, and can configure either or both.

## Codex Prototype

Codex support is secondary and uses the packaged skill under `codex/let-my-agent-sleep`.

The adapter resumes with:

```bash
codex exec resume "$LMAS_CODEX_SESSION_ID" - < resume_prompt.txt
```

If no session id is set, Let My Agent Sleep still writes `resume_prompt.txt`.

## Smoke Tests

```bash
tests/smoke/test-basic-handoff.sh
tests/smoke/test-success-completion.sh
tests/smoke/test-failed-completion.sh
tests/smoke/test-status-list.sh
tests/smoke/test-installer-dry-run.sh
tests/smoke/test-idempotent-install.sh
tests/smoke/test-opencode-adapter.sh
tests/smoke/test-codex-adapter.sh
```

## Protocol

See `docs/protocol.md` and `docs/adapters.md`.
