import { WARMUP_ROUNDS } from "./config";
import { type FraudDetector } from "./fraud";

const encoder = new TextEncoder();

const WARMUP_BODIES = [
  encoder.encode(
    '{"id":"tx-warmup-001","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.7090520965},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.8626479774}}',
  ),
  encoder.encode(
    '{"id":"tx-warmup-002","transaction":{"amount":5444.38,"installments":11,"requested_at":"2026-03-19T00:52:47Z"},"customer":{"avg_amount":104.54,"tx_count_24h":9,"known_merchants":["MERC-012","MERC-004","MERC-018"]},"merchant":{"id":"MERC-097","mcc":"7801","avg_amount":63.57},"terminal":{"is_online":true,"card_present":false,"km_from_home":932.4228241882},"last_transaction":null}',
  ),
];

export function warmupDetector(detector: FraudDetector, rounds = WARMUP_ROUNDS): void {
  if (rounds <= 0 || !detector.ready()) return;

  for (let i = 0; i < rounds; i += 1) {
    detector.countFraudJson(WARMUP_BODIES[i % WARMUP_BODIES.length]!);
  }
}
