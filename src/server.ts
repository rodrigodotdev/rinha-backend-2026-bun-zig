import { type FraudDetector } from "./fraud";
import { handleRequest } from "./http";
import { exposeSocket, prepareSocketDirectory, removeStaleSocket } from "./socket";

export type BunServer = ReturnType<typeof Bun.serve>;

export function startServer(socketPath: string, detector: FraudDetector): BunServer {
  prepareSocketDirectory(socketPath);
  removeStaleSocket(socketPath);

  const server = Bun.serve({
    unix: socketPath,
    fetch(req) {
      return handleRequest(req, detector);
    },
  });

  exposeSocket(socketPath);
  return server;
}
