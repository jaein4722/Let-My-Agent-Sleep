#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-handoff.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh sleep 1)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

[ -n "$RUN_ID" ] || { printf 'missing run_id\n' >&2; exit 1; }
[ -f "$RUN_DIR/handoff.txt" ] || { printf 'missing handoff.txt\n' >&2; exit 1; }
printf '%s\n' "$OUTPUT" | grep -q '^LMAS_HANDOFF v1$' || { printf 'start output did not emit LMAS_HANDOFF\n' >&2; exit 1; }
for field in run_id status cwd command pid_or_job_id stdout stderr metadata artifacts_dir started_at resume_instruction; do
  grep -q "^$field: " "$RUN_DIR/handoff.txt" || { printf 'handoff missing %s field\n' "$field" >&2; exit 1; }
done
grep -q "^run_id: $RUN_ID$" "$RUN_DIR/handoff.txt" || { printf 'handoff run_id did not match output run_id\n' >&2; exit 1; }
grep -q '^status: STARTED$' "$RUN_DIR/handoff.txt" || { printf 'handoff did not report STARTED\n' >&2; exit 1; }
grep -q "^stdout: $RUN_DIR/stdout.log$" "$RUN_DIR/handoff.txt" || { printf 'handoff stdout path drifted\n' >&2; exit 1; }
grep -q "^stderr: $RUN_DIR/stderr.log$" "$RUN_DIR/handoff.txt" || { printf 'handoff stderr path drifted\n' >&2; exit 1; }
grep -q "^metadata: $RUN_DIR/metadata.txt$" "$RUN_DIR/handoff.txt" || { printf 'handoff metadata path drifted\n' >&2; exit 1; }

if [ -f "$RUN_DIR/completion_event.txt" ]; then
  printf 'completion was written before handoff test could observe non-blocking start\n' >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }
for field in run_id status exit_code cwd command stdout stderr metadata artifacts_dir finished_at; do
  grep -q "^$field: " "$RUN_DIR/completion_event.txt" || { printf 'completion missing %s field\n' "$field" >&2; exit 1; }
done
grep -q "^run_id: $RUN_ID$" "$RUN_DIR/completion_event.txt" || { printf 'completion run_id did not match output run_id\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'completion did not report SUCCEEDED\n' >&2; exit 1; }
grep -q '^exit_code: 0$' "$RUN_DIR/completion_event.txt" || { printf 'completion did not report exit_code 0\n' >&2; exit 1; }
grep -q "^stdout: $RUN_DIR/stdout.log$" "$RUN_DIR/completion_event.txt" || { printf 'completion stdout path drifted\n' >&2; exit 1; }
grep -q "^stderr: $RUN_DIR/stderr.log$" "$RUN_DIR/completion_event.txt" || { printf 'completion stderr path drifted\n' >&2; exit 1; }
grep -q "^metadata: $RUN_DIR/metadata.txt$" "$RUN_DIR/completion_event.txt" || { printf 'completion metadata path drifted\n' >&2; exit 1; }
[ -f "$RUN_DIR/resume_prompt.txt" ] || { printf 'missing resume_prompt.txt\n' >&2; exit 1; }
grep -q '^LMAS_COMPLETION_EVENT v1$' "$RUN_DIR/resume_prompt.txt" || { printf 'resume prompt missing completion event\n' >&2; exit 1; }
grep -q '^Next steps:$' "$RUN_DIR/resume_prompt.txt" || { printf 'resume prompt missing next steps\n' >&2; exit 1; }
printf 'ok basic handoff: %s\n' "$RUN_ID"
