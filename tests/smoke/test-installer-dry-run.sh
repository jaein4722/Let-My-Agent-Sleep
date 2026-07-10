#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MOCK_BIN=$(mktemp -d "${TMPDIR:-/tmp}/lmas-detected-bin.XXXXXX")
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-installer-dry-home.XXXXXX")
trap 'rm -rf "$MOCK_BIN" "$TMP_HOME"' EXIT
EXPECTED_OMO_HOOKS=$(cd "$ROOT" && node --input-type=module -e 'import { omoContinuationHooks } from "./packages/let-my-agent-sleep/src/omo-constants.js"; console.log(omoContinuationHooks.join(" "))')

assert_output_mentions_omo_hooks() {
  output=$1
  for hook in $EXPECTED_OMO_HOOKS; do
    printf '%s\n' "$output" | grep -q "$hook" || {
      printf 'omo continuation dry-run missing disabled hook output: %s\n' "$hook" >&2
      exit 1
    }
  done
}

for command in opencode codex claude; do
  cat > "$MOCK_BIN/$command" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --version)
    printf 'mock command should not be executed for detection\n' >&2
    exit 42
    ;;
esac
printf 'mock\n'
SH
  chmod +x "$MOCK_BIN/$command"
done

OPENCODE_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --dry-run --yes)
OMO_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --disable-omo-continuation --dry-run --yes)
CODEX_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex --dry-run --yes)
CLAUDE_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js install --agent claude --dry-run --yes)
DETECTED_OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent detected --dry-run --yes)
DOCTOR_ERROR_OUTPUT=$(cd "$ROOT" && node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent bogus --yes 2>&1)
DOCTOR_ERROR_STATUS=$?

printf '%s\n' "$OPENCODE_OUTPUT" | grep -q 'plugin: let-my-agent-sleep@latest' || { printf 'opencode dry-run missing plugin config\n' >&2; exit 1; }
printf '%s\n' "$OPENCODE_OUTPUT" | grep -q '.config/opencode/opencode.jsonc' || { printf 'opencode dry-run should target opencode.jsonc\n' >&2; exit 1; }
printf '%s\n' "$OPENCODE_OUTPUT" | grep -q '.config/opencode/skills/let-my-agent-sleep/SKILL.md' || { printf 'opencode dry-run missing skill target\n' >&2; exit 1; }
printf '%s\n' "$OPENCODE_OUTPUT" | grep -q '.cache/opencode/package.json' || { printf 'opencode dry-run missing root plugin cache target\n' >&2; exit 1; }
if printf '%s\n' "$OPENCODE_OUTPUT" | grep -q 'Oh My OpenAgent continuation configured'; then
  printf 'opencode dry-run should not disable OMO continuation hooks by default\n' >&2
  exit 1
fi
assert_output_mentions_omo_hooks "$OMO_OUTPUT"
printf '%s\n' "$OMO_OUTPUT" | grep -q 'reason: requested by --disable-omo-continuation' || { printf 'explicit OMO continuation dry-run missing disable reason\n' >&2; exit 1; }
printf '%s\n' "$OMO_OUTPUT" | grep -q 'oh-my-openagent.json' || { printf 'omo continuation dry-run missing omo config target\n' >&2; exit 1; }
printf '%s\n' "$CODEX_OUTPUT" | grep -q '.codex/skills/let-my-agent-sleep' || { printf 'codex dry-run missing skill target\n' >&2; exit 1; }
printf '%s\n' "$CODEX_OUTPUT" | grep -q 'plugin: not installed' || { printf 'codex dry-run should avoid plugin install\n' >&2; exit 1; }
printf '%s\n' "$CLAUDE_OUTPUT" | grep -q '.claude/commands/let-my-agent-sleep.md' || { printf 'claude dry-run missing command target\n' >&2; exit 1; }
printf '%s\n' "$CLAUDE_OUTPUT" | grep -q '.claude/lmas/let-my-agent-sleep' || { printf 'claude dry-run missing assets target\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'detected dry-run did not complete\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q '✓ OpenCode' || { printf 'detected dry-run did not mark OpenCode as detected via PATH lookup\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q '✓ Codex' || { printf 'detected dry-run did not mark Codex as detected via PATH lookup\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q '✓ Claude Code' || { printf 'detected dry-run did not mark Claude Code as detected via PATH lookup\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'OpenCode install configured' || { printf 'detected dry-run did not include OpenCode target\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Codex install configured' || { printf 'detected dry-run did not include Codex target\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Claude Code install configured' || { printf 'detected dry-run did not include Claude Code target\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Restart OpenCode so it reloads plugins and skills' || { printf 'detected dry-run missing OpenCode restart instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'lmas doctor --agent opencode' || { printf 'detected dry-run missing OpenCode doctor instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'lmas doctor --agent opencode --server-url http://127.0.0.1:4096' || { printf 'detected dry-run missing OpenCode live doctor instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --directory "$PWD"' || { printf 'detected dry-run missing OpenCode directory live doctor instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --workspace "<workspace-id>"' || { printf 'detected dry-run missing OpenCode workspace live doctor instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Restart Codex so it reloads skills' || { printf 'detected dry-run missing Codex restart instruction\n' >&2; exit 1; }
printf '%s\n' "$DETECTED_OUTPUT" | grep -q 'Restart Claude Code so it reloads commands' || { printf 'detected dry-run missing Claude Code restart instruction\n' >&2; exit 1; }
if [ "$DOCTOR_ERROR_STATUS" -eq 0 ]; then
  printf 'doctor with invalid agent should fail\n' >&2
  exit 1
fi
printf '%s\n' "$DOCTOR_ERROR_OUTPUT" | grep -q 'lmas doctor failed:' || { printf 'doctor error should use command-specific prefix\n' >&2; exit 1; }

printf 'ok installer dry-run\n'
