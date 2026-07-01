#!/usr/bin/env bash
set -u

mode=${1:-success}

case "$mode" in
  success)
    printf 'fake_train: starting success run\n'
    sleep 0.2
    printf 'metric.accuracy=0.91\n'
    printf 'fake_train: completed\n'
    ;;
  fail)
    printf 'fake_train: starting failed run\n'
    sleep 0.2
    printf 'fake_train: simulated failure\n' >&2
    exit 7
    ;;
  sleep)
    seconds=${2:-2}
    printf 'fake_train: sleeping for %s seconds\n' "$seconds"
    sleep "$seconds"
    printf 'fake_train: woke up\n'
    ;;
  *)
    printf 'unknown fake_train mode: %s\n' "$mode" >&2
    exit 2
    ;;
esac
