#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PKG="$ROOT/packages/let-my-agent-sleep"

CANONICAL="$PKG/bin/lmas.sh"
CODEX_PLUGIN_BIN="$PKG/codex-plugin/let-my-agent-sleep/bin/lmas.sh"
CODEX_SKILL_BIN="$PKG/codex-plugin/let-my-agent-sleep/skills/let-my-agent-sleep/bin/lmas.sh"
CLAUDE_ASSET_BIN="$PKG/claude/let-my-agent-sleep/assets/bin/lmas.sh"
CODEX_WRAPPER="$PKG/codex-plugin/let-my-agent-sleep/skills/let-my-agent-sleep/scripts/lmas.sh"
CLAUDE_WRAPPER="$PKG/claude/let-my-agent-sleep/assets/scripts/lmas.sh"
CLAUDE_COMMAND="$PKG/claude/let-my-agent-sleep/commands/let-my-agent-sleep.md"
CODEX_PLUGIN_MANIFEST="$PKG/codex-plugin/let-my-agent-sleep/.codex-plugin/plugin.json"
ROOT_CHANGELOG="$ROOT/CHANGELOG.md"
PACKAGE_CHANGELOG="$PKG/CHANGELOG.md"

[ -x "$PKG/bin/lmas-install.js" ] || { printf 'lmas-install.js is not executable\n' >&2; exit 1; }
[ -x "$CANONICAL" ] || { printf 'canonical lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_PLUGIN_BIN" ] || { printf 'codex plugin lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_SKILL_BIN" ] || { printf 'codex skill lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CLAUDE_ASSET_BIN" ] || { printf 'claude asset lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_WRAPPER" ] || { printf 'codex wrapper lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CLAUDE_WRAPPER" ] || { printf 'claude wrapper lmas.sh is not executable\n' >&2; exit 1; }
[ -f "$CLAUDE_COMMAND" ] || { printf 'claude command was not packaged\n' >&2; exit 1; }
[ -f "$CODEX_PLUGIN_MANIFEST" ] || { printf 'codex plugin manifest was not packaged\n' >&2; exit 1; }
[ -f "$ROOT_CHANGELOG" ] || { printf 'root CHANGELOG.md is missing\n' >&2; exit 1; }
[ -f "$PACKAGE_CHANGELOG" ] || { printf 'package CHANGELOG.md is missing\n' >&2; exit 1; }

cmp -s "$CANONICAL" "$CODEX_PLUGIN_BIN" || { printf 'codex plugin bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$CANONICAL" "$CODEX_SKILL_BIN" || { printf 'codex skill bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$CANONICAL" "$CLAUDE_ASSET_BIN" || { printf 'claude asset bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$ROOT_CHANGELOG" "$PACKAGE_CHANGELOG" || { printf 'package CHANGELOG.md differs from root CHANGELOG.md\n' >&2; exit 1; }

CODEX_WRAPPER_OUTPUT=$(cd / && "$CODEX_WRAPPER" -h 2>&1)
printf '%s\n' "$CODEX_WRAPPER_OUTPUT" | grep -q '^Usage:' || {
  printf 'codex skill wrapper could not resolve packaged bin/lmas.sh outside the repo\n' >&2
  exit 1
}

CLAUDE_WRAPPER_OUTPUT=$(cd / && "$CLAUDE_WRAPPER" -h 2>&1)
printf '%s\n' "$CLAUDE_WRAPPER_OUTPUT" | grep -q '^Usage:' || {
  printf 'claude command asset wrapper could not resolve packaged bin/lmas.sh outside the repo\n' >&2
  exit 1
}

PACKAGE_VERSION=$(node -p "require(process.argv[1]).version" "$PKG/package.json")
MANIFEST_VERSION=$(node -p "require(process.argv[1]).version" "$CODEX_PLUGIN_MANIFEST")
[ "$MANIFEST_VERSION" = "$PACKAGE_VERSION" ] || {
  printf 'codex plugin manifest version %s does not match package version %s\n' "$MANIFEST_VERSION" "$PACKAGE_VERSION" >&2
  exit 1
}

printf 'ok packaged assets\n'
