// parse-command — turns a reader's free-form sentence into the app's own
// seven-command grammar: the original five shelf commands (`start`,
// `update`, `finish`, `rate`, `delete` — the first three take an
// optional trailing date, resolved from a phrase like "yesterday"), plus
// `remember` (save a note on how a book made them feel) and `recommend`
// (suggest a book, grounded in the reader's own shelf and remembered
// notes).
//
// This exists so the Groq API key never leaves the server. It used to sit
// in the Flutter app's bundled `.env`, which meant it shipped inside every
// APK/IPA and could be lifted out of one in minutes. Here it is a project
// secret the client never sees.
//
// The client sends `{ message, context? }` and gets back
// `{ commands: string[] }`. `context` is the reader's local "today"
// (needed to resolve "yesterday" et al. to an absolute date) plus, for
// `recommend` only, their current shelf titles and past `remember`
// notes — sent by the client because this function has no database
// access of its own for the caller's tables beyond `claim_ai_request()`
// (see below). Everything downstream of the returned commands —
// recognising, validating, applying — stays the Dart
// `LogCommandParser`'s job, exactly as before; this endpoint only ever
// splits prose into candidate command lines.
//
// Deploy:      supabase functions deploy parse-command
// Set secrets: supabase secrets set GROQ_API_KEY=...

import { createClient } from "jsr:@supabase/supabase-js@2";

const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "openai/gpt-oss-120b";

/** Long enough for any real sentence, short enough to bound the bill. */
const MAX_MESSAGE_LENGTH = 500;

/** Caps on the optional context block — bounds both the prompt's token
 * cost and how much of it one request can carry, regardless of how
 * large the reader's actual shelf or memory list has grown. */
const MAX_CONTEXT_ITEMS = 100;
const MAX_CONTEXT_ITEM_LENGTH = 200;

/** Upstream is the slow part; give up before the client's own timeout. */
const GROQ_TIMEOUT_MS = 15_000;

const BASE_SYSTEM_PROMPT =
  `You split a reader's natural-language sentence about their reading into a list of structured commands. Only these seven commands exist, and every line you output must match one of them exactly (case-insensitive keyword, one command per line, no numbering, no extra words):

start <book title> [date]
update <book title> <page number> [date]
finish <book title> [date]
rate <book title> <stars, 0-5, .5 allowed>
delete <book title>
remember <book title> :: <note>
recommend <book title> :: <reason>

Rules:
- Extract every distinct action the sentence describes, in the order mentioned. A single sentence can produce more than one line — e.g. "finished Dune, loved the ending" is both a finish line and a remember line.
- Use the book title as written (fix obvious capitalization only).
- If a sentence mentions no page number or star rating, don't guess one — drop that action instead of inventing a number.
- The optional trailing [date] on start/update/finish is a YYYY-MM-DD, present only when the sentence itself names or implies when the action happened ("yesterday", "last Friday", "on the 3rd", "two days ago", "this morning"). Resolve it relative to the reader's own "today" given below and append it as one more space-separated token after the command's other arguments (after the page number for update). Omit it entirely when the sentence doesn't reference a day — never invent one for a plain "started Dune".
- Emit a "remember" line whenever the sentence expresses a personal reaction, opinion, or feeling about a book, a character, or a chapter — not just a plain shelf action. Keep the note short and in the reader's own words; don't editorialize.
- Emit a "recommend" line whenever the sentence asks for a book suggestion. Recommend one real, already-published book that is not already on the reader's shelf (see the shelf and remembered notes below, if any) and that fits both the sentence's own stated criteria and, where relevant, what the remembered notes reveal about the reader's taste. <reason> is one short sentence explaining the pick.
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
  let body: { message?: unknown; context?: unknown };
  try {
    body = (await request.json()) ?? {};
  } catch (error) {
    return fail(400, "That message couldn't be read.", error);
  }
  const message = body.message;

  if (typeof message !== "string" || message.trim().length === 0) {
    return fail(400, "Type something first.");
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return fail(413, "That's a bit long — try one or two sentences.");
  }

  // `context` is optional and entirely client-supplied — the reader's
  // local "today" (for resolving "yesterday" on start/update/finish),
  // plus their shelf titles and remembered notes (grounding for
  // `recommend` only). Never trusted for anything but shaping the
  // prompt, so a malformed shape here degrades to "no context" rather
  // than a 400: the reader typed a real sentence, and it deserves an
  // answer even if the client sent context in a shape this version
  // doesn't expect.
  const systemPrompt = BASE_SYSTEM_PROMPT + buildContextBlock(body.context);

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
          { role: "system", content: systemPrompt },
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

/** Matches the client's `today` — a plain calendar date, no time. */
const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Turns the client-supplied `context` — the reader's local "today",
 * shelf titles, and remembered notes — into the block of prompt text
 * appended to the base prompt. Empty string when there's nothing usable
 * at all, so a request from a stale client that never sends `context`
 * degrades to the base prompt exactly as before this existed.
 *
 * Every value here is client-supplied and untrusted: it only ever
 * shapes a prompt, never touches SQL or a shell, so the worst a hostile
 * payload can do is waste tokens, produce a bad recommendation, or
 * resolve a relative date against a wrong "today" — all bounded by the
 * caps below and none of them a security issue on their own.
 */
function buildContextBlock(context: unknown): string {
  if (typeof context !== "object" || context === null) return "";
  const raw = context as {
    today?: unknown;
    library?: unknown;
    memories?: unknown;
  };

  const today = typeof raw.today === "string" && DATE_ONLY.test(raw.today)
    ? raw.today
    : null;
  const library = sanitizeStringList(raw.library);
  const memories = sanitizeMemoryList(raw.memories);
  if (today === null && library.length === 0 && memories.length === 0) {
    return "";
  }

  const lines: string[] = ["\n\nContext:"];
  if (today !== null) {
    lines.push(
      `Today's date is ${today} — resolve any relative date/time ` +
        'phrase ("yesterday", "last Friday") against this before ' +
        "appending it to a start/update/finish line, per the rule above.",
    );
  }
  if (library.length > 0 || memories.length > 0) {
    lines.push('For "recommend" only — ignore this part for every other command:');
    if (library.length > 0) {
      lines.push(`The reader's current shelf: ${library.join(", ")}.`);
    }
    if (memories.length > 0) {
      lines.push("Notes the reader has saved about past books:");
      for (const memory of memories) {
        lines.push(
          memory.title
            ? `- ${memory.title}: ${memory.note}`
            : `- ${memory.note}`,
        );
      }
    }
  }
  return lines.join("\n");
}

function sanitizeStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim().slice(0, MAX_CONTEXT_ITEM_LENGTH))
    .filter((item) => item.length > 0)
    .slice(0, MAX_CONTEXT_ITEMS);
}

function sanitizeMemoryList(
  value: unknown,
): { title: string | null; note: string }[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is Record<string, unknown> =>
      typeof item === "object" && item !== null
    )
    .map((item) => ({
      title: typeof item.title === "string"
        ? item.title.trim().slice(0, MAX_CONTEXT_ITEM_LENGTH)
        : null,
      note: typeof item.note === "string"
        ? item.note.trim().slice(0, MAX_CONTEXT_ITEM_LENGTH)
        : "",
    }))
    .filter((item) => item.note.length > 0)
    .slice(0, MAX_CONTEXT_ITEMS);
}
