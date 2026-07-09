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

Use it only when the user explicitly asks for status, or after completion.

Status can be `RUNNING`, `LOST`, `SUCCEEDED`, `FAILED`, `CANCELLED`, or `TIMEOUT`.

It reports:

- `run_id`
- `status`
- `exit_code` when complete
- `started_at` when known
- `elapsed_seconds` when epoch metadata is available
- `command` when known
- `run_dir`
- `stdout`
- `stderr`
- `metadata`
- `watcher_log`
- `adapter_log`
- `notify_log` when secondary notification is configured and has run
- `resume_prompt` when available
- `progress` and `progress_path` when `progress.txt` exists

Jobs may append lightweight progress lines to `<run_dir>/progress.txt`, such as `step=1200 loss=0.43`. LMAS never reads this file during handoff waiting. It is surfaced only when the user explicitly asks for status.

`RUNNING` is not a completion event. If status is `RUNNING`, stop the current agent turn and wait for `LMAS_COMPLETION_EVENT v1` unless the user explicitly asks for another status check.

## Secondary Notification

`--notify <url>` or `LMAS_NOTIFY_URL` sends the generated `resume_prompt.txt` to a secondary HTTP endpoint after completion handling. It is a notification path, not an adapter replacement: LMAS still writes `completion_event.txt`, writes `resume_prompt.txt`, and attempts the selected adapter first.

The notification URL is stored in `notify_url.txt`, not in `metadata.txt`, because webhook URLs may contain secrets. `metadata.txt` only records `notify=enabled`.

`LOST` means the handoff exists, no completion event was written, and the watcher process is no longer alive. Inspect `watcher_log` and `stderr` before deciding whether to relaunch.
