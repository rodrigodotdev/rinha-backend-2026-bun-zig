import { chmodSync, existsSync, mkdirSync, unlinkSync } from "node:fs";
import { dirname } from "node:path";

export function prepareSocketDirectory(socketPath: string): void {
  mkdirSync(dirname(socketPath), { recursive: true });
}

export function removeStaleSocket(socketPath: string): void {
  if (existsSync(socketPath)) unlinkSync(socketPath);
}

export function exposeSocket(socketPath: string): void {
  chmodSync(socketPath, 0o666);
}

export function cleanupSocket(socketPath: string): void {
  try {
    removeStaleSocket(socketPath);
  } catch {
    // Shutdown cleanup must never mask the signal path.
  }
}
