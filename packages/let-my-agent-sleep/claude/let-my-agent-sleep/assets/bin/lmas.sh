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
  lmas.sh cancel [--runs-dir <path>] [--reason <text>] <run_id|run_dir>
  lmas.sh list [--runs-dir <path>]

Options:
  --adapter <noop|opencode|codex|claude>
                                      Completion adapter to run. Default: noop
  --runs-dir <path>                Run directory root. Default: .lmas/runs
  --cwd <path>                     Working directory for the command. Default: current directory
  --artifacts-dir <path>           Artifact directory to report in events. Default: run directory
  --metadata <key=value>           Metadata line to append. May be repeated
  --notify <url>                   POST the completion resume prompt to this URL
  -h, --help                       Show help

Environment:
  LMAS_RUNS_DIR
  LMAS_NOTIFY_URL            Same as --notify
  LMAS_OPENCODE_SERVER_URL   Default: http://127.0.0.1:4096
  LMAS_OPENCODE_SESSION_ID   Required for opencode adapter
  LMAS_OPENCODE_USERNAME     Optional basic-auth username. Default: OPENCODE_SERVER_USERNAME or opencode
  LMAS_OPENCODE_PASSWORD     Optional basic-auth password
  LMAS_CODEX_SESSION_ID      Preferred for codex adapter; CODEX_THREAD_ID is also used when available
  LMAS_CLAUDE_SESSION_ID     Preferred for claude adapter exact resume
  LMAS_CLAUDE_CONTINUE       Set to 1 to let claude adapter use --continue
  LMAS_HTTP_CONNECT_TIMEOUT  HTTP adapter/notify connect timeout seconds. Default: 5
  LMAS_HTTP_MAX_TIME         HTTP adapter/notify total timeout seconds. Default: 30
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

now_epoch() {
  date '+%s'
}

compact_now_system() {
  date '+%Y%m%dT%H%M%S%z'
}

resolve_against_cwd() {
  local cwd path_value
  cwd=$1
  path_value=$2

  case "$path_value" in
    /*) printf '%s\n' "$path_value" ;;
    *) printf '%s/%s\n' "$cwd" "$path_value" ;;
  esac
}

absolute_dir() {
  local path_value
  path_value=$1
  ( cd "$path_value" && pwd -P )
}

shell_quote() {
  local value escaped
  value=$1
  escaped=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

display_shell_quote() {
  local value escaped
  value=$1
  value=$(printf '%s' "$value" | tr '\r\n' '  ')
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

display_quote_command() {
  local first=1 arg
  for arg in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ' '
    fi
    display_shell_quote "$arg"
    first=0
  done
}

write_line_field() {
  local key value
  key=$1
  value=$2
  printf '%s: %s\n' "$key" "$(safe_metadata_line "$value")"
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
    write_line_field run_id "$run_id"
    write_line_field status "$status"
    write_line_field cwd "$cwd"
    write_line_field command "$command_text"
    write_line_field pid_or_job_id "$pid_or_job_id"
    write_line_field stdout "$stdout_path"
    write_line_field stderr "$stderr_path"
    write_line_field metadata "$metadata_path"
    write_line_field artifacts_dir "$artifacts_dir"
    write_line_field started_at "$started_at"
    write_line_field resume_instruction "$resume_instruction"
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
    write_line_field run_id "$run_id"
    write_line_field status "$status"
    write_line_field exit_code "$exit_code"
    write_line_field cwd "$cwd"
    write_line_field command "$command_text"
    write_line_field stdout "$stdout_path"
    write_line_field stderr "$stderr_path"
    write_line_field metadata "$metadata_path"
    write_line_field artifacts_dir "$artifacts_dir"
    write_line_field finished_at "$finished_at"
  } > "$run_dir/.completion_event.txt"
}

write_resume_prompt() {
  local run_dir event_file
  run_dir=$1
  event_file="$run_dir/completion_event.txt"
  if [ -f "$run_dir/.completion_event.txt" ]; then
    event_file="$run_dir/.completion_event.txt"
  fi
  {
    printf 'A previously handoffed Let My Agent Sleep job has finished.\n\n'
    cat "$event_file"
    printf '\nNext steps:\n'
    printf '1. Inspect stdout and stderr first.\n'
    printf '2. Inspect metadata only if the command/result context is unclear.\n'
    printf '3. Summarize the result and metrics/checkpoints if present.\n'
    printf '4. Continue the original task from this completed job state.\n'
  } > "$run_dir/resume_prompt.txt"
  if [ -f "$run_dir/.completion_event.txt" ]; then
    mv "$run_dir/.completion_event.txt" "$run_dir/completion_event.txt"
  fi
}

run_opencode_adapter() {
  local run_dir prompt_file server_url session_id username password endpoint payload escaped connect_timeout max_time
  run_dir=$1
  prompt_file=$2
  server_url=${LMAS_OPENCODE_SERVER_URL:-http://127.0.0.1:4096}
  session_id=${LMAS_OPENCODE_SESSION_ID:-}
  username=${LMAS_OPENCODE_USERNAME:-${OPENCODE_SERVER_USERNAME:-opencode}}
  password=${LMAS_OPENCODE_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}
  connect_timeout=${LMAS_HTTP_CONNECT_TIMEOUT:-5}
  max_time=${LMAS_HTTP_MAX_TIME:-30}

  if [ -z "$session_id" ]; then
    printf 'opencode adapter skipped: LMAS_OPENCODE_SESSION_ID is empty\n' > "$run_dir/adapter.log"
    return 0
  fi

  escaped=$(json_string_from_file "$prompt_file")
  payload=$(printf '{"parts":[{"type":"text","text":%s}]}' "$escaped")
  endpoint="${server_url%/}/session/$session_id/prompt_async"

  if [ -n "$password" ]; then
    curl -fsS -X POST "$endpoint" \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      -u "$username:$password" \
      -H 'content-type: application/json' \
      --data "$payload" > "$run_dir/adapter.log" 2>&1 || {
        printf '\nopencode adapter failed for %s\n' "$endpoint" >> "$run_dir/adapter.log"
        return 0
      }
  else
    curl -fsS -X POST "$endpoint" \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
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
  session_id=$(awk -F= '$1 == "codex_session_id" { print substr($0, length($1) + 2); exit }' "$run_dir/metadata.txt" 2>/dev/null)
  [ -n "$session_id" ] || session_id=${LMAS_CODEX_SESSION_ID:-${CODEX_THREAD_ID:-}}

  if [ -z "$session_id" ]; then
    printf 'codex adapter skipped: codex_session_id, LMAS_CODEX_SESSION_ID, and CODEX_THREAD_ID are empty\n' > "$run_dir/adapter.log"
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

run_claude_adapter() {
  local run_dir prompt_file session_id continue_mode prompt cwd
  run_dir=$1
  prompt_file=$2
  session_id=${LMAS_CLAUDE_SESSION_ID:-}
  continue_mode=${LMAS_CLAUDE_CONTINUE:-}

  if ! command -v claude >/dev/null 2>&1; then
    printf 'claude adapter skipped: claude command not found\n' > "$run_dir/adapter.log"
    return 0
  fi

  prompt=$(cat "$prompt_file")
  cwd=$(awk -F= '$1 == "cwd" { print substr($0, 5); exit }' "$run_dir/metadata.txt" 2>/dev/null)
  [ -n "$cwd" ] || cwd=$(pwd)

  if [ -n "$session_id" ]; then
    ( cd "$cwd" && claude --resume "$session_id" -p "$prompt" ) > "$run_dir/adapter.log" 2>&1 || {
      printf '\nclaude adapter failed for session %s\n' "$session_id" >> "$run_dir/adapter.log"
      return 0
    }
    return 0
  fi

  if [ "$continue_mode" = "1" ] || [ "$continue_mode" = "true" ]; then
    ( cd "$cwd" && claude --continue -p "$prompt" ) > "$run_dir/adapter.log" 2>&1 || {
      printf '\nclaude adapter failed while continuing the most recent session\n' >> "$run_dir/adapter.log"
      return 0
    }
    return 0
  fi

  printf 'claude adapter skipped: LMAS_CLAUDE_SESSION_ID is empty; set LMAS_CLAUDE_CONTINUE=1 to continue the most recent Claude session in cwd\n' > "$run_dir/adapter.log"
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
    claude)
      run_claude_adapter "$run_dir" "$prompt_file"
      ;;
    *)
      printf 'unknown adapter %s; resume prompt left at %s\n' "$adapter" "$prompt_file" > "$run_dir/adapter.log"
      ;;
  esac
}

run_notification() {
  local run_dir prompt_file notify_url connect_timeout max_time
  run_dir=$1
  prompt_file=$2
  notify_url=${LMAS_NOTIFY_URL:-}
  connect_timeout=${LMAS_HTTP_CONNECT_TIMEOUT:-5}
  max_time=${LMAS_HTTP_MAX_TIME:-30}

  if [ -f "$run_dir/notify_url.txt" ]; then
    notify_url=$(cat "$run_dir/notify_url.txt")
  fi

  if [ -z "$notify_url" ]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'notify skipped: curl command not found\n' > "$run_dir/notify.log"
    return 0
  fi

  curl -fsS -X POST "$notify_url" \
    --connect-timeout "$connect_timeout" \
    --max-time "$max_time" \
    -H 'content-type: text/plain; charset=utf-8' \
    --data-binary @"$prompt_file" > "$run_dir/notify.log" 2>&1 || {
      printf '\nnotify failed\n' >> "$run_dir/notify.log"
      return 0
    }

  printf '\nnotify sent\n' >> "$run_dir/notify.log"
}

list_child_pids() {
  local parent
  parent=$1
  ps -eo pid=,ppid= 2>/dev/null | awk -v parent="$parent" '$2 == parent { print $1 }'
}

collect_process_tree() {
  local parent child
  parent=$1
  for child in $(list_child_pids "$parent"); do
    printf '%s\n' "$child"
    collect_process_tree "$child"
  done
}

process_pgid() {
  local pid
  pid=$1
  ps -o pgid= -p "$pid" 2>/dev/null | awk 'NF { print $1; exit }'
}

list_process_group_pids() {
  local pgid
  pgid=$1
  [ -n "$pgid" ] || return 0
  ps -eo pid=,pgid= 2>/dev/null | awk -v pgid="$pgid" '$2 == pgid { print $1 }'
}

terminate_pids() {
  local pid alive_pids surviving_pids
  alive_pids=
  surviving_pids=
  for pid in "$@"; do
    case "$pid" in
      ''|*[!0-9]*) continue ;;
    esac
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      alive_pids="$alive_pids $pid"
    fi
  done

  [ -n "$alive_pids" ] || return 0
  sleep 0.2

  for pid in $alive_pids; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  done

  sleep 0.2

  for pid in $alive_pids; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      surviving_pids="$surviving_pids $pid"
    fi
  done

  if [ -n "$surviving_pids" ]; then
    printf '%s\n' "$surviving_pids" | awk '{ for (i = 1; i <= NF; i++) if (!seen[$i]++) printf "%s%s", sep, $i; sep=" " }'
  fi
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
  local run_dir run_id adapter cwd command_text stdout_path stderr_path metadata_path artifacts_dir exit_code status finished_at finished_epoch child_pid
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
    "$@" &
    child_pid=$!
    printf '%s\n' "$child_pid" > "$run_dir/child_pid"
    wait "$child_pid"
  ) > "$stdout_path" 2> "$stderr_path"
  exit_code=$?
  printf '%s\n' "$exit_code" > "$run_dir/exit_code"

  if [ "$exit_code" -eq 0 ]; then
    status=SUCCEEDED
  else
    status=FAILED
  fi

  finished_at=$(now_system)
  finished_epoch=$(now_epoch)
  printf 'finished_epoch=%s\n' "$finished_epoch" >> "$metadata_path"
  write_completion_event "$run_dir" "$run_id" "$status" "$exit_code" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$finished_at"
  write_resume_prompt "$run_dir"
  run_adapter "$adapter" "$run_dir" "$run_dir/resume_prompt.txt"
  run_notification "$run_dir" "$run_dir/resume_prompt.txt"
}

start_command() {
  local adapter runs_dir cwd artifacts_dir notify_url run_id run_dir command_text started_at started_epoch metadata_path stdout_path stderr_path resume_instruction watcher_id codex_session_id
  local metadata=()

  adapter=${LMAS_ADAPTER:-noop}
  runs_dir=${LMAS_RUNS_DIR:-.lmas/runs}
  cwd=$(pwd)
  artifacts_dir=
  notify_url=${LMAS_NOTIFY_URL:-}

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
      --notify)
        [ "$#" -ge 2 ] || die "--notify requires a value"
        notify_url=$2
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
  cwd=$(absolute_dir "$cwd") || die "failed to resolve cwd: $cwd"
  runs_dir=$(resolve_against_cwd "$cwd" "$runs_dir")

  run_id="lmas_$(compact_now_system)_$$_${RANDOM:-0}"
  run_dir="$runs_dir/$run_id"
  mkdir -p "$run_dir" || die "failed to create run directory: $run_dir"

  if [ -z "$artifacts_dir" ]; then
    artifacts_dir="$run_dir"
  fi

  command_text=$(display_quote_command "$@")
  started_at=$(now_system)
  started_epoch=$(now_epoch)
  codex_session_id=
  if [ "$adapter" = "codex" ]; then
    codex_session_id=${LMAS_CODEX_SESSION_ID:-${CODEX_THREAD_ID:-}}
  fi
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
    printf 'started_epoch=%s\n' "$started_epoch"
    printf 'artifacts_dir=%s\n' "$(safe_metadata_line "$artifacts_dir")"
    if [ -n "$notify_url" ]; then
      printf 'notify=enabled\n'
    fi
    if [ -n "$codex_session_id" ]; then
      printf 'codex_session_id=%s\n' "$codex_session_id"
    fi
    set +u
    for item in "${metadata[@]}"; do
      printf '%s\n' "$(safe_metadata_line "$item")"
    done
    set -u
  } > "$metadata_path"
  if [ -n "$notify_url" ]; then
    printf '%s\n' "$notify_url" > "$run_dir/notify_url.txt"
    chmod 600 "$run_dir/notify_url.txt" 2>/dev/null || true
  fi
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

read_metadata_field() {
  local file field
  file=$1
  field=$2
  if [ -f "$file" ]; then
    awk -F= -v key="$field" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
  fi
}

completion_event_file() {
  local run_dir
  run_dir=$1
  if [ -f "$run_dir/completion_event.txt" ]; then
    printf '%s\n' "$run_dir/completion_event.txt"
    return 0
  fi
  if [ -f "$run_dir/.completion_event.txt" ]; then
    printf '%s\n' "$run_dir/.completion_event.txt"
    return 0
  fi
  return 1
}

status_from_exit_code() {
  local exit_code
  exit_code=$1
  if [ "$exit_code" = "0" ]; then
    printf 'SUCCEEDED\n'
  else
    printf 'FAILED\n'
  fi
}

safe_tsv_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

safe_metadata_line() {
  printf '%s' "$1" | tr '\r\n' '  '
}

short_tsv_field() {
  printf '%s' "$1" | tr '\t\r\n' '   ' | cut -c 1-96
}

elapsed_seconds_for_run() {
  local run_dir status start_epoch end_epoch current_epoch
  run_dir=$1
  status=$2

  start_epoch=$(read_metadata_field "$run_dir/metadata.txt" started_epoch)
  case "$start_epoch" in
    ''|*[!0-9]*) return 0 ;;
  esac

  if [ "$status" = "RUNNING" ] || [ "$status" = "LOST" ] || [ "$status" = "FINALIZING" ]; then
    current_epoch=$(now_epoch)
    printf '%s\n' "$((current_epoch - start_epoch))"
    return 0
  fi

  end_epoch=$(read_metadata_field "$run_dir/metadata.txt" finished_epoch)
  case "$end_epoch" in
    ''|*[!0-9]*) return 0 ;;
  esac
  printf '%s\n' "$((end_epoch - start_epoch))"
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

stop_watcher() {
  local id run_dir session tmux_socket cwd_for_socket
  id=$1
  run_dir=$2
  [ -n "$id" ] || return 1

  case "$id" in
    tmux:*)
      session=${id#tmux:}
      command -v tmux >/dev/null 2>&1 || return 1
      if [ -f "$run_dir/tmux_socket.txt" ]; then
        tmux_socket=$(sed -n '1p' "$run_dir/tmux_socket.txt")
      else
        tmux_socket=".lmas/tmux/${session}.sock"
      fi
      cwd_for_socket=$(read_metadata_field "$run_dir/metadata.txt" cwd)
      [ -n "$cwd_for_socket" ] || cwd_for_socket=$(pwd)
      ( cd "$cwd_for_socket" && tmux -S "$tmux_socket" kill-session -t "$session" >/dev/null 2>&1 )
      ;;
    *[!0-9]*)
      return 1
      ;;
    *)
      kill -TERM "$id" >/dev/null 2>&1
      ;;
  esac
}

watcher_root_pid() {
  local id run_dir session tmux_socket cwd_for_socket
  id=$1
  run_dir=$2
  [ -n "$id" ] || return 1

  case "$id" in
    tmux:*)
      session=${id#tmux:}
      command -v tmux >/dev/null 2>&1 || return 1
      if [ -f "$run_dir/tmux_socket.txt" ]; then
        tmux_socket=$(sed -n '1p' "$run_dir/tmux_socket.txt")
      else
        tmux_socket=".lmas/tmux/${session}.sock"
      fi
      cwd_for_socket=$(read_metadata_field "$run_dir/metadata.txt" cwd)
      [ -n "$cwd_for_socket" ] || cwd_for_socket=$(pwd)
      ( cd "$cwd_for_socket" && tmux -S "$tmux_socket" display-message -p -t "$session" '#{pane_pid}' 2>/dev/null )
      ;;
    *[!0-9]*)
      return 1
      ;;
    *)
      printf '%s\n' "$id"
      ;;
  esac
}

cancel_command() {
  local runs_dir reason run_ref run_dir event_file existing_status run_id pid_or_job_id child_pid child_tree_pids child_group_pids watcher_pid watcher_tree_pids watcher_group_pids killed_pids surviving_pids
  local adapter cwd command_text stdout_path stderr_path metadata_path artifacts_dir finished_at finished_epoch exit_code was_alive

  runs_dir=${LMAS_RUNS_DIR:-.lmas/runs}
  reason="user requested cancellation"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --runs-dir)
        [ "$#" -ge 2 ] || die "--runs-dir requires a value"
        runs_dir=$2
        shift 2
        ;;
      --reason)
        [ "$#" -ge 2 ] || die "--reason requires a value"
        reason=$2
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

  [ "$#" -eq 1 ] || die "cancel requires exactly one run_id or run_dir"
  run_ref=$1
  run_dir=$(resolve_run_dir "$runs_dir" "$run_ref") || die "run not found: $run_ref"

  if event_file=$(completion_event_file "$run_dir"); then
    run_id=$(read_field "$event_file" run_id)
    existing_status=$(read_field "$event_file" status)
    {
      printf 'LMAS_CANCEL v1\n'
      write_line_field run_id "$run_id"
      write_line_field status ALREADY_COMPLETED
      write_line_field existing_status "$existing_status"
      write_line_field run_dir "$run_dir"
      if [ "$event_file" = "$run_dir/.completion_event.txt" ]; then
        write_line_field message "job has already exited; completion event is finalizing"
      fi
    }
    return 0
  fi

  event_file="$run_dir/handoff.txt"
  [ -f "$event_file" ] || die "handoff not found for run: $run_ref"

  run_id=$(read_field "$event_file" run_id)
  if [ -f "$run_dir/exit_code" ]; then
    exit_code=$(sed -n '1p' "$run_dir/exit_code")
    existing_status=$(status_from_exit_code "$exit_code")
    {
      printf 'LMAS_CANCEL v1\n'
      write_line_field run_id "$run_id"
      write_line_field status ALREADY_COMPLETED
      write_line_field existing_status "$existing_status"
      write_line_field run_dir "$run_dir"
      write_line_field message "job has already exited; completion event is finalizing"
    }
    return 0
  fi
  pid_or_job_id=$(read_field "$event_file" pid_or_job_id)
  was_alive=0
  if watcher_alive "$pid_or_job_id" "$run_dir"; then
    was_alive=1
  fi

  if [ "$was_alive" -eq 0 ]; then
    {
      printf 'LMAS_CANCEL v1\n'
      write_line_field run_id "$run_id"
      write_line_field status LOST
      write_line_field run_dir "$run_dir"
      write_line_field message "watcher is not alive; no CANCELLED completion event was written"
    }
    return 0
  fi

  child_pid=
  child_tree_pids=
  child_group_pids=
  watcher_pid=
  watcher_tree_pids=
  watcher_group_pids=
  killed_pids=
  watcher_pid=$(watcher_root_pid "$pid_or_job_id" "$run_dir" || true)
  case "$watcher_pid" in
    ''|*[!0-9]*) watcher_pid= ;;
    *)
      watcher_tree_pids=$(collect_process_tree "$watcher_pid")
      watcher_group_pids=$(list_process_group_pids "$(process_pgid "$watcher_pid")")
      ;;
  esac
  if [ -f "$run_dir/child_pid" ]; then
    child_pid=$(sed -n '1p' "$run_dir/child_pid")
    case "$child_pid" in
      ''|*[!0-9]*) child_pid= ;;
      *)
        child_tree_pids=$(collect_process_tree "$child_pid")
        child_group_pids=$(list_process_group_pids "$(process_pgid "$child_pid")")
        ;;
    esac
  fi
  killed_pids=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$watcher_pid" "$watcher_tree_pids" "$watcher_group_pids" "$child_pid" "$child_tree_pids" "$child_group_pids" | awk 'NF && !seen[$1]++ { printf "%s%s", sep, $1; sep=" " }')

  if ! stop_watcher "$pid_or_job_id" "$run_dir"; then
    if event_file=$(completion_event_file "$run_dir"); then
      existing_status=$(read_field "$event_file" status)
      {
        printf 'LMAS_CANCEL v1\n'
        write_line_field run_id "$run_id"
        write_line_field status ALREADY_COMPLETED
        write_line_field existing_status "$existing_status"
        write_line_field run_dir "$run_dir"
        if [ "$event_file" = "$run_dir/.completion_event.txt" ]; then
          write_line_field message "job has already exited; completion event is finalizing"
        fi
      }
      return 0
    fi
    die "failed to stop watcher for run: $run_id"
  fi
  if [ -n "$killed_pids" ]; then
    surviving_pids=$(terminate_pids $killed_pids)
  fi

  if event_file=$(completion_event_file "$run_dir"); then
    existing_status=$(read_field "$event_file" status)
    {
      printf 'LMAS_CANCEL v1\n'
      write_line_field run_id "$run_id"
      write_line_field status ALREADY_COMPLETED
      write_line_field existing_status "$existing_status"
      write_line_field run_dir "$run_dir"
      if [ "$event_file" = "$run_dir/.completion_event.txt" ]; then
        write_line_field message "job has already exited; completion event is finalizing"
      fi
    }
    return 0
  fi

  adapter=$(read_metadata_field "$run_dir/metadata.txt" adapter)
  [ -n "$adapter" ] || adapter=noop
  cwd=$(read_metadata_field "$run_dir/metadata.txt" cwd)
  [ -n "$cwd" ] || cwd=$(pwd)
  command_text=$(read_metadata_field "$run_dir/metadata.txt" command)
  [ -n "$command_text" ] || command_text=$(read_field "$event_file" command)
  artifacts_dir=$(read_metadata_field "$run_dir/metadata.txt" artifacts_dir)
  [ -n "$artifacts_dir" ] || artifacts_dir=$(read_field "$event_file" artifacts_dir)
  stdout_path="$run_dir/stdout.log"
  stderr_path="$run_dir/stderr.log"
  metadata_path="$run_dir/metadata.txt"
  exit_code=130
  finished_at=$(now_system)
  finished_epoch=$(now_epoch)

  write_completion_event "$run_dir" "$run_id" CANCELLED "$exit_code" "$cwd" "$command_text" "$stdout_path" "$stderr_path" "$metadata_path" "$artifacts_dir" "$finished_at"
  printf '%s\n' "$exit_code" > "$run_dir/exit_code"
  {
    printf 'cancelled_at=%s\n' "$finished_at"
    printf 'finished_epoch=%s\n' "$finished_epoch"
    printf 'cancel_reason=%s\n' "$(safe_metadata_line "$reason")"
    if [ -n "$watcher_pid" ]; then
      printf 'cancel_watcher_pid=%s\n' "$watcher_pid"
    fi
    if [ -n "$child_pid" ]; then
      printf 'cancel_child_pid=%s\n' "$child_pid"
    fi
    if [ -n "$killed_pids" ]; then
      printf 'cancel_killed_pids=%s\n' "$killed_pids"
    fi
    if [ -n "$surviving_pids" ]; then
      printf 'cancel_surviving_pids=%s\n' "$surviving_pids"
    fi
  } >> "$run_dir/metadata.txt"
  write_resume_prompt "$run_dir"
  run_adapter "$adapter" "$run_dir" "$run_dir/resume_prompt.txt"
  run_notification "$run_dir" "$run_dir/resume_prompt.txt"

  {
    printf 'LMAS_CANCEL v1\n'
    write_line_field run_id "$run_id"
    write_line_field status CANCELLED
    write_line_field exit_code "$exit_code"
    write_line_field run_dir "$run_dir"
    write_line_field completion_event "$run_dir/completion_event.txt"
    write_line_field resume_prompt "$run_dir/resume_prompt.txt"
  }
}

status_command() {
  local runs_dir run_ref run_dir event_file status exit_code run_id pid_or_job_id command_text started_at elapsed progress_path progress_line
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
  elif [ -f "$run_dir/exit_code" ] || [ -f "$run_dir/.completion_event.txt" ]; then
    event_file="$run_dir/handoff.txt"
    [ -f "$event_file" ] || die "handoff not found for run: $run_ref"
    if [ -f "$run_dir/exit_code" ]; then
      exit_code=$(sed -n '1p' "$run_dir/exit_code")
    else
      exit_code=$(read_field "$run_dir/.completion_event.txt" exit_code)
    fi
    status=FINALIZING
  else
    event_file="$run_dir/handoff.txt"
    [ -f "$event_file" ] || die "handoff not found for run: $run_ref"
    pid_or_job_id=$(read_field "$event_file" pid_or_job_id)
    if watcher_alive "$pid_or_job_id" "$run_dir"; then
      status=RUNNING
    else
      status=LOST
    fi
    exit_code=
  fi

  run_id=$(read_field "$event_file" run_id)
  command_text=$(read_metadata_field "$run_dir/metadata.txt" command)
  [ -n "$command_text" ] || command_text=$(read_field "$run_dir/handoff.txt" command)
  started_at=$(read_metadata_field "$run_dir/metadata.txt" started_at)
  [ -n "$started_at" ] || started_at=$(read_field "$run_dir/handoff.txt" started_at)
  elapsed=$(elapsed_seconds_for_run "$run_dir" "$status")
  progress_path="$run_dir/progress.txt"
  {
    printf 'LMAS_STATUS v1\n'
    write_line_field run_id "$run_id"
    write_line_field status "$status"
    if [ "$status" = "RUNNING" ]; then
      printf 'meaning: job is still running; this is not a completion event\n'
      printf 'agent_instruction: stop now; do not poll, tail logs, inspect artifacts, or call lmas_status again until LMAS_COMPLETION_EVENT v1 arrives or the user explicitly asks for another status check\n'
    fi
    if [ "$status" = "FINALIZING" ]; then
      printf 'meaning: job process has exited and LMAS is preparing the completion event\n'
      printf 'agent_instruction: stop now; do not poll, tail logs, inspect artifacts, or call lmas_status again until LMAS_COMPLETION_EVENT v1 arrives or the user explicitly asks for another status check\n'
    fi
    if [ -n "$exit_code" ]; then
      write_line_field exit_code "$exit_code"
    fi
    if [ -n "$started_at" ]; then
      write_line_field started_at "$started_at"
    fi
    if [ -n "$elapsed" ]; then
      write_line_field elapsed_seconds "$elapsed"
    fi
    if [ -n "$command_text" ]; then
      write_line_field command "$command_text"
    fi
    write_line_field run_dir "$run_dir"
    write_line_field stdout "$run_dir/stdout.log"
    write_line_field stderr "$run_dir/stderr.log"
    write_line_field metadata "$run_dir/metadata.txt"
    write_line_field watcher_log "$run_dir/watcher.log"
    write_line_field adapter_log "$run_dir/adapter.log"
    if [ -f "$run_dir/notify.log" ]; then
      write_line_field notify_log "$run_dir/notify.log"
    fi
    if [ -f "$run_dir/resume_prompt.txt" ]; then
      write_line_field resume_prompt "$run_dir/resume_prompt.txt"
    fi
    if [ -f "$progress_path" ]; then
      progress_line=$(tail -n 1 "$progress_path" 2>/dev/null || true)
      write_line_field progress "$progress_line"
      write_line_field progress_path "$progress_path"
    fi
  }
}

list_command() {
  local runs_dir run_dir run_id status exit_code event_file elapsed command_text
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

  printf 'run_id\tstatus\texit_code\telapsed_seconds\tcommand\trun_dir\n'
  [ -d "$runs_dir" ] || return 0

  for run_dir in "$runs_dir"/lmas_*; do
    [ -d "$run_dir" ] || continue
    if [ -f "$run_dir/completion_event.txt" ]; then
      event_file="$run_dir/completion_event.txt"
      status=$(read_field "$event_file" status)
      exit_code=$(read_field "$event_file" exit_code)
    elif [ -f "$run_dir/exit_code" ] || [ -f "$run_dir/.completion_event.txt" ]; then
      event_file="$run_dir/handoff.txt"
      [ -f "$event_file" ] || continue
      if [ -f "$run_dir/exit_code" ]; then
        exit_code=$(sed -n '1p' "$run_dir/exit_code")
      else
        exit_code=$(read_field "$run_dir/.completion_event.txt" exit_code)
      fi
      status=FINALIZING
    else
      event_file="$run_dir/handoff.txt"
      [ -f "$event_file" ] || continue
      pid_or_job_id=$(read_field "$event_file" pid_or_job_id)
      if watcher_alive "$pid_or_job_id" "$run_dir"; then
        status=RUNNING
      else
        status=LOST
      fi
      exit_code=
    fi
    run_id=$(read_field "$event_file" run_id)
    elapsed=$(elapsed_seconds_for_run "$run_dir" "$status")
    command_text=$(read_metadata_field "$run_dir/metadata.txt" command)
    [ -n "$command_text" ] || command_text=$(read_field "$run_dir/handoff.txt" command)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$run_id" "$status" "$exit_code" "$elapsed" "$(short_tsv_field "$command_text")" "$(safe_tsv_field "$run_dir")"
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
    cancel)
      shift
      cancel_command "$@"
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
