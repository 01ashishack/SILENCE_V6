import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/member_data.dart';


class AddMemberStep5 extends StatelessWidget {
  final MemberData memberData;
  final String libraryName;
  final Function(int) onEditStep;
  final VoidCallback onSaveDraft;
  final VoidCallback onConfirmRegister;

  const AddMemberStep5({
    super.key,
    required this.memberData,
    required this.libraryName,
    required this.onEditStep,
    required this.onSaveDraft,
    required this.onConfirmRegister,
  });

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _getShareMessage() {
    final finalPrice = (memberData.totalBasePrice - memberData.discount).clamp(0, double.infinity).toInt();
    final start = _calculatedPlanStart;
    final expiry = _calculatedExpiry;
    final planLabel = memberData.planType == 'monthly'
        ? 'Monthly'
        : (memberData.planType == '3_month' ? '3-Month' : '6-Month');

    return 'Welcome to $libraryName!\n\n'
        'Member Details:\n'
        '• Name: ${memberData.name}\n'
        '• Phone: +91 ${memberData.phone}\n'
        '• Seat: ${memberData.selectedSeatLabel ?? "N/A"}\n'
        '• Shift: ${memberData.selectedShiftName}\n'
        '• Plan: $planLabel Plan\n'
        '• Validity: ${_formatDate(start)} to ${_formatDate(expiry)}\n'
        '• Status: ${memberData.paymentFlow == 'paid' ? 'Paid (₹$finalPrice via ${memberData.paymentMethod.toUpperCase()})' : 'Pending Payment (₹$finalPrice)'}\n\n'
        'Keep learning, keep shining!';
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final phone = memberData.phone.trim();
    final message = Uri.encodeComponent(_getShareMessage());
    final url = 'https://wa.me/91$phone?text=$message';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _shareGmail(BuildContext context) async {
    final email = memberData.email.trim();
    final subject = Uri.encodeComponent('Membership Confirmation - $libraryName');
    final body = Uri.encodeComponent(_getShareMessage());
    final url = 'mailto:$email?subject=$subject&body=$body';
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch Email app: $e')),
        );
      }
    }
  }

  Future<void> _shareSMS(BuildContext context) async {
    final phone = memberData.phone.trim();
    final body = Uri.encodeComponent(_getShareMessage());
    final url = 'sms:$phone?body=$body';
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch SMS app: $e')),
        );
      }
    }
  }

  DateTime get _calculatedPlanStart {
    if (memberData.mode == 'existing') {
      return memberData.planStartDate ?? memberData.joiningDate;
    } else {
      if (memberData.customPlanStart && memberData.planStartDate != null) {
        return memberData.planStartDate!;
      }
      return memberData.joiningDate.add(Duration(days: memberData.trialDays));
    }
  }

  DateTime get _calculatedExpiry {
    final start = _calculatedPlanStart;
    int durationMonths = 1;
    if (memberData.planType == '3_month') durationMonths = 3;
    if (memberData.planType == '6_month') durationMonths = 6;
    // Cap the day to the target month's last day (Jan 31 + 1mo = Feb 28/29).
    final y = start.year + ((start.month - 1 + durationMonths) ~/ 12);
    final m = (start.month - 1 + durationMonths) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, start.day > lastDay ? lastDay : start.day);
  }

  @override
  Widget build(BuildContext context) {
    final finalPrice = (memberData.totalBasePrice - memberData.discount).clamp(0, double.infinity).toInt();
    final start = _calculatedPlanStart;
    final expiry = _calculatedExpiry;

    // Membership Card styling replication from member_home.dart
    Color borderColor;
    String statusLabel;
    if (memberData.paymentFlow == 'paid') {
      borderColor = const Color(0xFF22C55E); // green
      statusLabel = 'Active';
    } else if (memberData.trialDays > 0) {
      borderColor = const Color(0xFF7C3AED); // purple
      statusLabel = 'Trial';
    } else {
      borderColor = const Color(0xFF9CA3AF); // gray
      statusLabel = 'Pending';
    }

    double progress = 0.0;
    final totalDays = expiry.difference(start).inDays;
    if (totalDays > 0) {
      final elapsed = DateTime.now().difference(start).inDays;
      progress = (elapsed / totalDays).clamp(0.0, 1.0);
    }
    final remainingDays = expiry.difference(DateTime.now()).inDays;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Review & Confirm *',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Double check the member details and membership card preview before completing registration.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),

          // MEMBERSHIP CARD PREVIEW (matching member_home.dart style)
          Text(
            'Membership Card Preview',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: borderColor, width: 4)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        libraryName.toUpperCase(),
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: borderColor),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFF1F5F9),
                      backgroundImage: memberData.profilePhoto != null
                          ? FileImage(memberData.profilePhoto!) as ImageProvider
                          : (memberData.existingPhotoUrl != null && memberData.existingPhotoUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(memberData.existingPhotoUrl!)
                              : null),
                      child: (memberData.profilePhoto == null && (memberData.existingPhotoUrl == null || memberData.existingPhotoUrl!.isEmpty))
                          ? const Icon(Icons.person, color: Color(0xFFE65C00), size: 20)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        memberData.name.isNotEmpty ? memberData.name : 'New Member',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.event_seat, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      memberData.selectedSeatLabel ?? 'Seat Pending',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFE65C00)),
                    ),
                    const SizedBox(width: 24),
                    const Icon(Icons.wb_sunny, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      memberData.selectedShiftName.isNotEmpty ? memberData.selectedShiftName : 'Shift Pending',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      '${memberData.planType == 'monthly' ? 'Monthly' : memberData.planType == '3_month' ? '3-Month' : '6-Month'} Plan',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '₹$finalPrice',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    color: borderColor,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Expires: ${_formatDate(expiry)}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                    ),
                    Text(
                      remainingDays > 0
                          ? '$remainingDays days left'
                          : remainingDays == 0
                              ? 'Expires today'
                              : 'Expired',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: remainingDays <= 7 ? Colors.redAccent : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // REVIEW SECTIONS
          _buildSectionHeader('Personal Details', 0),
          _buildReviewRow('Name', memberData.name),
          _buildReviewRow("Father's Name", memberData.fatherName.isNotEmpty ? memberData.fatherName : 'N/A'),
          _buildReviewRow('DOB', memberData.dob != null ? _formatDate(memberData.dob!) : 'N/A'),
          _buildReviewRow('Gender', memberData.gender?.toUpperCase() ?? 'N/A'),
          _buildReviewRow('Phone', '+91 ${memberData.phone}'),
          _buildReviewRow('Email', memberData.email.isNotEmpty ? memberData.email : 'N/A'),
          _buildReviewRow('Preparing For', memberData.preparingFor ?? 'N/A'),
          _buildReviewRow('Joining Date', _formatDate(memberData.joiningDate)),
          _buildReviewRow(
            'Documents',
            [
              if (memberData.idProof1File != null) memberData.idProof1Type ?? 'Doc 1',
              if (memberData.idProof2File != null) memberData.idProof2Type ?? 'Doc 2',
            ].join(', ').isEmpty
                ? 'None'
                : [
                    if (memberData.idProof1File != null) memberData.idProof1Type ?? 'Doc 1',
                    if (memberData.idProof2File != null) memberData.idProof2Type ?? 'Doc 2',
                  ].join(', '),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader('Plan & Schedule', 1),
          _buildReviewRow('Shift', memberData.selectedShiftName.isNotEmpty ? memberData.selectedShiftName : 'N/A'),
          _buildReviewRow('Plan Type', memberData.planType == 'monthly' ? 'Monthly' : (memberData.planType == '3_month' ? '3-Month' : '6-Month')),
          if (memberData.mode == 'new') _buildReviewRow('Trial Days', '${memberData.trialDays} Days'),
          _buildReviewRow('Start Date', _formatDate(start)),
          _buildReviewRow('Expiry Date', _formatDate(expiry)),
          const SizedBox(height: 16),

          _buildSectionHeader('Seat Assignment', 2),
          _buildReviewRow('Floor', memberData.selectedFloorName ?? 'N/A'),
          _buildReviewRow('Section', memberData.selectedSectionName ?? 'N/A'),
          _buildReviewRow('Seat Label', memberData.selectedSeatLabel ?? 'N/A'),
          const SizedBox(height: 16),

          if (memberData.mode != 'existing') ...[
            _buildSectionHeader('Payment & Confirmation', 3),
            _buildReviewRow('Subtotal', '₹${memberData.totalBasePrice}'),
            _buildReviewRow('Discount', '₹${memberData.discount}'),
            _buildReviewRow('Final Payable', '₹$finalPrice'),
            _buildReviewRow('Payment Flow', memberData.paymentFlow == 'paid' ? 'Mark as Paid Now' : 'Send Payment Request'),
            if (memberData.paymentFlow == 'paid') _buildReviewRow('Payment Mode', memberData.paymentMethod.toUpperCase()),
          ],
          const SizedBox(height: 24),

          // SHARE ACTIONS
          Text(
            'Share Details with Member',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareWhatsApp(context),
                  icon: const Icon(Icons.message, size: 18),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareGmail(context),
                  icon: const Icon(Icons.mail, size: 18),
                  label: const Text('Email'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA4335),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareSMS(context),
                  icon: const Icon(Icons.sms, size: 18),
                  label: const Text('SMS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ACTION BUTTONS
          OutlinedButton(
            onPressed: onSaveDraft,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Save as Draft',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE65C00),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onConfirmRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Confirm & Add Member',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int stepIndex) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
          ),
          InkWell(
            onTap: () => onEditStep(stepIndex),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  'Edit',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
