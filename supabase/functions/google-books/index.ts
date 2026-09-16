// google-books — a narrow proxy to the Google Books "volumes" API, so the
// API key never leaves the server.
//
// The key used to sit in the Flutter app's configuration, which put it inside
// every APK/IPA. Here it is a project secret, added to each request on its way
// to Google; the app calls this function instead of googleapis.com.
//
// It mirrors Google's own URL shape, so the client's parsing is unchanged:
//
//   GET /functions/v1/google-books/volumes?q=…&maxResults=…   (search)
//   GET /functions/v1/google-books/volumes/<volumeId>          (one volume)
//
// Only those two routes and a short allowlist of query parameters are
// forwarded — it is not an open proxy. Google's status and body are passed
// through untouched, so the client keeps telling a 404 (volume withdrawn)
// from a 429 (quota) from a 5xx exactly as before.
//
// Requires a signed-in caller (deploy with verify_jwt). Anonymous readers
// have real sessions, so every install can search.
//
// Deploy:     supabase functions deploy google-books
// Set secret: supabase secrets set GOOGLE_BOOKS_API_KEY=...
//             (without it, requests go out keyless at Google's lower quota)

const GOOGLE_BOOKS = "https://www.googleapis.com/books/v1/volumes";

/** Query parameters the app sends; anything else is dropped. */
const ALLOWED_PARAMS = ["q", "maxResults", "startIndex", "printType", "projection", "langRestrict", "orderBy"];

/** Long enough for any real title/author/ISBN query. */
const MAX_QUERY_LENGTH = 500;

/** Google volume ids are short base64url-ish strings. */
const VOLUME_ID = /^[A-Za-z0-9_-]{1,40}$/;

/** Give up before the client's own 12s timeout does. */
const DEADLINE_MS = 9_000;

/** One attempt's own ceiling, so a hung attempt still leaves room to retry. */
const ATTEMPT_TIMEOUT_MS = 3_500;

/**
 * Google Books' volumes endpoint answers 503 "backendFailed" at random —
 * measured 2026-09-16, the same request from this function failed about 60%
 * of the time, independently of the query, the key or quota. Each attempt
 * fails independently, so a few retries with exponential backoff and jitter
 * clear most of it.
 */
const MAX_ATTEMPTS = 3;
const BACKOFF_BASE_MS = 200;

/** Full jitter: a random wait up to base × 2^retry. */
function backoff(retry: number): number {
  return Math.random() * BACKOFF_BASE_MS * 2 ** (retry + 1);
}

function respond(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "GET") {
    return respond(405, { error: "Only GET is supported." });
  }

  const url = new URL(req.url);
  const route = url.pathname.match(/\/volumes(?:\/([^/]+))?\/?$/);
  if (!route) {
    return respond(404, { error: "Unknown route." });
  }

  const volumeId = route[1] ? decodeURIComponent(route[1]) : null;
  const upstream = new URL(volumeId ? `${GOOGLE_BOOKS}/${volumeId}` : GOOGLE_BOOKS);

  if (volumeId !== null) {
    if (!VOLUME_ID.test(volumeId)) {
      return respond(400, { error: "That isn't a Google Books id." });
    }
  } else {
    const q = url.searchParams.get("q")?.trim() ?? "";
    if (q.length === 0 || q.length > MAX_QUERY_LENGTH) {
      return respond(400, { error: "Enter a book title to search for." });
    }
  }

  for (const name of ALLOWED_PARAMS) {
    const value = url.searchParams.get(name);
    if (value !== null) upstream.searchParams.set(name, value);
  }
  const key = Deno.env.get("GOOGLE_BOOKS_API_KEY");
  if (key) upstream.searchParams.set("key", key);
  // Google Books localises availability by the caller's IP, and a data
  // centre's IP often has no country it recognises — which shows up as
  // intermittent 503 "backendFailed". Naming one, as Google's docs ask
  // server-side callers to, keeps it from guessing.
  upstream.searchParams.set("country", Deno.env.get("GOOGLE_BOOKS_COUNTRY") ?? "US");

  const started = Date.now();
  let last: { status: number; body: string } | null = null;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const left = DEADLINE_MS - (Date.now() - started);
    if (left <= 0) break;
    try {
      const response = await fetch(upstream, {
        signal: AbortSignal.timeout(Math.min(ATTEMPT_TIMEOUT_MS, left)),
      });
      // Read every body, failed ones included, so no connection is left open.
      last = { status: response.status, body: await response.text() };
      if (last.status < 500) break;
    } catch (error) {
      // Never echo the upstream URL: it carries the key.
      console.error("google-books: attempt failed", error instanceof Error ? error.name : "unknown");
    }
    if (attempt === MAX_ATTEMPTS - 1) break;
    const pause = backoff(attempt);
    if (Date.now() - started + pause >= DEADLINE_MS) break;
    await new Promise((resolve) => setTimeout(resolve, pause));
  }

  if (last === null) {
    return respond(504, { error: "Google Books didn't answer in time." });
  }
  if (last.status >= 500) {
    console.error("google-books: upstream still failing after retries", last.status);
  }
  return new Response(last.body, {
    status: last.status,
    headers: { "Content-Type": "application/json" },
  });
});
