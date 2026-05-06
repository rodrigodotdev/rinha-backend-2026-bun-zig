#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

IMAGE="${RINHA_API_IMAGE:-docker.io/rodrigodotdev/rinha-backend-2026-bun-zig:latest}"
RINHA_REF="${RINHA_REF:-main}"
NATIVE_TARGET="${NATIVE_TARGET:-x86_64-linux-gnu}"
NATIVE_CPU="${NATIVE_CPU:-haswell}"
FAST_NPROBE="${FAST_NPROBE:-10}"
FULL_NPROBE="${FULL_NPROBE:-16}"
INDEX_K="${INDEX_K:-4096}"
INDEX_ITERATIONS="${INDEX_ITERATIONS:-25}"
INDEX_SAMPLE="${INDEX_SAMPLE:-262144}"
INDEX_SEED="${INDEX_SEED:-0xdeadbeefcafebabe}"

docker buildx build \
  --platform linux/amd64 \
  --build-arg "RINHA_REF=$RINHA_REF" \
  --build-arg "NATIVE_TARGET=$NATIVE_TARGET" \
  --build-arg "NATIVE_CPU=$NATIVE_CPU" \
  --build-arg "FAST_NPROBE=$FAST_NPROBE" \
  --build-arg "FULL_NPROBE=$FULL_NPROBE" \
  --build-arg "INDEX_K=$INDEX_K" \
  --build-arg "INDEX_ITERATIONS=$INDEX_ITERATIONS" \
  --build-arg "INDEX_SAMPLE=$INDEX_SAMPLE" \
  --build-arg "INDEX_SEED=$INDEX_SEED" \
  --tag "$IMAGE" \
  --push \
  .
