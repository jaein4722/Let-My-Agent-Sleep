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
    "Inspect an LMAS run without manually reading run artifact files. Returns LMAS_STATUS v1 for a run id or run directory.",
  args: {
    run_id: tool.schema.string().describe("LMAS run id, for example lmas_20260701T044510Z_61653_17555, or a run directory path."),
    runs_dir: tool.schema.string().optional().describe("Run directory root. Defaults to LMAS_RUNS_DIR or .lmas/runs."),
    cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
  },
  async execute(args, context) {
    const cwd = args.cwd || context.directory || context.worktree || process.cwd()
    const root = findLmasRoot(cwd, context)
    const command = ["bash", `${root}/bin/lmas.sh`, "status"]

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
