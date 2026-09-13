// link-account — settles which library an email account keeps when a second
// device links an email that already has one.
//
// The device has proven both things before calling:
//   * it signed in to the email account (the request's Authorization header
//     is that account's JWT), and
//   * it holds the anonymous account it started on (`anonymous_access_token`
//     in the body).
// Both tokens are verified here; neither user id is taken from the body.
//
// `keep: "account"` — the email account's library stays; the anonymous
// account and everything on it is deleted.
// `keep: "device"`  — the anonymous account's library is moved onto the
// email account (replacing what was there) by `adopt_library`, then the
// anonymous account is deleted.
//
// The email account's user id survives either way — see the
// `20260915030000_account_linking` migration for why.
//
// Deploy: supabase functions deploy link-account
// Uses SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY, which
// every Supabase edge function already has.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function fail(status: number, message: string, logDetail?: unknown): Response {
  if (logDetail !== undefined) console.error(`link-account ${status}:`, logDetail);
  return respond(status, { error: message });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return fail(405, "That request isn't supported.");
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const accountToken = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!accountToken) return fail(401, "Sign in to your email first.");

  let body: { anonymous_access_token?: unknown; keep?: unknown };
  try {
    body = (await request.json()) ?? {};
  } catch (error) {
    return fail(400, "That request couldn't be read.", error);
  }
  const deviceToken = body.anonymous_access_token;
  const keep = body.keep;
  if (typeof deviceToken !== "string" || deviceToken.length === 0) {
    return fail(400, "This device's library couldn't be identified.");
  }
  if (keep !== "account" && keep !== "device") {
    return fail(400, "Choose which library to keep.");
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { data: accountData, error: accountError } = await admin.auth.getUser(
    accountToken,
  );
  const account = accountData?.user;
  if (accountError || !account) {
    return fail(401, "Your sign-in has expired — try again.", accountError);
  }
  if (account.is_anonymous || !account.email) {
    return fail(400, "That account has no email linked.");
  }

  const { data: deviceData, error: deviceError } = await admin.auth.getUser(
    deviceToken,
  );
  const device = deviceData?.user;
  if (deviceError || !device) {
    return fail(401, "This device's session has expired — reopen the app.", deviceError);
  }
  if (device.id === account.id) {
    return respond(200, { ok: true, user_id: account.id });
  }
  if (!device.is_anonymous) {
    // Never delete an account that has its own email: that is someone's
    // backed-up library, not a throwaway install.
    return fail(409, "This device is already linked to a different email.");
  }

  if (keep === "device") {
    const { error } = await admin.rpc("adopt_library", {
      p_from: device.id,
      p_to: account.id,
    });
    if (error) {
      return fail(500, "We couldn't move your library. Nothing was deleted.", error);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(device.id);
  if (deleteError) {
    // The library choice already landed; a leftover empty anonymous account
    // is harmless, so report success but log it.
    console.error("link-account: could not delete anonymous user", deleteError);
  }

  return respond(200, { ok: true, user_id: account.id });
});
