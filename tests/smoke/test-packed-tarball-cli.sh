#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-packed-tarball.XXXXXX")
PACK_DIR="$TMPDIR_ROOT/pack"
EXTRACT_DIR="$TMPDIR_ROOT/extract"
RUNS_DIR="$TMPDIR_ROOT/runs"
WORK_DIR="$TMPDIR_ROOT/work"
INSTALL_HOME="$TMPDIR_ROOT/home"
mkdir -p "$PACK_DIR" "$EXTRACT_DIR" "$WORK_DIR" "$INSTALL_HOME"

PACK_OUTPUT=$(cd "$ROOT" && npm_config_cache="$TMPDIR_ROOT/npm-cache" npm pack --workspace let-my-agent-sleep --pack-destination "$PACK_DIR" --silent)
TARBALL=$(find "$PACK_DIR" -maxdepth 1 -type f -name 'let-my-agent-sleep-*.tgz' -print | head -n 1)

[ -n "$TARBALL" ] || {
  printf 'npm pack did not produce let-my-agent-sleep tarball\n' >&2
  printf '%s\n' "$PACK_OUTPUT" >&2
  exit 1
}

tar -xzf "$TARBALL" -C "$EXTRACT_DIR"
PKG="$EXTRACT_DIR/package"

[ -f "$PKG/package.json" ] || { printf 'packed tarball missing package.json\n' >&2; exit 1; }
[ -x "$PKG/bin/lmas-install.js" ] || { printf 'packed tarball lmas-install.js is not executable\n' >&2; exit 1; }
[ -x "$PKG/bin/lmas.sh" ] || { printf 'packed tarball lmas.sh is not executable\n' >&2; exit 1; }
[ -f "$PKG/src/index.js" ] || { printf 'packed tarball missing OpenCode plugin entry\n' >&2; exit 1; }
[ -f "$PKG/skills/let-my-agent-sleep/SKILL.md" ] || { printf 'packed tarball missing OpenCode skill\n' >&2; exit 1; }
[ -f "$PKG/codex-plugin/let-my-agent-sleep/.codex-plugin/plugin.json" ] || { printf 'packed tarball missing Codex plugin manifest\n' >&2; exit 1; }
[ -f "$PKG/README.md" ] || { printf 'packed tarball missing README.md\n' >&2; exit 1; }
[ -f "$PKG/CHANGELOG.md" ] || { printf 'packed tarball missing CHANGELOG.md\n' >&2; exit 1; }
[ -f "$PKG/LICENSE" ] || { printf 'packed tarball missing LICENSE\n' >&2; exit 1; }
PACKAGE_VERSION=$(node -p "require(process.argv[1]).version" "$PKG/package.json")
grep -Eq "^## $PACKAGE_VERSION - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$PKG/CHANGELOG.md" || { printf 'packed tarball CHANGELOG.md missing dated %s entry\n' "$PACKAGE_VERSION" >&2; exit 1; }
! grep -q 'Unreleased' "$PKG/CHANGELOG.md" || { printf 'packed tarball CHANGELOG.md still contains Unreleased\n' >&2; exit 1; }
grep -q 'https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png' "$PKG/README.md" || { printf 'packed tarball README.md missing absolute PNG social card URL\n' >&2; exit 1; }
grep -q 'https://jaein4722.github.io/Let-My-Agent-Sleep/demo.gif' "$PKG/README.md" || { printf 'packed tarball README.md missing absolute demo GIF URL\n' >&2; exit 1; }
cmp -s "$ROOT/LICENSE" "$PKG/LICENSE" || { printf 'packed tarball LICENSE differs from root LICENSE\n' >&2; exit 1; }

OPENCODE_PLUGIN_DEP=$(node -p "require(process.argv[1]).dependencies['@opencode-ai/plugin']" "$PKG/package.json")
[ "$OPENCODE_PLUGIN_DEP" = "1.2.27" ] || {
  printf 'packed tarball should pin @opencode-ai/plugin to 1.2.27, got %s\n' "$OPENCODE_PLUGIN_DEP" >&2
  exit 1
}

CODEX_PLUGIN_VERSION=$(node -p "require(process.argv[1]).version" "$PKG/codex-plugin/let-my-agent-sleep/.codex-plugin/plugin.json")
[ "$CODEX_PLUGIN_VERSION" = "$PACKAGE_VERSION" ] || {
  printf 'packed tarball Codex plugin manifest version %s does not match package version %s\n' "$CODEX_PLUGIN_VERSION" "$PACKAGE_VERSION" >&2
  exit 1
}

BIN_NAMES=$(node --input-type=module - "$PKG/package.json" <<'JS'
import { readFileSync } from "node:fs"
const packageJson = JSON.parse(readFileSync(process.argv[2], "utf8"))
console.log(Object.entries(packageJson.bin || {}).map(([name, target]) => `${name}:${target}`).sort().join("\n"))
JS
)

printf '%s\n' "$BIN_NAMES" | grep -q '^let-my-agent-sleep:bin/lmas-install.js$' || {
  printf 'packed tarball missing let-my-agent-sleep bin mapping\n' >&2
  exit 1
}
printf '%s\n' "$BIN_NAMES" | grep -q '^lmas:bin/lmas-install.js$' || {
  printf 'packed tarball missing lmas bin mapping\n' >&2
  exit 1
}

HELP_OUTPUT=$(cd / && node "$PKG/bin/lmas-install.js" -h 2>&1)
printf '%s\n' "$HELP_OUTPUT" | grep -q '^Usage:' || {
  printf 'packed tarball CLI help failed\n' >&2
  exit 1
}
printf '%s\n' "$HELP_OUTPUT" | grep -q -- '--workspace <id>' || {
  printf 'packed tarball CLI help missing OpenCode workspace live doctor option\n' >&2
  exit 1
}

INSTALL_OUTPUT=$(cd / && HOME="$INSTALL_HOME" node "$PKG/bin/lmas-install.js" install --agent all --dry-run --yes 2>&1)
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'OpenCode install configured' || {
  printf 'packed tarball install dry-run did not configure OpenCode\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'Codex install configured' || {
  printf 'packed tarball install dry-run did not configure Codex\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'Claude Code install configured' || {
  printf 'packed tarball install dry-run did not configure Claude Code\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$INSTALL_OUTPUT" | grep -q '.claude/commands/let-my-agent-sleep.md' || {
  printf 'packed tarball install dry-run missing Claude command target\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$INSTALL_OUTPUT" | grep -q '.codex/skills/let-my-agent-sleep' || {
  printf 'packed tarball install dry-run missing Codex skill target\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --workspace "<workspace-id>"' || {
  printf 'packed tarball install dry-run missing OpenCode workspace live doctor instruction\n' >&2
  printf '%s\n' "$INSTALL_OUTPUT" >&2
  exit 1
}

START_OUTPUT=$(cd "$WORK_DIR" && LMAS_RUNS_DIR="$RUNS_DIR" node "$PKG/bin/lmas-install.js" start --adapter noop -- /bin/sh -c 'printf "tarball-cli-ok\n"')
RUN_ID=$(printf '%s\n' "$START_OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

[ -n "$RUN_ID" ] || { printf 'packed tarball CLI start did not emit run_id\n' >&2; exit 1; }
printf '%s\n' "$START_OUTPUT" | grep -q '^LMAS_HANDOFF v1$' || { printf 'packed tarball CLI start did not emit handoff\n' >&2; exit 1; }

for _ in $(seq 1 100); do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || {
  printf 'packed tarball CLI start did not write completion event\n' >&2
  [ -f "$RUN_DIR/watcher.log" ] && sed -n '1,160p' "$RUN_DIR/watcher.log" >&2
  exit 1
}
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'packed tarball completion did not report SUCCEEDED\n' >&2; exit 1; }
grep -q 'tarball-cli-ok' "$RUN_DIR/stdout.log" || { printf 'packed tarball command stdout was not captured\n' >&2; exit 1; }

STATUS_OUTPUT=$(cd "$WORK_DIR" && LMAS_RUNS_DIR="$RUNS_DIR" node "$PKG/bin/lmas-install.js" status "$RUN_ID")
printf '%s\n' "$STATUS_OUTPUT" | grep -q '^status: SUCCEEDED$' || { printf 'packed tarball CLI status did not report SUCCEEDED\n' >&2; exit 1; }

printf 'ok packed tarball cli: %s\n' "$RUN_ID"
