---
description: Start long-running jobs with Let My Agent Sleep handoff semantics in Claude Code.
allowed-tools: Bash Read
---

# Let My Agent Sleep

## HARD RULE: DO NOT POLL AFTER HANDOFF — ARM ONE NATIVE WAITER, THEN STOP

AFTER `LMAS_HANDOFF v1`, THE JOB IS HANDED OFF.

THE ONLY NEXT ACTION IS TO START `lmas.sh await <run_id>` WITH THE BASH TOOL'S `run_in_background: true` OPTION.

AFTER THAT TOOL RETURNS ITS BACKGROUND TASK ID, END THE TURN IMMEDIATELY.

UNTIL `LMAS_COMPLETION_EVENT v1` ARRIVES, OR THE USER EXPLICITLY ASKS FOR STATUS:

DO NOT POLL.
DO NOT CALL STATUS.
DO NOT TAIL LOGS.
DO NOT READ STDOUT OR STDERR.
DO NOT INSPECT ARTIFACTS.
DO NOT CALL `TaskOutput` FOR THE WAITER.
DO NOT CONTINUE THE LOOP JUST BECAUSE A TODO IS STILL OPEN.

The waiter only receives completion. The real command remains owned by LMAS and tmux. Killing or losing the waiter must never kill the real job.

Claude Code support is experimental. When the native waiter cannot be registered or is proven dead before delivery, LMAS uses the existing `claude --resume` adapter fallback. If delivery became ambiguous after the native waiter claimed it, LMAS suppresses fallback to prevent a duplicate and keeps `resume_prompt.txt` as the recovery source of truth.

Treat long-running jobs as handoff tasks, not completion tasks.

Use this command when a user asks Claude Code to start model training, evaluation, preprocessing, benchmarks, large migrations, or batch jobs that may run for minutes or hours.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with:

```bash
~/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh start --adapter claude -- <command...>
```

3. Use `--adapter claude` for real long jobs. Use `--adapter noop` only for local smoke tests or when the user explicitly asks for manual fallback.
4. After `LMAS_HANDOFF v1` is printed, record its `run_id`. In a second Bash tool call, run:

```bash
~/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh await <run_id>
```

Set that Bash tool call's `run_in_background` parameter to `true`. Do not append shell `&`, do not call `TaskOutput`, and do not poll the task.
5. As soon as the Bash tool returns its background task ID, end the current turn.
6. Completion re-invokes the session with a task notification. Read the notification's exact `<output-file>` path with `Read`; completed background tasks may already be absent from `TaskOutput`.
7. If the output file contains `LMAS_COMPLETION_EVENT v1`, inspect the referenced stdout/stderr/artifacts and continue the original task. If it contains `LMAS_NATIVE_DELIVERY_NOOP v1`, another delivery path already won; do not produce a second completion response.

Let My Agent Sleep uses `tmux` for watcher sessions. `tmux` must be installed and available on `PATH`; do not fall back to direct background shell execution.

## Required Behavior

- Do not run long jobs directly when the Let My Agent Sleep wrapper is available.
- If you maintain a TODO list, scope the long-job TODO to "start with LMAS and record handoff". Mark it complete immediately after `LMAS_HANDOFF v1`; do not leave a TODO that means "wait for job completion".
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- Do not force or suggest non-`tmux` launchers in Claude Code.
- After `LMAS_HANDOFF v1`, register exactly one native background waiter as described above, then do not check status, inspect artifacts, relaunch, or debug the job unless the user explicitly asks for a status check.
- If `scripts/lmas.sh status` reports `RUNNING` or `FINALIZING`, stop immediately. Do not call status again, tail logs, inspect artifacts, or continue the loop until `LMAS_COMPLETION_EVENT v1` arrives or the user explicitly asks for another status check.
- If the user explicitly asks to cancel, stop, or terminate an LMAS run, use `scripts/lmas.sh cancel <run_id>`. Do not kill tmux sessions or job processes directly.
- If a user later asks for status and `LMAS_STATUS v1` reports `LOST`, inspect `watcher.log` and `stderr.log`, report the run as lost, and ask before relaunching. Do not silently start a replacement job.
- If the Claude adapter cannot resume automatically, tell the user where `resume_prompt.txt` and `adapter.log` are.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.
- Do not replace this workflow with `claude --bg`, an agent daemon, Remote Control, terminal input injection, or a PATH/executable wrapper.

## Adapter Notes

The preferred live path is Claude Code's native Bash background-task completion callback. `lmas.sh await` is only a lightweight receiver; it does not own or run the real job.

When no native waiter was registered, or its process is proven dead before claiming delivery, the Claude Code adapter uses:

```bash
claude --resume "$claude_session_id" -p "$(cat resume_prompt.txt)"
```

The wrapper captures Claude Code's `CLAUDE_CODE_SESSION_ID` automatically when the job starts and resumes that exact session only on this definite native non-delivery path. A single atomic delivery claim prevents native and fallback completion payloads from both winning. If Claude Code does not expose a session ID, the wrapper leaves the prompt without claiming fallback delivery. Set `LMAS_CLAUDE_CONTINUE=1` only when continuing the most recent Claude session in the current working directory is acceptable.

User task or command context:

```text
$ARGUMENTS
```
