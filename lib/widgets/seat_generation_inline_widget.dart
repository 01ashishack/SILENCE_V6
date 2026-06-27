import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';

class SeatGenerationInlineWidget extends StatefulWidget {
  final String creationMode; // 'section' or 'direct'
  final Future<void> Function(String? sectionName, List<String> seatLabels) onSave;
  final VoidCallback onCancel;

  const SeatGenerationInlineWidget({
    super.key,
    required this.creationMode,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<SeatGenerationInlineWidget> createState() => _SeatGenerationInlineWidgetState();
}

class _SeatGenerationInlineWidgetState extends State<SeatGenerationInlineWidget> {
  final _sectionNameCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _bulkStartCtrl = TextEditingController();
  final _bulkEndCtrl = TextEditingController();
  final _singleSeatsCtrl = TextEditingController();

  String _bulkOrSingle = 'bulk';
  bool _isSaving = false;

  @override
  void dispose() {
    _sectionNameCtrl.dispose();
    _prefixCtrl.dispose();
    _bulkStartCtrl.dispose();
    _bulkEndCtrl.dispose();
    _singleSeatsCtrl.dispose();
    super.dispose();
  }

  String _getInlinePreviewText() {
    final prefix = _prefixCtrl.text.trim();
    final int? start = int.tryParse(_bulkStartCtrl.text.trim());
    final int? end = int.tryParse(_bulkEndCtrl.text.trim());

    if (start == null || end == null || start > end || end - start > 100) {
      return 'Invalid range (max 100 seats)';
    }

    final List<String> samples = [];
    for (int i = start; i <= end; i++) {
      final label = prefix.isEmpty ? '$i' : '$prefix-$i';
      samples.add(label);
      if (samples.length >= 3) break;
    }

    final total = end - start + 1;
    if (total <= 3) {
      return 'Will generate: ${samples.join(", ")}';
    } else {
      final lastLabel = prefix.isEmpty ? '$end' : '$prefix-$end';
      return 'Will generate: ${samples.join(", ")}, ..., $lastLabel ($total seats total)';
    }
  }

  Future<void> _handleSave() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final List<String> newLabels = [];

    if (_bulkOrSingle == 'bulk') {
      final prefix = _prefixCtrl.text.trim();
      final int? start = int.tryParse(_bulkStartCtrl.text.trim());
      final int? end = int.tryParse(_bulkEndCtrl.text.trim());

      if (start == null || end == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Please enter valid start and end numbers.'), backgroundColor: Colors.red),
        );
        return;
      }
      if (start > end) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Start number cannot be greater than end number.'), backgroundColor: Colors.red),
        );
        return;
      }
      if (end - start > 100) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Bulk generation is limited to 100 seats at a time.'), backgroundColor: Colors.red),
        );
        return;
      }

      for (int i = start; i <= end; i++) {
        final label = prefix.isEmpty ? '$i' : '$prefix-$i';
        newLabels.add(label);
      }
    } else {
      final text = _singleSeatsCtrl.text.trim();
      if (text.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Please enter at least one seat label.'), backgroundColor: Colors.red),
        );
        return;
      }
      final parts = text.split(',');
      for (final p in parts) {
        final label = p.trim();
        if (label.isNotEmpty) {
          final prefix = _prefixCtrl.text.trim();
          final fullLabel = prefix.isEmpty ? label : '$prefix-$label';
          newLabels.add(fullLabel);
        }
      }
    }

    if (newLabels.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('No seat labels generated.'), backgroundColor: Colors.red),
      );
      return;
    }

    String? sectionName;
    if (widget.creationMode == 'section') {
      sectionName = _sectionNameCtrl.text.trim();
      if (sectionName.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Section name is required.'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      await widget.onSave(sectionName, newLabels);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error saving layout content: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color orange = Color(0xFFE65C00);
    final Color dark = context.palette.textPrimary;
    final Color grey = context.palette.textMuted;

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.creationMode == 'section' ? 'Add Section & Seats' : 'Add Direct Seats',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: dark,
            ),
          ),
          const SizedBox(height: 16),

          if (widget.creationMode == 'section') ...[
            Text('Section Name *', style: GoogleFonts.inter(fontSize: 12, color: grey, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: TextField(
                controller: _sectionNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Boys Room, General Area',
                  hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange)),
                ),
                style: GoogleFonts.inter(fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Text('Seat Prefix (Optional)', style: GoogleFonts.inter(fontSize: 12, color: grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: TextField(
              controller: _prefixCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g. G, FL',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange)),
              ),
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _bulkOrSingle = 'bulk'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _bulkOrSingle == 'bulk' ? orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Bulk Range',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: _bulkOrSingle == 'bulk' ? FontWeight.bold : FontWeight.normal,
                        color: _bulkOrSingle == 'bulk' ? orange : grey,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _bulkOrSingle = 'single'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _bulkOrSingle == 'single' ? orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Single Seats',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: _bulkOrSingle == 'single' ? FontWeight.bold : FontWeight.normal,
                        color: _bulkOrSingle == 'single' ? orange : grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_bulkOrSingle == 'bulk') ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From', style: GoogleFonts.inter(fontSize: 11, color: grey)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _bulkStartCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'e.g. 1',
                            hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange)),
                          ),
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To', style: GoogleFonts.inter(fontSize: 11, color: grey)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _bulkEndCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'e.g. 10',
                            hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange)),
                          ),
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(8),
              ),
              width: double.infinity,
              child: Text(
                _getInlinePreviewText(),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ] else ...[
            Text('Comma-separated seat numbers/labels', style: GoogleFonts.inter(fontSize: 11, color: grey)),
            const SizedBox(height: 4),
            TextField(
              controller: _singleSeatsCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. 1, 2, 5A, 10B',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange)),
              ),
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: context.palette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          widget.creationMode == 'section' ? 'Create section + seats' : 'Add seats directly',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
