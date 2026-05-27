import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VerifiedBadgeScreen extends StatefulWidget {
  const VerifiedBadgeScreen({super.key});

  @override
  State<VerifiedBadgeScreen> createState() => _VerifiedBadgeScreenState();
}

class _VerifiedBadgeScreenState extends State<VerifiedBadgeScreen> {
  // Mock criteria values (verified tick rules)
  bool _profileComplete = false; 
  int _operatingDays = 32; // criteria >= 30
  int _paymentsCount = 23; // criteria >= 20
  int _attendanceCount = 14; // criteria >= 10
  double _profilePct = 0.78; // criteria >= 80%

  @override
  Widget build(BuildContext context) {
    bool meetsOperating = _operatingDays >= 30;
    bool meetsPayments = _paymentsCount >= 20;
    bool meetsAttendance = _attendanceCount >= 10;
    bool meetsProfile = _profilePct >= 0.80;
    bool isEligible = meetsOperating && meetsPayments && meetsAttendance && meetsProfile;

    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Verified Badge Status',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Badge Hero Card
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65C00).withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Gold/Orange badge symbol
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3ED),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE65C00).withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            '🎖️',
                            style: TextStyle(fontSize: 48),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'SILENCE Verified Badge',
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isEligible 
                            ? 'Your library has earned the verified status! ✓'
                            : 'Complete all trust building milestones below to earn your trust badge.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), height: 1.4),
                      ),
                      if (isEligible) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65C00).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFFE65C00)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, color: Color(0xFFE65C00), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'STATUS: VERIFIED',
                                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Criteria Section Header
                Text(
                  'Milestones & Progress',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),

                // 3. Criteria Checklist
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildCriteriaItem(
                        'Profile completion >= 80%',
                        'Current completion: ${(_profilePct * 100).toInt()}%',
                        meetsProfile,
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildCriteriaItem(
                        '30+ days operational history',
                        'Registered: $_operatingDays days ago',
                        meetsOperating,
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildCriteriaItem(
                        '20+ payments ledger transactions',
                        'Recorded: $_paymentsCount / 20',
                        meetsPayments,
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildCriteriaItem(
                        '10+ member attendance checks',
                        'Registered: $_attendanceCount / 10',
                        meetsAttendance,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Call to Action Button
                if (!isEligible)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, '/admin/library/setup/1');
                    },
                    child: Text(
                      'Complete Library Profile Now',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981), // Premium emerald green on success
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Badge already claimed successfully! 🎖️'), backgroundColor: Color(0xFF10B981)),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: Text(
                      'Claim Gold Badge 🎖️',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCriteriaItem(String title, String subtitle, bool isCompleted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFFFFF3ED) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.close,
              color: isCompleted ? const Color(0xFFE65C00) : const Color(0xFF94A3B8),
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13, 
                    fontWeight: FontWeight.bold, 
                    color: isCompleted ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
