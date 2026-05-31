import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/member_data.dart';

class AddMemberStep5 extends StatelessWidget {
  final MemberData memberData;
  final String libraryName;
  final Function(int) onEditStep;

  const AddMemberStep5({
    super.key,
    required this.memberData,
    required this.libraryName,
    required this.onEditStep,
  });

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _shareDetails() {
    final text = 'Welcome to $libraryName!\n\n'
        'Member Details:\n'
        'Name: ${memberData.name}\n'
        'Seat: ${memberData.selectedSeatLabel ?? "N/A"}\n'
        'Shift: ${memberData.selectedShiftName}\n'
        'Plan: ${memberData.planType == "monthly" ? "Monthly" : (memberData.planType == "3_month" ? "3-Month" : "6-Month")}\n'
        'Validity: ${_formatDate(_calculatedPlanStart)} to ${_formatDate(_calculatedExpiry)}\n'
        'Paid: ₹${(memberData.totalBasePrice - memberData.discount).clamp(0, double.infinity).toInt()} via ${memberData.paymentMethod.toUpperCase()}\n\n'
        'Keep learning, keep shining!';

    Share.share(text, subject: 'Membership Confirmation - $libraryName');
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
    return DateTime(start.year, start.month + durationMonths, start.day);
  }

  @override
  Widget build(BuildContext context) {
    final finalPrice = (memberData.totalBasePrice - memberData.discount).clamp(0, double.infinity).toInt();
    final start = _calculatedPlanStart;
    final expiry = _calculatedExpiry;

    return SingleChildScrollView(
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
  
          // MEMBERSHIP CARD PREVIEW
          Text(
            'Membership Card Preview',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            shadowColor: Colors.black26,
            child: Container(
              padding: const EdgeInsets.all(16),
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65C00), Color(0xFFFF802B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -50,
                    top: -50,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              libraryName.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'MEMBERSHIP CARD',
                              style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.white24,
                            backgroundImage: (() {
                              if (memberData.profilePhoto != null) {
                                return kIsWeb
                                    ? NetworkImage(memberData.profilePhoto!.path)
                                    : FileImage(memberData.profilePhoto!) as ImageProvider;
                              } else if (memberData.existingPhotoUrl != null && memberData.existingPhotoUrl!.isNotEmpty) {
                                return NetworkImage(memberData.existingPhotoUrl!);
                              }
                              return null;
                            })(),
                            child: (memberData.profilePhoto == null && (memberData.existingPhotoUrl == null || memberData.existingPhotoUrl!.isEmpty))
                                ? const Icon(Icons.person, size: 36, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  memberData.name.isNotEmpty ? memberData.name : 'Member Name',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.chair_outlined, color: Colors.white70, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Seat: ${memberData.selectedSeatLabel ?? "N/A"}',
                                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.access_time_outlined, color: Colors.white70, size: 14),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        memberData.selectedShiftName.isNotEmpty ? memberData.selectedShiftName : 'N/A',
                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VALID FROM',
                                style: GoogleFonts.inter(fontSize: 8, color: Colors.white70),
                              ),
                              Text(
                                _formatDate(start),
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VALID TILL',
                                style: GoogleFonts.inter(fontSize: 8, color: Colors.white70),
                              ),
                              Text(
                                _formatDate(expiry),
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              memberData.paymentFlow == 'paid' ? 'PAID' : 'PENDING',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: memberData.paymentFlow == 'paid' ? const Color(0xFFE65C00) : Colors.amber[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
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
  
          _buildSectionHeader('Payment & Confirmation', 3),
          _buildReviewRow('Subtotal', '₹${memberData.totalBasePrice}'),
          _buildReviewRow('Discount', '₹${memberData.discount}'),
          _buildReviewRow('Final Payable', '₹$finalPrice'),
          _buildReviewRow('Payment Flow', memberData.paymentFlow == 'paid' ? 'Mark as Paid Now' : 'Send Payment Request'),
          if (memberData.paymentFlow == 'paid') _buildReviewRow('Payment Mode', memberData.paymentMethod.toUpperCase()),
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
                  onPressed: _shareDetails,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
