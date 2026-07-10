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
OPENCODE_SKILL="$PKG/skills/let-my-agent-sleep/SKILL.md"
CODEX_SKILL="$PKG/codex-plugin/let-my-agent-sleep/skills/let-my-agent-sleep/SKILL.md"
CODEX_PLUGIN_MANIFEST="$PKG/codex-plugin/let-my-agent-sleep/.codex-plugin/plugin.json"
CODEX_PROTOCOL="$PKG/codex-plugin/let-my-agent-sleep/skills/let-my-agent-sleep/references/protocol.md"
ROOT_PROTOCOL="$ROOT/docs/protocol.md"
ROOT_CHANGELOG="$ROOT/CHANGELOG.md"
PACKAGE_CHANGELOG="$PKG/CHANGELOG.md"
ROOT_README="$ROOT/README.md"
PACKAGE_README="$PKG/README.md"
GITIGNORE="$ROOT/.gitignore"

[ -x "$PKG/bin/lmas-install.js" ] || { printf 'lmas-install.js is not executable\n' >&2; exit 1; }
[ -x "$CANONICAL" ] || { printf 'canonical lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_PLUGIN_BIN" ] || { printf 'codex plugin lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_SKILL_BIN" ] || { printf 'codex skill lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CLAUDE_ASSET_BIN" ] || { printf 'claude asset lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CODEX_WRAPPER" ] || { printf 'codex wrapper lmas.sh is not executable\n' >&2; exit 1; }
[ -x "$CLAUDE_WRAPPER" ] || { printf 'claude wrapper lmas.sh is not executable\n' >&2; exit 1; }
[ -f "$OPENCODE_SKILL" ] || { printf 'opencode skill was not packaged\n' >&2; exit 1; }
[ -f "$CODEX_SKILL" ] || { printf 'codex skill was not packaged\n' >&2; exit 1; }
[ -f "$CLAUDE_COMMAND" ] || { printf 'claude command was not packaged\n' >&2; exit 1; }
[ -f "$CODEX_PLUGIN_MANIFEST" ] || { printf 'codex plugin manifest was not packaged\n' >&2; exit 1; }
[ -f "$CODEX_PROTOCOL" ] || { printf 'codex protocol reference was not packaged\n' >&2; exit 1; }
[ -f "$ROOT_PROTOCOL" ] || { printf 'root protocol doc is missing\n' >&2; exit 1; }
[ -f "$ROOT_CHANGELOG" ] || { printf 'root CHANGELOG.md is missing\n' >&2; exit 1; }
[ -f "$PACKAGE_CHANGELOG" ] || { printf 'package CHANGELOG.md is missing\n' >&2; exit 1; }
[ -f "$ROOT_README" ] || { printf 'root README.md is missing\n' >&2; exit 1; }
[ -f "$PACKAGE_README" ] || { printf 'package README.md is missing\n' >&2; exit 1; }
[ -f "$GITIGNORE" ] || { printf '.gitignore is missing\n' >&2; exit 1; }

cmp -s "$CANONICAL" "$CODEX_PLUGIN_BIN" || { printf 'codex plugin bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$CANONICAL" "$CODEX_SKILL_BIN" || { printf 'codex skill bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$CANONICAL" "$CLAUDE_ASSET_BIN" || { printf 'claude asset bin/lmas.sh differs from canonical bin/lmas.sh\n' >&2; exit 1; }
cmp -s "$ROOT_CHANGELOG" "$PACKAGE_CHANGELOG" || { printf 'package CHANGELOG.md differs from root CHANGELOG.md\n' >&2; exit 1; }
grep -q 'site/social-card.png' "$ROOT_README" || { printf 'root README.md must use the PNG social card preview\n' >&2; exit 1; }
grep -q 'https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png' "$PACKAGE_README" || {
  printf 'package README.md must use the absolute PNG social card preview\n' >&2
  exit 1
}
python3 - "$ROOT_README" "$PACKAGE_README" <<'PY'
from pathlib import Path
import sys

root_readme, package_readme = map(Path, sys.argv[1:])
expected = root_readme.read_text().replace(
    'src="site/social-card.png"',
    'src="https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png"',
).replace(
    '<h1>Let My Agent Sleep</h1>',
    '<h1>let-my-agent-sleep</h1>',
)
actual = package_readme.read_text()

if actual != expected:
    sys.stderr.write(
        "package README.md must match root README.md except for npm-safe absolute media paths and package-name heading\n"
    )
    sys.exit(1)
PY
for protocol in "$ROOT_PROTOCOL" "$CODEX_PROTOCOL"; do
  grep -q 'LMAS_CANCEL v1' "$protocol" || { printf '%s missing cancel event contract\n' "$protocol" >&2; exit 1; }
  grep -q 'status: CANCELLED' "$protocol" || { printf '%s missing CANCELLED cancel status contract\n' "$protocol" >&2; exit 1; }
  grep -q 'status: ALREADY_COMPLETED' "$protocol" || { printf '%s missing ALREADY_COMPLETED cancel status contract\n' "$protocol" >&2; exit 1; }
  grep -q 'status: LOST' "$protocol" || { printf '%s missing LOST cancel status contract\n' "$protocol" >&2; exit 1; }
  grep -q 'FINALIZING' "$protocol" || { printf '%s missing FINALIZING status contract\n' "$protocol" >&2; exit 1; }
  grep -q 'completion_event' "$protocol" || { printf '%s missing cancel completion_event field\n' "$protocol" >&2; exit 1; }
  grep -q 'resume_prompt' "$protocol" || { printf '%s missing cancel resume_prompt field\n' "$protocol" >&2; exit 1; }
  grep -q 'Secondary Notification' "$protocol" || { printf '%s missing secondary notification section\n' "$protocol" >&2; exit 1; }
done
grep -q '^\.lmas/$' "$GITIGNORE" || { printf '.gitignore must exclude LMAS runtime runs\n' >&2; exit 1; }
grep -q '^\*\.tgz$' "$GITIGNORE" || { printf '.gitignore must exclude npm pack tarballs\n' >&2; exit 1; }
grep -q '^__pycache__/$' "$GITIGNORE" || { printf '.gitignore must exclude Python bytecode caches\n' >&2; exit 1; }

for instruction in "$OPENCODE_SKILL" "$CODEX_SKILL" "$CLAUDE_COMMAND"; do
  grep -q 'HARD RULE: DO NOT POLL AFTER HANDOFF' "$instruction" || { printf '%s missing hard no-poll heading\n' "$instruction" >&2; exit 1; }
  grep -q 'DO NOT POLL' "$instruction" || { printf '%s missing explicit no-poll rule\n' "$instruction" >&2; exit 1; }
  grep -q 'DO NOT TAIL LOGS' "$instruction" || { printf '%s missing no-tail rule\n' "$instruction" >&2; exit 1; }
  grep -q 'DO NOT INSPECT ARTIFACTS' "$instruction" || { printf '%s missing no-artifact-inspection rule\n' "$instruction" >&2; exit 1; }
  grep -q 'DO NOT CONTINUE THE LOOP JUST BECAUSE A TODO IS STILL OPEN' "$instruction" || { printf '%s missing no-TODO-continuation rule\n' "$instruction" >&2; exit 1; }
  grep -q 'start with LMAS and record handoff' "$instruction" || { printf '%s missing TODO scoping instruction\n' "$instruction" >&2; exit 1; }
  grep -q 'cancel' "$instruction" || { printf '%s missing cancel instruction\n' "$instruction" >&2; exit 1; }
  grep -q 'LOST' "$instruction" || { printf '%s missing LOST recovery instruction\n' "$instruction" >&2; exit 1; }
  grep -q 'FINALIZING' "$instruction" || { printf '%s missing FINALIZING stop instruction\n' "$instruction" >&2; exit 1; }
  grep -q 'resume_prompt.txt' "$instruction" || { printf '%s missing resume_prompt fallback instruction\n' "$instruction" >&2; exit 1; }
done

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
