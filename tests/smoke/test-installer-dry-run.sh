#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

OPENCODE_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --dry-run --yes)
CODEX_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex --dry-run --yes)
CLAUDE_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent claude --dry-run --yes)
DETECTED_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent detected --dry-run --yes)

printf '%s\n' "$OPENCODE_OUTPUT" | grep -q 'plugin: let-my-agent-sleep' || { printf 'opencode dry-run missing plugin config\n' >&2; exit 1; }
printf '%s\n' "$OPENCODE_OUTPUT" | grep -q '.config/opencode/skills/let-my-agent-sleep/SKILL.md' || { printf 'opencode dry-run missing skill target\n' >&2; exit 1; }
printf '%s\n' "$CODEX_OUTPUT" | grep -q '.agents/skills/let-my-agent-sleep' || { printf 'codex dry-run missing skill target\n' >&2; exit 1; }
printf '%s\n' "$CODEX_OUTPUT" | grep -q 'plugin: not installed' || { printf 'codex dry-run should avoid plugin install\n' >&2; exit 1; }
printf '%s\n' "$CLAUDE_OUTPUT" | grep -q '.claude/skills/let-my-agent-sleep' || { printf 'claude dry-run missing skill target\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'detected dry-run did not complete\n' >&2; exit 1; }

printf 'ok installer dry-run\n'
