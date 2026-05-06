import { dlopen, FFIType, suffix } from "bun:ffi";

const SCORE_JSON_ARGS = [FFIType.ptr, "usize"] as const;
const DEFAULT_NATIVE_LIBRARY_PATH = process.env.FRAUD_LIB_PATH ?? `./native/libfraud.${suffix}`;

type FraudNativeSymbols = {
  readonly fraud_init: () => number;
  readonly fraud_ready: () => boolean;
  readonly fraud_score_json: (body: Uint8Array, len: number | bigint) => number;
};

export type FraudDetector = {
  readonly init: () => number;
  readonly ready: () => boolean;
  readonly countFraudJson: (body: Uint8Array) => number;
};

export const UNAVAILABLE_DETECTOR: FraudDetector = {
  init: () => 1,
  ready: () => false,
  countFraudJson: () => 0,
};

export function loadNativeFraud(libraryPath = DEFAULT_NATIVE_LIBRARY_PATH): FraudDetector {
  const library = dlopen(libraryPath, {
    fraud_init: {
      args: [],
      returns: FFIType.i32,
    },
    fraud_ready: {
      args: [],
      returns: FFIType.bool,
    },
    fraud_score_json: {
      args: SCORE_JSON_ARGS,
      returns: FFIType.u8,
    },
  });

  const symbols = library.symbols as unknown as FraudNativeSymbols;

  return {
    init: symbols.fraud_init,
    ready: symbols.fraud_ready,
    countFraudJson: (body: Uint8Array) => symbols.fraud_score_json(body, body.byteLength),
  };
}
