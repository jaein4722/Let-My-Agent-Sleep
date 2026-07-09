#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

tests=(
  tests/smoke/test-basic-handoff.sh
  tests/smoke/test-success-completion.sh
  tests/smoke/test-failed-completion.sh
  tests/smoke/test-status-list.sh
  tests/smoke/test-cancel.sh
  tests/smoke/test-omo-guard.sh
  tests/smoke/test-opencode-plugin-guard.sh
  tests/smoke/test-opencode-plugin-real-import.sh
  tests/smoke/test-packed-opencode-plugin-import.sh
  tests/smoke/test-opencode-adapter.sh
  tests/smoke/test-codex-adapter.sh
  tests/smoke/test-claude-adapter.sh
  tests/smoke/test-doctor.sh
  tests/smoke/test-installer-dry-run.sh
  tests/smoke/test-idempotent-install.sh
  tests/smoke/test-opencode-legacy-cleanup.sh
  tests/smoke/test-package-metadata.sh
  tests/smoke/test-packaged-assets.sh
  tests/smoke/test-packed-tarball-cli.sh
)

while IFS= read -r discovered; do
  relative=${discovered#"$ROOT/"}
  listed=0
  for test_script in "${tests[@]}"; do
    if [ "$test_script" = "$relative" ]; then
      listed=1
      break
    fi
  done
  if [ "$listed" -eq 0 ]; then
    printf 'smoke test is not listed in tests/smoke/run.sh: %s\n' "$relative" >&2
    exit 1
  fi
done < <(find "$ROOT/tests/smoke" -maxdepth 1 -type f -name 'test-*.sh' -print | sort)

for test_script in "${tests[@]}"; do
  "$ROOT/$test_script"
done
