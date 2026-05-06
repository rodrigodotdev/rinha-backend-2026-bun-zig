#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

OUT="${SUBMISSION_DIR:-/tmp/rinha-backend-2026-bun-zig-submission}"

[ -f docker-compose.submission.yml ] || { printf '%s\n' "missing docker-compose.submission.yml" >&2; exit 1; }
[ -f haproxy.cfg ] || { printf '%s\n' "missing haproxy.cfg" >&2; exit 1; }
[ -f info.json ] || { printf '%s\n' "missing info.json" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp docker-compose.submission.yml "$OUT/docker-compose.yml"
cp haproxy.cfg "$OUT/haproxy.cfg"
cp info.json "$OUT/info.json"

printf '%s\n' "submission files written to $OUT"
find "$OUT" -maxdepth 1 -type f -printf '%f\n' | sort
