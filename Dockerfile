FROM --platform=linux/amd64 debian:bookworm-slim AS zig-toolchain

ARG ZIG_VERSION=0.16.0
ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl wget xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
  "amd64") ZIG_ARCH="x86_64" ;; \
  "arm64") ZIG_ARCH="aarch64" ;; \
  *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
  && mkdir -p /opt/zig \
  && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
  && /opt/zig/zig version

FROM zig-toolchain AS native-build

WORKDIR /app

COPY build.zig build.zig
COPY native native

ARG NATIVE_TARGET=x86_64-linux-gnu
ARG NATIVE_CPU=haswell
ARG FAST_NPROBE=10
ARG FULL_NPROBE=16

RUN /opt/zig/zig build \
  -Doptimize=ReleaseFast \
  -Dtarget="${NATIVE_TARGET}" \
  -Dcpu="${NATIVE_CPU}" \
  -Dfast-nprobe="${FAST_NPROBE}" \
  -Dfull-nprobe="${FULL_NPROBE}"

FROM native-build AS index-build

ARG INDEX_K=4096
ARG INDEX_ITERATIONS=25
ARG INDEX_SAMPLE=262144
ARG INDEX_SEED=0xdeadbeefcafebabe
ARG RINHA_REF=main

RUN wget -q \
  "https://raw.githubusercontent.com/zanfranceschi/rinha-de-backend-2026/${RINHA_REF}/resources/references.json.gz" \
  -O /app/references.json.gz

RUN /opt/zig/zig build \
  -Doptimize=ReleaseFast \
  build-index -- /app/references.json.gz /app/fraud-index.bin \
  --k "${INDEX_K}" \
  --iterations "${INDEX_ITERATIONS}" \
  --sample "${INDEX_SAMPLE}" \
  --seed "${INDEX_SEED}" \
  && test -s /app/fraud-index.bin

FROM --platform=linux/amd64 oven/bun AS build

WORKDIR /app

COPY ./src ./src
COPY --from=native-build /app/zig-out/lib/libfraud.so ./native/libfraud.so

ENV NODE_ENV=production

RUN bun build \
  --compile \
  --minify-whitespace \
  --minify-syntax \
  --outfile server \
  src/index.ts

FROM --platform=linux/amd64 gcr.io/distroless/base

WORKDIR /app

COPY --from=build /app/server server
COPY --from=build /app/native native
COPY --from=index-build /app/fraud-index.bin fraud-index.bin

ENV NODE_ENV=production
ENV FRAUD_LIB_PATH=/app/native/libfraud.so

CMD ["./server"]
