# SILENCE — UI/UX Overhaul: Decisions Log

> **Progress pointer (update me):** Last completed = **Phase C APPLIED to live DB (6 tables RLS-on) ·
> Admin Reservation tab fix (member_detail blank-screen → active-tab-only build; members_sub_tab card →
> full profile + ⋮ to top-right + menu Renew/Hold-Resume/Transfer/Remove; layout seat-desync reconcile +
> "Assign Member" picker) · add-member/amenities polish · `AGENTS.md` cross-agent onboarding** —
> 2026-06-11. Before: **B6 subscription (mock plans) · account
> deletion (member+admin, type-DELETE + dashboard banner) · global status-bar/top-bar consistency ·
> dup-prevention (approval re-entrancy) · Contact Admin single-tab · admin subscription entry** —
> 2026-06-10. Earlier: B1–B5 (real amount, add-ons, notify, audit, seat-sync); stats skeleton + offline
> cached card; member home cards UI; states-pass; Holiday/Queries.
> **Admin referral-config screen ✅ wired (2026-06-11):** entry added in admin profile → Operations
> → "Referral Rewards" → `/admin/settings/referrals` (screen + `AdminSettingsService` already existed,
> was just unreachable). Honest copy: crediting is manual for now (auto-credit needs server tier).
> **Member transfer ✅ built (2026-06-11):** new `member_transfer_screen.dart` — admin moves a member
> to another library they own (library → shift → seat/none → confirm). Frees old seat, marks old
> membership `transferred`, inserts new membership (expiry/plan/discount carried, `transferred_from`)
> + `transfers` row, occupies new seat, notifies + audits. Expiry preserved, no new payment (honest);
> dup-membership + seat-race guards. Entry: member_detail Overview → "Transfer to another library".
> **Draft persistence ✅ built (2026-06-11):** new `lib/utils/form_draft.dart` (SharedPreferences via
> CacheService, scoped per-user + per-library). Join + renewal forms auto-save (debounced text +
> step/selection changes), show a Resume/Start-fresh prompt on re-entry, clear on submit. Local draft,
> not a submission (honest).
> **Phase C schema reconciliation ✅ AUTHORED (2026-06-11):** runnable migration
> `silence_app/migrations/2026-06-11_phase_c_reconciliation.sql` + unified canonical
> `supabase_schema.sql` (6 missing tables w/ RLS; columns `join_requests.selected_addon_ids`,
> `queries.subject/type/screenshot_url`, `users.referral_code/scheduled_for_deletion/
> deletion_scheduled_at`, `seat_change_requests.approved_at`; guarded partial-uniques + attendance
> CHECKs; dead `library_closures` retired opt-in). **Code fix:** `admin_analytics_tab` expense
> categories normalized to canonical lowercase keys (+ label map). Loose `expenditures.sql`/
> `draft_members.sql`/`indices.sql` marked SUPERSEDED. Decisions: **additive only**, **guarded
> constraints**, **fix code to canonical** for expenditures. ⛔ **NOT applied to live DB** — apply
> order + verification gate in `PHASE_C_SCHEMA.md`.
> **Still deferred (won't fake):** dues banner (no data model). **Phase B remaining (server/OTP-gated
> or large):** FCM send (server) · claim/link (OTP, disabled) · referral auto-credit (server) ·
> owner-visibility of deletion (app-owner console). Full build log in `IMPLEMENTATION_PLAN.md`;
> status in `../CLAUDE.md` §0.
>
> **Phase B started (2026-06-10):** real payment amount (plan + add-ons − discount, no more hardcoded
> 1500/4000/7500) · add-ons persist (join → `member_add_ons`; **decided with user:** store
> `selected_addon_ids` on join_requests + amount = plan + add-ons) · notify on approve/reject + payment
> confirm/reject · central audit helper (canonical `audit_log`) · **seat reassign/release sync**
> (real Reassign dialog + membership.seat_id sync + notify, no more desync). **Next:** FCM, referral
> credit, transfer, claim/link, drafts, account-deletion, subscription mock plans → then Phase C.

> **Subscription payment channel — clarified (2026-06-17):** Razorpay will **NOT** be used *inside
> the app* (no 3rd-party gateway for digital goods in-app — Apple/Google policy). The library-owner
> subscription will be taken EITHER via (a) **Play Store / App Store in-app billing (IAP)**, OR (b) a
> **separate SILENCE website + Razorpay** (zero store commission, UPI-native, standard B2B-SaaS
> pattern). Final choice between (a)/(b) is still open, but **in-app Razorpay is ruled out either
> way.** Member↔admin payment stays **out-of-app UPI** (unchanged). Full blueprint + store-compliance
> notes: `SUBSCRIPTION_ARCHITECTURE.md`.

> Living document. Captures every product/UX decision made with the user during the
> requirements-gathering phase for the 3-phase overhaul. **Source of truth = the existing
> codebase**, NOT the `silence_app/` spec docs (user has added/removed features since).
>
> **Golden rules (apply everywhere):**
> 1. Work from the **existing codebase**, not the old spec.
> 2. Maintain **UI consistency + color hierarchy** (warm orange `#E65C00`, Material 3, GoogleFonts Inter/Outfit).
> 3. **Refine** the current style — declutter, one primary CTA per state, honest copy. No full redesign.
> 4. If a flow is **missing** something, **ASK the user before adding it**.
> 5. **No dishonest UI** — never show success/“done”/“paid”/“notified” for something that didn’t happen.

---

## The 3 Phases (agreed order)

1. **Phase A — UI/UX layer:** every screen, button, placeholder; build proper elements for every
   situation (loading / empty / error / offline / success). Add missing screens/elements per flow.
2. **Phase B — Navigation + Flow + Functions:** wire everything correctly, honest success/failure,
   recovery paths.
3. **Phase C — Backend schema:** fix duplicate/conflicting tables, missing tables, constraints,
   precompute. Reconcile one canonical schema.

---

## Decisions captured so far

### Foundation
| Topic | Decision |
|---|---|
| Scope/order | Member + Admin screens **in parallel**. No screen left behind, but ask before adding missing pieces. |
| Source of truth | **Existing codebase** (spec docs are stale). |
| Design language | **Refine current style** (warm orange, Material 3). Declutter dense screens; one primary CTA per state. |
| State widgets | Build **4 reusable widgets**: `LoadingState` (skeleton/shimmer), `EmptyState` (icon+msg+optional CTA), `ErrorState` (friendly msg + retry), `OfflineBanner`. All data screens use them. |

### Payments (the big reframe)
| Topic | Decision |
|---|---|
| Member ↔ library-admin payment | **Out of app.** Member pays the admin externally, then taps **“I have paid”**. Admin verifies in their own bank/UPI app, then **confirms** → plan goes active. |
| Member payment UI (join/renewal) | Admin-configured UPI IDs render as **deep-link app icons** (GPay/PhonePe/Paytm). Tap → opens the phone’s UPI app via `upi://pay?pa=...&pn=...&am=...` (real deep links via `url_launcher`). Return → **“I have paid”** declaration → admin verify → confirm. Remove hardcoded `owner@upi`/`9876543210@paytm` and the “Simulated deep link” snackbars. |
| Payment Methods config | **Dedicated “Payment Methods” section** in admin **profile tab** + still editable in **setup stage 3**. Fields: cash toggle + UPI IDs list with **app-type auto-detected** from the handle suffix. Stored in `libraries.social_links` (`cash_enabled`, `upi_ids`). |
| Razorpay | Only between **app-owner (you) ↔ library-owner** as a subscription gateway. **Integrate LAST.** First 1–2 months everyone is on **free tier**. |
| Admin subscription (“Pro Plan”) | Build **proper screens + UI/UX + flow** with **mock plans: Free + 2 paid (₹499 & ₹799)**. Plan **feature bullets decided later** (placeholder for now); Razorpay later. Remove payment-theatre (`Future.delayed`, fake invoice, “All Indian banks integrated”, “simulated mode”). |
| Add-on member payment | Same out-of-app model; add-on amount adds to total; **selection is saved** and shown to admin. |

### Notifications
| Topic | Decision |
|---|---|
| System | **In-app notification center (real `notifications` table)** + **FCM push**. Replace the static “You’re all caught up!” stub with real list + unread badge + mark-as-read + empty/loading/error states. |
| Member events | Announcements; join/renewal **approved/rejected**; (payment confirmed/rejected, expiry/renewal reminders implied by membership flow). |
| Admin events | New joinings; pending **actions/approvals/requests** to take. **Not** check-in/check-out noise. |

### Identity verification
| Topic | Decision |
|---|---|
| Email/phone OTP | **Build the screens + functions but keep them DISABLED** for now (testing). Remove the mock `123456` OTP and self-set “verified” flag. Enable for real later. No “Verified” badge until real verification exists. |

### Check-in / attendance / QR
| Topic | Decision |
|---|---|
| Offline check-in | **Stays enabled.** An **active** member of a library must **never** be blocked from check-in/check-out (online or offline). |
| Expired member at check-in | Show a **warning** (“membership expired” / “expiring in 1–2 days — renew soon”) — do not silently fake success. |
| Admin visibility of expiry | Admin **dashboard** shows members whose membership is **expired or about to expire**. In **Today’s Attendance**, expired members shown highlighted in **RED**. |
| Check-in policy | **Multiple sessions per day allowed** (morning + evening). Each session counts; hours add up. Show a per-day **session list**. Remove the blanket “Already checked in today” block. |

### Holidays (was “Close Today”)
| Topic | Decision |
|---|---|
| Rename/expand | Rename “Close Today” to a **Holiday** feature. Options: **single day**, **date range**, or **scheduled** holidays, each with a **reason** textbox. Allow **cancel/remove** of a holiday. |
| Effects | **Notify members.** During a holiday, member dashboard **check-in/check-out is disabled** (build the UI for this state). Admin **dashboard** shows **“Today is a holiday.”** Analytics tab gets a **holiday card** (e.g. “N holidays this month”). |
| Backend | Must write the table the **scanner actually reads** (`scheduled_closures`) — not the dead `library_closures`. Reconcile the two closure tables in Phase C. |

### Referrals (TWO separate systems)
| System | Decision |
|---|---|
| **Member → Member** | Admin can **activate** it and **decide how many extra days** the referrer gets. Add a **section in the admin profile tab** to configure this. Reward = membership extension for the referrer once conditions are met. |
| **Member → Admin (library acquisition)** | If a member brings a **new library owner**, they **contact the app-owner directly** for a reward: **₹200** or a **membership discount**. Write the **conditions on the screen** (mainly member→admin): the referred owner must **set up the library, add members, use it for ~30 days**, etc. |

### Holds (membership pause) — REFRAMED
| Topic | Decision |
|---|---|
| Member-side “create hold” | **Remove completely** from everywhere (member can no longer request a hold). |
| Admin holds a member | Admin can put any member’s membership **on hold for X days**. Membership goes to **hold** state; after the hold is lifted, the member uses the **remaining days** (expiry pushed by the held duration). |
| Notification | Member is notified: **“Your membership is on hold from <date> to <date>.”** |
| Member un-hold request | Member **can** send a **request to lift the hold early**. (So: no create-hold, but yes un-hold request → admin approves.) |
| Member dashboard state | Build a **“membership on hold”** state UI on the member home (check-in disabled, shows hold window + “request to resume”). |

### Misc UX / utility decisions
| Topic | Decision |
|---|---|
| Manually-added (offline) members | **Build a phone-based claim/link flow:** if such a member later signs up, they can claim/link their existing admin-created record by **phone (+ OTP when verification is enabled)**, avoiding duplicates. Until then admin tracks them manually. |
| QR regeneration | **Immediate-break**, but show the admin a **clear warning before regenerating** (“This will instantly invalidate all printed QR posters”). Member gets an accurate “scan the new QR” message. |
| `app_settings` fake buttons (cache clear, backup via `Future.delayed`) | **No fake progress.** Make them **real** where possible (e.g. real cache clear) or **remove** the ones that can’t be real yet. |
| Expired member access | **Always allow check-in with a warning** (no hard block; drop the `allow_expired_checkin` gate). Admin sees expired members in **red**. |
| Member home improvements | (1) **Dues banner** on the membership card when dues pending; (2) **Declutter** — one primary CTA per state (trial/active/expiring/expired/hold), demote secondary cards; (3) **Offline** → show cached membership card + offline banner (no crash); (4) **Expiry copy fix** (no “0 days left” while active) + clear countdown. Must look **visually appealing**, maintaining color + UI hierarchy. |
| Seat management UX | **Reassign** opens a dialog listing **vacant seats in the same shift** → choose → free old seat + occupy new + update `memberships.seat_id` + **notify member**. Release / maintenance / delete must **sync the membership** and notify (no more desync). (Currently reassign just navigates to setup = no-op.) |
| Member card (admin Members tab) | **Card tap → opens the member's FULL profile** (member_detail). The **⋮ menu moves to the top-right corner** and **drops "View Details"** (the card does that now); menu keeps **Renew + quick actions: Hold/Resume · Transfer · Remove** — each a real DB write + notify + audit + list refresh. (Was: card not tappable, ⋮ centered, profile opened blank — decided 2026-06-11.) |
| Vacant seat tap (admin Layout tab) | **Assign a seatless member now** — tap a vacant seat → picker of active members in that seat's shift who have no seat → occupy + set `memberships.seat_id` + notify + audit. (Was a no-op snackbar.) Occupied-seat "Renew" / "View Member Details" → **open the member profile**. |
| Seat-occupancy truth | Layout grid **reconciles occupancy from `memberships.seat_id`** (not only `seats.status`) on read + a best-effort DB self-heal, so an assigned seat never renders vacant. The add-member wizard writes the seat row **before** the payment insert so a payment failure can't desync it. |

### Misc UX / utility decisions (cont.)

### Features to BUILD / KEEP / REMOVE
| Item | Decision |
|---|---|
| Add-ons | **Build properly:** save selection (`member_add_ons`), surface to admin in member detail. |
| Member transfer (admin moves member between own libraries) | **Build the feature** (currently `transfers` table exists, zero code). |
| `payment_setup.dart` | **Delete** — true duplicate of `library_setup_stage3.dart` payment section. |
| `add_member_mode_selection.dart` | **Keep** — it IS used by `add_member_wizard.dart` (earlier “dead” claim was wrong). |
| Audit log | **Fix fully:** schema-correct writes for every admin action via a **central audit helper**; reader reads real columns. (Currently broken on both write and read.) |
| Account deletion | **Honest interim:** show “deletion request received, processed within 30 days”, set the flag, make the request **visible to the owner**; **do not** claim it’s deleted. Real server-side purge comes later with the server tier. |
| Queries/support | Build member **“My Queries”** list with status (open/replied) + admin reply visible to member + **notify on reply**. (Currently submits into a void.) |
| Revenue/payment amount | Join **approval must compute amount = real shift price − discount** via a **shared pricing function** (unify with the add-member wizard, which is already correct). Remove the hardcoded `1500/4000/7500`. Fixes revenue dashboard + exports. |
| Reviews | Works (member writes, admin replies) — **no change**. |
| Analytics correctness (TZ, fabricated numbers) | UI polish now; **correctness deferred to Phase B/C**. |
| Exports | Become correct automatically once the payment-amount fix lands. |
| Other areas | User hasn’t reviewed the rest yet — **for now fix what’s already visible/identified**; revisit later. |

---

## Still OPEN (to ask next)
- Subscription mock plan **names / prices / feature bullets** (user will provide the values).
- ✅ ~~Phase C schema reconciliation specifics~~ — **DECIDED + authored 2026-06-11** (additive-only, guarded constraints, fix-code-to-canonical for expenditures). See `PHASE_C_SCHEMA.md`. **APPLIED to live DB ✅ (2026-06-11)** — 6 tables RLS-on. **Remaining open:** the **security/RLS track** (P5-01 membership open-UPDATE, P5-07 users PII SELECT, P5-08 forged inserts) which Phase C deliberately did NOT touch.

---

*Started during requirements-gathering. Update as decisions are made; this feeds the final
implementation plan.*
