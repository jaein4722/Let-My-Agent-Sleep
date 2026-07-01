import { tool } from "@opencode-ai/plugin"
import { existsSync } from "node:fs"

function findLmasRoot(cwd: string, context: Record<string, unknown>) {
  const roots = [
    process.env.LMAS_ROOT,
    cwd,
    typeof context.directory === "string" ? context.directory : undefined,
    typeof context.worktree === "string" ? context.worktree : undefined,
    new URL("../../", import.meta.url).pathname.replace(/\/$/, ""),
  ].filter((value): value is string => Boolean(value && value !== "/"))

  for (const root of roots) {
    if (existsSync(`${root}/bin/lmas.sh`)) {
      return root
    }
  }

  throw new Error(`could not locate bin/lmas.sh; checked roots: ${roots.join(", ")}`)
}

export default tool({
  description:
    "Start a long-running training, evaluation, preprocessing, or batch job through Let My Agent Sleep. It returns an LMAS_HANDOFF v1 event immediately and resumes the same OpenCode session when the job finishes.",
  args: {
    command: tool.schema.string().describe("Shell command to run, for example: python train.py --config configs/exp.yaml"),
    cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
    artifacts_dir: tool.schema.string().optional().describe("Artifact directory to report in LMAS events."),
    metadata: tool.schema.record(tool.schema.string(), tool.schema.string()).optional().describe("Additional metadata to persist with this run."),
    server_url: tool.schema.string().optional().describe("OpenCode server URL. Defaults to LMAS_OPENCODE_SERVER_URL or http://127.0.0.1:4096."),
  },
  async execute(args, context) {
    const cwd = args.cwd || context.directory || context.worktree || process.cwd()
    const root = findLmasRoot(cwd, context)
    const script = `${root}/bin/lmas.sh`
    const env = {
      ...process.env,
      LMAS_OPENCODE_SESSION_ID: context.sessionID,
      LMAS_OPENCODE_SERVER_URL: args.server_url || process.env.LMAS_OPENCODE_SERVER_URL || "http://127.0.0.1:4096",
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

    const proc = Bun.spawn(command, { cwd, env, stdin: "ignore", stdout: "pipe", stderr: "pipe", detached: true })
    const stdout = await new Response(proc.stdout).text()
    const stderr = await new Response(proc.stderr).text()
    const code = await proc.exited

    if (code !== 0) {
      throw new Error(`lmas_start failed with exit code ${code}\n${stderr}`)
    }

    return stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
  },
})
