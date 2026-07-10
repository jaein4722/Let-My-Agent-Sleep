# Let My Agent Sleep Protocol v1

Let My Agent Sleep separates long-running work into a handoff event, a completion event, and explicit local control events.

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

`TIMEOUT` is reserved for protocol compatibility. LMAS does not schedule or enforce job timeouts.

## `LMAS_CANCEL v1`

Printed by `lmas cancel <run_id>` after a user explicitly asks LMAS to stop a handoffed run.

Meaning: cancellation was requested for a known LMAS run. Agents must not cancel a run merely because it is long-running; cancellation is a user-directed control action.

Successful cancellation writes a normal completion event with `status: CANCELLED` and `exit_code: 130`, writes `resume_prompt.txt`, and runs the configured adapter and secondary notification path.

Fields for successful cancellation:

- `run_id`
- `status: CANCELLED`
- `exit_code`
- `run_dir`
- `completion_event`
- `resume_prompt`

If the run already has `completion_event.txt`, or the watched command has already exited and LMAS is finalizing the completion event, cancel is a no-op and reports:

- `run_id`
- `status: ALREADY_COMPLETED`
- `existing_status`
- `run_dir`
- `message` when the completion event is still finalizing

If the handoff exists but the watcher is already gone and no completion event exists, cancel reports:

- `run_id`
- `status: LOST`
- `run_dir`
- `message`

`LOST` does not write a `CANCELLED` completion event or `resume_prompt.txt`, because LMAS can no longer prove the watcher-owned command state.

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
- `status: RUNNING | FINALIZING | LOST | SUCCEEDED | FAILED | CANCELLED | TIMEOUT`
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

The status surface may recognize reserved `TIMEOUT` records, but LMAS does not emit them on its own.

Jobs may append lightweight progress lines to `<run_dir>/progress.txt`, such as `step=1200 loss=0.43`. LMAS never reads this file during handoff waiting. It is surfaced only when the user explicitly asks for status.

`RUNNING` and `FINALIZING` are not completion events. `FINALIZING` means the watched process has exited and LMAS is preparing `resume_prompt.txt` plus `completion_event.txt`. If an agent sees either status, it should stop the current turn and wait for `LMAS_COMPLETION_EVENT v1` unless the user explicitly asks for another status check.

## Secondary Notification

`--notify <url>` or `LMAS_NOTIFY_URL` sends the generated `resume_prompt.txt` to a secondary HTTP endpoint after completion handling. It is a notification path, not an adapter replacement: LMAS still writes `completion_event.txt`, writes `resume_prompt.txt`, and attempts the selected adapter first.

The notification URL is stored in `notify_url.txt`, not in `metadata.txt`, because webhook URLs may contain secrets. `metadata.txt` only records `notify=enabled`.

HTTP adapter and notification calls are bounded by `LMAS_HTTP_CONNECT_TIMEOUT` and `LMAS_HTTP_MAX_TIME`, defaulting to 5 and 30 seconds. Timeout failures are recorded in `adapter.log` or `notify.log` and do not change the completed run status.

`LOST` means the handoff exists, no completion event is being finalized, and the watcher process is no longer alive. Treat it as a failed handoff/run state and inspect `watcher_log` plus `stderr` before deciding whether to relaunch.
