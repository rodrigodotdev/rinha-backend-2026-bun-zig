export const SOCKET_PATH = process.env.SOCKET_PATH ?? "/run/sock/api-1.sock";
export const WARMUP_ROUNDS = readNonNegativeInteger(process.env.WARMUP_ROUNDS, 16);

function readNonNegativeInteger(value: string | undefined, fallback: number): number {
  if (value === undefined || value === "") return fallback;

  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return Math.floor(parsed);
}
