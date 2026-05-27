import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminProfileTab extends StatelessWidget {
  final String? libraryId;
  final String libraryName;
  final String? coverPhotoUrl;
  final List<dynamic> myLibraries;
  final Function(String libId) onLibraryChanged;
  final VoidCallback onLogout;
  final String adminName;
  final String adminEmail;
  final String adminPhone;

  const AdminProfileTab({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.coverPhotoUrl,
    required this.myLibraries,
    required this.onLibraryChanged,
    required this.onLogout,
    required this.adminName,
    required this.adminEmail,
    required this.adminPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFE65C00),
        elevation: 0,
        title: Text(
          'Admin Profile',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Profile Header Card
            _buildProfileHeaderCard(),
            const SizedBox(height: 20),

            // 2. Your Libraries List
            _buildYourLibrariesCard(context),
            const SizedBox(height: 20),

            // 3. Business Settings Grid
            _buildBusinessSettingsGrid(context),
            const SizedBox(height: 20),

            // 4. Account Settings Rows
            _buildAccountSettingsCard(context),
            const SizedBox(height: 24),

            // 5. Logout Button
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
              label: Text(
                'Logout Account',
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Profile Pic Avatar
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF3ED),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.person, size: 36, color: Color(0xFFE65C00)),
            ),
          ),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminName,
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                Text(
                  'Owner • SILENCE Study Zone',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPill('${myLibraries.length} Branches', const Color(0xFFEFF6FF), const Color(0xFF3B82F6)),
                    const SizedBox(width: 6),
                    _buildPill('Pro Plan', const Color(0xFFFFF3ED), const Color(0xFFE65C00)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981), // Emerald operational green
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'All systems operational',
                      style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF10B981), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  Widget _buildYourLibrariesCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Libraries',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: myLibraries.length,
            separatorBuilder: (context, idx) => const Divider(height: 16, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, idx) {
              final lib = myLibraries[idx];
              final name = lib['name'] ?? 'Study Center';
              final city = lib['address_city'] ?? 'City';
              final libId = lib['id'];

              return InkWell(
                onTap: () {
                  Navigator.pushNamed(context, '/admin/library/profile', arguments: libId);
                },
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.storefront, color: Color(0xFF6B7280)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                          ),
                          Text(
                            '$city • 86% Occupancy • 120 Members',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/admin/library/profile', arguments: libraryId);
              },
              child: Text(
                'Manage Active Library Profile →',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessSettingsGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Business Settings',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const Icon(Icons.settings, size: 16, color: Color(0xFF6B7280)),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
            children: [
              _buildGridItem(context, Icons.access_time, 'Hours & Shifts', '/admin/settings/shifts'),
              _buildGridItem(context, Icons.receipt_long, 'Seat Pricing', '/admin/settings/pricing'),
              _buildGridItem(context, Icons.rule_folder, 'Conduct Rules', '/admin/settings/business-rules'),
              _buildGridItem(context, Icons.palette_outlined, 'Branding', '/admin/settings/branding'),
              _buildGridItem(context, Icons.qr_code, 'QR Assets', '/admin/settings/qr'),
              _buildGridItem(context, Icons.widgets_outlined, 'Add-on Services', '/admin/settings/addons'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, IconData icon, String label, String routeName) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, routeName);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: const Color(0xFFE65C00)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF4B5563)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSettingsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildListItem(context, Icons.person_outline, 'Edit Admin Profile', '/admin/profile/complete'),
          _buildListItem(context, Icons.stars_outlined, 'Subscription & Billing', '/admin/subscription'),
          _buildListItem(context, Icons.campaign_outlined, 'Announcements History', '/admin/announcements'),
          _buildListItem(context, Icons.ios_share, 'Exports & Reports', '/admin/exports'),
          _buildListItem(context, Icons.history_edu_outlined, 'Audit Log History', '/admin/audit-log'),
          _buildListItem(context, Icons.people_outline, 'Referrals Configuration', '/admin/settings/referrals'),
          _buildListItem(context, Icons.calendar_month_outlined, 'Scheduled Closures', '/admin/settings/closures'),
          _buildListItem(context, Icons.notifications_active_outlined, 'Notification Preferences', '/admin/settings/notifications'),
        ],
      ),
    );
  }

  Widget _buildListItem(BuildContext context, IconData icon, String title, String routeName) {
    return ListTile(
      leading: Icon(icon, size: 20, color: const Color(0xFF6B7280)),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
      ),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
      onTap: () {
        Navigator.pushNamed(context, routeName);
      },
    );
  }
}
