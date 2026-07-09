<div align="center">
  <img src="https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png" alt="Let My Agent Sleep - stop AI agents polling long-running jobs" width="780" />

  <h1>let-my-agent-sleep</h1>

  <p><strong>Start long jobs. Stop the loop. Resume supported agent sessions when they finish.</strong></p>

  <p>
    <a href="https://www.npmjs.com/package/let-my-agent-sleep"><img alt="npm version" src="https://img.shields.io/npm/v/let-my-agent-sleep.svg"></a>
    <a href="https://www.npmjs.com/package/let-my-agent-sleep"><img alt="npm downloads" src="https://img.shields.io/npm/dw/let-my-agent-sleep.svg"></a>
    <a href="https://github.com/jaein4722/Let-My-Agent-Sleep"><img alt="GitHub stars" src="https://img.shields.io/github/stars/jaein4722/Let-My-Agent-Sleep.svg?style=flat"></a>
    <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/License-MIT-green.svg"></a>
  </p>

  <p>
    <a href="https://jaein4722.github.io/Let-My-Agent-Sleep/"><strong>Website</strong></a>
    ·
    <a href="https://jaein4722.github.io/Let-My-Agent-Sleep/docs/"><strong>Docs</strong></a>
    ·
    <a href="https://www.npmjs.com/package/let-my-agent-sleep"><strong>npm</strong></a>
  </p>
</div>

---

AI agents should not spend hours polling a training log.

Let My Agent Sleep, or LMAS, lets OpenCode, Codex, and Claude Code start long-running training, evaluation, preprocessing, benchmark, migration, or batch jobs, hand them off, stop waiting, and resume a supported agent session when the job finishes. When exact resume is not available, LMAS records a manual resume prompt.

```text
start job -> LMAS_HANDOFF v1 -> agent stops
job exits -> LMAS_COMPLETION_EVENT v1 -> session resumes or prompt is recorded
```

## Contents

- [Why](#why)
- [Demo](#demo)
- [Quick Start](#quick-start)
- [Agent Support](#agent-support)
- [OpenCode](#opencode)
- [Codex](#codex)
- [Claude Code](#claude-code)
- [CLI](#cli)
- [Runtime Artifacts](#runtime-artifacts)
- [Why Not nohup?](#why-not-nohup)
- [Cost Model](#cost-model)
- [FAQ](#faq)

## Why

Without LMAS, a long-running job often turns into an expensive agent loop:

| Without LMAS | With LMAS |
| --- | --- |
| Agent starts a job and keeps checking logs. | Agent starts a job and receives a handoff. |
| Context fills with repeated `tail`, `ps`, and status output. | The session goes quiet while the job runs. |
| Loop runners keep forcing `continue`. | Completion wakes a supported session once. |
| Cost grows with wall-clock wait time. | Cost is handoff plus completion handling. |

LMAS does not make useful agent work free. It removes the waiting portion: polling turns, repeated context reloads, and artificial continue loops.

## Demo

![LMAS handoff demo](https://jaein4722.github.io/Let-My-Agent-Sleep/demo.gif)

The important boundary is the agent turn. LMAS starts the command, records `LMAS_HANDOFF v1`, and the agent stops. When the process exits, LMAS writes `LMAS_COMPLETION_EVENT v1` and resumes a supported session with stdout, stderr, metadata, and artifact paths.

This is different from a plain native background task. Native backgrounding is enough only when it also prevents agent polling, preserves the session handoff, records the recovery prompt, and wakes the same supported session on completion. LMAS standardizes that behavior across OpenCode, Codex, and experimental Claude Code support.

Verified live baseline: real OpenCode runs of 17 hours and 12 hours completed the full handoff -> completion -> session re-entry loop.

## Quick Start

Requirements:

- `tmux` installed and available on `PATH`
- Node.js with `npx` or a global npm install

Install:

```bash
npx let-my-agent-sleep install
```

Or install globally and use the short alias:

```bash
npm install -g let-my-agent-sleep
lmas install
```

Restart your agent after installation.

Then ask the agent to use LMAS for long-running work:

```text
Use the let-my-agent-sleep skill for this task.
Start the training job with:
python train.py --config configs/exp.yaml
After LMAS_HANDOFF v1, stop and do not wait or poll.
```

The agent should start the job, report a `run_id`, and stop. When the job finishes, LMAS injects an `LMAS_COMPLETION_EVENT v1` message so the agent can inspect logs, summarize results, and continue.

## Agent Support

| Agent | Status | Resume path |
| --- | --- | --- |
| OpenCode | Primary | Plugin tools and native completion prompt injection |
| Codex | Supported | Same-session resume from the job environment |
| Claude Code | Experimental | Slash command, resume when possible, manual fallback prompt when needed |

Install for a specific agent:

```bash
npx let-my-agent-sleep install --agent opencode
npx let-my-agent-sleep install --agent codex
npx let-my-agent-sleep install --agent claude  # experimental
npx let-my-agent-sleep install --agent detected --yes
npx let-my-agent-sleep install --agent all --yes
```

Use `--dry-run` to preview changes before writing files.

## OpenCode

OpenCode is the primary target. The installer adds the Let My Agent Sleep plugin and skill, including:

- `lmas_start`
- `lmas_status`
- `lmas_cancel`
- `lmas_info`

If OpenCode is running on a non-default server URL, pass that URL when asking the agent to start a job.

For OpenCode installs, LMAS writes an Oh My OpenAgent config entry that disables known OMO continuation hooks:

```bash
npx let-my-agent-sleep install --agent opencode
```

The disabled hooks are `todo-continuation-enforcer`, `ralph-loop`, `ulw-loop`, `ultrawork`, `start-work-continuation`, `boulder-continuation`, `unstable-agent-babysitter`, and `atlas`.
This keeps those known continuation hooks disabled in the OpenCode environment so they cannot re-enter an active LMAS handoff loop.
Use `--keep-omo-continuation` only if you explicitly want to keep those hooks enabled.

LMAS also installs a runtime guard in the OpenCode plugin. While an `LMAS_HANDOFF v1` is active, reply-expecting prompt injection into that same session is no-oped until `LMAS_COMPLETION_EVENT v1` arrives or the user explicitly asks for status/cancel. `noReply` internal notifications and LMAS completion prompts are allowed through. `lmas_info` is a diagnostic tool used by live doctor checks.

OpenCode docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/opencode.html

## Codex

Codex support is available through the installed Let My Agent Sleep skill.

For automatic resume, the Codex session must be resumable from the environment where the job is running.

Codex docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/codex.html

## Claude Code

Claude Code support is experimental. It is available through the installed `/let-my-agent-sleep` command, but automatic resume behavior is not guaranteed across every Claude Code frontend or remote session setup.

For exact automatic resume, set `LMAS_CLAUDE_SESSION_ID` before starting the job. Without it, LMAS leaves `resume_prompt.txt` as a manual fallback. Set `LMAS_CLAUDE_CONTINUE=1` only when continuing the most recent Claude session in the current working directory is acceptable.

Claude Code docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/claude-code.html

## CLI

```bash
lmas start -- python train.py --config configs/exp.yaml
lmas status <run_id>
lmas list
lmas cancel <run_id>
lmas start --notify https://ntfy.sh/my-topic -- python train.py
lmas doctor --agent opencode
lmas doctor --agent opencode --server-url http://127.0.0.1:4096
lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --directory "$PWD"
LMAS_OPENCODE_PASSWORD=<password> lmas doctor --agent opencode --server-url http://127.0.0.1:4096
```

Most users should let the agent call the installed skill or plugin tool instead of calling the CLI directly. The CLI is still useful for debugging, manual runs, and fallback workflows.

`--notify <url>` posts the completion resume prompt to a secondary webhook or ntfy URL after the job exits. It does not replace session resume; it is only an extra notification path. If the URL contains a secret, prefer environment injection and do not put it in prompts or shared logs.

HTTP completion paths are bounded: OpenCode adapter calls and `--notify` use `LMAS_HTTP_CONNECT_TIMEOUT` (default `5` seconds) and `LMAS_HTTP_MAX_TIME` (default `30` seconds). A timeout leaves `resume_prompt.txt` available for manual recovery.

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
- `notify.log` (only when `--notify` or `LMAS_NOTIFY_URL` is set)
- `progress.txt` (optional, written by your job)

Keep `.lmas/` ignored by git. Do not place secrets in command-line arguments or metadata.

`lmas list` includes `elapsed_seconds` and a short command summary. `lmas status <run_id>` includes the command, elapsed time, and the last line of `progress.txt` when that file exists. `FINALIZING` means the process has exited and LMAS is preparing `resume_prompt.txt` plus `completion_event.txt`; it is still a stop-and-wait state, not permission to poll. Status checks are for explicit user requests only; agents must still stop after `LMAS_HANDOFF v1` and must not poll.

## Why Not nohup?

`nohup` keeps a process alive. LMAS also gives the agent a clean handoff point, records run metadata, watches for process exit, and injects a completion event so a supported session can continue.

More detail: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/why-not-nohup.html

## Cost Model

In one observed OpenCode loop, repeated status checks cost about `$2.72` over `10.2 minutes`. Projected over a 24-hour wait, that is about `$382` and `1.93B` tokens.

LMAS does not make completion free. The start handoff and wake-up prompt still cost tokens. The saving is that the waiting interval no longer produces polling turns.

Cost method: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/cost.html

## FAQ

### Does LMAS require changing my training code?

No. LMAS wraps the command the agent was already going to run.

### Does it require a daemon?

No. LMAS uses `tmux` and plain files. There is no database, cloud scheduler, or project-specific callback.

### What happens if a job fails?

The completion event includes `status`, `exit_code`, `stdout`, `stderr`, `metadata`, and `artifacts_dir`. The agent can inspect the failure and decide the next step.

### What happens if I cancel a run?

Use `lmas_cancel` from the agent or `lmas cancel <run_id>` from the CLI. If the watcher is still alive, LMAS records a `CANCELLED` completion event. If the job has already exited and LMAS is finalizing completion, cancel reports `ALREADY_COMPLETED`. If a job is killed outside LMAS and the watcher is gone, `lmas_status` reports `LOST`.

When the run was started with `--notify` or `LMAS_NOTIFY_URL`, cancellation also posts the `CANCELLED` resume prompt to that secondary notification URL.

## Links

- Website: https://jaein4722.github.io/Let-My-Agent-Sleep/
- Docs: https://jaein4722.github.io/Let-My-Agent-Sleep/docs/
- GitHub: https://github.com/jaein4722/Let-My-Agent-Sleep
- npm: https://www.npmjs.com/package/let-my-agent-sleep

## License

MIT. See [LICENSE](LICENSE).
