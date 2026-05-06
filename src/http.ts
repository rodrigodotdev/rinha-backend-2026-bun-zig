import { type FraudDetector } from "./fraud";

const JSON_HEADERS = {
  "Content-Type": "application/json",
} as const;

const OK_JSON = {
  status: 200,
  headers: JSON_HEADERS,
} as const;

const NOT_READY_JSON_INIT = {
  status: 503,
  headers: JSON_HEADERS,
} as const;

const NOT_FOUND_JSON_INIT = {
  status: 404,
  headers: JSON_HEADERS,
} as const;

const METHOD_NOT_ALLOWED_GET_INIT = {
  status: 405,
  headers: { ...JSON_HEADERS, Allow: "GET" },
} as const;

const METHOD_NOT_ALLOWED_POST_INIT = {
  status: 405,
  headers: { ...JSON_HEADERS, Allow: "POST" },
} as const;

const READY_JSON = "{\"status\":\"ok\"}";
const NOT_READY_JSON = "{\"status\":\"not_ready\"}";
const NOT_FOUND_JSON = "{\"error\":\"not_found\"}";
const METHOD_NOT_ALLOWED_JSON = "{\"error\":\"method_not_allowed\"}";

const FRAUD_FALLBACK_JSON = "{\"approved\":true,\"fraud_score\":0.0}";
const FRAUD_RESPONSE_BY_NEIGHBOR_COUNT = [
  FRAUD_FALLBACK_JSON,
  "{\"approved\":true,\"fraud_score\":0.2}",
  "{\"approved\":true,\"fraud_score\":0.4}",
  "{\"approved\":false,\"fraud_score\":0.6}",
  "{\"approved\":false,\"fraud_score\":0.8}",
  "{\"approved\":false,\"fraud_score\":1}",
] as const;
const MAX_FRAUD_RESPONSE_JSON = FRAUD_RESPONSE_BY_NEIGHBOR_COUNT[5];

function requestPath(rawUrl: string): string {
  const schemeIndex = rawUrl.indexOf("://");
  let pathStart = 0;

  if (schemeIndex !== -1) {
    pathStart = rawUrl.indexOf("/", schemeIndex + 3);
    if (pathStart === -1) return "/";
  }

  const queryStart = rawUrl.indexOf("?", pathStart);
  return queryStart === -1 ? rawUrl.slice(pathStart) : rawUrl.slice(pathStart, queryStart);
}

function fraudResponseJson(neighbors: number): string {
  if (neighbors <= 0) return FRAUD_FALLBACK_JSON;
  return FRAUD_RESPONSE_BY_NEIGHBOR_COUNT[neighbors] ?? MAX_FRAUD_RESPONSE_JSON;
}

function readyResponse(detector: FraudDetector): Response {
  try {
    return detector.ready()
      ? new Response(READY_JSON, OK_JSON)
      : new Response(NOT_READY_JSON, NOT_READY_JSON_INIT);
  } catch {
    return new Response(NOT_READY_JSON, NOT_READY_JSON_INIT);
  }
}

async function fraudScoreResponse(req: Request, detector: FraudDetector): Promise<Response> {
  try {
    const body = await req.bytes();
    return new Response(fraudResponseJson(detector.countFraudJson(body)), OK_JSON);
  } catch {
    return new Response(FRAUD_FALLBACK_JSON, OK_JSON);
  }
}

export function handleRequest(req: Request, detector: FraudDetector): Response | Promise<Response> {
  const path = requestPath(req.url);

  if (path === "/ready") {
    return req.method === "GET"
      ? readyResponse(detector)
      : new Response(METHOD_NOT_ALLOWED_JSON, METHOD_NOT_ALLOWED_GET_INIT);
  }

  if (path === "/fraud-score") {
    return req.method === "POST"
      ? fraudScoreResponse(req, detector)
      : new Response(METHOD_NOT_ALLOWED_JSON, METHOD_NOT_ALLOWED_POST_INIT);
  }

  return new Response(NOT_FOUND_JSON, NOT_FOUND_JSON_INIT);
}
