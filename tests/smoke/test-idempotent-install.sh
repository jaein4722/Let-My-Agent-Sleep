#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
unset OPENCODE_CONFIG_DIR
unset OPENCODE_CONFIG_FILE
unset XDG_CONFIG_HOME
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-home.XXXXXX")
TMP_XDG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-home.XXXXXX")
TMP_XDG_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-config.XXXXXX")
TMP_XDG_OMO_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-omo-home.XXXXXX")
TMP_XDG_OMO_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-xdg-omo-config.XXXXXX")
TMP_CUSTOM_CONFIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-home.XXXXXX")
TMP_CUSTOM_CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-custom-config-dir.XXXXXX")
EXPECTED_XDG_CONFIG_HOME=$(cd "$TMP_XDG_CONFIG_HOME" && pwd)
EXPECTED_XDG_OMO_CONFIG_HOME=$(cd "$TMP_XDG_OMO_CONFIG_HOME" && pwd)
EXPECTED_CUSTOM_CONFIG_DIR=$(cd "$TMP_CUSTOM_CONFIG_DIR" && pwd)
TMP_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-jsonc-home.XXXXXX")
TMP_COMMENT_ONLY_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-comment-only-jsonc-home.XXXXXX")
TMP_REPLACE_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-replace-jsonc-home.XXXXXX")
TMP_STALE_CACHE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-stale-cache-home.XXXXXX")
TMP_OMO_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-omo-home.XXXXXX")
TMP_OMO_COMMENT_ONLY_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-omo-comment-only-home.XXXXXX")
TMP_OMO_JSONC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-omo-jsonc-home.XXXXXX")
TMP_PLUGIN_ORDER_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-plugin-order-home.XXXXXX")
TMP_PLUGIN_ORDER_DISABLE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-plugin-order-disable-home.XXXXXX")
TMP_PLUGIN_ORDER_KEEP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-plugin-order-keep-home.XXXXXX")
TMP_MODE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-mode-home.XXXXXX")
TMP_CODEX_HOME_OVERRIDE=$(mktemp -d "${TMPDIR:-/tmp}/lmas-codex-home.XXXXXX")
PACKAGE_VERSION=$(cd "$ROOT" && node -p "require('./packages/let-my-agent-sleep/package.json').version")
EXPECTED_OMO_HOOKS="todo-continuation-enforcer ralph-loop ulw-loop ultrawork start-work-continuation boulder-continuation unstable-agent-babysitter atlas"
EXPECTED_OMO_HIDDEN_SKILLS="let-my-agent-sleep-codex let-my-agent-sleep-claude"

assert_output_mentions_omo_hooks() {
  output=$1
  label=$2
  for hook in $EXPECTED_OMO_HOOKS; do
    printf '%s\n' "$output" | grep -q "$hook" || {
      printf '%s output missing OMO disabled hook %s\n' "$label" "$hook" >&2
      exit 1
    }
  done
}

assert_file_has_omo_hooks() {
  target=$1
  label=$2
  for hook in $EXPECTED_OMO_HOOKS; do
    grep -q "\"$hook\"" "$target" || {
      printf '%s missing OMO disabled hook %s\n' "$label" "$hook" >&2
      exit 1
    }
  done
}

assert_file_lacks_omo_hook() {
  target=$1
  hook=$2
  label=$3
  if grep -q "\"$hook\"" "$target"; then
    printf '%s should not disable OMO hook %s\n' "$label" "$hook" >&2
    exit 1
  fi
}

assert_file_has_omo_hidden_skills() {
  target=$1
  label=$2
  for skill in $EXPECTED_OMO_HIDDEN_SKILLS; do
    grep -q "\"$skill\"" "$target" || {
      printf '%s missing OMO disabled skill %s\n' "$label" "$skill" >&2
      exit 1
    }
  done
}

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
XDG_OUTPUT=$(cd "$ROOT" && HOME="$TMP_XDG_HOME" XDG_CONFIG_HOME="$TMP_XDG_CONFIG_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

mkdir -p "$TMP_XDG_OMO_CONFIG_HOME/opencode"
cat > "$TMP_XDG_OMO_CONFIG_HOME/opencode/opencode.jsonc" <<'JSONC'
{
  "plugin": [
    ["oh-my-openagent@latest", { "keep": true }]
  ]
}
JSONC
XDG_OMO_OUTPUT=$(cd "$ROOT" && HOME="$TMP_XDG_OMO_HOME" XDG_CONFIG_HOME="$TMP_XDG_OMO_CONFIG_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

CUSTOM_CONFIG_OUTPUT=$(cd "$ROOT" && HOME="$TMP_CUSTOM_CONFIG_HOME" OPENCODE_CONFIG_DIR="$TMP_CUSTOM_CONFIG_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)

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

mkdir -p "$TMP_OMO_HOME/.config/opencode"
cat > "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json" <<'JSON'
{
  "disabled_hooks": [
    "comment-checker"
  ]
}
JSON
OMO_OUTPUT=$(cd "$ROOT" && HOME="$TMP_OMO_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)
OMO_SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_OMO_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)

mkdir -p "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode"
cat > "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc" <<'JSONC'
{
  // Comment-only OMO config should remain valid after insertion.
}
JSONC
OMO_COMMENT_ONLY_OUTPUT=$(cd "$ROOT" && HOME="$TMP_OMO_COMMENT_ONLY_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)
OMO_COMMENT_ONLY_SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_OMO_COMMENT_ONLY_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)

mkdir -p "$TMP_OMO_JSONC_HOME/.config/opencode"
cat > "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc" <<'JSONC'
{
  // Existing OMO JSONC config should remain the target.
  "disabled_hooks": [
    "runtime-fallback"
  ]
}
JSONC
OMO_JSONC_OUTPUT=$(cd "$ROOT" && HOME="$TMP_OMO_JSONC_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)

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

mkdir -p "$TMP_PLUGIN_ORDER_DISABLE_HOME/.config/opencode"
cat > "$TMP_PLUGIN_ORDER_DISABLE_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  "plugin": [
    "oh-my-openagent@latest"
  ]
}
JSONC
PLUGIN_ORDER_DISABLE_OUTPUT=$(cd "$ROOT" && HOME="$TMP_PLUGIN_ORDER_DISABLE_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --yes)

mkdir -p "$TMP_PLUGIN_ORDER_KEEP_HOME/.config/opencode"
cat > "$TMP_PLUGIN_ORDER_KEEP_HOME/.config/opencode/opencode.jsonc" <<'JSONC'
{
  "plugin": [
    "oh-my-openagent@latest"
  ]
}
JSONC
PLUGIN_ORDER_KEEP_OUTPUT=$(cd "$ROOT" && HOME="$TMP_PLUGIN_ORDER_KEEP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --keep-omo-continuation --yes)

set +e
CONFLICT_OUTPUT=$(cd "$ROOT" && HOME="$TMP_PLUGIN_ORDER_KEEP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --keep-omo-continuation --yes 2>&1)
CONFLICT_STATUS=$?
set -e

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
printf '%s\n' "$XDG_OMO_OUTPUT" | grep -Fq "$EXPECTED_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json" || { printf 'xdg omo install did not use XDG_CONFIG_HOME omo config path\n' >&2; exit 1; }
printf '%s\n' "$CUSTOM_CONFIG_OUTPUT" | grep -Fq "$EXPECTED_CUSTOM_CONFIG_DIR/opencode.jsonc" || { printf 'custom opencode install did not use OPENCODE_CONFIG_DIR config path\n' >&2; exit 1; }
printf '%s\n' "$CUSTOM_CONFIG_OUTPUT" | grep -Fq "$EXPECTED_CUSTOM_CONFIG_DIR/oh-my-openagent.json" || { printf 'custom omo install did not use OPENCODE_CONFIG_DIR omo config path\n' >&2; exit 1; }
printf '%s\n' "$JSONC_OUTPUT" | grep -q 'opencode.jsonc' || { printf 'opencode jsonc config was not used\n' >&2; exit 1; }
printf '%s\n' "$COMMENT_ONLY_JSONC_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'comment-only opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$COMMENT_ONLY_JSONC_SECOND_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'second comment-only opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$REPLACE_JSONC_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'replace opencode jsonc install did not complete\n' >&2; exit 1; }
printf '%s\n' "$REPLACE_JSONC_SECOND_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'second replace opencode jsonc install did not complete\n' >&2; exit 1; }
assert_output_mentions_omo_hooks "$OMO_OUTPUT" "omo continuation install"
assert_output_mentions_omo_hooks "$OMO_SECOND_OUTPUT" "second omo continuation install"
assert_output_mentions_omo_hooks "$OMO_COMMENT_ONLY_OUTPUT" "comment-only omo continuation install"
assert_output_mentions_omo_hooks "$OMO_COMMENT_ONLY_SECOND_OUTPUT" "second comment-only omo continuation install"
printf '%s\n' "$OMO_JSONC_OUTPUT" | grep -q 'oh-my-opencode.jsonc' || { printf 'omo jsonc continuation install did not target existing jsonc file\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'plugin order install did not complete\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'Oh My OpenAgent continuation configured' || { printf 'omo plugin install did not automatically disable continuation hook\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_OUTPUT" | grep -q 'reason: OpenCode install defaults to disabling known OMO continuation hooks' || { printf 'omo plugin auto-disable reason was not reported\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_DISABLE_OUTPUT" | grep -q 'Oh My OpenAgent continuation configured' || { printf 'omo plugin disable install did not configure continuation hook\n' >&2; exit 1; }
printf '%s\n' "$PLUGIN_ORDER_DISABLE_OUTPUT" | grep -q 'reason: requested by --disable-omo-continuation' || { printf 'omo plugin explicit disable reason was not reported\n' >&2; exit 1; }
if printf '%s\n' "$PLUGIN_ORDER_DISABLE_OUTPUT" | grep -q '\[warn\] Oh My OpenAgent plugin detected'; then
  printf 'omo plugin explicit disable install should not emit continuation warning\n' >&2
  exit 1
fi
printf '%s\n' "$PLUGIN_ORDER_KEEP_OUTPUT" | grep -q 'OMO continuation hooks were left enabled because --keep-omo-continuation was used' || { printf 'omo plugin keep install did not warn continuation stayed enabled\n' >&2; exit 1; }

if [ "$CONFLICT_STATUS" -eq 0 ]; then
  printf 'conflicting omo continuation flags should fail\n' >&2
  exit 1
fi
printf '%s\n' "$CONFLICT_OUTPUT" | grep -q 'cannot be used together' || { printf 'conflicting omo continuation flags did not report conflict\n' >&2; exit 1; }

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

if [ ! -f "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json" ]; then
  printf 'xdg omo install did not write disabled hook under XDG_CONFIG_HOME\n' >&2
  exit 1
fi

if [ -e "$TMP_XDG_OMO_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'xdg omo install incorrectly wrote disabled hook under HOME .config\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CUSTOM_CONFIG_DIR/opencode.jsonc" ]; then
  printf 'custom opencode install did not create config under OPENCODE_CONFIG_DIR\n' >&2
  exit 1
fi

if [ ! -f "$TMP_CUSTOM_CONFIG_DIR/oh-my-openagent.json" ]; then
  printf 'custom omo install did not write disabled hook under OPENCODE_CONFIG_DIR\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_HOME/.config/opencode/opencode.jsonc" ]; then
  printf 'custom opencode install incorrectly wrote under HOME .config\n' >&2
  exit 1
fi

if [ -e "$TMP_CUSTOM_CONFIG_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'custom omo install incorrectly wrote disabled hook under HOME .config\n' >&2
  exit 1
fi

if ! grep -q '"let-my-agent-sleep@latest"' "$TMP_JSONC_HOME/.config/opencode/opencode.jsonc"; then
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

if ! grep -q '"let-my-agent-sleep@latest"' "$TMP_COMMENT_ONLY_JSONC_HOME/.config/opencode/opencode.jsonc"; then
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

if ! grep -q '"let-my-agent-sleep@latest"' "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc missing latest plugin entry\n' >&2
  exit 1
fi

if grep -q '"let-my-agent-sleep@0.1.0"' "$TMP_REPLACE_JSONC_HOME/.config/opencode/opencode.jsonc"; then
  printf 'replace opencode jsonc kept stale lmas plugin entry\n' >&2
  exit 1
fi

if ! grep -q '"let-my-agent-sleep@latest"' "$TMP_HOME/.config/opencode/opencode.jsonc"; then
  printf 'fresh opencode config missing @latest plugin entry\n' >&2
  exit 1
fi

FRESH_ROOT_CACHE_VERSION=$(node -p "require(process.argv[1]).dependencies['let-my-agent-sleep']" "$TMP_HOME/.cache/opencode/package.json")

if [ "$FRESH_ROOT_CACHE_VERSION" != ">=0.0.0" ]; then
  printf 'fresh opencode root plugin cache dependency was not created with registry-compatible semver range\n' >&2
  exit 1
fi

assert_file_has_omo_hooks "$TMP_HOME/.config/opencode/oh-my-openagent.json" "fresh opencode install"
assert_file_has_omo_hooks "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json" "xdg opencode install"
assert_file_has_omo_hooks "$TMP_CUSTOM_CONFIG_DIR/oh-my-openagent.json" "custom OPENCODE_CONFIG_DIR install"
assert_file_lacks_omo_hook "$TMP_HOME/.config/opencode/oh-my-openagent.json" "start-work" "fresh opencode install"
assert_file_has_omo_hidden_skills "$TMP_HOME/.config/opencode/oh-my-openagent.json" "fresh opencode install"
assert_file_has_omo_hidden_skills "$TMP_XDG_OMO_CONFIG_HOME/opencode/oh-my-openagent.json" "xdg opencode install"
assert_file_has_omo_hidden_skills "$TMP_CUSTOM_CONFIG_DIR/oh-my-openagent.json" "custom OPENCODE_CONFIG_DIR install"

if grep -q '"let-my-agent-sleep"' "$TMP_HOME/.config/opencode/opencode.jsonc"; then
  printf 'fresh opencode config should not keep bare plugin entry\n' >&2
  exit 1
fi

if ! grep -q '"comment-checker"' "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json"; then
  printf 'omo config lost existing disabled hook\n' >&2
  exit 1
fi

assert_file_has_omo_hooks "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json" "omo config"
assert_file_lacks_omo_hook "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json" "start-work" "omo config"
assert_file_has_omo_hidden_skills "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json" "omo config"

OMO_HOOK_COUNTS=$(node --input-type=module - "$TMP_OMO_HOME/.config/opencode/oh-my-openagent.json" $EXPECTED_OMO_HOOKS <<'JS'
import { readFileSync } from "node:fs"
const config = JSON.parse(readFileSync(process.argv[2], "utf8"))
const expectedHooks = process.argv.slice(3)
console.log(expectedHooks.map((expected) => `${expected}:${config.disabled_hooks.filter((hook) => hook === expected).length}`).join("\n"))
JS
)

if printf '%s\n' "$OMO_HOOK_COUNTS" | grep -vq ':1$'; then
  printf 'omo disabled hooks should be idempotent, got counts:\n%s\n' "$OMO_HOOK_COUNTS" >&2
  exit 1
fi

if ! grep -q '"runtime-fallback"' "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc"; then
  printf 'omo jsonc config lost existing disabled hook\n' >&2
  exit 1
fi

assert_file_has_omo_hooks "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc" "omo jsonc config"
assert_file_lacks_omo_hook "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc" "start-work" "omo jsonc config"
assert_file_has_omo_hidden_skills "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc" "omo jsonc config"

if ! grep -q 'Comment-only OMO config should remain valid after insertion' "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc"; then
  printf 'comment-only omo jsonc comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc" "comment-only omo jsonc"

assert_file_has_omo_hooks "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc" "comment-only omo jsonc"
assert_file_lacks_omo_hook "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc" "start-work" "comment-only omo jsonc"
assert_file_has_omo_hidden_skills "$TMP_OMO_COMMENT_ONLY_HOME/.config/opencode/oh-my-openagent.jsonc" "comment-only omo jsonc"

if ! grep -q 'Existing OMO JSONC config should remain the target' "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc"; then
  printf 'omo jsonc config comment was not preserved\n' >&2
  exit 1
fi
assert_jsonc_parses "$TMP_OMO_JSONC_HOME/.config/opencode/oh-my-opencode.jsonc" "omo jsonc config"

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

EXPECTED_PLUGIN_ORDER=$(printf '%s\n%s\n' 'let-my-agent-sleep@latest' 'oh-my-openagent@latest')
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

assert_file_has_omo_hooks "$TMP_PLUGIN_ORDER_HOME/.config/opencode/oh-my-openagent.json" "omo plugin auto install"
assert_file_lacks_omo_hook "$TMP_PLUGIN_ORDER_HOME/.config/opencode/oh-my-openagent.json" "start-work" "omo plugin auto install"
assert_file_has_omo_hidden_skills "$TMP_PLUGIN_ORDER_HOME/.config/opencode/oh-my-openagent.json" "omo plugin auto install"

assert_file_has_omo_hooks "$TMP_PLUGIN_ORDER_DISABLE_HOME/.config/opencode/oh-my-openagent.json" "omo plugin disable install"
assert_file_lacks_omo_hook "$TMP_PLUGIN_ORDER_DISABLE_HOME/.config/opencode/oh-my-openagent.json" "start-work" "omo plugin disable install"
assert_file_has_omo_hidden_skills "$TMP_PLUGIN_ORDER_DISABLE_HOME/.config/opencode/oh-my-openagent.json" "omo plugin disable install"

if [ ! -f "$TMP_PLUGIN_ORDER_KEEP_HOME/.config/opencode/oh-my-openagent.json" ]; then
  printf 'omo plugin keep install should still write hidden cross-agent skill config\n' >&2
  exit 1
fi
if grep -q '"todo-continuation-enforcer"' "$TMP_PLUGIN_ORDER_KEEP_HOME/.config/opencode/oh-my-openagent.json"; then
  printf 'omo plugin keep install should not write disabled hook config\n' >&2
  exit 1
fi
assert_file_has_omo_hidden_skills "$TMP_PLUGIN_ORDER_KEEP_HOME/.config/opencode/oh-my-openagent.json" "omo plugin keep install"

ROOT_CACHE_VERSION=$(node -p "require(process.argv[1]).dependencies['let-my-agent-sleep']" "$TMP_STALE_CACHE_HOME/.cache/opencode/package.json")

if [ "$ROOT_CACHE_VERSION" != ">=0.0.0" ]; then
  printf 'opencode root plugin cache dependency was not updated to registry-compatible semver range\n' >&2
  exit 1
fi

if [ -e "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep" ]; then
  printf 'stale opencode package cache still exists\n' >&2
  exit 1
fi

if [ -e "$TMP_STALE_CACHE_HOME/.cache/opencode/packages/let-my-agent-sleep@latest" ]; then
  printf 'stale opencode @latest package cache still exists\n' >&2
  exit 1
fi

if [ -e "$TMP_STALE_CACHE_HOME/.cache/opencode/bun.lock" ]; then
  printf 'stale opencode root bun.lock still exists\n' >&2
  exit 1
fi

if [ -e "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/let-my-agent-sleep" ]; then
  printf 'stale opencode root node_modules package still exists\n' >&2
  exit 1
fi

if [ -e "$TMP_STALE_CACHE_HOME/.cache/opencode/node_modules/.bin/lmas" ]; then
  printf 'stale opencode root lmas bin link still exists\n' >&2
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
