# Let My Agent Sleep Protocol v1

Long-running jobs are handoff tasks, not completion tasks.

## Handoff Event

`LMAS_HANDOFF v1` means the current agent loop has completed its responsibility: the job was started in a resumable way.

Required fields:

- `run_id`
- `status: STARTED`
- `cwd`
- `command`
- `pid_or_job_id`
- `stdout`
- `stderr`
- `metadata`
- `artifacts_dir`
- `started_at`
- `resume_instruction`

## Completion Event

`LMAS_COMPLETION_EVENT v1` means a previously handoffed job finished and the agent should resume work.

Required fields:

- `run_id`
- `status: SUCCEEDED | FAILED | CANCELLED | TIMEOUT`
- `exit_code`
- `cwd`
- `command`
- `stdout`
- `stderr`
- `metadata`
- `artifacts_dir`
- `finished_at`

## Status Event

`LMAS_STATUS v1` is emitted by:

```bash
lmas.sh status <run_id>
```

Use it for quick inspection before reading stdout/stderr.

Status can be `RUNNING`, `LOST`, `SUCCEEDED`, `FAILED`, `CANCELLED`, or `TIMEOUT`.

`RUNNING` is not a completion event. If status is `RUNNING`, stop the current agent turn and wait for `LMAS_COMPLETION_EVENT v1` unless the user explicitly asks for another status check.

`LOST` means the handoff exists, no completion event was written, and the watcher process is no longer alive. Inspect `watcher_log` and `stderr` before deciding whether to relaunch.
