#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-doctor-home.XXXXXX")
trap 'rm -rf "$TMP_HOME"' EXIT

INSTALL_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'OpenCode install configured' || {
  printf 'opencode install did not complete before doctor test\n' >&2
  exit 1
}

DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes)
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'Let My Agent Sleep doctor passed' || {
  printf 'doctor did not pass after opencode install\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'let-my-agent-sleep is first in the OpenCode plugin list' || {
  printf 'doctor did not verify LMAS-first plugin order\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'OMO continuation hooks are disabled' || {
  printf 'doctor did not verify OMO continuation hooks\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}

node --input-type=module - "$TMP_HOME/.config/opencode/opencode.jsonc" <<'JS'
import { readFileSync, writeFileSync } from "node:fs"

const target = process.argv[2]
const config = JSON.parse(readFileSync(target, "utf8"))
config.plugin = ["oh-my-openagent@latest", ...config.plugin.filter((item) => item !== "oh-my-openagent@latest")]
writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`)
JS

if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes >/tmp/lmas-doctor-fail.out 2>&1; then
  printf 'doctor should fail when Oh My OpenAgent loads before LMAS\n' >&2
  cat /tmp/lmas-doctor-fail.out >&2
  exit 1
fi

grep -q 'is not first in the OpenCode plugin list' /tmp/lmas-doctor-fail.out || {
  printf 'doctor failure did not explain plugin order problem\n' >&2
  cat /tmp/lmas-doctor-fail.out >&2
  exit 1
}

printf 'ok doctor\n'
