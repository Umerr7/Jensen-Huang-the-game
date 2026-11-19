// Cloudflare Worker: a small proxy between the game and Google's Gemini API.
//
// The game sends Alice's conversation here; this Worker adds the API key
// (stored as a Cloudflare secret, never in the game) and forwards it to Google.
// So the key is never downloadable from the itch.io build.
//
// Setup: paste this file into a Worker, then add a SECRET named GEMINI_API_KEY.
//
// Abuse limits (anyone can find this URL in the game, so it only does exactly
// what Alice needs): allowed models only, short conversations only, capped
// reply length, and browsers are only accepted from itch.io and localhost.

const ALLOWED_MODELS = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest"];
const MAX_TURNS = 12;               // Alice's chat is ~8 messages at most
const MAX_REQUEST_CHARS = 40000;    // personality file (~12k) + the chat
const MAX_OUTPUT_TOKENS = 1024;

function originAllowed(origin) {
  if (!origin) return true;   // desktop / editor builds send no Origin header
  try {
    const host = new URL(origin).hostname;
    return host === "itch.io" || host.endsWith(".itch.io") || host.endsWith(".itch.zone") ||
           host === "localhost" || host === "127.0.0.1";
  } catch {
    return false;
  }
}

function cors(origin) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function reply(status, body, origin) {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors(origin) },
  });
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    if (!originAllowed(origin)) return reply(403, { error: "origin not allowed" }, null);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
    if (request.method !== "POST") return reply(405, { error: "POST only" }, origin);
    if (!env.GEMINI_API_KEY) return reply(500, { error: "GEMINI_API_KEY secret is not set on the Worker" }, origin);

    const raw = await request.text();
    if (raw.length > MAX_REQUEST_CHARS) return reply(413, { error: "request too large" }, origin);
    let req;
    try { req = JSON.parse(raw); } catch { return reply(400, { error: "invalid JSON" }, origin); }

    const model = String(req.model || "");
    if (!ALLOWED_MODELS.includes(model)) return reply(400, { error: "model not allowed" }, origin);
    if (!Array.isArray(req.contents) || req.contents.length === 0 || req.contents.length > MAX_TURNS)
      return reply(400, { error: "bad conversation length" }, origin);

    // Only forward the fields Alice uses, with the reply length capped.
    const gen = Object.assign({}, req.generationConfig || {});
    gen.maxOutputTokens = Math.min(Number(gen.maxOutputTokens) || MAX_OUTPUT_TOKENS, MAX_OUTPUT_TOKENS);
    const body = { contents: req.contents, generationConfig: gen };
    if (req.systemInstruction) body.systemInstruction = req.systemInstruction;

    const google = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: JSON.stringify(body),
      }
    );
    return reply(google.status, await google.text(), origin);
  },
};
