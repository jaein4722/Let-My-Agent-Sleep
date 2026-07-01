#!/usr/bin/env bash
set -u

SCRIPT_NAME=${0##*/}
SCRIPT_PATH=$0
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
esac

usage() {
  cat <<'EOF'
Usage:
  lmas.sh start [options] -- <command...>
  lmas.sh status [--runs-dir <path>] <run_id|run_dir>
  lmas.sh list [--runs-dir <path>]

Options:
  --adapter <noop|opencode|codex>  Completion adapter to run. Default: noop
  --runs-dir <path>                Run directory root. Default: .lmas/runs
  --cwd <path>                     Working directory for the command. Default: current directory
  --artifacts-dir <path>           Artifact directory to report in events. Default: run directory
  --metadata <key=value>           Metadata line to append. May be repeated
  -h, --help                       Show help

Environment:
  LMAS_RUNS_DIR
  LMAS_OPENCODE_SERVER_URL   Default: http://127.0.0.1:4096
  LMAS_OPENCODE_SESSION_ID   Required for opencode adapter
  LMAS_OPENCODE_PASSWORD     Optional basic-auth password
  LMAS_CODEX_SESSION_ID      Required for codex adapter
EOF
}

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 2
}

timezone_offset() {
  local offset
  offset=$(date '+%z')
  printf '%s:%s\n' "${offset%??}" "${offset#???}"
}

now_system() {
  printf '%s%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(timezone_offset)"
}

compact_now_system() {
  date '+%Y%m%dT%H%M%S%z'
}

shell_quote() {
  local value escaped
  value=$1
  escaped=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

quote_command() {
  local first=1 arg
  for arg in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ' '
    fi
    shell_quote "$arg"
    first=0
  done
}

json_string_from_file() {
  local file
  file=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$file"
    return
  fi
  awk '
    BEGIN { printf "\"" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\t/,"\\t")
      gsub(/\r/,"\\r")
      if (NR > 1) printf "\\n"
      printf "%s", $0
    }
    END { printf "\"" }
  ' "$file"
}

write_handoff() {
  local run_dir run_id status cwd command_text pid_or_job_id stdout_path stderr_path metadata_path artifacts_dir resume_instruction started_at
  run_dir=$1
  run_id=$2
  status=$3
  cwd=$4
  command_text=$5
  pid_or_job_id=$6
  stdout_path=$7
  stderr_path=$8
  metadata_path=$9
  artifacts_dir=${10}
  resume_instruction=${11}
  started_at=${12}

  {
    printf 'LMAS_HANDOFF v1\n'
    printf 'run_id: %s\n' "$run_id"
    printf 'status: %s\n' "$status"
    printf 'cwd: %s\n' "$cwd"
    printf 'command: %s\n' "$command_text"
    printf 'pid_or_job_id: %s\n' "$pid_or_job_id"
    printf 'stdout: %s\n' "$stdout_path"
    printf 'stderr: %s\n' "$stderr_path"
    printf 'metadata: %s\n' "$metadata_path"
    printf 'artifacts_dir: %s\n' "$artifacts_dir"
    printf 'started_at: %s\n' "$started_at"
    printf 'resume_instruction: %s\n' "$resume_instruction"
  } > "$run_dir/handoff.txt"
}

write_completion_event() {
  local run_dir run_id status exit_code cwd command_text stdout_path stderr_path metadata_path artifacts_dir finished_at
  run_dir=$1
  run_id=$2
  status=$3
  exit_code=$4
  cwd=$5
  command_text=$6
  stdout_path=$7
  stderr_path=$8
  metadata_path=$9
  artifacts_dir=${10}
  finished_at=${11}

  {
    printf 'LMAS_COMPLETION_EVENT v1\n'
    printf 'run_id: %s\n' "$run_id"
    printf 'status: %s\n' "$status"
    printf 'exit_code: %s\n' "$exit_code"
    printf 'cwd: %s\n' "$cwd"
    printf 'command: %s\n' "$command_text"
    printf 'stdout: %s\n' "$stdout_path"
    printf 'stderr: %s\n' "$stderr_path"
    printf 'metadata: %s\n' "$metadata_path"
    printf 'artifacts_dir: %s\n' "$artifacts_dir"
    printf 'finished_at: %s\n' "$finished_at"
  } > "$run_dir/completion_event.txt"
}

write_resume_prompt() {
  local run_dir
  run_dir=$1
  {
    printf 'A previously handoffed Let My Agent Sleep job has finished.\n\n'
    cat "$run_dir/completion_event.txt"
    printf '\nNext steps:\n'
    printf '1. Inspect stdout and stderr first.\n'
    printf '2. Inspect metadata only if the command/result context is unclear.\n'
    printf '3. Summarize the result and metrics/checkpoints if present.\n'
    printf '4. Continue the original task from this completed job state.\n'
  } > "$run_dir/resume_prompt.txt"
}

run_opencode_adapter() {
  local run_dir prompt_file server_url session_id password endpoint payload escaped
  run_dir=$1
  prompt_file=$2
  server_url=${LMAS_OPENCODE_SERVER_URL:-http://127.0.0.1:4096}
  session_id=${LMAS_OPENCODE_SESSION_ID:-}
  password=${LMAS_OPENCODE_PASSWORD:-}

  if [ -z "$session_id" ]; then
    printf 'opencode adapter skipped: LMAS_OPENCODE_SESSION_ID is empty\n' > "$run_dir/adapter.log"
    return 0
  fi

  escaped=$(json_string_from_file "$prompt_file")
  payload=$(printf '{"parts":[{"type":"text","text":%s}]}' "$escaped")
  endpoint="${server_url%/}/session/$session_id/prompt_async"

  if [ -n "$password" ]; then
    curl -fsS -X POST "$endpoint" \
      -u ":$password" \
      -H 'content-type: application/json' \
      --data "$payload" > "$run_dir/adapter.log" 2>&1 || {
        printf '\nopencode adapter failed for %s\n' "$endpoint" >> "$run_dir/adapter.log"
        return 0
      }
  else
    curl -fsS -X POST "$endpoint" \
      -H 'content-type: application/json' \
      --data "$payload" > "$run_dir/adapter.log" 2>&1 || {
        printf '\nopencode adapter failed for %s\n' "$endpoint" >> "$run_dir/adapter.log"
        return 0
      }
  fi
}

run_codex_adapter() {
  local run_dir prompt_file session_id
  run_dir=$1
  prompt_file=$2
  session_id=${LMAS_CODEX_SESSION_ID:-}

  if [ -z "$session_id" ]; then
    printf 'codex adapter skipped: LMAS_CODEX_SESSION_ID is empty\n' > "$run_dir/adapter.log"
    return 0
  fi

  if ! command -v codex >/dev/null 2>&1; then
    printf 'codex adapter skipped: codex command not found\n' > "$run_dir/adapter.log"
    return 0
  fi

  codex exec resume "$session_id" - < "$prompt_file" > "$run_dir/adapter.log" 2>&1 || {
    printf '\ncodex adapter failed for session %s\n' "$session_id" >> "$run_dir/adapter.log"
    return 0
  }
}

run_adapter() {
  local adapter run_dir prompt_file
  adapter=$1
  run_dir=$2
  prompt_file=$3

  case "$adapter" in
    noop)
      printf 'noop adapter: resume prompt left at %s\n' "$prompt_file" > "$run_dir/adapter.log"
      ;;
    opencode)
      run_opencode_adapter "$run_dir" "$prompt_file"
      ;;
    codex)
      run_codex_adapter "$run_dir" "$prompt_file"
      ;;
    *)
      printf 'unknown adapter %s; resume prompt left at %s\n' "$adapter" "$prompt_file" > "$run_dir/adapter.log"
      ;;
  esac
}

launch_watcher_tmux() {
  local run_dir run_id adapter cwd command_text stdout_path stderr_path metadata_path artifacts_dir session command_line log_path tmux_socket
  run_dir=$1
  run_id=$2
  adapter=$3
  cwd=$4
  command_text=$5
  stdout_path=$6
  stderr_path=$7
  metadata_path=$8
  artifacts_dir=$9
  shift 9

  command -v tmux >/dev/null 2>&1 || die "tmux launcher requested but tmux is not available"
  session="$run_id"
  mkdir -p "$cwd/.lmas/tmux" || die "failed to create tmux socket directory: $cwd/.lmas/tmux"
  tmux_socket=".lmas/tmux/${run_id}.sock"
  printf '%s\n' "$tmux_socket" > "$run_dir/tmux_socket.txt"
  command_line=$(quote_command "$SCRIPT_PATH" __watch "$run_dir" "$run_id" "$adapter" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" -- "$@")
  log_path=$(shell_quote "$run_dir/watcher.log")
  ( cd "$cwd" && tmux -S "$tmux_socket" new-session -d -s "$session" "exec $command_line > $log_path 2>&1" ) || die "failed to start tmux watcher session: $session"
  printf 'tmux:%s\n' "$session"
}

watch_command() {
  local run_dir run_id adapter cwd command_text stdout_path stderr_path metadata_path artifacts_dir exit_code status finished_at
  run_dir=$1
  run_id=$2
  adapter=$3
  cwd=$4
  command_text=$5
  stdout_path=$6
  stderr_path=$7
  metadata_path=$8
  artifacts_dir=$9
  shift 9

  set +e
  (
    cd "$cwd" || exit 127
    "$@"
  ) > "$stdout_path" 2> "$stderr_path"
  exit_code=$?
  printf '%s\n' "$exit_code" > "$run_dir/exit_code"

  if [ "$exit_code" -eq 0 ]; then
    status=SUCCEEDED
  else
    status=FAILED
  fi

  finished_at=$(now_system)
  write_completion_event "$run_dir" "$run_id" "$status" "$exit_code" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$finished_at"
  write_resume_prompt "$run_dir"
  run_adapter "$adapter" "$run_dir" "$run_dir/resume_prompt.txt"
}

start_command() {
  local adapter runs_dir cwd artifacts_dir run_id run_dir command_text started_at metadata_path stdout_path stderr_path resume_instruction watcher_id
  local metadata=()

  adapter=${LMAS_ADAPTER:-noop}
  runs_dir=${LMAS_RUNS_DIR:-.lmas/runs}
  cwd=$(pwd)
  artifacts_dir=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --adapter)
        [ "$#" -ge 2 ] || die "--adapter requires a value"
        adapter=$2
        shift 2
        ;;
      --runs-dir)
        [ "$#" -ge 2 ] || die "--runs-dir requires a value"
        runs_dir=$2
        shift 2
        ;;
      --cwd)
        [ "$#" -ge 2 ] || die "--cwd requires a value"
        cwd=$2
        shift 2
        ;;
      --artifacts-dir)
        [ "$#" -ge 2 ] || die "--artifacts-dir requires a value"
        artifacts_dir=$2
        shift 2
        ;;
      --launcher)
        [ "$#" -ge 2 ] || die "--launcher requires a value"
        case "$2" in
          auto|tmux) ;;
          *) die "only tmux launcher is supported" ;;
        esac
        shift 2
        ;;
      --metadata)
        [ "$#" -ge 2 ] || die "--metadata requires a value"
        metadata+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done

  [ "$#" -gt 0 ] || die "missing command after --"
  [ -d "$cwd" ] || die "cwd does not exist: $cwd"

  run_id="lmas_$(compact_now_system)_$$_${RANDOM:-0}"
  run_dir="$runs_dir/$run_id"
  mkdir -p "$run_dir" || die "failed to create run directory: $run_dir"

  if [ -z "$artifacts_dir" ]; then
    artifacts_dir="$run_dir"
  fi

  command_text=$(quote_command "$@")
  started_at=$(now_system)
  metadata_path="$run_dir/metadata.txt"
  stdout_path="$run_dir/stdout.log"
  stderr_path="$run_dir/stderr.log"
  resume_instruction="Wait for completion event or inspect $run_dir/resume_prompt.txt after the job exits."

  {
    printf 'run_id=%s\n' "$run_id"
    printf 'adapter=%s\n' "$adapter"
    printf 'launcher=tmux\n'
    printf 'cwd=%s\n' "$cwd"
    printf 'command=%s\n' "$command_text"
    printf 'started_at=%s\n' "$started_at"
    printf 'artifacts_dir=%s\n' "$artifacts_dir"
    set +u
    for item in "${metadata[@]}"; do
      printf '%s\n' "$item"
    done
    set -u
  } > "$metadata_path"
  printf '%s\n' "$command_text" > "$run_dir/command.txt"

  watcher_id=$(launch_watcher_tmux "$run_dir" "$run_id" "$adapter" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$@") || die "failed to start tmux watcher"

  write_handoff "$run_dir" "$run_id" STARTED "$cwd" "$command_text" "$watcher_id" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$resume_instruction" "$started_at"
  cat "$run_dir/handoff.txt"
}

resolve_run_dir() {
  local runs_dir run_ref
  runs_dir=$1
  run_ref=$2

  if [ -d "$run_ref" ]; then
    printf '%s\n' "$run_ref"
    return 0
  fi

  if [ -d "$runs_dir/$run_ref" ]; then
    printf '%s\n' "$runs_dir/$run_ref"
    return 0
  fi

  return 1
}

read_field() {
  local file field
  file=$1
  field=$2
  if [ -f "$file" ]; then
    awk -F ': ' -v key="$field" '$1 == key { print substr($0, length(key) + 3); exit }' "$file"
  fi
}

watcher_alive() {
  local id run_dir session tmux_socket cwd_for_socket
  id=$1
  run_dir=${2:-}
  [ -n "$id" ] || return 1
  case "$id" in
    tmux:*)
      session=${id#tmux:}
      command -v tmux >/dev/null 2>&1 || return 1
      if [ -n "$run_dir" ] && [ -f "$run_dir/tmux_socket.txt" ]; then
        tmux_socket=$(sed -n '1p' "$run_dir/tmux_socket.txt")
      else
        tmux_socket=".lmas/tmux/${session}.sock"
      fi
      cwd_for_socket=$(awk -F= '$1 == "cwd" { print substr($0, 5); exit }' "$run_dir/metadata.txt" 2>/dev/null)
      [ -n "$cwd_for_socket" ] || cwd_for_socket=$(pwd)
      ( cd "$cwd_for_socket" && tmux -S "$tmux_socket" has-session -t "$session" >/dev/null 2>&1 )
      ;;
    *[!0-9]*)
      return 1
      ;;
    *)
      kill -0 "$id" >/dev/null 2>&1
      ;;
  esac
}

status_command() {
  local runs_dir run_ref run_dir event_file status exit_code run_id pid_or_job_id
  runs_dir=${LMAS_RUNS_DIR:-.lmas/runs}

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --runs-dir)
        [ "$#" -ge 2 ] || die "--runs-dir requires a value"
        runs_dir=$2
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  [ "$#" -eq 1 ] || die "status requires exactly one run_id or run_dir"
  run_ref=$1
  run_dir=$(resolve_run_dir "$runs_dir" "$run_ref") || die "run not found: $run_ref"

  if [ -f "$run_dir/completion_event.txt" ]; then
    event_file="$run_dir/completion_event.txt"
    status=$(read_field "$event_file" status)
    exit_code=$(read_field "$event_file" exit_code)
  else
    event_file="$run_dir/handoff.txt"
    pid_or_job_id=$(read_field "$event_file" pid_or_job_id)
    if watcher_alive "$pid_or_job_id" "$run_dir"; then
      status=RUNNING
    else
      status=LOST
    fi
    exit_code=
  fi

  run_id=$(read_field "$event_file" run_id)
  {
    printf 'LMAS_STATUS v1\n'
    printf 'run_id: %s\n' "$run_id"
    printf 'status: %s\n' "$status"
    if [ -n "$exit_code" ]; then
      printf 'exit_code: %s\n' "$exit_code"
    fi
    printf 'run_dir: %s\n' "$run_dir"
    printf 'stdout: %s\n' "$run_dir/stdout.log"
    printf 'stderr: %s\n' "$run_dir/stderr.log"
    printf 'metadata: %s\n' "$run_dir/metadata.txt"
    printf 'watcher_log: %s\n' "$run_dir/watcher.log"
    printf 'adapter_log: %s\n' "$run_dir/adapter.log"
    if [ -f "$run_dir/resume_prompt.txt" ]; then
      printf 'resume_prompt: %s\n' "$run_dir/resume_prompt.txt"
    fi
  }
}

list_command() {
  local runs_dir run_dir run_id status exit_code event_file
  runs_dir=${LMAS_RUNS_DIR:-.lmas/runs}

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --runs-dir)
        [ "$#" -ge 2 ] || die "--runs-dir requires a value"
        runs_dir=$2
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done

  printf 'run_id\tstatus\texit_code\trun_dir\n'
  [ -d "$runs_dir" ] || return 0

  for run_dir in "$runs_dir"/lmas_*; do
    [ -d "$run_dir" ] || continue
    if [ -f "$run_dir/completion_event.txt" ]; then
      event_file="$run_dir/completion_event.txt"
      status=$(read_field "$event_file" status)
      exit_code=$(read_field "$event_file" exit_code)
    else
      event_file="$run_dir/handoff.txt"
      pid_or_job_id=$(read_field "$event_file" pid_or_job_id)
      if watcher_alive "$pid_or_job_id" "$run_dir"; then
        status=RUNNING
      else
        status=LOST
      fi
      exit_code=
    fi
    run_id=$(read_field "$event_file" run_id)
    printf '%s\t%s\t%s\t%s\n' "$run_id" "$status" "$exit_code" "$run_dir"
  done
}

watch_command_from_cli() {
  local run_dir run_id adapter cwd command_text stdout_path stderr_path metadata_path artifacts_dir
  [ "$#" -ge 10 ] || die "__watch missing arguments"
  run_dir=$1
  run_id=$2
  adapter=$3
  cwd=$4
  command_text=$5
  stdout_path=$6
  stderr_path=$7
  metadata_path=$8
  artifacts_dir=$9
  shift 9
  [ "${1:-}" = "--" ] || die "__watch missing -- separator"
  shift
  [ "$#" -gt 0 ] || die "__watch missing command"
  watch_command "$run_dir" "$run_id" "$adapter" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$@"
}

main() {
  local command
  command=${1:-}
  case "$command" in
    start)
      shift
      start_command "$@"
      ;;
    status)
      shift
      status_command "$@"
      ;;
    list)
      shift
      list_command "$@"
      ;;
    __watch)
      shift
      watch_command_from_cli "$@"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      die "unknown command: $command"
      ;;
  esac
}

main "$@"
