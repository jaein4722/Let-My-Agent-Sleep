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
bin/lmas.sh status <run_id>
```

It reports:

- `run_id`
- `status: RUNNING | LOST | SUCCEEDED | FAILED | CANCELLED | TIMEOUT`
- `exit_code` when complete
- `run_dir`
- `stdout`
- `stderr`
- `metadata`
- `watcher_log`
- `adapter_log`
- `resume_prompt` when available

`LOST` means the handoff exists, no completion event was written, and the watcher process is no longer alive. Treat it as a failed handoff/run state and inspect `watcher_log` plus `stderr` before deciding whether to relaunch.
