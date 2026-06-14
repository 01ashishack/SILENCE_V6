# SILENCE — Subscription Architecture & Webhook Blueprint

> **Maqsad (purpose).** Ye doc batata hai ki SILENCE ka **library-owner subscription** (Free / ₹499 /
> ₹799) end-to-end kaise kaam karega — paisa kahan liya jayega, app ko plan kaise pata chalega,
> features kaise lock/unlock honge, aur ise **App Store / Play Store policy ke andar** kaise rakha jaye.
> Created 2026-06-14. Ye abhi sirf **blueprint** hai (koi code nahi badla) — implementation baad mein.

---

## 0. Do alag-alag "payments" — confuse mat karna

SILENCE mein paisa do jagah ghoomta hai. Inhe alag rakhna ZAROORI hai:

| # | Kaun → Kaun | Kya hai | App ka role | Razorpay? | Store policy |
|---|---|---|---|---|---|
| 1 | **Member → Library Admin** | Seat / membership fees | App sirf **hisaab (ledger)** rakhta hai — paisa app ke andar nahi jaata | ❌ Nahi chahiye | Bilkul allowed (app paisa hi nahi le raha) |
| 2 | **Library Owner → App Owner (aap)** | SILENCE software ka subscription | App plan **read** karke features unlock kare | ✅ **Website** par | Allowed — niche §6 |

> **User decision (2026-06-14):** Member↔Admin payment app ke andar BILKUL NAHI hogi. App un dono ke
> liye sirf record-keeping tool hai. Isliye Razorpay sirf #2 (subscription) ke liye, wo bhi **website**
> par. Ye doc poora #2 ke baare mein hai.

---

## 1. Core principle — "App padhti hai, App likhti NAHI"

Sabse important rule, jispe poora design tika hai:

> **Plan ka faisla hamesha SERVER karta hai (website + webhook). App us faisle ko sirf DB se
> PADHTI hai aur features unlock/lock karti hai. App khud kabhi plan set nahi karti.**

Kyun? Kyunki agar app khud `subscription_plan = 'pro'` likh sakti hai, to koi bhi tech-savvy admin app
ko modify karke bina paise diye saare features khol lega. Isliye plan column ko **sirf server likhe**.

### ⚠️ Abhi yahi galat hai (audit P6-03)
`lib/screens/admin_home.dart:961-971` — library launch par app **khud** likhti hai:
```dart
.from('users').update({
  'subscription_plan': 'starter',
  'subscription_status': 'active',
  'subscription_expiry': ... +14 days,   // 14-day trial
})
```
Ye client self-write hai = billing bypass risk. Blueprint isko **server-side** le jaata hai (§4 + §7).

---

## 2. End-to-end flow (picture)

```
[Library Owner]
   │  1. SILENCE website kholta hai → login → "Upgrade to ₹499/Pro" dabata hai
   ▼
[Website checkout + Razorpay]
   │  2. Razorpay se payment karta hai (UPI/card/netbanking)
   │  3. Razorpay → "payment.captured" WEBHOOK bhejta hai aapke server ko
   ▼
[Webhook server  (Supabase Edge Function ya chhota Node service)]
   │  4. Razorpay signature VERIFY karta hai (asli event hai, nakli nahi)
   │  5. Supabase DB likhta hai (service-role key se):
   │       users.subscription_plan   = 'pro'
   │       users.subscription_status = 'active'
   │       users.subscription_expiry = now + 30/365 din
   │     + ek subscription_events row (audit/idempotency ke liye)
   ▼
[Supabase DB]   ←──  SINGLE SOURCE OF TRUTH
   │  6. App open hote hi ye row padhta hai
   ▼
[SILENCE App]
   │  7. PlanService plan + expiry padhta hai → features unlock/lock
   │     (analytics, member-limit, export, branding, etc.)
   ▼
[Owner ko sahi features dikhte hain]
```

App ka Razorpay se **koi direct contact nahi**. App↔DB, website↔Razorpay↔DB. Bas.

---

## 3. Data model (DB) — kya already hai, kya add karna hai

### Already maujood (✅ `silence_app/supabase_schema.sql:72-74`)
```sql
subscription_plan   TEXT CHECK (subscription_plan IN ('starter','basic','pro','trial')),
subscription_status TEXT DEFAULT 'active'
    CHECK (subscription_status IN ('active','grace','readonly','locked','cancelled')),
subscription_expiry TIMESTAMPTZ,
```
> Note: plan keys abhi `starter/basic/pro/trial` hain, par UI Free/₹499/₹799 dikhata hai. Ek baar
> final naam decide karke dono jagah same rakhna (mapping §5). Iske liye CHECK update karni padegi.

### Add karna hoga (jab implement karein)
1. **`subscription_events`** table — har webhook event ka record (idempotency + audit):
   `id, user_id, razorpay_payment_id (unique), razorpay_signature, event_type, plan, amount,
   period_start, period_end, raw_payload jsonb, created_at`.
   *(Unique `razorpay_payment_id` → same webhook 2 baar aaye to double-credit na ho.)*
2. **`subscription_plan`** ko `'free'` value allow karao (abhi 'free' CHECK mein nahi hai).

---

## 4. Server tier — webhook (Razorpay → DB)

> Ye **server tier (RC-1)** ka hissa hai. Form: **Supabase Edge Function** (kyunki Razorpay call +
> signature verify chahiye — ye plain SQL RPC nahi kar sakta). `docs_fix/SERVER_TIER_PLAN.md` mein
> decision: "Edge Functions only later for Razorpay/FCM" — ye wahi "later" hai.

**Edge Function `razorpay-webhook` kya karega:**
1. Razorpay `X-Razorpay-Signature` header ko `RAZORPAY_WEBHOOK_SECRET` se **HMAC verify** kare.
   Galat signature → 400, kuch mat likho. (Ye sabse zaroori security step hai — warna koi bhi
   nakli "payment success" bhej ke free plan le lega.)
2. Event `payment.captured` / `subscription.charged` ho to:
   - `razorpay_payment_id` se check karo `subscription_events` mein already hai kya → haan to skip
     (idempotent).
   - `notes`/`metadata` se `user_id` + `plan` nikaalo (checkout banate waqt bhejo).
   - **service-role** client se `users` update karo (plan/status/expiry) + `subscription_events` insert.
3. Cancellation/refund event → `subscription_status='cancelled'` ya expiry chhoti kar do.

**Secrets** (Edge Function env, app mein KABHI nahi): `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`,
`RAZORPAY_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`.

---

## 5. App side — PlanService (feature gate)

Abhi gating bikhri hui hai (har screen alag check karti hai, e.g.
`verified_badge_screen.dart:136-138` `_adminPremium = plan != 'none' && status == 'active'`).
Ek **central jagah** honi chahiye:

```dart
// lib/services/plan_service.dart  (naya)
class PlanService {
  // DB se aaye 3 values: subscription_plan, subscription_status, subscription_expiry
  // Ye sab in-memory, app ke load par set; PlanService kuch likhta NAHI.

  static bool get isActive;            // status=='active' && expiry future me
  static String get plan;             // 'free' | 'pro' | 'premium'
  static bool canUse(Feature f);      // feature gate
  static int  get maxMembers;         // Free=N, Pro=unlimited
  static int  get maxLibraries;       // Free=1, Pro=many
  // ... jaise jaise features decide hon
}
```

Phir har feature bas `if (PlanService.canUse(Feature.analytics)) {...} else showUpgrade();`.

### 🔢 Decide karna hai — kaun se plan mein kya (ye AAP batao)
Niche **sirf example** hai, final aap decide karoge. Isi se PlanService ki body banegi:

| Feature | Free | ₹499 | ₹799 |
|---|---|---|---|
| Members add (limit) | 50? | 200? | Unlimited? |
| Libraries (branches) | 1 | 1 | Many? |
| Analytics tab | Basic? | Full | Full |
| CSV/PDF export | ❌? | ✅ | ✅ |
| Branding (logo/cover) | ❌? | ✅ | ✅ |
| Verified badge | ❌ | ✅ | ✅ |
| Holidays/closures | ✅ | ✅ | ✅ |

> Jab tak ye table aap final nahi karte, PlanService ko **sab kuch free/unlocked** rakhenge (CLAUDE.md:
> "First 1-2 months everyone is free tier"). Structure ready rahega, switch baad mein.

---

## 6. Expiry / lifecycle (status machine)

`subscription_status` ki value app ke behaviour ko control karti hai:

| status | Matlab | App behaviour |
|---|---|---|
| `active` | Plan chालू, expiry future me | Sab features plan ke hisaab se |
| `grace` | Expiry nikal gayi, thoda time diya | Warn karo "renew karo", features abhi chalu |
| `readonly` | Grace bhi khatam | Purana data dikhe, naya add NA ho |
| `locked` | Aur aage | Sirf "renew" screen |
| `cancelled` | Owner ne band kiya | Free tier pe wapas |

**Expiry kaun decide kare?** Best: ek roz chalne wala server job (Edge Function + cron) jo
`expiry < now` waale ko `grace`/`readonly` kare. App side bhi ek safety check rakho (expiry past →
PlanService.isActive=false) taaki turant reflect ho.

---

## 7. Security — feature-gate tabhi bharosemand jab plan column LOCK ho

Feature gate (PlanService) **akela kaafi nahi**. Agar app khud plan likh sakti hai to gate bekaar hai.
Isliye 2 cheez chahiye (dono server-tier track me already planned — `SECURITY_HARDENING_RUNBOOK.md`):

1. **RLS:** admin apni `subscription_plan/status/expiry` columns **UPDATE na kar sake**.
   (Audit P6-03 / Cycle 5 in runbook.) → `REVOKE UPDATE (subscription_plan, subscription_status,
   subscription_expiry) ON users FROM authenticated;`
2. **Sirf webhook (service-role / SECURITY DEFINER)** hi likhe.

Iska matlab: pehle `admin_home.dart:961-971` ka client self-write hatана padega (warna RLS use tod
degi). Wo trial-set bhi server-side jana chahiye (signup par ek `set_trial` RPC, ya webhook se).

---

## 8. App Store / Play Store compliance (verified 2025-26)

- **Member↔Admin (UPI/external):** App paisa hi nahi le raha → IAP rule lagta hi nahi. ✅ Safe.
- **Subscription = website par:** Library owner SILENCE **website** par Razorpay se plan le. App ke
  andar koi "Buy / Subscribe / ₹499 pay karo" button ya direct link **mat rakho** — bas status
  dikhao ("Active plan: Pro") + "manage on website" jaisa neutral text. Ye **B2B SaaS** ka standard
  pattern hai (Slack, Zoho, QuickBooks) aur har region me safe, kyunki app digital good "bech" nahi rahi.
- US me ab in-app external payment link bhi allowed hai (Epic v. Apple 2025), par India/global ke liye
  **website-only** rasta sabse safe + zero-commission hai.
- Razorpay khud galat nahi — galat hota hai "app ke andar digital good bechna 3rd-party gateway se".
  Website par wo problem hi nahi.

> Sources (2025-26): Apple external-link ruling (9to5mac/TechCrunch, Epic v. Apple Apr 2025);
> Google Play alternative-billing program (Play Console Help). Region-specific terms badal rahe hain —
> launch se pehle Play Console / App Store Connect me current terms verify karna.

---

## 9. Implementation order (jab GO milega)

**Phase 1 — App side, abhi ho sakta hai (website/Razorpay ki zaroorat nahi):**
1. `PlanService` banao (central gate). Abhi sab free/unlocked (beta).
2. Bikhre hue `subscription_plan` reads ko PlanService se replace karo
   (`admin_home`, `admin_profile_tab`, `subscription_screen`, `verified_badge_screen`).
3. Expiry → status logic (app-side safety check).
4. Subscription screen: honest "manage on website (coming soon)" copy, koi in-app buy button nahi.

**Phase 2 — Server side (jab website + Razorpay ready):**
5. `subscription_events` table + 'free' plan CHECK.
6. Edge Function `razorpay-webhook` (signature verify → service-role DB write → idempotent).
7. Daily expiry job (grace/readonly/locked).
8. **Tab** RLS lock: `subscription_*` columns client-update REVOKE + `admin_home` self-write hatao
   (server-side trial). Verify: app se plan nahi badal sakti; webhook se badalta hai.

**Phase 3 — Polish:** plan-wise feature table finalize (§5), upgrade prompts, invoices on website.

---

## 10. Aapse pending decisions
1. **Plan-wise feature list** (§5 table) — har plan me kya milega? (Members limit, branches, analytics,
   export, branding — number/✅❌ daal do.)
2. **Plan period** — monthly / yearly / dono?
3. **Final plan keys** — `free/pro/premium`? (DB CHECK + UI dono update karne ke liye.)
4. **Trial** — rakhna hai? Kitne din? (Abhi 14-day client-side hai.)

> In 4 ka jawab aate hi Phase 1 (PlanService) ka concrete code likh sakte hain.
