// Supabase Edge Function: process-account-deletions
// -----------------------------------------------------------------------------
// Permanently purges accounts whose 7-day recovery window has passed without an
// approved recovery. Intended to run on a SCHEDULE (cron), e.g. daily.
//
// For each due user it: deletes their storage objects, calls the SECURITY
// DEFINER `purge_account(user_id)` RPC (DB rows), then deletes the auth user.
//
// Due = scheduled_for_deletion = true
//       AND deletion_scheduled_at < now()
//       AND deletion_recovery_status <> 'approved'
//
// Deploy:   supabase functions deploy process-account-deletions
// Schedule: Dashboard → Edge Functions → process-account-deletions → add a cron
//           schedule (e.g. "0 2 * * *"), OR pg_cron calling the function URL.
//
// (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// ⛔ DESTRUCTIVE & IRREVERSIBLE. Test on a throwaway account before scheduling.
//    Verify purge_account() covers all your FK-referencing tables.
// -----------------------------------------------------------------------------

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Find accounts past their recovery window, not approved.
    const { data: due, error } = await supabase
      .from("users")
      .select("id")
      .eq("scheduled_for_deletion", true)
      .neq("deletion_recovery_status", "approved")
      .lt("deletion_scheduled_at", new Date().toISOString());
    if (error) throw error;
    if (!due || due.length === 0) {
      return json({ purged: 0, reason: "none due" }, 200);
    }

    const results: Record<string, string> = {};
    for (const { id } of due) {
      try {
        // 2. Delete their storage objects (best-effort, per known path family).
        for (const prefix of [`member_profiles/${id}`, `payment_proofs/${id}`]) {
          try {
            const { data: files } = await supabase.storage
              .from("silence_private")
              .list(prefix);
            if (files && files.length) {
              await supabase.storage
                .from("silence_private")
                .remove(files.map((f) => `${prefix}/${f.name}`));
            }
          } catch (_) { /* ignore storage gaps */ }
        }

        // 3. Delete all DB rows (transactional, server-side).
        const { error: purgeErr } = await supabase.rpc("purge_account", { p_user_id: id });
        if (purgeErr) throw purgeErr;

        // 4. Delete the auth user (admin API).
        const { error: authErr } = await supabase.auth.admin.deleteUser(id);
        if (authErr && !`${authErr.message}`.includes("not found")) throw authErr;

        results[id] = "purged";
      } catch (e) {
        console.error(`purge failed for ${id}:`, e);
        results[id] = `failed: ${e}`;
      }
    }

    const purged = Object.values(results).filter((v) => v === "purged").length;
    return json({ purged, total: due.length, results }, 200);
  } catch (e) {
    console.error("process-account-deletions error:", e);
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
