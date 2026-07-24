import { spawn } from "node:child_process";
import readline from "node:readline";

const server = spawn("codex", ["app-server", "--stdio"], {
  stdio: ["pipe", "pipe", "pipe"],
});

const pending = new Map();
const notifications = [];
let nextID = 1;

function send(message) {
  server.stdin.write(`${JSON.stringify(message)}\n`);
}

function request(method, params = null) {
  const id = nextID++;
  send({ id, method, params });

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`Timed out waiting for ${method}`));
    }, 15_000);

    pending.set(id, {
      method,
      resolve: (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
    });
  });
}

const lines = readline.createInterface({ input: server.stdout });
lines.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message.id !== undefined && pending.has(message.id)) {
    const waiter = pending.get(message.id);
    pending.delete(message.id);
    waiter.resolve(message);
    return;
  }

  if (typeof message.method === "string") {
    notifications.push(message);
  }
});

let stderr = "";
server.stderr.on("data", (chunk) => {
  stderr += chunk.toString("utf8");
});

function summarizeWindow(window) {
  if (!window) {
    return null;
  }

  return {
    usedPercent: window.usedPercent,
    remainingPercent:
      typeof window.usedPercent === "number" ? 100 - window.usedPercent : null,
    windowDurationMins: window.windowDurationMins ?? null,
    resetsAt: window.resetsAt ?? null,
  };
}

function summarizeSnapshot(snapshot) {
  if (!snapshot) {
    return null;
  }

  return {
    limitId: snapshot.limitId ?? null,
    limitName: snapshot.limitName ?? null,
    planType: snapshot.planType ?? null,
    primary: summarizeWindow(snapshot.primary),
    secondary: summarizeWindow(snapshot.secondary),
    rateLimitReachedType: snapshot.rateLimitReachedType ?? null,
  };
}

function summarizeThread(thread) {
  return {
    id: thread.id,
    sessionId: thread.sessionId,
    source: thread.source,
    status: thread.status,
    updatedAt: thread.updatedAt,
  };
}

try {
  const initializeResponse = await request("initialize", {
    clientInfo: {
      name: "codex-beacon-quota-probe",
      title: "Codex Beacon quota probe",
      version: "0.0.1",
    },
    capabilities: {
      experimentalApi: true,
    },
  });

  if (initializeResponse.error) {
    throw new Error(`initialize failed: ${JSON.stringify(initializeResponse.error)}`);
  }

  send({ method: "initialized" });

  const rateLimitsResponse = await request("account/rateLimits/read");
  const usageResponse = await request("account/usage/read");
  const appServerThreadListResponse = await request("thread/list", {
    limit: 20,
    sortKey: "updated_at",
    sortDirection: "desc",
    sourceKinds: ["appServer"],
    useStateDbOnly: true,
  });
  const interactiveThreadListResponse = await request("thread/list", {
    limit: 20,
    sortKey: "updated_at",
    sortDirection: "desc",
    useStateDbOnly: false,
  });
  await new Promise((resolve) => setTimeout(resolve, 1_500));

  const result = {
    initializeSucceeded: true,
    rateLimitsError: rateLimitsResponse.error ?? null,
    rateLimits: summarizeSnapshot(rateLimitsResponse.result?.rateLimits),
    rateLimitsByLimitId: Object.fromEntries(
      Object.entries(rateLimitsResponse.result?.rateLimitsByLimitId ?? {}).map(
        ([limitID, snapshot]) => [limitID, summarizeSnapshot(snapshot)],
      ),
    ),
    resetCredits: rateLimitsResponse.result?.rateLimitResetCredits
      ? {
          availableCount:
            rateLimitsResponse.result.rateLimitResetCredits.availableCount,
          detailCount:
            rateLimitsResponse.result.rateLimitResetCredits.credits?.length ?? null,
        }
      : null,
    usageReadSupported: !usageResponse.error,
    usageReadError: usageResponse.error ?? null,
    appServerThreadListError: appServerThreadListResponse.error ?? null,
    appServerThreads:
      appServerThreadListResponse.result?.data?.map(summarizeThread) ?? [],
    interactiveThreadListError: interactiveThreadListResponse.error ?? null,
    interactiveThreads:
      interactiveThreadListResponse.result?.data?.map(summarizeThread) ?? [],
    observedNotificationMethods: [
      ...new Set(notifications.map((notification) => notification.method)),
    ].sort(),
  };

  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(
    JSON.stringify(
      {
        error: error instanceof Error ? error.message : String(error),
        stderr: stderr.trim(),
      },
      null,
      2,
    ),
  );
  process.exitCode = 1;
} finally {
  lines.close();
  server.kill("SIGTERM");
}
