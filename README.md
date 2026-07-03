# Let My Agent Sleep

Let My Agent Sleep lets AI agents start long-running jobs, stop waiting, and resume the same session when the job finishes.

Use it for training, evaluation, preprocessing, benchmarks, migrations, or batch jobs that would otherwise make an agent poll logs or repeatedly continue.

[Website](https://jaein4722.github.io/Let-My-Agent-Sleep/) · [Docs](https://jaein4722.github.io/Let-My-Agent-Sleep/docs/) · [npm](https://www.npmjs.com/package/let-my-agent-sleep)

## Requirements

`tmux` must be installed and available on `PATH`.

## Install

```bash
npx let-my-agent-sleep install
```

The short CLI alias is:

```bash
lmas install
```

To install for a specific agent:

```bash
npx let-my-agent-sleep install --agent opencode
npx let-my-agent-sleep install --agent codex
npx let-my-agent-sleep install --agent claude  # experimental
npx let-my-agent-sleep install --agent detected --yes
npx let-my-agent-sleep install --agent all --yes
```

Use `--dry-run` to preview changes before writing files.

## Usage

Restart your agent after installation, then ask it to use Let My Agent Sleep for long-running work.

Example:

```text
Use the let-my-agent-sleep skill for this task. Start the training job with:
python train.py --config configs/exp.yaml
After LMAS_HANDOFF v1, stop and do not wait or poll.
```

The agent should start the job, report a `run_id`, and stop. When the job finishes, Let My Agent Sleep injects an `LMAS_COMPLETION_EVENT v1` message so the agent can inspect logs, summarize results, and continue.

## OpenCode

OpenCode is the primary target. The installer adds the Let My Agent Sleep plugin and skill, including:

- `lmas_start`
- `lmas_status`
- `lmas_cancel`

If OpenCode is running on a non-default server URL, pass that URL when asking the agent to start a job.

Use `lmas_cancel` for explicit user-requested cancellation. It records a `CANCELLED` completion event when the LMAS watcher is still alive. If a job was killed outside LMAS and the watcher is gone, `lmas_status` reports `LOST` instead.

OpenCode docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/opencode.html

## Codex

Codex support is available through the installed Let My Agent Sleep skill.

For automatic resume, the Codex session must be resumable from the environment where the job is running.

Codex docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/codex.html

## Claude Code

Claude Code support is experimental. It is available through the installed Let My Agent Sleep skill, but automatic resume behavior is not guaranteed across every Claude Code frontend or remote session setup.

For exact automatic resume, set `LMAS_CLAUDE_SESSION_ID` before starting the job. Without it, Let My Agent Sleep leaves `resume_prompt.txt` as a manual fallback. Set `LMAS_CLAUDE_CONTINUE=1` only when continuing the most recent Claude session in the current working directory is acceptable.

Claude Code docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/claude-code.html

## Why Not nohup?

`nohup` keeps a process alive. Let My Agent Sleep also gives the agent a clean handoff point, records run metadata, watches for process exit, and injects a completion event so the same session can continue.

More detail: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/why-not-nohup.html

## Runtime Artifacts

Runs are stored under:

```text
.lmas/runs/<run_id>/
```

Common files:

- `handoff.txt`
- `completion_event.txt`
- `stdout.log`
- `stderr.log`
- `metadata.txt`
- `resume_prompt.txt`

Check a run manually:

```bash
lmas status <run_id>
lmas list
```

Do not place secrets in command-line arguments or metadata. Keep `.lmas/` ignored by git.
