import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/plan_service.dart';

/// Gate an admin **management** action behind the plan.
///
/// Returns `true` if the action is allowed (caller proceeds); if blocked, it
/// shows an honest "upgrade" sheet and returns `false`.
///
/// During beta (`PlanService.betaMode == true`) this ALWAYS returns true, so
/// nothing is blocked yet — the gates are in place but inert until the flag is
/// flipped. Essential ops (accept requests, reply queries, check-in, holidays)
/// must NOT use this helper — they stay free even when a plan expires.
///
/// Usage:
/// ```dart
/// if (!await ensurePlan(context, AdminFeature.addMember, featureLabel: 'Adding members')) return;
/// ```
Future<bool> ensurePlan(
  BuildContext context,
  AdminFeature feature, {
  String featureLabel = 'This feature',
}) async {
  if (PlanService.instance.canUse(feature)) return true;
  if (!context.mounted) return false;

  final nav = Navigator.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: Color(0xFFE65C00), size: 40),
          const SizedBox(height: 12),
          Text(
            'Upgrade to unlock',
            style: GoogleFonts.outfit(
                fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 8),
          Text(
            '$featureLabel is part of a paid plan. Your library keeps running on the free plan '
            '(check-ins, join requests, queries all work) — upgrade to manage and grow.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                nav.pushNamed('/admin/subscription');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('See plans',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Not now',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );
  return false;
}
