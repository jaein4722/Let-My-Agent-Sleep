import { existsSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))

export function findLmasScript(cwd, context = {}) {
  const roots = [
    process.env.LMAS_ROOT,
    packageRoot,
    context.directory,
    context.worktree,
    cwd,
  ].filter((value) => value && value !== "/")

  for (const root of roots) {
    const candidate = join(root, "bin", "lmas.sh")
    if (existsSync(candidate)) return candidate
  }

  throw new Error(`could not locate bin/lmas.sh; checked roots: ${roots.join(", ")}`)
}
