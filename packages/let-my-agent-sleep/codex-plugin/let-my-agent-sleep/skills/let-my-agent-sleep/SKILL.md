---
name: let-my-agent-sleep
description: Start long-running training, evaluation, preprocessing, benchmark, or batch jobs with Let My Agent Sleep handoff semantics in Codex. Use when a task would otherwise require waiting, polling, or repeated continue loops until a job finishes.
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

Treat long-running jobs as handoff tasks, not completion tasks.

Use this skill when a command is likely to run for minutes or hours, including model training, evaluation, dataset preprocessing, benchmark suites, large migrations, or batch inference.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with:

```bash
${CODEX_HOME:-~/.codex}/skills/let-my-agent-sleep/scripts/lmas.sh start --adapter codex -- <command...>
```

3. Use `--adapter codex` for real long jobs. Use `--adapter noop` only for local smoke tests or when the user explicitly asks for manual fallback.
4. After `LMAS_HANDOFF v1` is printed, stop the current loop. Do not poll the logs or wait for completion.
5. When `LMAS_COMPLETION_EVENT v1` appears later in the session, run `lmas.sh status <run_id>` if you need a concise summary, then inspect stdout/stderr/artifacts and continue the original task.

Let My Agent Sleep uses `tmux` for watcher sessions. `tmux` must be installed and available on `PATH`; do not fall back to `nohup`, `launchctl`, or direct background shell execution.
Codex's default workspace sandbox can block tmux socket creation. If LMAS reports that the watcher session could not be started or verified, request the narrowly scoped permission needed to rerun the same LMAS start command. Never accept a handoff unless `LMAS_HANDOFF v1` was printed after watcher verification.

## Required Behavior

- Do not run long jobs directly when the Let My Agent Sleep wrapper is available.
- If you maintain a TODO list, scope the long-job TODO to "start with LMAS and record handoff". Mark it complete immediately after `LMAS_HANDOFF v1`; do not leave a TODO that means "wait for job completion".
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- Do not force or suggest non-`tmux` launchers in Codex.
- After `LMAS_HANDOFF v1`, do not check status, inspect artifacts, relaunch, or debug the job unless the user explicitly asks for a status check. A user asking whether enough time has passed, why there is no update, or whether the job finished counts as a status check request.
- If `scripts/lmas.sh status` reports `RUNNING` or `FINALIZING`, stop immediately. Do not call status again, tail logs, inspect artifacts, or continue the loop until `LMAS_COMPLETION_EVENT v1` arrives or the user explicitly asks for another status check.
- If the user explicitly asks to cancel, stop, or terminate an LMAS run, use `scripts/lmas.sh cancel <run_id>`. Do not kill tmux sessions or job processes directly.
- If a user later asks for status and `LMAS_STATUS v1` reports `LOST`, inspect `watcher.log` and `stderr.log`, report the run as lost, and ask before relaunching. Do not silently start a replacement job.
- If the Codex adapter cannot resume automatically, tell the user where `resume_prompt.txt` and `adapter.log` are.
- If completion was externally resumed while a Codex Desktop task or CLI TUI remained open, tell the user to reload or reopen that task before sending another message. The persisted turn can be visible even when the already-running process's model context does not include it.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.
- After completion, read stdout/stderr first; read metadata only when command context is unclear.

## Path Rules

- Prefer workspace-local paths under `.lmas/` for all LMAS run data and artifacts.
- Use `.lmas/runs` as the default `--runs-dir`.
- Use `.lmas/artifacts/<task-name-or-timestamp>` as the default `--artifacts-dir` for task outputs and reproducible helper scripts.
- Use `/tmp` only when the current workspace is not writable or the user explicitly requests a temporary system path.

## Adapter Notes

The Codex adapter captures the `CODEX_THREAD_ID` supplied by Codex at job start. No manual session-id environment variable is required.

On completion it runs:

```bash
${LMAS_CODEX_BIN:-codex} exec resume --skip-git-repo-check "$codex_session_id" - < resume_prompt.txt
```

If no session id is available, the wrapper writes the prompt and skips automatic resume. Set `LMAS_CODEX_BIN` to an executable path when `codex` on `PATH` is not usable.
