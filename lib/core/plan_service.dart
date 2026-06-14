import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-side **management** features that require an active paid plan
/// (Pro / Premium / trial). Member-facing actions and essential day-to-day ops
/// — accept join/seat requests, reply to queries, mark holidays, member
/// check-in, view data — are intentionally NOT in this enum: they stay allowed
/// even when a plan has expired (the "Free / readonly floor"), so the library
/// keeps running and no member is ever blocked.
enum AdminFeature {
  addMember,
  fullAnalytics,
  export,
  branding,
  verifiedBadge,
  announcements,
  referralConfig,
  pricingEdit,
  shiftEdit,
  layoutEdit,
  addonsManage,
  expenditure,
  auditLog,
  multiLibrary, // Premium-only
}

/// Single source of truth for "what is this admin's plan and what can they do".
///
/// Golden rule (see docs_fix/SUBSCRIPTION_ARCHITECTURE.md): the **server**
/// decides the plan (website + Razorpay webhook write `users.subscription_*`);
/// the app only **reads** it here and gates features. This class never writes
/// the plan.
///
/// Gating is 2-level:
///   • active vs expired  → admin management on/off (`managementUnlocked`)
///   • Pro vs Premium     → library count (`maxLibraries`: 1 vs unlimited)
class PlanService {
  PlanService._();
  static final PlanService instance = PlanService._();

  /// BETA SWITCH. During launch everyone gets full access. Flip to `false`
  /// (after the subscription website + webhook + the `subscription_*` RLS lock
  /// are live) to start ENFORCING plan limits. While true, every gate below
  /// returns "allowed", so the app behaves exactly as it does today.
  static const bool betaMode = true;

  static const int _unlimited = 1 << 30;

  String _plan = 'free'; // 'free' | 'pro' | 'premium'
  String _status = 'active'; // active | grace | readonly | cancelled
  DateTime? _expiry;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get plan => _plan;
  String get status => _status;
  DateTime? get expiry => _expiry;

  /// 'Free' | 'Pro' | 'Premium' for display.
  String get displayPlanName =>
      _plan.isEmpty ? 'Free' : '${_plan[0].toUpperCase()}${_plan.substring(1)}';

  // ── Hydration (app READS, never writes) ─────────────────────────────────────

  /// Feed from an already-loaded `users` row (no extra query). Call this where
  /// admin user data is loaded (e.g. admin_home).
  void hydrateFromRow(Map<String, dynamic>? row) {
    if (row == null) return;
    hydrate(
      plan: row['subscription_plan']?.toString(),
      status: row['subscription_status']?.toString(),
      expiry: _parseDate(row['subscription_expiry']),
    );
  }

  void hydrate({String? plan, String? status, DateTime? expiry}) {
    _plan = _normalizePlan(plan);
    _status = (status == null || status.trim().isEmpty) ? 'active' : status.trim();
    _expiry = expiry;
    _loaded = true;
  }

  /// Self-fetch the current admin's subscription fields (use when no row is
  /// already loaded). Safe to call repeatedly; failures leave defaults.
  Future<void> load() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('users')
          .select('subscription_plan, subscription_status, subscription_expiry')
          .eq('id', user.id)
          .maybeSingle();
      hydrateFromRow(row);
    } catch (_) {
      // Leave defaults; beta mode keeps things unlocked anyway.
    }
  }

  void reset() {
    _plan = 'free';
    _status = 'active';
    _expiry = null;
    _loaded = false;
  }

  // ── Derived state ───────────────────────────────────────────────────────────

  bool get _hasPaidTier => _plan == 'pro' || _plan == 'premium';

  /// True when management is unlocked: a paid/trial plan that hasn't expired.
  /// `free` is the restricted floor → false (essential ops still allowed,
  /// because those are never routed through `canUse`).
  bool get managementUnlocked {
    if (betaMode) return true;
    if (!_hasPaidTier) return false;
    if (_status == 'readonly' || _status == 'cancelled') return false;
    if (_expiry != null && _expiry!.isBefore(DateTime.now())) return false;
    return _status == 'active' || _status == 'grace';
  }

  /// Restricted "Free / Expired" floor (admin management locked).
  bool get isExpired => !managementUnlocked;

  bool get isPremium => _plan == 'premium';

  /// Pro = 1 library, Premium = unlimited. (Beta = unlimited.)
  int get maxLibraries {
    if (betaMode) return _unlimited;
    if (managementUnlocked && isPremium) return _unlimited;
    return 1; // free + pro
  }

  bool canAddLibrary(int currentCount) => currentCount < maxLibraries;

  /// Whether an admin management feature is available right now.
  bool canUse(AdminFeature f) {
    if (betaMode) return true;
    if (f == AdminFeature.multiLibrary) return managementUnlocked && isPremium;
    return managementUnlocked; // all other management features need an active plan
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  static String _normalizePlan(String? raw) {
    final p = (raw ?? '').toLowerCase().trim();
    switch (p) {
      case 'premium':
        return 'premium';
      case 'pro':
      case 'pro_plan':
        return 'pro';
      // legacy keys → closest current tier
      case 'starter':
      case 'basic':
        return 'pro';
      case 'trial':
        return 'premium'; // trial = full access
      default:
        return 'free';
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
