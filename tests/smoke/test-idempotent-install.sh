#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-home.XXXXXX")
TMP_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-jsonc-home.XXXXXX")

FIRST_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)
SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)

mkdir -p "$TMP_JSONC_HOME/.config/opencode"
cat > "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  // Existing user config should remain readable as JSONC.
  "model": "example/model",
}
JSONC
JSONC_OUTPUT=$(cd "$ROOT" && HOME="$TMP_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_HOME/.agents/plugins/plugins/let-my-agent-sleep/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep.bak.20260701T000000Z"
printf 'stale plugin skill\n' > "$TMP_HOME/.agents/plugins/plugins/let-my-agent-sleep/skills/let-my-agent-sleep/SKILL.md"
printf 'stale backup skill\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep.bak.20260701T000000Z/SKILL.md"
cat > "$TMP_HOME/.agents/plugins/marketplace.json" <<'JSON'
{
  "name": "personal",
  "interface": {
    "displayName": "Personal"
  },
  "plugins": [
    {
      "name": "let-my-agent-sleep",
      "source": {
        "source": "local",
        "path": "./plugins/let-my-agent-sleep"
      }
    }
  ]
}
JSON
THIRD_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex --yes)

printf '%s\n' "$FIRST_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'first install did not complete\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] write:' || { printf 'second install did not skip unchanged writes\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy:' || { printf 'second install did not skip unchanged file copy\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy-dir:' || { printf 'second install did not skip unchanged directory copy\n' >&2; exit 1; }
printf '%s\n' "$THIRD_OUTPUT" | grep -q '\[write\] move-aside:' || { printf 'legacy codex duplicates were not moved aside\n' >&2; exit 1; }
printf '%s\n' "$JSONC_OUTPUT" | grep -q 'opencode.jsonc' || { printf 'opencode jsonc config was not used\n' >&2; exit 1; }

if [ ! -f "$TMP_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'fresh opencode install did not create opencode.jsonc\n' >&2
  exit 1
fi

if [ -f "$TMP_HOME/.config/opencode/opencode.json" ]; then
  printf 'fresh opencode install should not create opencode.json\n' >&2
  exit 1
fi

if ! grep -q '"let-my-agent-sleep"' "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode jsonc config missing plugin entry\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.agents/plugins/plugins/let-my-agent-sleep" ]; then
  printf 'legacy codex plugin still exists\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.agents/skills/let-my-agent-sleep.bak.20260701T000000Z" ]; then
  printf 'legacy skill backup still exists in discoverable skills dir\n' >&2
  exit 1
fi

if grep -q 'let-my-agent-sleep' "$TMP_HOME/.agents/plugins/marketplace.json"; then
  printf 'legacy codex marketplace entry still exists\n' >&2
  exit 1
fi

if find "$TMP_HOME/.config/opencode" "$TMP_HOME/.agents/skills" "$TMP_HOME/.agents/plugins" -name '*.bak.*' -print -quit | grep -q .; then
  printf 'discoverable backup files still exist after idempotent install\n' >&2
  exit 1
fi

if [ ! -f "$TMP_HOME/.claude/skills/let-my-agent-sleep/SKILL.md" ]; then
  printf 'claude skill was not installed\n' >&2
  exit 1
fi

CLAUDE_SCRIPT_OUTPUT=$(cd / && HOME="$TMP_HOME" "$TMP_HOME/.claude/skills/let-my-agent-sleep/scripts/lmas.sh" -h 2>&1)
printf '%s\n' "$CLAUDE_SCRIPT_OUTPUT" | grep -q '^Usage:' || {
  printf 'installed claude skill script could not find bin/lmas.sh outside the repo\n' >&2
  exit 1
}

printf 'ok idempotent install\n'
