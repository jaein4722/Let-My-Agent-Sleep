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

- Validate fresh and upgraded 0.3.2 installs in a real OpenCode + Oh My OpenAgent session, including handoff, one-shot status, exact-run cancellation, completion resume, and the read-only 0.3.0 residue warning.
- Keep the global fetch/client guard replacement, OpenCode SDK upgrade, structured multilingual authorization, and formal repair/uninstall commands out of 0.3.2; each needs a separate compatibility cycle.

## Completed Hardening

- **Cancel process-tree verification.** `lmas cancel` collects both child trees and process-group peers, stops the tmux watcher, escalates TERM to KILL for remaining pids, writes `cancel_killed_pids`, and records `cancel_surviving_pids` if any pid still survives. Smoke tests cover TERM-aware children, TERM-ignoring children, grandchildren, LOST cancellation, and completion/cancel races.
- **Failure-mode hardening.** Smoke tests now cover adapter failure after completion event creation, preserving `resume_prompt.txt` for manual recovery, status exposure of that prompt path, missing watcher `LOST`, missing tmux session `LOST`, cancellation of already-lost runs, and completion/cancel races.
- **Observability without polling.** `lmas list` reports elapsed seconds and a command summary. `lmas status` reports started time, elapsed seconds, command, and the last line of `progress.txt` when present. Smoke tests cover the progress contract while keeping the no-poll handoff rule intact.
- **Secondary completion notification.** `--notify <url>` and `LMAS_NOTIFY_URL` post the generated resume prompt to a webhook/ntfy endpoint after the adapter attempt, without replacing session injection. Smoke tests cover notification delivery even when OpenCode adapter injection fails.
- **OpenCode continuation guard surface.** Runtime guards now cover the official OpenCode hooks in `@opencode-ai/plugin@1.2.27` that can start, resume, summarize, or observe active handoff state: `chat.message`, `experimental.chat.messages.transform`, `experimental.chat.system.transform`, `experimental.session.compacting`, `tool.execute.before`, `tool.execute.after`, `shell.env`, `command.execute.before`, and `permission.ask`. LMAS also exposes a best-effort `experimental.compaction.autocontinue` compatibility hook for OpenCode builds that call it, but the pinned plugin type surface does not currently list that hook; compaction protection therefore relies on `experimental.session.compacting` context preservation plus downstream message, prompt, command, permission, and tool guards. Smoke tests cover plugin-tool handoff, CLI fallback handoff, CLI fallback status/cancel/completion output, prompt injection, compaction/system context preservation, shell environment injection, explicit user cancel, OMO continuation commands, and the compatibility autocontinue hook. The remaining official hooks in `@opencode-ai/plugin@1.2.27` (`chat.params`, `chat.headers`, `experimental.text.complete`, and `tool.definition`) are not handoff state transition hooks and are intentionally left unused unless a concrete live-agent failure points to them.
- **Release surface.** README and site assets use the source-backed social card, concise handoff flow, and the verified 17-hour/12-hour OpenCode live-run baseline without a generated demo GIF.

## Optional Ideas (not planned)

Kept here so they are not re-proposed from scratch; none are committed.

- **Job chaining** (`--after <run_id>`): only worth revisiting if agent-driven self-pipelining proves insufficient in practice.
- **Machine-readable events** (`completion_event.json` alongside the text event): only when an external integration actually needs to parse events.
- **Adapter plugin interface** (external `lmas-adapter-<name>` executables): only if third-party adapter demand appears.
- **Claude Code real-time injection into an open session:** blocked upstream; revisit when Claude Code exposes an official notification/injection path. Until then, restart-based recovery is the documented behavior.
