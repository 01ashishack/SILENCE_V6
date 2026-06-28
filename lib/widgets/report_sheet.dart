import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_snackbar.dart';
import '../services/moderation_service.dart';
import '../theme/app_palette.dart';
import '../utils/error_messages.dart';

/// Human labels for the report reasons (keys must match
/// [ModerationService.reasons]).
const Map<String, String> _reasonLabels = {
  'spam': 'Spam or misleading',
  'harassment': 'Harassment or abuse',
  'inappropriate': 'Inappropriate / explicit',
  'impersonation': 'Impersonation',
  'copyright': 'Copyright / IP',
  'other': 'Something else',
};

/// Shows the "Report content" bottom sheet for a UGC [targetType]/[targetId].
/// Returns `true` if a report was successfully submitted.
///
/// Honest results: success → green snackbar; an already-existing open report →
/// info snackbar; any failure → error snackbar (never a false success).
Future<bool> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? libraryId,
  String? targetLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      libraryId: libraryId,
      targetLabel: targetLabel,
    ),
  );
  return result ?? false;
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String? libraryId;
  final String? targetLabel;
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    this.libraryId,
    this.targetLabel,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ModerationService.submitReport(
        targetType: widget.targetType,
        targetId: widget.targetId,
        libraryId: widget.libraryId,
        reason: _reason!,
        description: _descCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      AppSnackbar.success(context, 'Report sent. Thanks — we\'ll review it.');
    } on DuplicateReportException {
      if (!mounted) return;
      Navigator.pop(context, false);
      AppSnackbar.info(context, 'You\'ve already reported this — it\'s under review.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Color(0xFFE65C00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Report ${widget.targetLabel ?? 'content'}',
                    style: GoogleFonts.outfit(
                        fontSize: 17, fontWeight: FontWeight.bold, color: p.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tell us what\'s wrong. Reports are confidential.',
              style: GoogleFonts.inter(fontSize: 12.5, color: p.textMuted)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ModerationService.reasons.map((r) {
              final selected = _reason == r;
              return ChoiceChip(
                label: Text(_reasonLabels[r] ?? r),
                selected: selected,
                onSelected: (_) => setState(() => _reason = r),
                labelStyle: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : p.textSecondary),
                selectedColor: const Color(0xFFE65C00),
                backgroundColor: p.scaffold,
                side: BorderSide(color: selected ? const Color(0xFFE65C00) : p.border),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            maxLength: 500,
            style: GoogleFonts.inter(fontSize: 13.5, color: p.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add details (optional)',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: p.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_reason == null || _submitting) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : Text('Submit report',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
