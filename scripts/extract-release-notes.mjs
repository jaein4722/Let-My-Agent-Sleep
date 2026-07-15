#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises"

const usage =
  "usage: extract-release-notes.mjs --version <version> --changelog <path> --output <path>"

function parseArguments(arguments_) {
  const options = {}

  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index]
    const value = arguments_[index + 1]

    if (!name?.startsWith("--") || value === undefined) {
      throw new Error(usage)
    }

    if (!["--version", "--changelog", "--output"].includes(name)) {
      throw new Error(`unknown option: ${name}`)
    }

    options[name.slice(2)] = value
  }

  for (const name of ["version", "changelog", "output"]) {
    if (!options[name]) throw new Error(`missing --${name}\n${usage}`)
  }

  return options
}

function escapeRegularExpression(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function extractReleaseNotes(changelog, version) {
  const lines = changelog.replaceAll("\r\n", "\n").split("\n")
  const heading = new RegExp(
    `^## ${escapeRegularExpression(version)}(?:\\s+-\\s+.+)?\\s*$`,
  )
  const start = lines.findIndex((line) => heading.test(line))

  if (start === -1) {
    throw new Error(`CHANGELOG entry for version ${version} was not found`)
  }

  const nextHeading = lines.findIndex(
    (line, index) => index > start && line.startsWith("## "),
  )
  const end = nextHeading === -1 ? lines.length : nextHeading
  const body = lines.slice(start + 1, end).join("\n").trim()
  if (!body) {
    throw new Error(`CHANGELOG entry for version ${version} is empty`)
  }

  return `${body}\n`
}

async function main() {
  const options = parseArguments(process.argv.slice(2))
  const changelog = await readFile(options.changelog, "utf8")
  const notes = extractReleaseNotes(changelog, options.version)
  await writeFile(options.output, notes, "utf8")
}

main().catch((error) => {
  console.error(error.message)
  process.exitCode = 1
})
