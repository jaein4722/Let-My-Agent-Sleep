---
name: let-my-agent-sleep
description: Start long-running training, evaluation, preprocessing, benchmark, or batch jobs with Let My Agent Sleep handoff semantics in Codex. Use when a task would otherwise require waiting, polling, or repeated continue loops until a job finishes.
---

# Let My Agent Sleep

Treat long-running jobs as handoff tasks, not completion tasks.

Use this skill when a command is likely to run for minutes or hours, including model training, evaluation, dataset preprocessing, benchmark suites, large migrations, or batch inference.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with:

```bash
codex/let-my-agent-sleep/skills/let-my-agent-sleep/scripts/lmas.sh start --adapter codex -- <command...>
```

3. If `LMAS_CODEX_SESSION_ID` is known, set it before starting the job so the watcher can run `codex exec resume`.
4. After `LMAS_HANDOFF v1` is printed, stop the current loop. Do not poll the logs or wait for completion.
5. When `LMAS_COMPLETION_EVENT v1` appears later in the session, run `lmas.sh status <run_id>` if you need a concise summary, then inspect stdout/stderr/artifacts and continue the original task.

## Required Behavior

- Do not run long jobs directly when the Let My Agent Sleep wrapper is available.
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- If the Codex adapter cannot resume automatically, tell the user where `resume_prompt.txt` is.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.
- Read stdout/stderr first; read metadata only when command context is unclear.

## Adapter Notes

The Codex prototype adapter uses:

```bash
codex exec resume "$LMAS_CODEX_SESSION_ID" - < resume_prompt.txt
```

If the session id is absent, the wrapper writes the prompt and skips automatic resume.
