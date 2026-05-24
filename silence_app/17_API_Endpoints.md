## File 17: API Endpoints (Supabase Functions & RPC) – Complete

**File name:** `17_API_Endpoints.md` (regenerated, all content unified)

```markdown
# SILENCE – API Endpoints (Supabase)

## Overview
SILENCE uses **Supabase** for CRUD operations directly from the client (with RLS). Complex or multi‑step operations use **Postgres functions** (via `.rpc()`) or **Edge Functions** (for webhooks, payments, notifications).

---

## 1. Postgres Functions (RPC)

### `rpc_check_in` – Record a check-in
**Parameters:**
```json
{
  "p_member_id": "uuid",
  "p_library_id": "uuid",
  "p_shift_id": "uuid",
  "p_qr_version": "integer",
  "p_device_id": "text",
  "p_timestamp": "timestamptz"
}
```
**Returns:** `{ success: boolean, session_id: uuid, message: text }`
**Logic:**
- Validate membership (active/trial/grace/expired with admin toggle)
- Check no open session for today
- Create attendance record with `check_in_time`
- Update seat status to occupied

### `rpc_check_out` – Record a checkout (or handle overtime)
**Parameters:** same as check-in
**Returns:** `{ success: boolean, duration_minutes: integer, message: text }`
**Logic:**
- Find open session for member+library+shift today
- Set `check_out_time = p_timestamp`
- Compute duration, handle overtime (notify admin if post‑shift)
- If session already closed, return error

### `rpc_auto_checkout_sweep` – Scheduled job
**Parameters:** `{ p_shift_id: uuid, p_cutoff_time: timestamptz }`
**Returns:** `{ closed_count: integer }`
**Logic:**
- Find all open sessions for shift with no check‑out
- Set `check_out_time = shift_end_time`
- Mark `session_type = 'auto_checkout'`

### `rpc_auto_hold_expired` – Scheduled job
**Parameters:** `{ p_grace_days: integer }`
**Returns:** `{ held_count: integer }`
**Logic:**
- Find memberships with `status = 'active'` and `end_date < now() - grace_days`
- Set `status = 'hold'`, `hold_until = now() + 30 days`
- Free seat (set `seats.occupied_by_member_id = NULL`)

### `rpc_can_member_join` – Pre‑validation before join request
**Parameters:** `{ p_member_id: uuid, p_library_id: uuid, p_phone: text }`
**Returns:** `{ allowed: boolean, existing_membership_id: uuid, message: text }`
**Logic:**
- Check if phone already has active membership at this library
- If yes, return existing membership ID for reactivation
- Check if library is accepting new members (`status='active'`)

### `rpc_approve_join_request` – Full approval transaction
**Parameters:** `{ p_request_id: uuid, p_seat_id: uuid, p_admin_id: uuid }`
**Returns:** `{ membership_id: uuid, success: boolean }`
**Logic (transactional):**
- Lock join_request row
- Verify seat still vacant for chosen shift
- Create membership record
- Update `seat.occupied_by_member_id`
- Update `join_request.status = 'approved'`
- Send notification
- Log in `audit_log`

### `rpc_renew_membership` – Renew an existing membership
**Parameters:** `{ p_membership_id: uuid, p_new_plan: text, p_new_shift_id: uuid, p_new_seat_id: uuid, p_start_date: date, p_discount_amount: integer, p_discount_reason: text, p_admin_id: uuid }`
**Returns:** `{ new_membership_id: uuid, success: boolean }`
**Logic:**
- End current membership (`status='transferred'` or `'exited'`)
- Create new membership with same member_id
- Preserve history linkage (`transferred_from` column)
- Update seat occupancy if shift/seat changed

### `rpc_transfer_member` – Move member between libraries (same admin)
**Parameters:** `{ p_member_id: uuid, p_from_library_id: uuid, p_to_library_id: uuid, p_new_shift_id: uuid, p_new_seat_id: uuid, p_transfer_date: timestamptz, p_admin_id: uuid }`
**Returns:** `{ new_membership_id: uuid, success: boolean }`
**Logic:**
- Verify both libraries belong to same admin (`owner_id`)
- End old membership (`status='transferred'`)
- Create new membership at destination
- Preserve member_id, copy history flags
- Log in `transfers` table

### `rpc_earn_badge` – Auto badge assignment (trigger on attendance)
**Parameters:** `{ p_member_id: uuid, p_library_id: uuid }`
**Returns:** `{ badges_earned: text[] }`
**Logic:**
- Check all badge conditions for this member
- Insert new rows in `badges` table for any newly earned
- Return list of badges earned

### `rpc_get_leaderboard` – Get top members by study hours
**Parameters:** `{ p_library_id: uuid, p_period: text, p_limit: integer }` (period: `'week'`, `'month'`, `'all'`)
**Returns:** `[{ rank, nickname, hours, member_id }]`
**Logic:**
- Sum `attendance.duration_minutes` for period, filter by library
- Exclude incomplete sessions (`duration_minutes = 0`)
- Order by hours desc, limit

### `rpc_sync_offline_queue` – Batch insert offline scans (called from client after online)
**Parameters:** `{ p_scans: json[] }` (each scan: `member_id`, `library_id`, `shift_id`, `timestamp`, `qr_version`, `device_id`)
**Returns:** `{ accepted_count: integer, rejected_count: integer, errors: json[] }`
**Logic:**
- For each scan, attempt check‑in/check‑out
- If successful, remove from queue
- If conflict (duplicate or window exceeded), reject and notify client to delete

---

## 2. Edge Functions (HTTP)

### `POST /edge/send-notification`
**Trigger:** From backend or webhook  
**Auth:** Service role key (not for client)  
**Body:**
```json
{
  "user_id": "uuid",
  "title": "string",
  "body": "string",
  "data": { "screen": "string", "id": "uuid" }
}
```
**Action:** Fetch user's `fcm_token` from `users` table, send via FCM.

### `POST /edge/razorpay-webhook`
**Auth:** Razorpay signature verification  
**Body:** Razorpay event payload  
**Actions:**
- `subscription.charged` → update `users.subscription_expiry`, log payment
- `subscription.payment_failed` → start grace period
- `subscription.cancelled` → set status to cancelled (active until expiry)

### `POST /edge/create-razorpay-subscription`
**Auth:** Admin session (JWT)  
**Body:**
```json
{
  "plan_id": "plan_Pro_Monthly",
  "billing_cycle": "monthly"
}
```
**Action:** Create Razorpay subscription, return `subscription_id` and `order_id` to client for checkout.

### `POST /edge/cancel-razorpay-subscription`
**Auth:** Admin session  
**Body:** `{ "reason": "optional" }`  
**Action:** Call Razorpay API to cancel future renewals. Update `users.subscription_status = 'cancelled'`.

### `POST /edge/send-bulk-notifications`
**Trigger:** Admin sends announcement  
**Auth:** Admin session  
**Body:**
```json
{
  "library_id": "uuid",
  "title": "string",
  "message": "string",
  "recipient_ids": ["uuid"]
}
```
**Action:** Insert announcement record, then call `send-notification` for each recipient in batch.

### `GET /edge/health`
**Auth:** None (public)  
**Returns:** `{ status: "ok", timestamp: "..." }`  
**Use:** Monitoring

---

## 3. Standard Supabase REST (Client Direct)

The following tables are directly accessible via Supabase REST API (with RLS enforced):

- `users` (partial: update own profile, select for members list)
- `libraries` (select, insert/update by owner)
- `shifts`, `floors`, `sections`, `seats` (CRUD by owner, select by anyone)
- `memberships`, `attendance`, `payments` (select by owner/member, insert by member)
- `join_requests`, `seat_change_requests`, `hold_requests` (select/insert by member, update by admin)
- `add_ons`, `member_add_ons`
- `referrals`, `badges`, `announcements`, `queries`, `notifications`, `audit_log`, `scheduled_closures`

**Real‑time subscriptions** are optional (enable via Supabase Realtime for live occupancy updates).

---

## 4. Supabase Storage (File Upload)

**Endpoints (client‑side):**
- `supabase.storage.from('silence_assets').upload(path, file)`
- `supabase.storage.from('silence_private').upload(path, file)`

**Public URLs** are generated automatically. Use RLS to restrict access (defined in `10_Storage_Folders.txt`).

---

## Summary Table

| Purpose | Method | Example |
|---------|--------|---------|
| Check‑in | RPC | `supabase.rpc('rpc_check_in', {...})` |
| Check‑out | RPC | `supabase.rpc('rpc_check_out', {...})` |
| Auto sweep | Scheduled | `SELECT rpc_auto_checkout_sweep(...)` |
| Approve join | RPC | `supabase.rpc('rpc_approve_join_request', {...})` |
| Renewal | RPC | `supabase.rpc('rpc_renew_membership', {...})` |
| Transfer | RPC | `supabase.rpc('rpc_transfer_member', {...})` |
| Leaderboard | RPC | `supabase.rpc('rpc_get_leaderboard', {...})` |
| Send notification | Edge Function | `POST /edge/send-notification` |
| Razorpay webhook | Edge Function | `POST /edge/razorpay-webhook` |
| Standard CRUD | REST | `supabase.from('memberships').select(...)` |

---

