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
const UPSTREAM_TIMEOUT_MS = 10_000;

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

  try {
    const response = await fetch(upstream, {
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    // Never echo the upstream URL: it carries the key.
    console.error("google-books: upstream request failed", error instanceof Error ? error.name : "unknown");
    return respond(504, { error: "Google Books didn't answer in time." });
  }
});
