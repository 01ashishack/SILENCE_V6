// ============================================================================
// legal_content.dart — SINGLE in-app source of truth for legal/policy copy.
// ----------------------------------------------------------------------------
// Mirrors the canonical Markdown documents under `legal/` (privacy_policy.md,
// terms_and_conditions.md, refund_and_cancellation_policy.md,
// community_and_content_policy.md, about_and_contact.md). When the canonical
// docs change, update THIS file in the same change so the in-app screens and
// the published documents stay in sync.
//
// These are informational, not legal advice; a qualified Indian lawyer must
// review before public launch.
//
// Rendering: every legal screen renders a `LegalDoc` via the shared
// `LegalDocScreen` in `lib/screens/policy_screens.dart` (dark-aware, warm
// orange). There is no markdown dependency — content is structured here.
// ============================================================================

/// Operator / contact constants (locked facts).
const String kLegalLastUpdated = 'Last updated: 28 June 2026';
const String kOperatorName = 'Ashish Kumar';
const String kOperatorPlace = 'Alwar, Rajasthan, India';
const String kSupportEmail = 'ashish.premierbro@gmail.com';
const String kSupportPhone = '+91 72978 79930';
const String kAppFullName = 'Silence – Library Management & QR Attendance';
const String kWebsite = 'https://silenceapp.in';

/// A single heading + body block inside a legal document.
class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

/// A tappable cross-reference to a related policy screen (route is a named
/// route registered in `main.dart`, so it resolves from any role context).
class LegalRelated {
  final String label;
  final String route;
  const LegalRelated(this.label, this.route);
}

/// A complete legal/policy document rendered by `LegalDocScreen`.
class LegalDoc {
  final String title;
  final String intro;
  final List<LegalSection> sections;
  final List<LegalRelated> related;
  const LegalDoc({
    required this.title,
    required this.intro,
    required this.sections,
    this.related = const [],
  });
}

// Shared related-policy references (named routes from main.dart).
const _relTerms = LegalRelated('Terms & Conditions', '/member/terms');
const _relPrivacy = LegalRelated('Privacy Policy', '/member/privacy-policy');
const _relRefund = LegalRelated('Refund Policy', '/policy/refund');
const _relCancellation = LegalRelated('Cancellation Policy', '/policy/cancellation');
const _relCommunity = LegalRelated('Community Guidelines', '/policy/community');
const _relAbout = LegalRelated('About & Contact', '/member/about');

// ============================================================================
// ABOUT & CONTACT  (mirrors legal/about_and_contact.md)
// ============================================================================
const LegalDoc legalAbout = LegalDoc(
  title: 'About Us',
  intro:
      'Silence is a simple, honest library and study-space management app built '
      'for India. It helps library owners run their study spaces — seats, shifts, '
      'memberships, payment tracking, and QR-based attendance — and helps students '
      'find libraries, check in with a QR code, and track their study time and '
      'membership.',
  sections: [
    LegalSection('Who runs Silence',
        'Silence is operated by $kOperatorName, a sole proprietor based in '
        '$kOperatorPlace, trading as "$kAppFullName". Silence is a neutral '
        'technology platform — we provide the software. Libraries are owned and '
        'run by independent Library Owners; we are not a party to the '
        'relationship between a library and its students.'),
    LegalSection('What we believe',
        '• Honest software: we never show fake success. If something fails, we '
        'say so.\n'
        '• Privacy first: we collect only what is needed and protect it (see the '
        'Privacy Policy).\n'
        '• Fair and simple: clear rules for owners and students alike.'),
    LegalSection('Contact & Support',
        'Email: $kSupportEmail\n'
        'Phone: $kSupportPhone\n'
        'Address: $kOperatorPlace\n'
        'Website: $kWebsite\n'
        'Support response: best-effort, typically within 2–3 business days.\n\n'
        'Students: for anything about your membership, fees, seat, or refunds, '
        'please contact your library directly (use "Contact Admin" in the app) — '
        'those are managed by the library, not by Silence.'),
    LegalSection('Grievance Officer',
        'In line with Indian law (IT Rules, 2021 and the DPDP Act, 2023):\n\n'
        'Grievance Officer: $kOperatorName\n'
        'Email: $kSupportEmail\n'
        'Phone: $kSupportPhone\n\n'
        'We acknowledge complaints within 48 hours and aim to resolve them '
        'within 15 days.'),
    LegalSection('Account deletion',
        'You can delete your account in the app (Profile → account deletion) or '
        'request it at $kWebsite/delete-account. Deletion freezes the account '
        'immediately and permanently removes data within 30 days, subject to '
        'limited legal retention.'),
  ],
  related: [_relTerms, _relPrivacy, _relRefund, _relCommunity],
);

// ============================================================================
// PRIVACY POLICY  (mirrors legal/privacy_policy.md)
// ============================================================================
const LegalDoc legalPrivacy = LegalDoc(
  title: 'Privacy Policy',
  intro:
      'This Privacy Policy describes our actual practices in plain language. It '
      'is also published at $kWebsite/privacy. It is not legal advice. By using '
      'Silence you agree to the practices described here.',
  sections: [
    LegalSection('1. Who we are',
        'Silence ("we", "us", "our") is a software platform operated by '
        '$kOperatorName, a sole proprietor based in $kOperatorPlace, trading as '
        '"$kAppFullName".\n\n'
        'Contact / Support: $kSupportEmail · $kSupportPhone\n'
        'Grievance Officer: $kOperatorName (see Section 14)\n'
        'Website: $kWebsite\n\n'
        'Silence is a neutral technology platform. Library and study-space owners '
        '("Library Owners") use it to manage their spaces, seats, shifts, '
        'attendance and members ("Members"/students). Silence does not run '
        'libraries, does not collect fees from Members, and is not a party to the '
        'relationship between a Library Owner and a Member.'),
    LegalSection('2. Our role under the DPDP Act, 2023',
        'Because Silence is a neutral platform, responsibility for personal data '
        'is split:\n\n'
        '• For a Member\'s personal data that a Library Owner chooses to collect '
        '(e.g., verification documents, contact details, attendance), the Library '
        'Owner is the Data Fiduciary and Silence acts as a Data Processor — we '
        'only store and process it on the Library Owner\'s instructions.\n'
        '• For account, authentication, app-usage and Library-Owner subscription '
        'data whose purpose we decide, Silence is the Data Fiduciary.\n\n'
        'Members should also review the privacy practices of the specific library '
        'they join.'),
    LegalSection('3. Information we collect',
        'a) Account info (Members and Library Owners): name (and optional '
        'nickname), email, mobile number, and a password (stored only as a secure '
        'hash by our authentication provider — we never see it in plain text). '
        'For Members: date of birth, gender, address, and a profile photo. For '
        'Library Owners: library name, address, photos, opening hours, and the '
        'payment handles (e.g., UPI IDs) they use to receive payments from their '
        'own Members.\n\n'
        'b) Verification documents (optional, collected by Library Owners): a '
        'Library Owner may ask a Member to upload verification document images. '
        'Silence does not require, request, or use these for its own purposes — '
        'they are collected by, and belong to, the Library Owner, and are stored '
        'in restricted, owner-scoped private storage that is not publicly '
        'accessible.\n\n'
        'c) Usage and attendance data: QR check-in/out records, session times, '
        'seat and shift information, membership status, and payment records a '
        'Library Owner records in the app.\n\n'
        'd) Device and technical data: app version, device model, OS, crash and '
        'diagnostic logs, and a push-notification token.\n\n'
        'e) Location data: with your permission, your device\'s location is used '
        'only while the app is in use to help you find nearby libraries. We do '
        'not track location in the background.\n\n'
        'We do not knowingly collect data from anyone under 18 (see Section 11).'),
    LegalSection('4. How we use your information',
        'To create and secure your account and authenticate sign-in (including '
        'Google and Apple sign-in); to provide core features (QR attendance, '
        'seat/shift management, memberships, notifications, finding nearby '
        'libraries); to let Library Owners manage their own Members; to send '
        'transactional/service notifications; to maintain security, prevent abuse '
        'and fraud, and debug crashes; and to comply with law.\n\n'
        'We do not sell your personal data and do not use it for third-party '
        'advertising.'),
    LegalSection('5. Consent',
        'We process personal data based on your consent (given when you create an '
        'account and accept this Policy and our Terms), to perform the service you '
        'requested, and to meet legal obligations. You may withdraw consent by '
        'deleting your account (Section 9); this may mean you can no longer use '
        'the service.'),
    LegalSection('6. Payments',
        'Member → Library payments are made outside Silence (e.g., via a UPI '
        'app). Silence never receives, holds, processes, or stores your '
        'card/bank/UPI credentials or the payment itself — we only record that a '
        'Library Owner marked a payment as received.\n\n'
        'Library-Owner subscriptions to Silence are free during the current beta. '
        'If paid plans launch later, payments will be handled by a third-party '
        'provider (e.g., Razorpay) under their own privacy policy; Silence will '
        'not store your full card/bank details.'),
    LegalSection('7. Sharing and third-party services',
        'We share data only as needed to run the service:\n\n'
        '• Supabase — database, file storage, authentication (hosted in the '
        'Northeast Asia / Seoul region).\n'
        '• Google Firebase — push notifications (Cloud Messaging), crash '
        'reporting (Crashlytics), and basic analytics (Analytics).\n'
        '• Google Sign-In / Apple Sign-In — optional login (only the identity '
        'token needed to log you in).\n'
        '• Razorpay (future) — Library-Owner subscription payments, only if/when '
        'paid plans launch.\n\n'
        'We may also disclose data if required by law, to enforce our Terms, or '
        'to protect users and the public. We do not sell your data.'),
    LegalSection('8. International data transfer',
        'Our infrastructure provider stores data in the Seoul (South Korea) '
        'region. By using Silence you acknowledge your data is processed outside '
        'India. We take reasonable steps to keep it secure and handled in line '
        'with this Policy.'),
    LegalSection('9. Data retention and account deletion',
        'We keep personal data only as long as needed to provide the service or '
        'as required by law. You can request deletion from inside the app '
        '(Profile → account deletion) or via $kWebsite/delete-account. On '
        'request, your account is frozen immediately and permanently deleted '
        'within 30 days (a short recovery window applies, as described in the '
        'app). Some records may be retained briefly where required for legal, '
        'tax, security, or dispute purposes, then deleted or anonymised. Member '
        'records held on behalf of a Library Owner are also subject to that '
        'owner\'s retention decisions.'),
    LegalSection('10. Cookies (website only)',
        'Our website may use strictly-necessary and basic analytics cookies. The '
        'mobile app does not use advertising cookies.'),
    LegalSection('11. Children',
        'Silence is intended for users 18 years and older. We do not knowingly '
        'collect personal data from children. If a Library Owner enrols a Member '
        'under 18, the Library Owner is responsible for obtaining any consent '
        'required by law. If we learn we hold a child\'s data without a lawful '
        'basis, we will delete it.'),
    LegalSection('12. Security',
        'We use reasonable technical and organisational measures: encryption in '
        'transit (HTTPS/TLS) and at rest (provider-side); row-level access '
        'controls so users only access data they are permitted to; private, '
        'owner-scoped storage for verification documents; and need-to-know access '
        'limits. No system is perfectly secure. If a personal-data breach occurs, '
        'we will act promptly and, where the law requires, notify the Data '
        'Protection Board of India and affected users.'),
    LegalSection('13. Your rights',
        'Subject to applicable law you may: access the data we hold about you; '
        'correct inaccurate data (most data is editable in-app); erase your data '
        'by deleting your account; withdraw consent; and complain to our '
        'Grievance Officer. For data a Library Owner controls, we may direct your '
        'request to that Library Owner.'),
    LegalSection('14. Grievance Officer',
        'Grievance Officer: $kOperatorName\n'
        'Email: $kSupportEmail\n'
        'Phone: $kSupportPhone\n'
        'Address: $kOperatorPlace\n\n'
        'We acknowledge complaints within 48 hours and aim to resolve them within '
        '15 days.'),
    LegalSection('15. Changes & contact',
        'We may update this Policy. Material changes will be notified in-app or '
        'on the website with a revised "Last updated" date. Questions about '
        'privacy? Email $kSupportEmail.'),
  ],
  related: [_relTerms, _relCommunity, _relRefund],
);

// ============================================================================
// TERMS & CONDITIONS  (mirrors legal/terms_and_conditions.md)
// ============================================================================
const LegalDoc legalTerms = LegalDoc(
  title: 'Terms & Conditions',
  intro:
      'Please read these Terms carefully. This is not legal advice. By creating '
      'an account or using Silence, you agree to these Terms. Also published at '
      '$kWebsite/terms.',
  sections: [
    LegalSection('1. Who we are; what Silence is',
        'Silence is operated by $kOperatorName, sole proprietor, $kOperatorPlace '
        '("Silence", "we", "us"). Silence is a neutral technology platform: '
        'software that Library Owners use to run their libraries/study spaces and '
        'that Members (students) use to find libraries, check in via QR, and '
        'manage their membership.\n\n'
        'We are not a party to any agreement between a Library Owner and a '
        'Member. We do not own or operate any library, do not provide study '
        'seats, do not collect membership fees, and do not guarantee the conduct, '
        'services, pricing, refunds, safety, or facilities of any Library Owner.'),
    LegalSection('2. Eligibility',
        'You must be 18 years or older and legally able to enter a contract. '
        'Silence is not directed at children. A Library Owner enrolling a Member '
        'under 18 is responsible for obtaining any legally required consent.'),
    LegalSection('3. Definitions',
        'Member / Student: a user who joins libraries to study and track '
        'attendance. Library Owner / Admin: a user who creates and manages '
        'libraries. Content: anything uploaded or posted (photos, reviews, '
        'messages, names, documents). Services: the Silence app, website, and '
        'related features.'),
    LegalSection('4. Accounts',
        'Provide accurate information and keep your login secure; you are '
        'responsible for activity under your account. You may sign in with '
        'email/password, Google, or Apple. We may suspend or terminate accounts '
        'that violate these Terms, the law, or platform rules. Your initial role '
        '(Member or Library Owner) is selected at signup; changing roles later '
        'may reset/erase your account data, as described in the app.'),
    LegalSection('5. Library Owner responsibilities',
        'If you are a Library Owner: you are solely responsible for your library '
        '(seats, shifts, pricing, trials, memberships, refunds, safety, '
        'facilities, and your relationship with Members). You are the Data '
        'Fiduciary for the Member data you collect through Silence and must have '
        'a lawful basis, collect only what you need, and protect it. If you '
        'collect verification documents you must comply with applicable law, '
        'avoid collecting any government ID unless strictly necessary and lawful, '
        'and never misuse, over-collect, or publicly expose any ID. All fees you '
        'charge Members are collected by you directly (e.g., via UPI), outside '
        'Silence; your invoicing, taxes, and refunds to Members are your '
        'responsibility. Accuracy of the attendance, seat, payment, and '
        'membership records you enter or confirm is your responsibility.'),
    LegalSection('6. Member responsibilities',
        'If you are a Member: your membership, fees, refunds, seat, and '
        'facilities are arranged with the Library Owner, not with Silence. '
        'Provide accurate information, use QR check-in honestly (no proxy or '
        'fraudulent check-ins), follow the rules of the library you join, and '
        'behave respectfully.'),
    LegalSection('7. QR attendance',
        'QR check-in/out is a convenience tool. Silence does not guarantee that '
        'every scan, time, or record is accurate or available at all times '
        '(network, device, or configuration issues can occur). Attendance records '
        'are managed and verified by the Library Owner. Silence is not liable for '
        'disputes arising from attendance records.'),
    LegalSection('8. Payments, subscriptions, refunds',
        'a) Member ↔ Library payments (not our money): all such payments happen '
        'outside Silence (e.g., via UPI). Silence never receives, holds, '
        'processes, or refunds these payments. Any payment, dispute, refund, or '
        'chargeback is strictly between the Member and the Library Owner, and '
        'Silence has no liability for them (see the Refund & Cancellation '
        'Policy).\n\n'
        'b) Library-Owner subscription to Silence: the service is free during the '
        'current beta. If paid plans are introduced later, they will be billed '
        'through a third-party provider (e.g., Razorpay) and/or the app store\'s '
        'billing as required by store policies; fees are non-refundable once a '
        'billing period begins, except where required by law; and if a Library '
        'Owner stops paying, essential functions for their existing Members '
        'continue while some Owner-only management features may be limited.'),
    LegalSection('9. Acceptable use',
        'You must not: break any law, infringe others\' rights, or upload '
        'illegal, obscene, hateful, defamatory, or harmful content; impersonate '
        'others, create fake accounts, or submit fraudulent attendance/payments; '
        'attempt to hack, overload, reverse-engineer, scrape, or disrupt the '
        'Services; collect or misuse other users\' personal data; or post spam or '
        'harass any user. See the Community & Content Policy for details and '
        'reporting.'),
    LegalSection('10. User content and licence',
        'You retain ownership of Content you upload. By uploading Content, you '
        'grant Silence a non-exclusive, royalty-free, worldwide licence to host, '
        'store, display, and process that Content solely to operate and provide '
        'the Services (for example, showing your library photos or reviews). You '
        'confirm you have the right to upload it and that it does not infringe '
        'anyone\'s rights. We may remove Content and suspend accounts that violate '
        'these Terms.'),
    LegalSection('11. Intellectual property',
        'The Silence app, website, software, design, and logo are owned by us and '
        'protected by law; you may not copy, modify, or redistribute them without '
        'permission. The name "Silence" is used by us as a brand; it is not '
        'claimed as a registered trademark at this time. Other names and marks '
        '(Google, Apple, UPI, Razorpay, etc.) belong to their respective owners.'),
    LegalSection('12. Suspension and termination',
        'We may suspend, limit, or terminate access (with or without notice) if '
        'you breach these Terms, the law, or platform rules, or to protect users '
        'or the Services. You may stop using Silence and delete your account at '
        'any time (Section 13).'),
    LegalSection('13. Account deletion',
        'You may delete your account from inside the app or at '
        '$kWebsite/delete-account. Deletion freezes the account immediately and '
        'permanently removes data within 30 days, subject to limited legal '
        'retention. See the Privacy Policy for details.'),
    LegalSection('14. Disclaimers',
        'The Services are provided "as is" and "as available", without warranties '
        'of any kind, to the maximum extent permitted by law. We do not warrant '
        'that the Services will be uninterrupted, error-free, or secure, or that '
        'records (including attendance and payments) will be accurate. We are not '
        'responsible for the acts, omissions, services, facilities, safety, '
        'pricing, or refunds of any Library Owner or Member.'),
    LegalSection('15. Limitation of liability',
        'To the maximum extent permitted by law, Silence (and its proprietor) '
        'will not be liable for any indirect, incidental, special, consequential, '
        'or punitive damages, or for loss of data, money, profits, or goodwill, '
        'arising from your use of the Services or from any dealing between a '
        'Member and a Library Owner. Where liability cannot be excluded, our total '
        'aggregate liability is limited to the amount you paid to Silence (if '
        'any) in the 3 months before the claim — which, during the free beta, is '
        '₹0.'),
    LegalSection('16. Indemnity',
        'You agree to indemnify and hold harmless Silence and its proprietor from '
        'any claims, losses, or expenses arising from your Content, your use of '
        'the Services, your breach of these Terms or the law, or (for Library '
        'Owners) your handling of Members and their data.'),
    LegalSection('17. Governing law and disputes',
        'These Terms are governed by the laws of India. Subject to applicable '
        'law, the courts at Alwar, Rajasthan have exclusive jurisdiction. Please '
        'first contact our Grievance Officer to resolve any issue amicably.'),
    LegalSection('18. Grievance Officer',
        'Name: $kOperatorName · Email: $kSupportEmail · Phone: $kSupportPhone. '
        'Complaints acknowledged within 48 hours, resolved within 15 days.'),
    LegalSection('19. Changes & contact',
        'We may update these Terms; material changes are notified in-app or on '
        'the website with a new "Last updated" date, and continued use means '
        'acceptance. Contact: $kSupportEmail · $kSupportPhone · $kOperatorPlace.'),
  ],
  related: [_relPrivacy, _relRefund, _relCancellation, _relCommunity],
);

// ============================================================================
// REFUND POLICY  (mirrors legal/refund_and_cancellation_policy.md — refunds)
// ============================================================================
const LegalDoc legalRefund = LegalDoc(
  title: 'Refund Policy',
  intro:
      'Silence involves two separate money flows. Please read the one that '
      'applies to you. Read together with our Terms & Conditions. Also published '
      'at $kWebsite/refunds.',
  sections: [
    LegalSection('1. Member ↔ Library payments (handled by the library, not Silence)',
        'When a Member pays a Library Owner (for a seat, shift, or membership), '
        'that payment is made directly to the Library Owner outside Silence — for '
        'example through a UPI app. Silence never receives, holds, processes, or '
        'refunds this money; the app only lets a Library Owner record that a '
        'payment was received. All refunds, cancellations, trial terms, and '
        'disputes for memberships are decided solely by the Library Owner, '
        'according to that library\'s own rules.'),
    LegalSection('2. How to get a membership refund',
        'If you want a refund or wish to cancel your membership, contact the '
        'Library Owner directly. Silence cannot issue, guarantee, or force any '
        'such refund and is not responsible for it. Silence may, at its '
        'discretion, provide attendance or payment records to help resolve a '
        'dispute, but takes no responsibility for the outcome.'),
    LegalSection('3. Library-Owner subscription to Silence',
        'The Silence service is currently free during beta, so there is nothing '
        'to refund. If paid subscription plans are introduced in future: '
        'subscription fees are non-refundable once a billing period has begun, '
        'except where a refund is required by applicable law. Where store billing '
        '(Google Play / Apple) is used, the relevant store\'s refund rules also '
        'apply.'),
    LegalSection('4. How to request (subscription)',
        'If/when paid plans exist, email $kSupportEmail from your registered '
        'email with your account details. We acknowledge within 48 hours.'),
    LegalSection('5. Changes',
        'We may update this Policy with a revised "Last updated" date.'),
  ],
  related: [_relCancellation, _relTerms, _relPrivacy],
);

// ============================================================================
// CANCELLATION POLICY  (mirrors legal/refund_and_cancellation_policy.md — cancel)
// ============================================================================
const LegalDoc legalCancellation = LegalDoc(
  title: 'Cancellation Policy',
  intro:
      'This explains how to cancel a membership, a join request, or a Library '
      'Owner subscription. Read together with our Refund Policy and Terms.',
  sections: [
    LegalSection('1. Cancelling a pending join request',
        'A membership join request that has not yet been approved can be '
        'withdrawn from the app at any time at no charge.'),
    LegalSection('2. Cancelling an active membership',
        'You may stop using your seat at any time. Memberships and their fees are '
        'arranged with the Library Owner outside Silence; cancelling in the app '
        'does not automatically create a refund (see the Refund Policy), and any '
        'refund is decided solely by the Library Owner.'),
    LegalSection('3. Membership hold / pause',
        'Where a library enables holds, you can pause your membership within that '
        'library\'s allowed limits; the remaining days resume after the hold.'),
    LegalSection('4. Owner subscription cancellation',
        'The service is free during beta. If paid plans launch later, a Library '
        'Owner can cancel anytime; cancellation stops future renewals but does '
        'not refund the current period. On cancellation or non-payment, essential '
        'features for existing Members continue so Members are not disrupted, '
        'while some Owner-only management features may become limited until you '
        'resubscribe.'),
    LegalSection('5. Account deletion',
        'Deleting your account is separate from cancelling a single membership. '
        'Deletion freezes the account immediately and permanently removes data '
        'within 30 days (a short recovery window applies, as described in the '
        'app).'),
  ],
  related: [_relRefund, _relTerms],
);

// ============================================================================
// COMMUNITY & CONTENT POLICY  (mirrors legal/community_and_content_policy.md)
// ============================================================================
const LegalDoc legalCommunity = LegalDoc(
  title: 'Community Guidelines',
  intro:
      'Silence connects students and library owners. Treat everyone with '
      'respect. These guidelines cover community standards, acceptable content, '
      'reporting/abuse, and copyright complaints. Also published at '
      '$kWebsite/community.',
  sections: [
    LegalSection('1. Be respectful',
        'Harassment, bullying, threats, hate speech, or discrimination of any '
        'kind are not allowed. In study spaces, keep noise to a minimum, silence '
        'your phone, and take calls outside the study area.'),
    LegalSection('2. Content that is NOT allowed',
        'You may not post, upload, or share content that: is illegal, '
        'fraudulent, or infringes anyone\'s rights; is obscene, sexually '
        'explicit, or harmful to minors; is hateful, abusive, defamatory, or '
        'harassing; is spam, misleading, or impersonates another person or '
        'business; contains malware, or someone else\'s personal/identity data '
        'without consent; or attempts to manipulate reviews, attendance, or '
        'payments.'),
    LegalSection('3. User-generated content (reviews, photos, messages, names)',
        'You are responsible for the content you post (such as library reviews, '
        'photos, and messages). By posting, you grant Silence a licence to host '
        'and display it to operate the Services (see Terms, Section 10). We may '
        'remove content and suspend or terminate accounts that violate this '
        'Policy — with or without notice.'),
    LegalSection('4. Reporting and moderation',
        'Any user can report content or a library that violates this Policy using '
        'the in-app Report option, or by emailing $kSupportEmail with details and '
        'a screenshot. We aim to review reported content within 24 hours and will '
        'remove content or take action where appropriate. Library Owners can '
        'remove or hide reviews and content on their own library; Silence can '
        'remove any content on the platform. You can also block abusive users '
        'from inside the app.'),
    LegalSection('5. Copyright / intellectual-property complaints',
        'If you believe content on Silence infringes your copyright or other IP '
        'rights, email $kSupportEmail with: your name and contact details; '
        'identification of the work that is infringed; the location (screen) of '
        'the infringing content; a statement that you believe in good faith the '
        'use is unauthorised; and a statement that the information is accurate '
        'and you are the rights holder or authorised to act. We will review and, '
        'where justified, remove the content and may suspend the responsible '
        'account. Repeat infringers will be terminated.'),
    LegalSection('6. Enforcement',
        'Violations may lead to content removal, warnings, suspension, or '
        'permanent termination, at our discretion, and may be reported to '
        'authorities where required by law.'),
    LegalSection('7. Changes',
        'We may update this Policy with a revised "Last updated" date.'),
  ],
  related: [_relTerms, _relPrivacy, _relAbout],
);
