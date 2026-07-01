---
name: let-my-agent-sleep
description: Start long-running training, evaluation, preprocessing, benchmark, or batch jobs with Let My Agent Sleep handoff semantics in Claude Code. Use when a task would otherwise require waiting, polling, or repeated continue loops until a job finishes.
allowed-tools: Bash Read
---

# Let My Agent Sleep

Treat long-running jobs as handoff tasks, not completion tasks.

Use this skill when a command is likely to run for minutes or hours, including model training, evaluation, dataset preprocessing, benchmark suites, large migrations, or batch inference.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with:

```bash
~/.claude/skills/let-my-agent-sleep/scripts/lmas.sh start --adapter claude -- <command...>
```

3. Use `--adapter claude` for real long jobs. Use `--adapter noop` only for local smoke tests or when the user explicitly asks for manual fallback.
4. After `LMAS_HANDOFF v1` is printed, stop the current loop. Do not poll the logs or wait for completion.
5. When `LMAS_COMPLETION_EVENT v1` appears later in the session, run `lmas.sh status <run_id>` if you need a concise summary, then inspect stdout/stderr/artifacts and continue the original task.

Let My Agent Sleep uses `tmux` for watcher sessions. `tmux` must be installed and available on `PATH`; do not fall back to direct background shell execution.

## Required Behavior

- Do not run long jobs directly when the Let My Agent Sleep wrapper is available.
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- Do not force or suggest non-`tmux` launchers in Claude Code.
- After `LMAS_HANDOFF v1`, do not check status, inspect artifacts, relaunch, or debug the job unless the user explicitly asks for a status check. A user asking whether enough time has passed, why there is no update, or whether the job finished counts as a status check request.
- If a user later asks for status and `LMAS_STATUS v1` reports `LOST`, inspect `watcher.log` and `stderr.log`, report the run as lost, and ask before relaunching. Do not silently start a replacement job.
- If the Claude adapter cannot resume automatically, tell the user where `resume_prompt.txt` and `adapter.log` are.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.
- Read stdout/stderr first; read metadata only when command context is unclear.

## Path Rules

- Prefer workspace-local paths under `.lmas/` for all LMAS run data and artifacts.
- Use `.lmas/runs` as the default `--runs-dir`.
- Use `.lmas/artifacts/<task-name-or-timestamp>` as the default `--artifacts-dir` for task outputs and reproducible helper scripts.
- Use `/tmp` only when the current workspace is not writable or the user explicitly requests a temporary system path.

## Adapter Notes

The Claude Code adapter uses:

```bash
claude --resume "$LMAS_CLAUDE_SESSION_ID" -p "$(cat resume_prompt.txt)"
```

If `LMAS_CLAUDE_SESSION_ID` is absent, the wrapper writes the prompt and skips automatic resume. Set `LMAS_CLAUDE_CONTINUE=1` only when continuing the most recent Claude session in the current working directory is acceptable.
