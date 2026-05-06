import { SOCKET_PATH } from "./config";
import { createRuntimeDetector } from "./runtime";
import { startServer } from "./server";
import { cleanupSocket } from "./socket";
import { warmupDetector } from "./warmup";

const detector = createRuntimeDetector();
warmupDetector(detector);

const server = startServer(SOCKET_PATH, detector);

console.log(`Bun server listening on unix:${SOCKET_PATH}`);

async function shutdown(signal: string): Promise<void> {
  console.log(`Received ${signal}, shutting down...`);

  try {
    await server.stop?.();
  } catch {
    // Keep shutdown best-effort.
  }

  cleanupSocket(SOCKET_PATH);
  process.exit(0);
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));
