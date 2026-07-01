---
name: let-my-agent-sleep
description: Start long-running training, evaluation, preprocessing, or batch jobs with Let My Agent Sleep handoff semantics in OpenCode. Use when a task would otherwise require waiting, polling, or repeated continue loops until a job finishes.
compatibility: opencode
---

# Let My Agent Sleep

Treat long-running jobs as handoff tasks, not completion tasks.

Use this skill when a command is likely to run for minutes or hours, including model training, evaluation, dataset preprocessing, benchmark suites, large migrations, or batch inference.

## Workflow

1. Prepare the command and run a short sanity check when practical.
2. Start the real long job with the `lmas_start` tool.
3. After the tool returns `LMAS_HANDOFF v1`, stop the current loop. Do not poll the log or wait for completion.
4. When `LMAS_COMPLETION_EVENT v1` appears later in the session, use `lmas_status` if you need a quick run summary, then inspect stdout/stderr/artifacts and continue the original task.

## Required Behavior

- Do not run long jobs directly with the normal bash tool when `lmas_start` is available.
- Do not call `skill_mcp` for Let My Agent Sleep. This is an OpenCode plugin tool, not an MCP server.
- If `lmas_start` is not available in the tool list, the OpenCode plugin is not loaded in the current session. Tell the user to restart OpenCode after running `lmas install --agent opencode`; do not invent `.opencode/tools` paths or start a normal shell fallback unless the user explicitly asks for manual fallback.
- Do not treat an unfinished long job as a failure after `LMAS_HANDOFF v1`.
- After `LMAS_HANDOFF v1`, do not check status, inspect artifacts, relaunch, or debug the job unless the user explicitly asks for a status check. A user asking whether enough time has passed, why there is no update, or whether the job finished counts as a status check request.
- If a user later asks for status and `LMAS_STATUS v1` reports `LOST`, inspect `watcher.log` and `stderr.log`, report the run as lost, and ask before relaunching. Do not silently start a replacement job.
- Preserve the original command in metadata.
- Make the completion response concrete: cite the run id, status, exit code, and relevant log/artifact paths.
- Prefer `lmas_status` over manually reading metadata files. Read stdout/stderr first; read metadata only when command context is unclear.

## Path Rules

- Prefer workspace-local paths under `.lmas/` for all LMAS run data and artifacts.
- Use `.lmas/runs` as the default run directory.
- Use `.lmas/artifacts/<task-name-or-timestamp>` as the default artifact directory for task outputs and reproducible helper scripts.
- Use `/tmp` only when the current workspace is not writable or the user explicitly requests a temporary system path.

## OpenCode Setup

`lmas_start` and `lmas_status` are provided by the installed OpenCode plugin. They are not project-local files and should not be looked up under `.opencode/tools`.

The installer updates the OpenCode config, usually `~/.config/opencode/opencode.jsonc`, and installs this skill under `~/.config/opencode/skills/let-my-agent-sleep/SKILL.md`. OpenCode must be restarted after install so it reloads plugin tools.

OpenCode must know the server URL used for completion injection. The plugin usually receives it from the running OpenCode server. When needed, set:

```bash
export LMAS_OPENCODE_SERVER_URL=http://127.0.0.1:4096
```

The tool supplies `LMAS_OPENCODE_SESSION_ID` from the current OpenCode tool context.

When running against a non-default server, pass `server_url` to `lmas_start`. The URL must point to the same OpenCode server that owns the current session id; otherwise completion injection will fail with 404 and `resume_prompt.txt` will be left as fallback.
