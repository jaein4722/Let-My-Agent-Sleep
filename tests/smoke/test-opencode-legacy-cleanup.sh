#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-opencode-legacy-home.XXXXXX")
trap 'rm -rf "$TMP_HOME"' EXIT

unset OPENCODE_CONFIG OPENCODE_CONFIG_FILE OPENCODE_CONFIG_DIR OPENCODE_CACHE_DIR
export HOME="$TMP_HOME"
export XDG_CONFIG_HOME="$TMP_HOME/.config"
export XDG_CACHE_HOME="$TMP_HOME/.cache"

mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z"
printf 'legacy codex default\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep/SKILL.md"
printf 'legacy codex renamed\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex/SKILL.md"
printf 'legacy codex renamed backup\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z/SKILL.md"
printf 'legacy claude default\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep/SKILL.md"
printf 'legacy claude renamed\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude/SKILL.md"
printf 'legacy claude renamed backup\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z/SKILL.md"

OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

printf '%s\n' "$OUTPUT" | grep -q 'OpenCode install configured' || {
  printf 'opencode install did not complete\n' >&2
  exit 1
}

for path in \
  "$TMP_HOME/.agents/skills/let-my-agent-sleep" \
  "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex" \
  "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z" \
  "$TMP_HOME/.claude/skills/let-my-agent-sleep" \
  "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude" \
  "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z"
do
  if [ ! -e "$path" ]; then
    printf 'opencode-only install moved another agent\x27s skill: %s\n' "$path" >&2
    exit 1
  fi
done

if [ -e "$TMP_HOME/.agents/lmas-backups" ] || [ -e "$TMP_HOME/.claude/lmas-backups" ]; then
  printf 'opencode-only install created cross-agent backup directories\n' >&2
  exit 1
fi
if [ -e "$TMP_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'opencode-only install created an OMO config\n' >&2
  exit 1
fi

printf 'ok opencode cross-agent preservation\n'
