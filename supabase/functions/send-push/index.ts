// Supabase Edge Function: send-push
// -----------------------------------------------------------------------------
// Sends an FCM push when a row is inserted into public.notifications.
// Trigger it via a Supabase Database Webhook (Dashboard → Database → Webhooks):
//   table: notifications · event: INSERT · type: HTTP Request → this function URL.
//
// Secrets (set once):
//   1) Base64-encode the service-account JSON (avoids newline/quote issues):
//        PowerShell:
//          [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\sa.json"))
//   2) supabase secrets set FIREBASE_SERVICE_ACCOUNT_B64="<paste the base64 string>"
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// Deploy:
//   supabase functions deploy send-push
//
// The service account is the JSON from:
//   Firebase Console → Project Settings → Service accounts → Generate new private key.
// It is a SECRET — it lives only here, never in the app.
// -----------------------------------------------------------------------------

import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

Deno.serve(async (req) => {
  try {
    // Hardening: when PUSH_WEBHOOK_SECRET is set, require the caller (the DB
    // webhook) to send a matching `x-webhook-secret` header. Until the secret is
    // set, the check is skipped (so deploy order is flexible) — set it + add the
    // webhook header to lock the public function URL against abuse.
    const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
    if (expectedSecret && req.headers.get("x-webhook-secret") !== expectedSecret) {
      return json({ error: "unauthorized" }, 401);
    }

    const payload = await req.json();
    // A Database Webhook posts { type, table, record, old_record }.
    const record = payload?.record ?? payload;
    const userId: string | undefined = record?.user_id;
    if (!userId) return json({ skipped: "no user_id in payload" }, 200);

    const title: string = record?.title ?? "SILENCE";
    const body: string = record?.body ?? "";
    const data = record?.data ?? {};

    // The service account is stored base64-encoded to survive shell/newline quoting.
    const b64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64");
    const serviceAccount = JSON.parse(
      b64 ? atob(b64) : Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!,
    );
    const projectId: string = serviceAccount.project_id;

    // 1. Read the recipient's device tokens (service role bypasses RLS).
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId);
    if (error) throw error;
    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, reason: "no device tokens for user" }, 200);
    }

    // 2. OAuth access token for the FCM HTTP v1 API.
    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: [FCM_SCOPE],
    });
    const { access_token } = await jwtClient.authorize();

    // 3. Send to every device; collect dead tokens to prune.
    const dead: string[] = [];
    let sent = 0;
    for (const { token } of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access_token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body },
              data: stringifyValues(data),
            },
          }),
        },
      );

      if (res.ok) {
        sent++;
      } else {
        const errText = await res.text();
        // Only prune tokens FCM says are gone — never on a transient/payload error.
        if (res.status === 404 || errText.includes("UNREGISTERED")) {
          dead.push(token);
        }
        console.error(`FCM send failed (${res.status}): ${errText}`);
      }
    }

    // 4. Remove stale tokens so we stop pushing to dead devices.
    if (dead.length) {
      await supabase.from("device_tokens").delete().in("token", dead);
    }

    return json({ sent, pruned: dead.length }, 200);
  } catch (e) {
    console.error("send-push error:", e);
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// FCM v1 `data` values must all be strings.
function stringifyValues(obj: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj ?? {})) {
    out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}
