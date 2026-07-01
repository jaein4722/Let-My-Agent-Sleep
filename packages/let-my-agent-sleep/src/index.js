import { existsSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { tool } from "@opencode-ai/plugin"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))

function findLmasScript(cwd, context) {
  const roots = [
    process.env.LMAS_ROOT,
    cwd,
    context.directory,
    context.worktree,
    packageRoot,
  ].filter((value) => value && value !== "/")

  for (const root of roots) {
    const candidate = join(root, "bin", "lmas.sh")
    if (existsSync(candidate)) return candidate
  }

  throw new Error(`could not locate bin/lmas.sh; checked roots: ${roots.join(", ")}`)
}

function createStartTool(defaultServerUrl) {
  return tool({
    description:
      "Start a long-running training, evaluation, preprocessing, benchmark, or batch job through Let My Agent Sleep. Returns LMAS_HANDOFF v1 immediately and injects a completion prompt into this OpenCode session when the job finishes.",
    args: {
      command: tool.schema.string().describe("Shell command to run, for example: python train.py --config configs/exp.yaml"),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
      artifacts_dir: tool.schema.string().optional().describe("Artifact directory to report in LMAS events."),
      metadata: tool.schema.record(tool.schema.string(), tool.schema.string()).optional().describe("Additional metadata to persist with this run."),
      server_url: tool.schema.string().optional().describe("OpenCode server URL. Defaults to this plugin's current OpenCode server URL."),
    },
    async execute(args, context) {
      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const serverUrl = args.server_url || process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      const env = {
        ...process.env,
        LMAS_OPENCODE_SESSION_ID: context.sessionID,
        LMAS_OPENCODE_SERVER_URL: serverUrl,
      }

      const command = [
        "bash",
        script,
        "start",
        "--adapter",
        "opencode",
        "--cwd",
        cwd,
        "--metadata",
        `requested_command=${args.command}`,
      ]

      if (args.artifacts_dir) {
        command.push("--artifacts-dir", args.artifacts_dir)
      }

      if (args.metadata) {
        for (const [key, value] of Object.entries(args.metadata)) {
          command.push("--metadata", `${key}=${value}`)
        }
      }

      command.push("--", "bash", "-lc", args.command)

      const proc = Bun.spawn(command, {
        cwd,
        env,
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
        detached: true,
      })
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      const code = await proc.exited

      if (code !== 0) {
        throw new Error(`lmas_start failed with exit code ${code}\n${stderr}`)
      }

      return stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
    },
  })
}

function createStatusTool() {
  return tool({
    description:
      "Inspect an LMAS run without manually reading run artifact files. Returns LMAS_STATUS v1 for a run id or run directory.",
    args: {
      run_id: tool.schema.string().describe("LMAS run id, for example lmas_20260701T134510+0900_61653_17555, or a run directory path."),
      runs_dir: tool.schema.string().optional().describe("Run directory root. Defaults to LMAS_RUNS_DIR or .lmas/runs."),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
    },
    async execute(args, context) {
      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const command = ["bash", script, "status"]

      if (args.runs_dir) {
        command.push("--runs-dir", args.runs_dir)
      }

      command.push(args.run_id)

      const proc = Bun.spawn(command, {
        cwd,
        env: { ...process.env },
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
      })
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      const code = await proc.exited

      if (code !== 0) {
        throw new Error(`lmas_status failed with exit code ${code}\n${stderr}`)
      }

      return stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
    },
  })
}

export const LetMyAgentSleepPlugin = async ({ serverUrl }) => {
  const defaultServerUrl = serverUrl?.toString?.().replace(/\/$/, "") || "http://127.0.0.1:4096"

  return {
    tool: {
      lmas_start: createStartTool(defaultServerUrl),
      lmas_status: createStatusTool(),
    },
  }
}

export default LetMyAgentSleepPlugin
