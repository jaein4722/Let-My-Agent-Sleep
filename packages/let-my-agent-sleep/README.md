# let-my-agent-sleep

Let My Agent Sleep lets AI agents start long-running jobs, stop waiting, and resume the same session when the job finishes.

Use it for training, evaluation, preprocessing, benchmarks, migrations, or batch jobs that would otherwise make an agent poll logs or repeatedly continue.

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

If OpenCode is running on a non-default server URL, pass that URL when asking the agent to start a job.

## Codex

Codex support is available through the installed Let My Agent Sleep skill.

For automatic resume, the Codex session must be resumable from the environment where the job is running.

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
