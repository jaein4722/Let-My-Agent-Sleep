# Let My Agent Sleep Protocol v1

Let My Agent Sleep separates long-running work into two events: handoff and completion.

## `LMAS_HANDOFF v1`

Printed immediately after a long-running job is started under watcher control.

Meaning: the current loop is complete; do not poll or keep continuing just because the job is still running.

Fields:

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

## `LMAS_COMPLETION_EVENT v1`

Written after the watched command exits, and optionally injected back into the original agent session.

Meaning: the handoffed job is finished; inspect logs, metrics, checkpoints, and continue the original task.

Fields:

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

## Run Directory

Default layout:

```text
.lmas/runs/<run_id>/
  command.txt
  metadata.txt
  stdout.log
  stderr.log
  handoff.txt
  completion_event.txt
  resume_prompt.txt
  exit_code
  watcher.log
  adapter.log
```

## Status Event

`LMAS_STATUS v1` is a local inspection event emitted by:

```bash
packages/let-my-agent-sleep/bin/lmas.sh status <run_id>
```

It reports:

- `run_id`
- `status: RUNNING | LOST | SUCCEEDED | FAILED | CANCELLED | TIMEOUT`
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

`RUNNING` is not a completion event. If an agent sees `RUNNING`, it should stop the current turn and wait for `LMAS_COMPLETION_EVENT v1` unless the user explicitly asks for another status check.

## Secondary Notification

`--notify <url>` or `LMAS_NOTIFY_URL` sends the generated `resume_prompt.txt` to a secondary HTTP endpoint after completion handling. It is a notification path, not an adapter replacement: LMAS still writes `completion_event.txt`, writes `resume_prompt.txt`, and attempts the selected adapter first.

The notification URL is stored in `notify_url.txt`, not in `metadata.txt`, because webhook URLs may contain secrets. `metadata.txt` only records `notify=enabled`.

`LOST` means the handoff exists, no completion event was written, and the watcher process is no longer alive. Treat it as a failed handoff/run state and inspect `watcher_log` plus `stderr` before deciding whether to relaunch.
