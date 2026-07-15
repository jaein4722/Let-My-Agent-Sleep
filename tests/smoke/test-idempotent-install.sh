#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
unset OPENCODE_CONFIG_DIR
unset OPENCODE_CONFIG
unset OPENCODE_CONFIG_FILE
unset XDG_CONFIG_HOME
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-home.XXXXXX")
TMP_XDG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-home.XXXXXX")
TMP_XDG_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-config.XXXXXX")
TMP_XDG_OMO_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-omo-home.XXXXXX")
TMP_XDG_OMO_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-omo-config.XXXXXX")
TMP_CUSTOM_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-home.XXXXXX")
TMP_CUSTOM_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-dir.XXXXXX")
TMP_CUSTOM_CONFIG_FILE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-file-home.XXXXXX")
TMP_CUSTOM_CONFIG_FILE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-file-dir.XXXXXX")
EXPECTED_XDG_CONFIG_HOME=$(cd "$TMP_XDG_CONFIG_HOME" && pwd)
EXPECTED_XDG_OMO_CONFIG_HOME=$(cd "$TMP_XDG_OMO_CONFIG_HOME" && pwd)
EXPECTED_CUSTOM_CONFIG_DIR=$(cd "$TMP_CUSTOM_CONFIG_DIR" && pwd)
EXPECTED_CUSTOM_CONFIG_FILE_DIR=$(cd "$TMP_CUSTOM_CONFIG_FILE_DIR" && pwd)
TMP_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-jsonc-home.XXXXXX")
TMP_COMMENT_ONLY_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-comment-only-jsonc-home.XXXXXX")
TMP_REPLACE_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-replace-jsonc-home.XXXXXX")
TMP_MIXED_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-mixed-config-home.XXXXXX")
TMP_STALE_CACHE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-stale-cache-home.XXXXXX")
TMP_PLUGIN_ORDER_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-plugin-order-home.XXXXXX")
TMP_MODE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-mode-home.XXXXXX")
TMP_CODEX_HOME_OVERRIDE=$(mktemp -d "${TMPDIR:-/tmp}/lmas-codex-home.XXXXXX")
PACKAGE_VERSION=$(cd "$ROOT" && node -p "require('./packages/let-my-agent-sleep/package.json').version")

assert_jsonc_parses() {
  target=$1
  label=$2
  node --input-type=module - "$target" "$label" <<'JS'
import { readFileSync } from "node:fs"

const target = process.argv[2]
const label = process.argv[3]
const input = readFileSync(target, "utf8")

function stripJsonc(text) {
  let output = ""
  let inString = false
  let quote = ""
  let escaped = false
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]
    const next = text[index + 1]
    if (inString) {
      output += char
      if (escaped) escaped = false
      else if (char === "\\") escaped = true
      else if (char === quote) inString = false
      continue
    }
    if (char === "\"" || char === "'") {
      inString = true
      quote = char
      output += char
      continue
    }
    if (char === "/" && next === "/") {
      while (index < text.length && text[index] !== "\n") index += 1
      output += "\n"
      continue
    }
    if (char === "/" && next === "*") {
      index += 2
      while (index < text.length && !(text[index] === "*" && text[index + 1] === "/")) index += 1
      index += 1
      continue
    }
    output += char
  }
  return output.replace(/,\s*([}\]])/g, "$1")
}

try {
  JSON.parse(stripJsonc(input))
} catch (error) {
  console.error(`${label} is not parseable JSONC: ${error.message}`)
  process.exit(1)
}
JS
}

mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude"
mkdir -p "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z"
printf 'legacy global codex skill\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep/SKILL.md"
printf 'legacy named codex skill\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex/SKILL.md"
printf 'legacy named codex backup skill\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z/SKILL.md"
printf 'legacy global claude skill\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep/SKILL.md"
printf 'legacy experimental claude skill\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude/SKILL.md"
printf 'legacy experimental claude backup skill\n' > "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z/SKILL.md"

FIRST_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)
SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)
mkdir -p "$TMP_XDG_HOME/.agents/skills/let-my-agent-sleep" "$TMP_XDG_HOME/.claude/skills/let-my-agent-sleep"
printf 'codex-owned skill\n' > "$TMP_XDG_HOME/.agents/skills/let-my-agent-sleep/SKILL.md"
printf 'claude-owned skill\n' > "$TMP_XDG_HOME/.claude/skills/let-my-agent-sleep/SKILL.md"
XDG_OUTPUT=$(cd "$ROOT" && HOME="$TMP_XDG_HOME" XDG_CONFIG_HOME="$TMP_XDG_CONFIG_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_XDG_OMO_CONFIG_HOME/opencode"
cat > "$TMP_XDG_OMO_CONFIG_HOME/opencode/opencode.jsonc" <<'JSONC'
{
  "plugin": [
    ["oh-my-openagent@latest", { "keep": true }]
  ]
}
JSONC
cat > "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json" <<'JSON'
{
  "disabled_hooks": ["todo-continuation-enforcer", "user-custom-hook"],
  "disabled_skills": ["user-custom-skill"]
}
JSON
XDG_OMO_CONFIG_BEFORE=$(shasum "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json")
XDG_OMO_OUTPUT=$(cd "$ROOT" && HOME="$TMP_XDG_OMO_HOME" XDG_CONFIG_HOME="$TMP_XDG_OMO_CONFIG_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

CUSTOM_CONFIG_OUTPUT=$(cd "$ROOT" && HOME="$TMP_CUSTOM_CONFIG_HOME" OPENCODE_CONFIG_DIR="$TMP_CUSTOM_CONFIG_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)
CUSTOM_CONFIG_FILE_OUTPUT=$(cd "$ROOT" && HOME="$TMP_CUSTOM_CONFIG_FILE_HOME" OPENCODE_CONFIG="$EXPECTED_CUSTOM_CONFIG_FILE_DIR/custom-opencode.jsonc" OPENCODE_CONFIG_DIR="$EXPECTED_CUSTOM_CONFIG_FILE_DIR/assets" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_JSONC_HOME/.config/opencode"
cat > "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  // Existing user config should remain readable as JSONC.
  "model": "example/model",
}
JSONC
JSONC_OUTPUT=$(cd "$ROOT" && HOME="$TMP_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode"
cat > "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  // Comment-only config should remain valid after insertion.
}
JSONC
COMMENT_ONLY_JSONC_OUTPUT=$(cd "$ROOT" && HOME="$TMP_COMMENT_ONLY_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)
COMMENT_ONLY_JSONC_SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_COMMENT_ONLY_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_REPLACE_JSONC_HOME/.config/opencode"
cat > "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  "plugin": [
    "let-my-agent-sleep@0.1.0",
    "other-plugin"
  ], // plugin list comment should remain
  "model": "example/model"
}
JSONC
REPLACE_JSONC_OUTPUT=$(cd "$ROOT" && HOME="$TMP_REPLACE_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)
REPLACE_JSONC_SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_REPLACE_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_MIXED_CONFIG_HOME/.config/opencode"
cat > "$TMP_MIXED_CONFIG_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  "$schema": "https://opencode.ai/config.json"
}
JSONC
cat > "$TMP_MIXED_CONFIG_HOME/.config/opencode/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "let-my-agent-sleep@0.2.6"
  ]
}
JSON
MIXED_CONFIG_OUTPUT=$(cd "$ROOT" && HOME="$TMP_MIXED_CONFIG_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_PLUGIN_ORDER_HOME/.config/opencode"
cat > "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  // Existing OpenCode comments should survive tuple plugin normalization.
  "plugin": [
    "let-my-agent-sleep",
    ["let-my-agent-sleep@0.2.5", { "stale": true }],
    ["oh-my-openagent@latest", { "keep": true }]
  ], // plugin order comment should survive
  "model": "example/model"
}
JSONC
PLUGIN_ORDER_OUTPUT=$(cd "$ROOT" && HOME="$TMP_PLUGIN_ORDER_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep/node_modules/let-my-agent-sleep"
mkdir -p "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/let-my-agent-sleep"
mkdir -p "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/.bin"
cat > "$TMP_STALE_CACHE_HOME/.cache/opencode/package.json" <<'JSON'
{
  "dependencies": {
    "opencode-other-plugin": "1.0.0",
    "let-my-agent-sleep": "0.1.5"
  }
}
JSON
printf 'stale bun lock\n' > "$TMP_STALE_CACHE_HOME/.cache/opencode/bun.lock"
printf '{"version":"0.1.5"}\n' > "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/let-my-agent-sleep/package.json"
ln -s ../let-my-agent-sleep/bin/lmas-install.js "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/.bin/lmas"
ln -s ../let-my-agent-sleep/bin/lmas-install.js "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/.bin/let-my-agent-sleep"
cat > "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep/package.json" <<'JSON'
{
  "dependencies": {
    "let-my-agent-sleep": "0.1.0"
  }
}
JSON
printf 'stale lock\n' > "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep/package-lock.json"
printf '{"version":"0.1.0"}\n' > "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep/node_modules/let-my-agent-sleep/package.json"
STALE_CACHE_OUTPUT=$(cd "$ROOT" && HOME="$TMP_STALE_CACHE_HOME" OPENCODE_CACHE_DIR="$TMP_STALE_CACHE_HOME/.cache/opencode" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_HOME/.agents/plugins/plugins/let-my-agent-sleep/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep"
mkdir -p "$TMP_HOME/.agents/skills/let-my-agent-sleep.bak.20260701T000000Z"
printf 'stale plugin skill\n' > "$TMP_HOME/.agents/plugins/plugins/let-my-agent-sleep/skills/let-my-agent-sleep/SKILL.md"
printf 'legacy codex skill\n' > "$TMP_HOME/.agents/skills/let-my-agent-sleep/SKILL.md"
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
CODEX_HOME_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" CODEX_HOME="$TMP_CODEX_HOME_OVERRIDE" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex --yes)

MODE_FIRST_OUTPUT=$(cd "$ROOT" && HOME="$TMP_MODE_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex,claude --yes)
chmod 0644 "$TMP_MODE_HOME/.codex/skills/let-my-agent-sleep/bin/lmas.sh"
chmod 0644 "$TMP_MODE_HOME/.codex/skills/let-my-agent-sleep/scripts/lmas.sh"
chmod 0644 "$TMP_MODE_HOME/.claude/lmas/let-my-agent-sleep/bin/lmas.sh"
chmod 0644 "$TMP_MODE_HOME/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh"
MODE_SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_MODE_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex,claude --yes)

printf '%s\n' "$FIRST_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'first install did not complete\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] write:' || { printf 'second install did not skip unchanged writes\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy:' || { printf 'second install did not skip unchanged file copy\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy-dir:' || { printf 'second install did not skip unchanged directory copy\n' >&2; exit 1; }
printf '%s\n' "$THIRD_OUTPUT" | grep -q '\[write\] move-aside:' || { printf 'legacy codex duplicates were not moved aside\n' >&2; exit 1; }
printf '%s\n' "$MODE_FIRST_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'mode fixture install did not complete\n' >&2; exit 1; }
printf '%s\n' "$MODE_SECOND_OUTPUT" | grep -q '\[write\] copy-dir:' || { printf 'mode repair install did not recopy same-content directory with changed modes\n' >&2; exit 1; }
printf '%s\n' "$XDG_OUTPUT" | grep -Fq "$EXPECTED_XDG_CONFIG_HOME/opencode/opencode.jsonc" || { printf 'xdg opencode install did not use XDG_CONFIG_HOME config path\n' >&2; exit 1; }
printf '%s\n' "$CUSTOM_CONFIG_OUTPUT" | grep -Fq "$EXPECTED_CUSTOM_CONFIG_DIR/opencode.jsonc" || { printf 'custom opencode install did not use OPENCODE_CONFIG_DIR config path\n' >&2; exit 1; }
printf '%s\n' "$CUSTOM_CONFIG_FILE_OUTPUT" | grep -Fq "$EXPECTED_CUSTOM_CONFIG_FILE_DIR/custom-opencode.jsonc" || { printf 'custom opencode install did not use OPENCODE_CONFIG path\n' >&2; exit 1; }
printf '%s\n' "$CUSTOM_CONFIG_FILE_OUTPUT" | grep -Fq "$EXPECTED_CUSTOM_CONFIG_FILE_DIR/assets/skills/let-my-agent-sleep/SKILL.md" || { printf 'custom opencode install did not use OPENCODE_CONFIG_DIR asset path\n' >&2; exit 1; }
printf '%s\n' "$JSONC_OUTPUT" | grep -q 'opencode.jsonc' || { printf 'opencode jsonc config was not used\n' >&2; exit 1; }
printf '%s\n' "$COMMENT_ONLY_JSONC_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'comment-only opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$COMMENT_ONLY_JSONC_SECOND_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'second comment-only opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$REPLACE_JSONC_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'replace opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$REPLACE_JSONC_SECOND_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'second replace opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$MIXED_CONFIG_OUTPUT" | grep -q 'opencode.json' || { printf 'mixed opencode config did not use existing plugin-bearing json config\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'plugin order install did not complete\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'does not modify OMO disabled_hooks' || { printf 'omo plugin install did not report preservation policy\n' >&2; exit 1; }
if printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'Oh My OpenAgent continuation configured'; then
  printf 'omo plugin default install should not automatically disable continuation hooks\n' >&2
  exit 1
fi

if [ ! -f "$TMP_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'fresh opencode install did not create opencode.jsonc\n' >&2
  exit 1
fi

if [ -f "$TMP_HOME/.config/opencode/opencode.json" ]; then
  printf 'fresh opencode install should not create opencode.json\n' >&2
  exit 1
fi

if [ ! -f "$TMP_XDG_CONFIG_HOME/opencode/opencode.jsonc" ]; then
  printf 'xdg opencode install did not create config under XDG_CONFIG_HOME\n' >&2
  exit 1
fi

if [ -e "$TMP_XDG_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'xdg opencode install incorrectly wrote under HOME .config\n' >&2
  exit 1
fi
[ -f "$TMP_XDG_HOME/.agents/skills/let-my-agent-sleep/SKILL.md" ] || { printf 'opencode-only install moved a Codex-owned skill\n' >&2; exit 1; }
[ -f "$TMP_XDG_HOME/.claude/skills/let-my-agent-sleep/SKILL.md" ] || { printf 'opencode-only install moved a Claude-owned skill\n' >&2; exit 1; }

XDG_OMO_CONFIG_AFTER=$(shasum "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json")
[ "$XDG_OMO_CONFIG_BEFORE" = "$XDG_OMO_CONFIG_AFTER" ] || { printf 'opencode install modified existing OMO config\n' >&2; exit 1; }

if [ -e "$TMP_XDG_OMO_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'xdg opencode install incorrectly created OMO config under HOME .config\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CUSTOM_CONFIG_DIR/opencode.jsonc" ]; then
  printf 'custom opencode install did not create config under OPENCODE_CONFIG_DIR\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_DIR/oh-my-openagent.json" ]; then
  printf 'custom opencode install should not create OMO config\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CUSTOM_CONFIG_FILE_DIR/custom-opencode.jsonc" ]; then
  printf 'custom opencode install did not create OPENCODE_CONFIG target\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_FILE_DIR/assets/oh-my-openagent.json" ]; then
  printf 'custom opencode install should not create OMO config under OPENCODE_CONFIG_DIR\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CUSTOM_CONFIG_FILE_DIR/assets/skills/let-my-agent-sleep/SKILL.md" ]; then
  printf 'custom opencode install did not install skill under OPENCODE_CONFIG_DIR\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'custom opencode install incorrectly wrote under HOME .config\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'custom opencode install incorrectly created OMO config under HOME .config\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_FILE_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'custom OPENCODE_CONFIG install incorrectly wrote under HOME .config\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_FILE_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'custom OPENCODE_CONFIG install incorrectly created OMO config under HOME .config\n' >&2
  exit 1
fi

if ! grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode jsonc config missing plugin entry\n' >&2
  exit 1
fi

if ! grep -q 'Existing user config should remain readable as JSONC' "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode jsonc config comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc" "opencode jsonc config"

if ! grep -q 'Comment-only config should remain valid after insertion' "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'comment-only opencode jsonc comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode/opencode.jsonc" "comment-only opencode jsonc"

if ! grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'comment-only opencode jsonc missing plugin entry\n' >&2
  exit 1
fi

if ! grep -q 'plugin list comment should remain' "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc trailing comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc" "replace opencode jsonc"

if ! grep -q '"other-plugin"' "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc lost existing plugin\n' >&2
  exit 1
fi

if ! grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc missing latest plugin entry\n' >&2
  exit 1
fi

if grep -q '"let-my-agent-sleep@0.1.0"' "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc kept stale lmas plugin entry\n' >&2
  exit 1
fi

if ! grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_MIXED_CONFIG_HOME/.config/opencode/opencode.json"; then
  printf 'mixed opencode json config missing latest plugin entry\n' >&2
  exit 1
fi

if grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_MIXED_CONFIG_HOME/.config/opencode/opencode.jsonc"; then
  printf 'mixed opencode install wrote plugin entry to inactive jsonc config\n' >&2
  exit 1
fi

if ! grep -q "\"let-my-agent-sleep@$PACKAGE_VERSION\"" "$TMP_HOME/.config/opencode/opencode.jsonc"; then
  printf 'fresh opencode config missing exact plugin entry\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.cache/opencode/package.json" ]; then
  printf 'fresh opencode install should leave plugin cache creation to OpenCode\n' >&2
  exit 1
fi

[ ! -e "$TMP_HOME/.config/opencode/oh-my-openagent.json" ] || { printf 'fresh opencode install created OMO config\n' >&2; exit 1; }

if grep -q '"let-my-agent-sleep"' "$TMP_HOME/.config/opencode/opencode.jsonc"; then
  printf 'fresh opencode config should not keep bare plugin entry\n' >&2
  exit 1
fi

PLUGIN_ORDER=$(node --input-type=module - "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc" <<'JS'
import { readFileSync } from "node:fs"

function stripJsonc(text) {
  let output = ""
  let inString = false
  let quote = ""
  let escaped = false
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]
    const next = text[index + 1]
    if (inString) {
      output += char
      if (escaped) escaped = false
      else if (char === "\\") escaped = true
      else if (char === quote) inString = false
      continue
    }
    if (char === "\"" || char === "'") {
      inString = true
      quote = char
      output += char
      continue
    }
    if (char === "/" && next === "/") {
      while (index < text.length && text[index] !== "\n") index += 1
      output += "\n"
      continue
    }
    if (char === "/" && next === "*") {
      index += 2
      while (index < text.length && !(text[index] === "*" && text[index + 1] === "/")) index += 1
      index += 1
      continue
    }
    output += char
  }
  return output.replace(/,\s*([}\]])/g, "$1")
}

const config = JSON.parse(stripJsonc(readFileSync(process.argv[2], "utf8")))
console.log(config.plugin.map((plugin) => Array.isArray(plugin) ? plugin[0] : plugin).join("\n"))
JS
)

EXPECTED_PLUGIN_ORDER=$(printf '%s\n%s\n' "let-my-agent-sleep@$PACKAGE_VERSION" 'oh-my-openagent@latest')
if [ "$PLUGIN_ORDER" != "$EXPECTED_PLUGIN_ORDER" ]; then
  printf 'opencode plugin order was not normalized with LMAS first\n' >&2
  printf 'got:\n%s\n' "$PLUGIN_ORDER" >&2
  exit 1
fi
if ! grep -q '"keep": true' "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode plugin tuple options were not preserved\n' >&2
  exit 1
fi
if ! grep -q 'Existing OpenCode comments should survive tuple plugin normalization' "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode tuple plugin config top-level comment was not preserved\n' >&2
  exit 1
fi
if ! grep -q 'plugin order comment should survive' "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode tuple plugin config trailing comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc" "tuple plugin opencode jsonc"
if grep -q '"stale": true' "$TMP_PLUGIN_ORDER_HOME/.config/opencode/opencode.jsonc"; then
  printf 'opencode stale LMAS tuple was not removed\n' >&2
  exit 1
fi

[ ! -e "$TMP_PLUGIN_ORDER_HOME/.config/opencode/oh-my-openagent.json" ] || { printf 'OMO plugin detection created an OMO config\n' >&2; exit 1; }

ROOT_CACHE_VERSION=$(node -p "require(process.argv[1]).dependencies['let-my-agent-sleep']" "$TMP_STALE_CACHE_HOME/.cache/opencode/package.json")

if [ "$ROOT_CACHE_VERSION" != "0.1.5" ]; then
  printf 'opencode install modified the OpenCode-managed root cache package\n' >&2
  exit 1
fi

if [ ! -e "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep" ]; then
  printf 'opencode install removed an OpenCode-managed versioned package cache\n' >&2
  exit 1
fi

if [ ! -e "$TMP_STALE_CACHE_HOME/.cache/opencode/bun.lock" ]; then
  printf 'opencode shared bun.lock should be preserved\n' >&2
  exit 1
fi

if [ ! -e "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/let-my-agent-sleep" ]; then
  printf 'opencode install removed an OpenCode-managed root node_modules package\n' >&2
  exit 1
fi

if [ ! -L "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/.bin/lmas" ]; then
  printf 'opencode install removed an OpenCode-managed lmas bin link\n' >&2
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

if [ -e "$TMP_HOME/.agents/skills/let-my-agent-sleep" ]; then
  printf 'legacy codex skill still exists under OpenCode-colliding name\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex" ]; then
  printf 'codex skill should not be installed under OpenCode-discovered .agents skills\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.agents/skills/let-my-agent-sleep-codex.bak.20260701T000000Z" ]; then
  printf 'legacy renamed codex backup still exists in discoverable skills dir\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.claude/skills/let-my-agent-sleep" ]; then
  printf 'legacy claude skill still exists under OpenCode-colliding name\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude" ]; then
  printf 'experimental claude skill should not remain under OpenCode-discovered .claude skills\n' >&2
  exit 1
fi

if [ -e "$TMP_HOME/.claude/skills/let-my-agent-sleep-claude.bak.20260701T000000Z" ]; then
  printf 'legacy renamed claude backup still exists in discoverable skills dir\n' >&2
  exit 1
fi

if grep -q 'let-my-agent-sleep' "$TMP_HOME/.agents/plugins/marketplace.json"; then
  printf 'legacy codex marketplace entry still exists\n' >&2
  exit 1
fi

if find "$TMP_HOME/.config/opencode" "$TMP_HOME/.agents/skills" "$TMP_HOME/.agents/plugins" "$TMP_HOME/.claude/skills" -name '*.bak.*' -print -quit | grep -q .; then
  printf 'discoverable backup files still exist after idempotent install\n' >&2
  exit 1
fi

if [ ! -f "$TMP_HOME/.claude/commands/let-my-agent-sleep.md" ]; then
  printf 'claude command was not installed\n' >&2
  exit 1
fi

if [ ! -f "$TMP_HOME/.codex/skills/let-my-agent-sleep/SKILL.md" ]; then
  printf 'codex skill was not installed\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CODEX_HOME_OVERRIDE/skills/let-my-agent-sleep/SKILL.md" ]; then
  printf 'codex skill was not installed under CODEX_HOME\n' >&2
  exit 1
fi

if [ ! -x "$TMP_MODE_HOME/.codex/skills/let-my-agent-sleep/bin/lmas.sh" ]; then
  printf 'codex skill bin/lmas.sh executable mode was not repaired\n' >&2
  exit 1
fi

if [ ! -x "$TMP_MODE_HOME/.codex/skills/let-my-agent-sleep/scripts/lmas.sh" ]; then
  printf 'codex skill wrapper executable mode was not repaired\n' >&2
  exit 1
fi
if find "$TMP_MODE_HOME/.codex/skills" -name 'let-my-agent-sleep.bak.*' -print -quit | grep -q .; then
  printf 'Codex skill backup remained in the discoverable skills directory\n' >&2
  exit 1
fi
find "$TMP_MODE_HOME/.codex/lmas-backups/skills" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q . || {
  printf 'Codex skill repair did not preserve an out-of-band backup\n' >&2
  exit 1
}

if [ ! -x "$TMP_MODE_HOME/.claude/lmas/let-my-agent-sleep/bin/lmas.sh" ]; then
  printf 'claude asset bin/lmas.sh executable mode was not repaired\n' >&2
  exit 1
fi

if [ ! -x "$TMP_MODE_HOME/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh" ]; then
  printf 'claude asset wrapper executable mode was not repaired\n' >&2
  exit 1
fi

CODEX_SCRIPT_OUTPUT=$(cd / && HOME="$TMP_HOME" "$TMP_HOME/.codex/skills/let-my-agent-sleep/scripts/lmas.sh" -h 2>&1)
printf '%s\n' "$CODEX_SCRIPT_OUTPUT" | grep -q '^Usage:' || {
  printf 'installed codex skill script could not find bin/lmas.sh outside the repo\n' >&2
  exit 1
}

CLAUDE_SCRIPT_OUTPUT=$(cd / && HOME="$TMP_HOME" "$TMP_HOME/.claude/lmas/let-my-agent-sleep/scripts/lmas.sh" -h 2>&1)
printf '%s\n' "$CLAUDE_SCRIPT_OUTPUT" | grep -q '^Usage:' || {
  printf 'installed claude command asset script could not find bin/lmas.sh outside the repo\n' >&2
  exit 1
}

printf 'ok idempotent install\n'
