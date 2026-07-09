---
description: Start long-running jobs with Let My Agent Sleep handoff semantics in Claude Code.
allowed-tools: Bash Read
---

# Let My Agent Sleep

## HARD RULE: DO NOT POLL AFTER HANDOFF

AFTER `LMAS_HANDOFF v1`, THE JOB IS HANDED OFF.

UNTIL `LMAS_COMPLETION_EVENT v1` ARRIVES, OR THE USER EXPLICITLY ASKS FOR STATUS:

DO NOT POLL.
DO NOT CALL STATUS.
DO NOT TAIL LOGS.
DO NOT READ STDOUT OR STDERR.
DO NOT INSPECT ARTIFACTS.
DO NOT CONTINUE THE LOOP JUST BECAUSE A TODO IS STILL OPEN.

Stop the current turn after handoff.

Claude Code support is experimental. Automatic resume is not guaranteed across every Claude Code frontend, desktop session list, or remote SSH setup. If automatic resume does not appear in the expected session, use `resume_prompt.txt` as the fallback source of truth.

Treat long-running jobs as handoff tasks, not completion tasks.

Use this command when a user asks Claude Code to start model training, evaluation, preprocessing, benchmarks, large migrations, or batch jobs that may run for minutes or hours.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with:

```bash
~/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh start --adapter claude -- <command...>
```

3. Use `--adapter claude` for real long jobs. Use `--adapter noop` only for local smoke tests or when the user explicitly asks for manual fallback.
4. After `LMAS_HANDOFF v1` is printed, stop the current loop. Do not poll the logs or wait for completion.
5. When `LMAS_COMPLETION_EVENT v1` appears later in the session, run `lmas.sh status <run_id>` if you need a concise summary, then inspect stdout/stderr/artifacts and continue the original task.

Let My Agent Sleep uses `tmux` for watcher sessions. `tmux` must be installed and available on `PATH`; do not fall back to direct background shell execution.

## Required Behavior

- Do not run long jobs directly when the Let My Agent Sleep wrapper is available.
- If you maintain a TODO list, scope the long-job TODO to "start with LMAS and record handoff". Mark it complete immediately after `LMAS_HANDOFF v1`; do not leave a TODO that means "wait for job completion".
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- Do not force or suggest non-`tmux` launchers in Claude Code.
- After `LMAS_HANDOFF v1`, do not check status, inspect artifacts, relaunch, or debug the job unless the user explicitly asks for a status check.
- If `scripts/lmas.sh status` reports `RUNNING`, stop immediately. Do not call status again, tail logs, inspect artifacts, or continue the loop until `LMAS_COMPLETION_EVENT v1` arrives or the user explicitly asks for another status check.
- If the user explicitly asks to cancel, stop, or terminate an LMAS run, use `scripts/lmas.sh cancel <run_id>`. Do not kill tmux sessions or job processes directly.
- If a user later asks for status and `LMAS_STATUS v1` reports `LOST`, inspect `watcher.log` and `stderr.log`, report the run as lost, and ask before relaunching. Do not silently start a replacement job.
- If the Claude adapter cannot resume automatically, tell the user where `resume_prompt.txt` and `adapter.log` are.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.

## Adapter Notes

The Claude Code adapter uses:

```bash
claude --resume "$LMAS_CLAUDE_SESSION_ID" -p "$(cat resume_prompt.txt)"
```

If `LMAS_CLAUDE_SESSION_ID` is absent, the wrapper writes the prompt and skips automatic resume. Set `LMAS_CLAUDE_CONTINUE=1` only when continuing the most recent Claude session in the current working directory is acceptable.

User task or command context:

```text
$ARGUMENTS
```
