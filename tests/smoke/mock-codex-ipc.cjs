#!/usr/bin/env node

const { existsSync, unlinkSync, writeFileSync } = require("node:fs")
const net = require("node:net")

const [socketPath, mode, capturePath, readyPath] = process.argv.slice(2)
if (!socketPath || !mode || !capturePath || !readyPath) {
  throw new Error("usage: mock-codex-ipc.cjs <socket> <success|no-client|timeout> <capture> <ready>")
}

if (existsSync(socketPath)) unlinkSync(socketPath)

function frame(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8")
  const header = Buffer.allocUnsafe(4)
  header.writeUInt32LE(body.length, 0)
  return Buffer.concat([header, body])
}

const server = net.createServer((socket) => {
  let buffer = Buffer.alloc(0)

  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk])
    while (buffer.length >= 4) {
      const length = buffer.readUInt32LE(0)
      if (buffer.length < length + 4) return
      const message = JSON.parse(buffer.subarray(4, length + 4).toString("utf8"))
      buffer = buffer.subarray(length + 4)

      if (message.method === "initialize") {
        socket.write(frame({
          type: "response",
          requestId: message.requestId,
          resultType: "success",
          method: "initialize",
          handledByClientId: "mock-router",
          result: { clientId: "mock-lmas-client" },
        }))
        continue
      }

      if (message.method !== "thread-follower-start-turn") continue
      writeFileSync(capturePath, `${JSON.stringify(message, null, 2)}\n`)

      if (mode === "success") {
        socket.write(frame({
          type: "response",
          requestId: message.requestId,
          resultType: "success",
          method: message.method,
          handledByClientId: "mock-owner",
          result: { result: { turn: { id: "mock-turn", status: "inProgress" } } },
        }))
      } else if (mode === "no-client") {
        socket.write(frame({
          type: "response",
          requestId: message.requestId,
          resultType: "error",
          error: "no-client-found",
        }))
      } else if (mode !== "timeout") {
        throw new Error(`unknown mock mode: ${mode}`)
      }
    }
  })

  socket.on("error", () => {})
  socket.on("close", () => server.close())
})

server.listen(socketPath, () => {
  writeFileSync(readyPath, "ready\n")
})

const deadline = setTimeout(() => server.close(), 10_000)
deadline.unref()

process.on("exit", () => {
  if (existsSync(socketPath)) unlinkSync(socketPath)
})
