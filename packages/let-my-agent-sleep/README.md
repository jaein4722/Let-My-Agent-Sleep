# let-my-agent-sleep

Let My Agent Sleep is an OpenCode plugin, installer, and handoff protocol for long-running agent jobs.

Let My Agent Sleep lets an agent start training, evaluation, preprocessing, or batch work, stop after `LMAS_HANDOFF v1`, and resume the same session when `LMAS_COMPLETION_EVENT v1` is injected later.

## Install

```bash
npx let-my-agent-sleep install
```

After global install, the short alias is:

```bash
lmas install
```

The installer detects local agents and lists installed agents first. It supports:

```bash
npx let-my-agent-sleep install --agent opencode
npx let-my-agent-sleep install --agent codex
npx let-my-agent-sleep install --agent detected --yes
npx let-my-agent-sleep install --agent all --yes
```

Use `--dry-run` to preview file writes.

## OpenCode

The installer updates `~/.config/opencode/opencode.json`:

```json
{
  "plugin": ["let-my-agent-sleep"]
}
```

It also installs the Let My Agent Sleep skill to:

```text
~/.config/opencode/skills/let-my-agent-sleep/SKILL.md
```

The plugin provides:

- `lmas_start`
- `lmas_status`

## Codex

The installer copies a Codex-compatible standalone skill into the user's agent skill directory. It does not install a Codex plugin entry, so Codex indexes only one `let-my-agent-sleep` skill.

For Codex, `--launcher auto` uses `launchctl` on macOS and `tmux` when available elsewhere so the watcher can survive the sandboxed tool process. On local macOS, protected workspace paths such as `Documents`, `Desktop`, or `Downloads` may still be blocked by host privacy controls; `Operation not permitted` in `watcher.log` means a TCC/host permission issue, not a failed training command.

## Runtime Artifacts

Runs are stored under:

```text
.lmas/runs/<run_id>/
```

Task artifacts and reproducible helper scripts should live under:

```text
.lmas/artifacts/<task-or-timestamp>/
```

Use:

```bash
lmas status <run_id>
lmas list
```

Do not place secrets in command-line arguments or metadata. Keep `.lmas/` ignored by git.
