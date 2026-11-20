// Cloudflare Worker: a small proxy between the game and Google's Gemini API.
//
// The game sends Alice's conversation here; this Worker adds the API key
// (stored as a Cloudflare secret, never in the game) and forwards it to Google.
// So the key is never downloadable from the itch.io build.
//
// Setup: paste this file into a Worker, then add a SECRET named GEMINI_API_KEY.
//
// Backup models: Google's free tier allows 15 requests per minute PER MODEL.
// When the requested model is over its limit (HTTP 429) or overloaded
// (500/503), the Worker retries the same request on the next backup model,
// which has its own separate limit. The game doesn't need to know.
//
// Abuse limits (anyone can find this URL in the game, so it only does exactly
// what Alice needs): allowed models only, short conversations only, capped
// reply length, and browsers are only accepted from itch.io and localhost.

const ALLOWED_MODELS = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest"];
// Tried in order when the requested model is busy. 2.5 is only served to
// projects that already used it, so it may answer 403/404: that's skipped too.
const FALLBACK_MODELS = ["gemini-3.1-flash-lite", "gemini-2.5-flash-lite"];
const RETRY_STATUSES = [429, 500, 503];
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

    const models = [model, ...FALLBACK_MODELS.filter((m) => m !== model)];
    let first = null;
    for (let i = 0; i < models.length; i++) {
      const isBackup = i > 0;
      let res = await callGoogle(models[i], body, env.GEMINI_API_KEY);
      // Older models don't all accept the same thinking settings: retry without them.
      if (res.status === 400 && body.generationConfig.thinkingConfig && /thinking/i.test(res.text)) {
        const plain = { ...body, generationConfig: { ...body.generationConfig } };
        delete plain.generationConfig.thinkingConfig;
        res = await callGoogle(models[i], plain, env.GEMINI_API_KEY);
      }
      if (!first) first = res;
      const busy = RETRY_STATUSES.includes(res.status);
      const unavailable = isBackup && [400, 403, 404].includes(res.status);   // backup not usable here
      if (!busy && !unavailable) {
        const r = reply(res.status, res.text, origin);
        r.headers.set("X-Model-Used", models[i]);
        return r;
      }
    }
    return reply(first.status, first.text, origin);   // every model busy: pass on the main model's refusal (e.g. 429, so the game backs off)
  },
};

async function callGoogle(model, body, key) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify(body),
    }
  );
  return { status: res.status, text: await res.text() };
}
