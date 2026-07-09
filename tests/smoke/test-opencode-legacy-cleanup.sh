#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-opencode-legacy-home.XXXXXX")
trap 'rm -rf "$TMP_HOME"' EXIT

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
  if [ -e "$path" ]; then
    printf 'legacy cross-agent skill still exists after opencode-only install: %s\n' "$path" >&2
    exit 1
  fi
done

for path in \
  "$TMP_HOME/.agents/lmas-backups/skills/let-my-agent-sleep."* \
  "$TMP_HOME/.agents/lmas-backups/skills/let-my-agent-sleep-codex."* \
  "$TMP_HOME/.agents/lmas-backups/skills/let-my-agent-sleep-codex.bak.20260701T000000Z."* \
  "$TMP_HOME/.claude/lmas-backups/skills/let-my-agent-sleep."* \
  "$TMP_HOME/.claude/lmas-backups/skills/let-my-agent-sleep-claude."* \
  "$TMP_HOME/.claude/lmas-backups/skills/let-my-agent-sleep-claude.bak.20260701T000000Z."*
do
  if [ ! -e "$path" ]; then
    printf 'legacy cross-agent skill was not backed up: %s\n' "$path" >&2
    exit 1
  fi
done

grep -q '"let-my-agent-sleep-codex"' "$TMP_HOME/.config/opencode/oh-my-openagent.json" || {
  printf 'opencode install did not add legacy codex skill to OMO disabled_skills\n' >&2
  exit 1
}
grep -q '"let-my-agent-sleep-claude"' "$TMP_HOME/.config/opencode/oh-my-openagent.json" || {
  printf 'opencode install did not add legacy claude skill to OMO disabled_skills\n' >&2
  exit 1
}

printf 'ok opencode legacy cleanup\n'
