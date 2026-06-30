# SILENCE — Phase 14: Play Store / App Store Readiness Audit

**Phase:** 14 of 16 — Store Readiness *(deferred earlier; completed after Phase 16 by request)*
**Completed (local time):** 2026-06-08
**Auditor roles:** App-Store Review Consultant (lead) · Mobile Engineer · Security/Privacy · Product · Legal-aware (DPDP)
**Goal:** Assess submission readiness for Google Play and Apple App Store — permission justification, data-safety/privacy disclosure, account deletion, payment-policy compliance, signing/versioning, and metadata — and produce a rejection-risk list.
**Method:** Direct review of `AndroidManifest.xml` (all variants), `ios/Runner/Info.plist`, `android/app/build.gradle.kts`, `pubspec.yaml`, the privacy/terms/licences screens, the account-deletion flow, and payment surfaces; mapped against current Google Play & Apple guidelines. Behavior **Code-Inferred** (no real submission/TestFlight) — declared limitation: actual review outcomes and the iOS location-crash need a device/TestFlight run (V-51…V-53).
**Constraint honored:** No code modified. Audit only.

> **Sequence note:** Phase 14 was deferred before Phase 15 and completed after Phase 16 at the user's request. Its findings **adjust the cumulative totals** (now 22 C · 68 H · 63 M · 22 L); the master registers and Phase 16 closeout are updated accordingly.

---

## 1. Executive Summary — Can it be submitted?

**No. SILENCE would be rejected by both stores on first submission, and on iOS it would crash before review even completes.** Even setting aside the catastrophic security/payment issues from Phases 6/9/10, the build itself is not submittable and several store-specific policies are violated:

- **The release build is non-functional and unsigned-for-release.** `INTERNET` exists only in the *debug/profile* manifests, not `main` (P1-01) → the shipped app has no network and does nothing; and the release build is **debug-signed** (P1-02) → Play rejects the upload outright. **These two alone block submission.**
- **Account deletion is theatre.** The "Delete Account" flow only writes a `scheduled_for_deletion` flag (+ a SharedPreferences boolean) and relies on a 30-day job that **does not exist** (no server tier — RC-1). Data is **never actually deleted.** Both stores now mandate *real* account/data deletion (Apple 5.1.1(v); Google's account-deletion policy) → **rejection** + DPDP non-compliance.
- **Location is used without being declared.** `geolocator` is called on **member home and explore** (`member_home.dart:159`, `member_explore_screen.dart:112-123`), but Android declares **no location permission** and iOS has **no `NSLocationWhenInUseUsageDescription`** → on **iOS the app crashes** the moment location is requested (a core screen), and Apple rejects any API used without its purpose string; on Android location silently fails.
- **Digital subscription via external/mock payment violates billing policy.** The admin "Pro Plan" (₹799) is a digital SaaS subscription → must use **Play Billing / StoreKit**; routing it through UPI/mock (P0-01/P9-02) is a policy violation. (Member *library* memberships are a real-world service and are exempt — that distinction matters for the fix.)
- **Reviewer-visible demo seams + false claims.** "Simulated deep link" (P3-02), "cancellation locked in simulated mode" (P9-21), payment theatre with **"Netbanking — All Indian banks integrated"** (P9-02) — Apple 2.2 (incomplete/demo) and misrepresentation policies → rejection.
- **Permission hygiene + metadata.** Microphone is **declared on iOS but never used**; legacy storage permissions; app label is lowercase "silence"; `pubspec` description is the Flutter default **"A new Flutter project."**

**Store-readiness score: 1 / 10. Submittable: NO — hard blockers on both stores.** The good news: roughly half the store blockers (INTERNET, signing, permission declarations, microphone, metadata) are **small config fixes**; the substantive ones (real account deletion, real payments, removing demo seams) are the *same* server-tier/payment work already on the critical path (RC-1/RC-2).

---

## 2. Permission → Declared Purpose → Actually Used (map)

| Permission | Android decl? | iOS purpose string? | Actually used? | Verdict |
|---|---|---|---|---|
| **INTERNET** | ❌ **main missing** (debug/profile only) | n/a | core (all networking) | **BLOCKER (P1-01)** |
| Camera | ✅ CAMERA | ✅ NSCameraUsageDescription | ✅ QR scan, photos | OK |
| Photo library / media | ✅ READ_MEDIA_IMAGES (+legacy READ/WRITE_EXTERNAL_STORAGE) | ✅ NSPhotoLibraryUsageDescription | ✅ image_picker uploads | OK (legacy perms over-broad) |
| **Location** | ❌ **none** (no ACCESS_FINE/COARSE) | ❌ **no NSLocation… string** | ✅ Geolocator (home, explore) | **BLOCKER — iOS crash + rejection (P14-03)** |
| **Microphone** | — (not declared) | ✅ **NSMicrophoneUsageDescription present** | ❌ **never used** | **Over-declared → rejection risk (P14-06)** |
| POST_NOTIFICATIONS | ❌ | n/a | n/a (no push — P0-03) | N/A now; needed if notifications built |

---

## 3. Store-Readiness Checklist

### Android (Google Play)
| Item | Status | Evidence |
|---|---|---|
| Release `INTERNET` permission | ❌ missing | P1-01 |
| Release signing (not debug) | ❌ debug-signed | P1-02 (`build.gradle.kts:37`) |
| AAB / target API 34+ | ⚠️ targetSdk = `flutter.targetSdkVersion` (unpinned) | P14-09 |
| Account deletion (in-app + web URL + real delete) | ❌ flag-only, no deletion, no URL | P14-02 |
| Data Safety form accurate | ❌ not present; would misrepresent (public PII) | P14-07 |
| Play Billing for digital goods | ❌ external/mock | P14-04 |
| Permissions justified/minimal | ⚠️ legacy storage; location undeclared-but-used | P14-03/06 |
| App name/metadata/listing | ❌ label "silence"; desc "A new Flutter project." | P14-08 |
| Privacy policy URL (public) | ❌ in-app screen only, no hosted URL | P14-10 |
| Versioning/track | ⚠️ 1.0.0+1, no track config | P14-11 |

### iOS (Apple App Store)
| Item | Status | Evidence |
|---|---|---|
| Location purpose string | ❌ missing → **crash** | P14-03 |
| Microphone string for unused capability | ❌ declared-unused → rejection | P14-06 |
| Account deletion (real, in-app) | ❌ flag-only | P14-02 (Guideline 5.1.1(v)) |
| IAP for digital subscription | ❌ external/mock | P14-04 (Guideline 3.1.1) |
| No demo/incomplete seams | ❌ "simulated" strings, payment theatre | P14-05 (Guideline 2.2) |
| Privacy nutrition labels match | ❌ not configured; would misrepresent | P14-07 (Guideline 5.1) |
| App completeness / not crashing | ❌ location crash + non-functional w/o INTERNET | P14-03 (Guideline 2.1) |
| ATS / bundle / display name | ✅ Display "Silence"; bundle via Xcode var | OK-ish |
| Encryption export compliance | ⚠️ no `ITSAppUsesNonExemptEncryption` key | P14-11 |

---

## 4. Rejection-Risk Register

| # | Risk | Store | Guideline / Policy | Severity |
|---|---|---|---|---|
| RR-1 | Release has no INTERNET → app non-functional | Both | Play "broken functionality" / Apple 2.1 | **Blocker** |
| RR-2 | Debug-signed release | Play | Play signing / debuggable | **Blocker** |
| RR-3 | Account deletion never actually deletes | Both | Apple 5.1.1(v); Play account-deletion policy | **Blocker** |
| RR-4 | Location API used without purpose string → iOS crash | Apple | 2.1 (crash) + 5.1.1 (purpose) | **Blocker (iOS)** |
| RR-5 | Digital subscription via external/mock payment | Both | Apple 3.1.1; Play Billing policy | **Blocker** |
| RR-6 | Demo seams + "All Indian banks integrated" false claim | Apple | 2.2 (incomplete) + misrepresentation | High |
| RR-7 | Microphone declared, unused | Apple | 5.1.1 (data minimization) | High |
| RR-8 | Data Safety / privacy labels missing/inaccurate (govt IDs, location, financial) | Both | Play Data Safety; Apple 5.1 | High |
| RR-9 | Privacy policy not hosted at a public URL | Both | both require a reachable URL | High |
| RR-10 | targetSdk may be below Play minimum (34/35) | Play | target-API policy | Medium |
| RR-11 | App identity placeholders ("silence", "A new Flutter project.") | Both | metadata quality | Medium |
| RR-12 | No encryption export-compliance key | Apple | export compliance | Low |

---

## 5. Required-Disclosure Gaps (Data Safety / Privacy Nutrition)

SILENCE collects, per Phases 5/10: **name, email, phone, address, date-of-birth, government ID documents (ID proofs), profile photos, precise location, payment screenshots/financial info, attendance/usage.** Both stores require this be declared and matched to the privacy policy. Gaps:
- **Government ID collection** triggers heightened review (sensitive personal data); must be justified and protected — but it is currently **publicly/cross-readable** (P10-01/02), which the privacy policy does **not** disclose → **misrepresentation**.
- **Location** must be declared (collected) — yet it isn't even permitted in the manifest (P14-03).
- **Financial info** (payment screenshots) — must be declared; currently in a public bucket (P10-02).
- The in-app privacy policy (`member_privacy_policy_screen.dart`, 245 lines) is reasonably written and mentions 30-day deletion, **but** (a) it isn't hosted at a public URL the stores can reach, and (b) it claims a deletion capability that doesn't actually delete (P14-02) and omits the public-exposure reality.

**Net:** the Data Safety form cannot be completed truthfully without first fixing the storage exposure (P10) — i.e., **a privacy/security fix is a prerequisite for an honest store listing.**

---

## 6. Payment-Policy Analysis (the nuance that matters for the fix)

| Payment | Nature | Store rule | Current | Verdict |
|---|---|---|---|---|
| **Member library membership** (UPI to owner) | **Real-world service** (physical seat/study space) | **Exempt** from Play/Apple billing (like booking a physical service) | mocked/placeholder UPI (P3-01) | external UPI is *policy-OK* once real; fix the mock |
| **Admin "Pro Plan" ₹799** | **Digital SaaS subscription** (in-app features) | **Must use Play Billing / StoreKit** | mock + external (P9-02) | **policy violation** — must move to store billing (or qualify for India user-choice billing with compliance) |

**Implication:** when payments are built (MC-01/RC-2), they must be split: **store-billing for the Pro subscription, external UPI/processor for memberships.** Shipping the Pro subscription on UPI/external would be rejected even when "real."

---

## 7. Account-Deletion Compliance (deep dive)

`member_privacy_security_screen.dart:375-455`: "Delete Account" sets `users.scheduled_for_deletion=true` + `deletion_scheduled_at=+30d` and a SharedPreferences flag; "Cancel" unsets them. **There is no job, function, or process that deletes the account or its data after 30 days** (no server tier — RC-1; no cron/Edge). Consequences:
- **Data is never deleted** → Apple 5.1.1(v) and Google account-deletion policy violation; **DPDP** "right to erasure" violation.
- **SharedPreferences dependency** → uninstall/reinstall or device change loses the local flag (the DB flag persists but nothing acts on it).
- **No web deletion URL** (Play requires an off-app deletion path too).
- The privacy policy advertises this capability (`:237`) → advertising a control that doesn't function.
**Fix:** a real server-side deletion job (Edge/cron) that purges user rows + storage objects after the grace period; a public web deletion request URL; honest status.

---

## 8. Cross-Phase Connections
| Store finding | Reinforces |
|---|---|
| RR-1/RR-2 (INTERNET/signing) | P1-01/P1-02 (Architecture) |
| RR-3/§7 (fake deletion) | RC-1 no server tier; MC-22 (Phase 15); DPDP (P10) |
| RR-4 (location no-permission) | P8-21 (null coords), P11-06 (explore), P1-11 (geolocator surface) |
| RR-5/§6 (payment policy) | P0-01/P9-02 (mocked money); MC-01 |
| RR-6 (demo seams/false claims) | P3-02, P9-02, P9-21 (Trust) |
| RR-8 (data safety vs public PII) | P10-01/02/04 (Security); DPDP |

---

## 9. Findings (new this phase)

### P14-01 — Release build is non-functional & not release-signed → cannot be submitted 🔴 (store-blocker) · Links **P1-01, P1-02**
**Class:** Store-blocker. INTERNET only in debug/profile manifests; release debug-signed (`build.gradle.kts:37`). Play rejects debug-signed uploads; the app has no network when shipped. **Fix:** add `INTERNET` to `main`; configure a real release keystore.

### P14-02 — Account deletion never deletes (flag-only; no job) 🟠 High (NEW)
**Class:** Policy/Privacy. `member_privacy_security_screen.dart:375-455` sets flags only; no deletion process exists (RC-1). Violates Apple 5.1.1(v), Google account-deletion policy, DPDP erasure. No web deletion URL. **Fix:** server-side deletion job + web URL + honest status.

### P14-03 — Location used without permission/purpose string → iOS crash + rejection, Android silent-fail 🟠 High (NEW; Critical on iOS)
**Class:** Crash/Policy. `geolocator` called (`member_home.dart:159`, `member_explore_screen.dart:112-123`) but no Android `ACCESS_*_LOCATION` and no iOS `NSLocationWhenInUseUsageDescription`. iOS terminates the app when location is requested on a core screen. **Fix:** declare permissions + purpose strings, or remove location usage.

### P14-04 — Digital "Pro Plan" subscription via external/mock payment violates store billing 🟠 High (NEW) · Links **P0-01, P9-02**
**Class:** Payment policy. Pro subscription must use Play Billing/StoreKit; member memberships (physical service) are exempt. **Fix:** split billing — store billing for Pro, external for memberships.

### P14-05 — Reviewer-visible demo seams & false capability claims 🟠 High (NEW) · Links **P3-02, P9-02, P9-21**
**Class:** Apple 2.2 / misrepresentation. "Simulated deep link", "cancellation locked in simulated mode", "Netbanking — All Indian banks integrated". **Fix:** remove demo seams and false claims before submission.

### P14-06 — Permission hygiene: microphone declared-unused; legacy storage perms 🟠 High (NEW) · Links **P1-11**
**Class:** Data minimization. iOS `NSMicrophoneUsageDescription` with no microphone use; `WRITE/READ_EXTERNAL_STORAGE` legacy. **Fix:** remove unused mic string; rely on Photo Picker / scoped media.

### P14-07 — Data-Safety / privacy disclosures cannot be completed truthfully 🟠 High (NEW) · Links **P10-01/02/04**
**Class:** Privacy. Collects govt IDs/financial/location/contact/photos; public-bucket exposure means an honest Data Safety form would disclose a breach. **Fix:** fix P10 storage scoping first, then complete accurate Data Safety + nutrition labels.

### P14-08 — App identity placeholders 🟡 Medium (NEW)
**Class:** Metadata. Android label `silence` (lowercase); `pubspec` description "A new Flutter project."; inconsistent `CFBundleName` (`silence`) vs Display (`Silence`). **Fix:** real display name, description, consistent naming.

### P14-09 — targetSdk unpinned; may miss Play's required API level 🟡 Medium (NEW)
**Class:** Compatibility. `targetSdk = flutter.targetSdkVersion`; Play requires API 34 (and 35 from Aug 2025). **Fix:** pin targetSdk to the current Play minimum; verify (V-52).

### P14-10 — No hosted privacy-policy / web account-deletion URL 🟡 Medium (NEW)
**Class:** Listing requirement. Both stores need reachable URLs; only in-app screens exist. **Fix:** host policy + deletion-request page.

### P14-11 — Versioning/metadata/export-compliance not configured 🟢 Low (NEW)
**Class:** Submission hygiene. `1.0.0+1`, no `ITSAppUsesNonExemptEncryption`, no store assets/screenshots. **Fix:** set version strategy, encryption key, store listing assets.

---

## 10. Priority Fix List (Phase 14, ordered) — pre-submission gate
1. **P14-01** — INTERNET in release + real keystore (blocker, small).
2. **P14-03** — Declare location permission/purpose strings or remove location (iOS crash).
3. **P14-02** — Real account deletion (server job + web URL) — needs RC-1.
4. **P14-04 / §6** — Move Pro subscription to store billing; keep memberships external.
5. **P14-05** — Remove demo seams + false claims.
6. **P14-07** — Fix P10 storage exposure, then complete Data Safety/nutrition labels.
7. **P14-06 / P14-08 / P14-09 / P14-10 / P14-11** — Permission hygiene, identity, targetSdk, hosted URLs, versioning/encryption.

---

## 11. Feature Checklist (Phase 14 scope — store readiness)
| Q | Verdict |
|---|---|
| Build submittable | **No** — non-functional + debug-signed. |
| Permissions correct/minimal | **No** — location undeclared-but-used; mic declared-unused. |
| Account deletion compliant | **No** — flag-only, never deletes. |
| Payment policy compliant | **No** — digital sub via external/mock. |
| Privacy/data-safety accurate | **No** — can't be truthful given P10 exposure. |
| Metadata professional | **No** — placeholders. |
| Store-ready | **No (1/10).** |

---

## 12. Verdict

**SILENCE is not submittable to either store today, and on iOS it would crash on a core screen before review concludes.** Two blockers are trivial config (INTERNET, release signing); the rest reflect the same systemic gaps found throughout the audit — **no server tier** (real account deletion, real payments), **mocked money** (billing policy), and **the public-PII exposure** (which makes an honest Data Safety form impossible). **Store submission must wait until Wave 0–1 of the Phase 16 remediation roadmap is complete**, plus the store-specific items above (location declaration, billing split, demo-seam removal, hosted policy/deletion URLs, metadata). Order of operations: fix the build + privacy/security first (so the listing can be truthful), then payments + deletion (so the policies are met), then metadata/permissions polish.

---

**Limitations honored:** Reviewed from project config + code; no actual TestFlight/Play Console submission. The iOS location crash (P14-03), the precise Play target-API minimum at submission time (P14-09), and review outcomes are to be confirmed on-device/in-console (Verification Pending V-51 iOS location-crash repro, V-52 targetSdk vs Play minimum, V-53 Data Safety/nutrition completion against fixed storage). No code was modified.

**Audit status:** With Phase 14 complete, **all phases 0–16 are delivered** (none remaining). See Phase 16 for the consolidated verdict and roadmap (now incorporating these store blockers in Wave 0–1).
