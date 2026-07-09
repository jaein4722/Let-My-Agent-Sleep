# Let My Agent Sleep Roadmap

This roadmap records what LMAS will and will not do, so future work stays aligned with the original design intent.

## Design Principles and Non-Goals

These are deliberate decisions, not gaps.

- **No skill-level timeouts.** Training runs of 12 hours, 24 hours, or 3+ days are normal. Even if a job deadlocks and goes silent, diagnosing and terminating it belongs to the user (`lmas_status`, then `lmas cancel` on request). LMAS never kills a slow job on its own, and the `TIMEOUT` status in the protocol is reserved, not scheduled for implementation.
- **Persistent OpenCode server is a hard assumption for the OpenCode adapter.** That adapter hands completion off over the HTTP API, so `opencode serve` is expected to stay up under tmux or systemd. Codex/Claude use different resume paths (`codex exec resume`, `claude --resume`) and do not depend on a live server. If the machine reboots, the training job dies with it — `LOST` is the correct terminal representation of that situation, not a recovery gap to fix.
- **No built-in job chaining; pipelines are agent-driven.** The intended loop is: completion prompt arrives → the agent inspects results → designs the next experiment itself → starts the next LMAS run. A session may hold multiple LMAS runs, but LMAS itself never becomes a scheduler — chaining stays out of scope (see Optional Ideas).
- **Remote execution is already the deployment model.** The agent itself runs on the remote host over SSH; the local desktop app merely attaches to that session. LMAS does not need its own remote transport layer.
- **Real agent behavior is the release gate.** Automated checks cover the core protocol and package surface, but real OpenCode/Codex/Claude behavior is validated in live agent sessions before release.

Verified baseline: 17-hour and 12-hour real OpenCode training runs completed the full handoff → completion → session re-entry loop.

## Short-Term Plan

Ordered roughly by value per effort.

1. **Failure-mode hardening.** Cover the failure modes that matter for long runs: adapter failure path leaving `resume_prompt.txt`, and more `LOST` detection cases after the watcher dies.
2. **Observability without polling.** The no-poll rule constrains the agent, not the user. Add: elapsed time and command summary columns to `lmas list`; a `progress.txt` contract the job may append to (e.g. `step=1200 loss=0.43`), which the agent reads only when the user explicitly asks for status.
3. **Secondary completion notification.** Optional `--notify <url>` (webhook/ntfy) and an OS notification fallback when the adapter fails, alongside — never instead of — session injection. Low priority given the persistent-server assumption; treated as cheap insurance for the exact-moment-of-completion edge.
4. **Release pitch.** Add a README demo GIF of an OpenCode session going quiet on handoff and waking on completion; add a comparison note against native background-task features, citing the 17h/12h live validation.

## Completed Hardening

- **Cancel process-tree verification.** `lmas cancel` collects both child trees and process-group peers, stops the tmux watcher, escalates TERM to KILL for remaining pids, writes `cancel_killed_pids`, and records `cancel_surviving_pids` if any pid still survives. Smoke tests cover TERM-aware children, TERM-ignoring children, grandchildren, LOST cancellation, and completion/cancel races.

## Optional Ideas (not planned)

Kept here so they are not re-proposed from scratch; none are committed.

- **Job chaining** (`--after <run_id>`): only worth revisiting if agent-driven self-pipelining proves insufficient in practice.
- **Machine-readable events** (`completion_event.json` alongside the text event): only when an external integration actually needs to parse events.
- **Adapter plugin interface** (external `lmas-adapter-<name>` executables): only if third-party adapter demand appears.
- **Claude Code real-time injection into an open session:** blocked upstream; revisit when Claude Code exposes an official notification/injection path. Until then, restart-based recovery is the documented behavior.
