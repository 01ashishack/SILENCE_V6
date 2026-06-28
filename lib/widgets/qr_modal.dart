import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_palette.dart';

class QRModal extends StatefulWidget {
  final String libraryId;
  final String libraryCode;
  final String libraryName;
  final int initialQrVersion;
  final String qrType; // 'join' or 'attendance'
  final Function(int newVersion) onQrVersionChanged;

  const QRModal({
    super.key,
    required this.libraryId,
    required this.libraryCode,
    required this.libraryName,
    required this.initialQrVersion,
    required this.qrType,
    required this.onQrVersionChanged,
  });

  @override
  State<QRModal> createState() => _QRModalState();
}

class _QRModalState extends State<QRModal> {
  late int _qrVersion;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _qrVersion = widget.initialQrVersion;
  }

  String get _joiningQrData {
    return jsonEncode({
      'type': 'join',
      'library_id': widget.libraryId,
    });
  }

  String get _attendanceQrData {
    return 'attendance:${widget.libraryId}:$_qrVersion';
  }

  String get _currentQrData =>
      widget.qrType == 'join' ? _joiningQrData : _attendanceQrData;

  String get _currentTitle =>
      widget.qrType == 'join' ? 'Joining QR' : 'Attendance QR';

  Future<void> _copyCodeToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.libraryCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Library Code copied to clipboard!',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<pw.Document> _generatePdf(String qrData, String title, String description) async {
    final pdf = pw.Document();

    // Load the SILENCE horizontal logo from assets
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/images/horizontal app logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      // Logo loading failed — fallback to text
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromInt(0xFFE65C00), width: 3),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
            ),
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Header Row (Logo on Left, Badges on Right)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.Image(logoImage, width: 140, height: 42, fit: pw.BoxFit.contain)
                        else
                          pw.Text(
                            'SILENCE',
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFFE65C00),
                              letterSpacing: 2.0,
                            ),
                          ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Library Management System',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: PdfColor.fromInt(0xFF6B7280),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Row(
                      children: [
                        _buildStoreBadge('GET IT ON', 'Google Play'),
                        pw.SizedBox(width: 8),
                        _buildStoreBadge('Download on the', 'App Store'),
                      ],
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 1, color: PdfColor.fromInt(0xFFE5E7EB)),
                pw.SizedBox(height: 16),

                // Main Greeting/Title
                pw.Text(
                  widget.libraryName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF111827),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'WELCOME TO OUR SMART LIBRARY',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromInt(0xFFE65C00),
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),

                pw.SizedBox(height: 24),

                // QR Code Card
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFAF7F2),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                    border: pw.Border.all(color: PdfColor.fromInt(0xFFFFF3ED), width: 1),
                  ),
                  padding: const pw.EdgeInsets.all(24),
                  child: pw.Column(
                    children: [
                      // Styled QR Container
                      pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                          border: pw.Border.all(color: PdfColor.fromInt(0xFFE65C00), width: 2),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qrData,
                          width: 180,
                          height: 180,
                          color: PdfColor.fromInt(0xFF111827),
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text(
                        title.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFFE65C00),
                          letterSpacing: 1.0,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        description,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColor.fromInt(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 24),

                // Instructions (1, 2, 3 Steps)
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'HOW TO CONNECT:',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF111827),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                pw.SizedBox(height: 12),

                // Step 1
                _buildInstructionStep(
                  '1',
                  'Download the Silence App',
                  'Search for "SILENCE" on Google Play Store or Apple App Store.',
                ),
                pw.SizedBox(height: 10),

                // Step 2
                _buildInstructionStep(
                  '2',
                  'Scan the QR Code',
                  widget.qrType == 'join'
                      ? 'Open the scanner in the app and scan this QR code to register and apply.'
                      : 'Scan this QR code using the in-app scanner to check in/out and mark attendance.',
                ),
                pw.SizedBox(height: 10),

                // Step 3
                _buildInstructionStep(
                  '3',
                  'Instant Verification',
                  widget.qrType == 'join'
                      ? 'Your profile is instantly updated, and a joining request is sent to the administrator.'
                      : 'Your shift timer starts ticking, tracking your library hours securely.',
                ),

                pw.SizedBox(height: 24),

                // Monospace Library Code Box
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFFF3ED),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    border: pw.Border.all(color: PdfColor.fromInt(0xFFFFD1B3), width: 1.5, style: pw.BorderStyle.dashed),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'MANUAL ENTRY CODE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColor.fromInt(0xFFE65C00),
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        widget.libraryCode,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFFE65C00),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                pw.Spacer(),

                // Bottom Footer Region
                pw.Divider(thickness: 1, color: PdfColor.fromInt(0xFFE5E7EB)),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'www.silenceapp.in',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFE65C00),
                      ),
                    ),
                    pw.Text(
                      'ashish.premierbro@gmail.com',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColor.fromInt(0xFF4B5563),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Gen: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColor.fromInt(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf;
  }

  /// Builds a text-based app store pill badge for the PDF.
  static pw.Widget _buildStoreBadge(String topLine, String bottomLine) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF111827),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            bottomLine == 'Google Play' ? '▶ ' : ' ',
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColor.fromInt(0xFFFFFFFF),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                topLine,
                style: pw.TextStyle(
                  fontSize: 5,
                  color: PdfColor.fromInt(0xFF9CA3AF),
                ),
              ),
              pw.Text(
                bottomLine,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a beautiful numbered instruction item for the A4 PDF setup.
  static pw.Widget _buildInstructionStep(String stepNumber, String title, String description) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 18,
          height: 18,
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE65C00),
            shape: pw.BoxShape.circle,
          ),
          child: pw.Center(
            child: pw.Text(
              stepNumber,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF111827),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                description,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColor.fromInt(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadPdf(String qrData, String type) async {
    final title = type == 'join' ? 'Joining QR Code' : 'Attendance QR Code';
    final desc = type == 'join'
        ? 'Scan this QR to join ${widget.libraryName}'
        : 'Scan this QR to mark your attendance';

    try {
      final doc = await _generatePdf(qrData, title, desc);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '${widget.libraryName.replaceAll(' ', '_')}_${type}_QR.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: $e')),
      );
    }
  }

  Future<void> _sharePdf(String qrData, String type) async {
    final title = type == 'join' ? 'Joining QR Code' : 'Attendance QR Code';
    final desc = type == 'join'
        ? 'Scan this QR to join ${widget.libraryName}'
        : 'Scan this QR to mark your attendance';

    try {
      final doc = await _generatePdf(qrData, title, desc);
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.libraryName.replaceAll(' ', '_')}_${type}_QR.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share PDF: $e')),
      );
    }
  }

  void _showRegenerateBottomSheet() {
    final textController = TextEditingController();
    bool isValid = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        'Regenerate QR?',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ Old QR will stop working immediately after regeneration. Members will need to scan the new QR code.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF374151),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Type "REGENERATE" below to confirm:',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    onChanged: (val) {
                      setModalState(() {
                        isValid = val.trim() == 'REGENERATE';
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'REGENERATE',
                      hintStyle: GoogleFonts.inter(color: Colors.grey[400]),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: textController.text.isNotEmpty && !isValid ? Colors.red : const Color(0xFFE5E7EB),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isValid ? const Color(0xFF22C55E) : Colors.red,
                          width: 2,
                        ),
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isValid
                              ? () {
                                  Navigator.pop(context);
                                  _performRegeneration();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            disabledBackgroundColor: Colors.grey[200],
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Confirm',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isValid ? Colors.white : Colors.grey[400],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performRegeneration() async {
    setState(() {
      _isRegenerating = true;
    });

    final newVersion = _qrVersion + 1;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('libraries').update({
        'qr_version': newVersion,
      }).eq('id', widget.libraryId);

      _qrVersion = newVersion;
      widget.onQrVersionChanged(_qrVersion);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'QR version incremented to v$_qrVersion successfully!',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update QR version in database: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRegenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String footerNote = widget.qrType == 'attendance'
        ? '🔒 Attendance QR:\nPrint, laminate, fix on wall. Works forever.'
        : '🔒 Joining QR:\nShare with new members to let them register & apply.';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 10,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Title Bar with close button
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 20, bottom: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _currentTitle,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65C00),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ],
              ),

              // Content Body
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // QR Frame
                    Center(
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: CustomPaint(
                          painter: CornerBracketsPainter(),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Container(
                              color: Colors.white,
                              child: _isRegenerating
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFE65C00),
                                      ),
                                    )
                                  : QrImageView(
                                      data: _currentQrData,
                                      version: QrVersions.auto,
                                      size: 196,
                                      gapless: false,
                                      errorStateBuilder: (cxt, err) {
                                        return const Center(child: Text('QR generation failed'));
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Library Code Section
                    Text(
                      'Library Code',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: _copyCodeToClipboard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3ED),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE65C00).withAlpha(38)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.libraryCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE65C00),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.copy, size: 14, color: Color(0xFFE65C00)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Three action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _downloadPdf(_currentQrData, widget.qrType),
                            icon: const Icon(Icons.file_download, size: 14, color: Color(0xFF6B7280)),
                            label: Text(
                              'PDF',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _sharePdf(_currentQrData, widget.qrType),
                            icon: const Icon(Icons.share, size: 14, color: Color(0xFFE65C00)),
                            label: Text(
                              'Share',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFFD1B3)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showRegenerateBottomSheet,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.refresh, size: 16, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Footer Note
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF5EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        footerNote,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF6B7280), height: 1.4, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CornerBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE65C00)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double lineLength = 22.0;

    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(lineLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, lineLength), paint);

    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - lineLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, lineLength), paint);

    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(lineLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - lineLength), paint);

    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - lineLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - lineLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
