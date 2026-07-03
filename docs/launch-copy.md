# Let My Agent Sleep launch copy

Use these as starting points for sharing LMAS. Keep the claim boundary intact: LMAS removes polling and waiting cost, not the cost of useful handoff or completion work.

## Short launch post

I built Let My Agent Sleep, a tiny tool that lets AI agents start long-running training, evaluation, preprocessing, benchmark, or batch jobs, stop polling logs, and resume the same session when the job finishes.

It is built for the failure mode where an agent starts a long run, keeps checking `tail -n 20 train.log`, reloads the same context again and again, and burns tokens while learning nothing.

LMAS turns that into:

```text
start job -> LMAS_HANDOFF -> agent stops
job finishes -> LMAS_COMPLETION_EVENT -> same session resumes
```

Install:

```bash
npx let-my-agent-sleep install
```

OpenCode is the primary target. Codex is supported. Claude Code support is experimental.

## Direct cost angle

AI agents should not spend hundreds of dollars polling a training log.

In one observed OpenCode loop, repeated status checks cost about `$2.72` over `10.2 minutes`. Projected over a 24-hour wait, that is about `$382` and `1.93B` tokens.

LMAS does not make the wake-up free. It makes the waiting disappear. The agent pays for one handoff and one completion prompt, then uses the result to continue.

## Hacker News style

Show HN: Let My Agent Sleep - stop AI agents polling long-running jobs

I built a small npm package for agent workflows where long training/evaluation jobs cause the agent to keep polling logs or repeatedly continuing.

The idea is simple: long-running jobs are handoff tasks, not completion tasks. The agent starts the command, records a structured handoff, stops, and a lightweight watcher resumes the same session when the process exits.

It uses tmux and plain files. No daemon, no database, no training-code callback.

OpenCode is the primary target, Codex is supported, and Claude Code support is still experimental.

## X / short social post

Built a tiny tool for AI agents that keep wasting tokens polling long-running jobs.

Let My Agent Sleep:
- starts the training/eval job
- emits a handoff
- stops the agent loop
- wakes the same session when the job finishes

`npx let-my-agent-sleep install`

OpenCode primary. Codex supported. Claude experimental.

## Reddit / Discord post

I kept hitting a specific agent workflow problem: when an agent starts a long-running training or evaluation job, it often keeps polling logs or gets repeatedly continued by a loop runner.

That is expensive and usually pointless. The job is not done, but that is a valid state. The agent should hand it off, stop, and resume when there is a real completion event.

So I built Let My Agent Sleep.

It wraps the command, runs it through tmux, records stdout/stderr/metadata/artifacts, and injects a completion event back into the same agent session.

The package is intentionally small:

```bash
npx let-my-agent-sleep install
```

It currently targets OpenCode first, supports Codex, and has experimental Claude Code support.

## Claim boundary

Use this wording when challenged:

LMAS does not claim that agent work becomes free. The handoff prompt, completion prompt, log inspection, and next-step planning still cost tokens. The saving is that the waiting interval no longer produces polling turns, repeated context reloads, or artificial continue loops.
