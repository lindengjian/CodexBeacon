import crypto from "node:crypto";
import net from "node:net";
import path from "node:path";

const watchSeconds = Number(
  process.argv.find((argument) => argument.startsWith("--watch-seconds="))?.split("=")[1] ??
    "5",
);
const pollMilliseconds = Number(
  process.argv.find((argument) => argument.startsWith("--poll-ms="))?.split("=")[1] ??
    "0",
);

if (!Number.isFinite(watchSeconds) || watchSeconds < 0) {
  throw new Error("--watch-seconds must be a non-negative number");
}
if (!Number.isFinite(pollMilliseconds) || pollMilliseconds < 0) {
  throw new Error("--poll-ms must be a non-negative number");
}

const socketPath =
  process.env.CODEX_SOCKET ||
  path.join(
    process.env.HOME,
    ".codex",
    "app-server-control",
    "app-server-control.sock",
  );

const pending = new Map();
let nextID = 1;
let incomingServerRequestCount = 0;
let readBuffer = Buffer.alloc(0);
let fragmentOpcode = null;
let fragmentBuffers = [];
let handshakeComplete = false;
let resolveHandshake;
let rejectHandshake;

const handshake = new Promise((resolve, reject) => {
  resolveHandshake = resolve;
  rejectHandshake = reject;
});

const socket = net.createConnection(socketPath);

function emit(type, payload) {
  process.stdout.write(
    `${JSON.stringify({ at: new Date().toISOString(), type, ...payload })}\n`,
  );
}

function send(message) {
  sendFrame(0x1, Buffer.from(JSON.stringify(message), "utf8"));
}

function request(method, params = {}, timeoutMs = 15_000) {
  const id = nextID++;
  send({ id, method, params });

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`Timed out waiting for ${method}`));
    }, timeoutMs);

    pending.set(id, {
      method,
      resolve: (message) => {
        clearTimeout(timeout);
        resolve(message);
      },
    });
  });
}

function handleMessage(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    emit("invalid_json", { line });
    return;
  }

  if (message.id !== undefined && pending.has(message.id) && !message.method) {
    const waiter = pending.get(message.id);
    pending.delete(message.id);
    waiter.resolve(message);
    return;
  }

  if (message.id !== undefined && typeof message.method === "string") {
    incomingServerRequestCount += 1;
    emit("incoming_server_request", {
      method: message.method,
      id: message.id,
      params: message.params ?? null,
    });
    return;
  }

  if (typeof message.method === "string") {
    emit("notification", {
      method: message.method,
      params: message.params ?? null,
    });
  }
}

function sendFrame(opcode, payload) {
  const mask = crypto.randomBytes(4);
  let header;

  if (payload.length < 126) {
    header = Buffer.alloc(2);
    header[1] = 0x80 | payload.length;
  } else if (payload.length <= 0xffff) {
    header = Buffer.alloc(4);
    header[1] = 0x80 | 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }

  header[0] = 0x80 | opcode;
  const masked = Buffer.alloc(payload.length);
  for (let index = 0; index < payload.length; index += 1) {
    masked[index] = payload[index] ^ mask[index % 4];
  }
  socket.write(Buffer.concat([header, mask, masked]));
}

function processFrames() {
  while (readBuffer.length >= 2) {
    const first = readBuffer[0];
    const second = readBuffer[1];
    const final = (first & 0x80) !== 0;
    const opcode = first & 0x0f;
    const masked = (second & 0x80) !== 0;
    let payloadLength = second & 0x7f;
    let offset = 2;

    if (payloadLength === 126) {
      if (readBuffer.length < 4) return;
      payloadLength = readBuffer.readUInt16BE(2);
      offset = 4;
    } else if (payloadLength === 127) {
      if (readBuffer.length < 10) return;
      const longLength = readBuffer.readBigUInt64BE(2);
      if (longLength > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new Error("WebSocket frame exceeds safe integer size");
      }
      payloadLength = Number(longLength);
      offset = 10;
    }

    const maskLength = masked ? 4 : 0;
    if (readBuffer.length < offset + maskLength + payloadLength) return;

    const mask = masked ? readBuffer.subarray(offset, offset + 4) : null;
    offset += maskLength;
    const payload = Buffer.from(readBuffer.subarray(offset, offset + payloadLength));
    readBuffer = readBuffer.subarray(offset + payloadLength);

    if (mask) {
      for (let index = 0; index < payload.length; index += 1) {
        payload[index] ^= mask[index % 4];
      }
    }

    if (opcode === 0x8) {
      socket.end();
      return;
    }
    if (opcode === 0x9) {
      sendFrame(0x0a, payload);
      continue;
    }
    if (opcode === 0x0a) continue;

    if (opcode !== 0x0) {
      fragmentOpcode = opcode;
      fragmentBuffers = [];
    }
    fragmentBuffers.push(payload);

    if (final) {
      const completePayload = Buffer.concat(fragmentBuffers);
      if (fragmentOpcode === 0x1) {
        handleMessage(completePayload.toString("utf8"));
      }
      fragmentOpcode = null;
      fragmentBuffers = [];
    }
  }
}

socket.on("data", (chunk) => {
  readBuffer = Buffer.concat([readBuffer, chunk]);

  if (!handshakeComplete) {
    const headerEnd = readBuffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) return;

    const responseHeaders = readBuffer.subarray(0, headerEnd).toString("utf8");
    readBuffer = readBuffer.subarray(headerEnd + 4);
    if (!responseHeaders.startsWith("HTTP/1.1 101")) {
      rejectHandshake(new Error(`WebSocket upgrade failed: ${responseHeaders}`));
      return;
    }
    handshakeComplete = true;
    resolveHandshake();
  }

  processFrames();
});

socket.on("error", (error) => {
  if (!handshakeComplete) rejectHandshake(error);
  else emit("socket_error", { error: error.message });
});

function requireResult(response, method) {
  if (response.error) {
    throw new Error(`${method} failed: ${JSON.stringify(response.error)}`);
  }
  return response.result;
}

function summarizeThread(thread) {
  return {
    id: thread.id,
    name: thread.name ?? null,
    source: thread.source ?? null,
    threadSource: thread.threadSource ?? null,
    ephemeral: thread.ephemeral ?? null,
    parentThreadId: thread.parentThreadId ?? null,
    canAcceptDirectInput: thread.canAcceptDirectInput ?? null,
    status: thread.status ?? null,
    updatedAt: thread.updatedAt ?? null,
  };
}

async function readLoadedThreads() {
  const loadedThreadIDs =
    requireResult(
      await request("thread/loaded/list"),
      "thread/loaded/list",
    )?.data ?? [];

  const loadedThreads = [];
  for (const threadId of loadedThreadIDs) {
    const response = await request("thread/read", {
      threadId,
      includeTurns: false,
    });
    if (response.error) {
      loadedThreads.push({ id: threadId, error: response.error });
    } else {
      loadedThreads.push(summarizeThread(response.result.thread));
    }
  }

  return { loadedThreadIDs, loadedThreads };
}

async function readLatestTurn(threadId) {
  const response = await request("thread/turns/list", {
    threadId,
    limit: 1,
    sortDirection: "desc",
    itemsView: "summary",
  });
  if (response.error) return { error: response.error };

  const turn = response.result?.data?.[0];
  if (!turn) return null;
  return {
    id: turn.id,
    status: turn.status,
    error: turn.error ?? null,
  };
}

try {
  await new Promise((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("error", reject);
  });

  const webSocketKey = crypto.randomBytes(16).toString("base64");
  socket.write(
    [
      "GET / HTTP/1.1",
      "Host: localhost",
      "Connection: Upgrade",
      "Upgrade: websocket",
      "Sec-WebSocket-Version: 13",
      `Sec-WebSocket-Key: ${webSocketKey}`,
      "\r\n",
    ].join("\r\n"),
  );
  await handshake;

  requireResult(
    await request("initialize", {
      clientInfo: {
        name: "codex-beacon-passive-observer",
        title: "Codex Beacon passive observer",
        version: "0.0.1",
      },
      capabilities: {
        experimentalApi: true,
      },
    }),
    "initialize",
  );
  send({ method: "initialized" });

  const initialThreads = await readLoadedThreads();

  const rateLimitsResponse = await request("account/rateLimits/read");
  const desktopThreadsResponse = await request("thread/list", {
    limit: 20,
    sortKey: "updated_at",
    sortDirection: "desc",
    sourceKinds: ["appServer"],
    useStateDbOnly: true,
  });

  emit("snapshot", {
    loadedThreadIDs: initialThreads.loadedThreadIDs,
    loadedThreads: initialThreads.loadedThreads,
    rateLimits: rateLimitsResponse.result ?? null,
    rateLimitsError: rateLimitsResponse.error ?? null,
    desktopThreads:
      desktopThreadsResponse.result?.data?.map(summarizeThread) ?? [],
    desktopThreadsError: desktopThreadsResponse.error ?? null,
  });

  if (watchSeconds > 0 && pollMilliseconds > 0) {
    const endTime = Date.now() + watchSeconds * 1_000;
    let previousStates = new Map(
      initialThreads.loadedThreads.map((thread) => [
        thread.id,
        JSON.stringify(thread.status ?? thread.error ?? null),
      ]),
    );

    while (Date.now() < endTime) {
      await new Promise((resolve) =>
        setTimeout(resolve, Math.min(pollMilliseconds, endTime - Date.now())),
      );

      const currentThreads = await readLoadedThreads();
      const currentStates = new Map(
        currentThreads.loadedThreads.map((thread) => [
          thread.id,
          JSON.stringify(thread.status ?? thread.error ?? null),
        ]),
      );

      for (const thread of currentThreads.loadedThreads) {
        if (previousStates.get(thread.id) !== currentStates.get(thread.id)) {
          emit("polled_thread_state_changed", {
            thread,
            latestTurn: await readLatestTurn(thread.id),
          });
        }
      }
      for (const threadId of previousStates.keys()) {
        if (!currentStates.has(threadId)) {
          emit("polled_thread_unloaded", { threadId });
        }
      }
      previousStates = currentStates;
    }
  } else if (watchSeconds > 0) {
    await new Promise((resolve) => setTimeout(resolve, watchSeconds * 1_000));
  }

  emit("finished", {
    incomingServerRequestCount,
  });
} catch (error) {
  emit("failed", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exitCode = 1;
} finally {
  if (!socket.destroyed) {
    if (handshakeComplete) sendFrame(0x8, Buffer.alloc(0));
    socket.end();
  }
}
