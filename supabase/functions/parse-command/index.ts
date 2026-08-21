// parse-command — turns a reader's free-form sentence into the app's own
// five-command grammar (`start`, `update`, `finish`, `rate`, `delete`).
//
// This exists so the Groq API key never leaves the server. It used to sit
// in the Flutter app's bundled `.env`, which meant it shipped inside every
// APK/IPA and could be lifted out of one in minutes. Here it is a project
// secret the client never sees.
//
// The client sends `{ message }` and gets back `{ commands: string[] }`.
// Everything downstream of that — recognising, validating, applying —
// stays the Dart `LogCommandParser`'s job, exactly as before; this
// endpoint only ever splits prose into candidate command lines.
//
// Deploy:      supabase functions deploy parse-command
// Set secrets: supabase secrets set GROQ_API_KEY=...

import { createClient } from "jsr:@supabase/supabase-js@2";

const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "openai/gpt-oss-120b";

/** Long enough for any real sentence, short enough to bound the bill. */
const MAX_MESSAGE_LENGTH = 500;

/** Upstream is the slow part; give up before the client's own timeout. */
const GROQ_TIMEOUT_MS = 15_000;

const SYSTEM_PROMPT =
  `You split a reader's natural-language sentence about their reading into a list of structured commands. Only these five commands exist, and every line you output must match one of them exactly (case-insensitive keyword, one command per line, no numbering, no extra words):

start <book title>
update <book title> <page number>
finish <book title>
rate <book title> <stars, 0-5, .5 allowed>
delete <book title>

Rules:
- Extract every distinct action the sentence describes, in the order mentioned.
- Use the book title as written (fix obvious capitalization only).
- If a sentence mentions no page number or star rating, don't guess one — drop that action instead of inventing a number.
- Output ONLY a JSON array of strings, each string one command line. No prose, no markdown fences.
- If nothing recognizable is mentioned, output a single-element array containing exactly the word "gibberish" (lowercase, nothing else): ["gibberish"]`;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Every failure the client can see. `message` is written for a reader and
 * is rendered verbatim by the app, so it must never carry upstream detail
 * — that goes to the function logs instead.
 */
function fail(status: number, message: string, logDetail?: unknown): Response {
  if (logDetail !== undefined) {
    console.error(`parse-command ${status}:`, logDetail);
  }
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return fail(405, "That request isn't supported.");
  }

  const groqApiKey = Deno.env.get("GROQ_API_KEY");
  if (!groqApiKey) {
    return fail(
      500,
      "The AI isn't available right now.",
      "GROQ_API_KEY is not set on this project.",
    );
  }

  // ------------------------------------------------------------- input
  let message: unknown;
  try {
    message = (await request.json())?.message;
  } catch (error) {
    return fail(400, "That message couldn't be read.", error);
  }

  if (typeof message !== "string" || message.trim().length === 0) {
    return fail(400, "Type something first.");
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return fail(413, "That's a bit long — try one or two sentences.");
  }

  // ------------------------------------------------- caller + allowance
  // The client's own JWT is forwarded rather than using the service role,
  // so `auth.uid()` inside `claim_ai_request()` resolves to the actual
  // reader and the rate limit is per-reader rather than per-project.
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return fail(401, "Sign in to use this.");
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: user, error: userError } = await supabase.auth.getUser();
  if (userError || !user?.user) {
    return fail(401, "Sign in to use this.", userError);
  }

  const { data: allowed, error: limitError } = await supabase.rpc(
    "claim_ai_request",
  );
  if (limitError) {
    return fail(500, "The AI isn't available right now.", limitError);
  }
  if (allowed === false) {
    return fail(429, "You've used a lot of AI just now — try again shortly.");
  }

  // ---------------------------------------------------------- upstream
  let groqResponse: Response;
  try {
    groqResponse = await fetch(GROQ_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        temperature: 0,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: message },
        ],
      }),
      signal: AbortSignal.timeout(GROQ_TIMEOUT_MS),
    });
  } catch (error) {
    return fail(
      504,
      "Couldn't reach the AI right now — try again in a moment.",
      error,
    );
  }

  if (!groqResponse.ok) {
    return fail(
      502,
      "Couldn't reach the AI right now — try again in a moment.",
      `Groq HTTP ${groqResponse.status}: ${await groqResponse.text()}`,
    );
  }

  // ------------------------------------------------------------ output
  let commands: string[];
  try {
    commands = parseCommands(await groqResponse.json());
  } catch (error) {
    return fail(502, "The AI's reply couldn't be read.", error);
  }

  return new Response(JSON.stringify({ commands }), {
    status: 200,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
});

/**
 * Digs the model's reply out of the chat-completions envelope, then
 * decodes the JSON array it was asked for — tolerant of a stray code
 * fence around it, since models add those despite being told not to.
 * Throws (rather than degrading to an empty list) for anything that isn't
 * that shape, so a malformed reply surfaces as a real error instead of
 * silently doing nothing.
 */
function parseCommands(body: unknown): string[] {
  const content = (body as {
    choices?: { message?: { content?: unknown } }[];
  })?.choices?.[0]?.message?.content;

  if (typeof content !== "string") {
    throw new Error("no string content in completion");
  }

  const cleaned = content
    .trim()
    .replace(/^```(?:json)?/m, "")
    .replace(/```$/m, "")
    .trim();

  const decoded: unknown = JSON.parse(cleaned);
  if (!Array.isArray(decoded)) {
    throw new Error("completion content is not a JSON array");
  }

  return decoded
    .filter((line): line is string => typeof line === "string")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}
