import { UNAVAILABLE_DETECTOR, loadNativeFraud, type FraudDetector } from "./fraud";

export function createRuntimeDetector(): FraudDetector {
  try {
    const detector = loadNativeFraud();
    const initCode = detector.init();

    if (initCode !== 0) {
      console.error(`fraud_init failed with code ${initCode}`);
      return UNAVAILABLE_DETECTOR;
    }

    return detector;
  } catch (error) {
    console.error("failed to load fraud native library", error);
    return UNAVAILABLE_DETECTOR;
  }
}
