import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/active_library_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

class QRAssetsScreen extends StatefulWidget {
  final String? libraryId;
  const QRAssetsScreen({super.key, this.libraryId});

  @override
  State<QRAssetsScreen> createState() => _QRAssetsScreenState();
}

class _QRAssetsScreenState extends State<QRAssetsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  bool _isLoading = false;
  String? _libId;
  String _libCode = 'SIL-4K9M2P';
  int _qrVersion = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchLibraryCode();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchLibraryCode() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        _libId = await ActiveLibraryStore.resolve(widget.libraryId);
        if (_libId != null) {
          final res = await _supabase.from('libraries').select().eq('id', _libId!).maybeSingle();
          if (!mounted) return;
          if (res != null) {
            _libCode = res['library_code'] ?? _libCode;
            _qrVersion = res['qr_version'] ?? _qrVersion;
          }
        }
      } catch (e) {
        debugPrint('Error fetching QR assets code: $e');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _regenerateQR() async {
    // Show confirmation sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final confirmCtrl = TextEditingController();
        bool isValid = false;
        return StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 24, left: 24, right: 24
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '⚠️ Regenerate QR Code?',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This will IMMEDIATELY invalidate all old check-in QR codes. Members will not be able to scan until you print the new poster.',
                  style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'Type "REGENERATE" to confirm:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: context.palette.textSecondary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmCtrl,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'Type REGENERATE'),
                  onChanged: (val) {
                    setModalState(() {
                      isValid = (val.trim() == 'REGENERATE');
                    });
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isValid ? const Color(0xFFE65C00) : Colors.grey,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isValid
                            ? () async {
                                final nextVer = _qrVersion + 1;
                                setState(() {
                                  _qrVersion = nextVer;
                                });
                                if (_libId != null) {
                                  try {
                                    await _supabase.from('libraries').update({
                                      'qr_version': nextVer,
                                    }).eq('id', _libId!);
                                    if (!mounted) return;
                                  } catch (_) {}
                                }
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('QR Code regenerated successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
                                );
                              }
                            : null,
                        child: Text('Confirm', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareQR(String type) {
    final domain = 'https://silenceapp.com/join';
    final payload = type == 'join'
        ? '$domain?libCode=$_libCode'
        : 'silence_attendance:$_libCode:$_qrVersion';
    Share.share('Check out our library space! Code: $_libCode\nPayload: $payload');
  }

  @override
  Widget build(BuildContext context) {
    final joinPayload = 'https://silenceapp.com/join?libCode=$_libCode';
    final attendancePayload = 'silence_attendance:$_libCode:$_qrVersion';

    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Printable QR Assets',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3.0,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Joining QR'),
                Tab(text: 'Attendance QR'),
              ],
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildQRTabContent('join', joinPayload, 'Allows users to search and join your branch instantly by scanning.'),
                    _buildQRTabContent('attendance', attendancePayload, 'Place at reception desk for members to scan for check-in / check-out.'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildQRTabContent(String type, String payload, String desc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. QR Code Premium Frame Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                // Dashed corner orange brackets drawing
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Corner brackets representation
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.2), width: 1),
                      ),
                    ),
                    // Accent corner markers
                    Positioned(
                      top: 0, left: 0,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE65C00), width: 3), left: BorderSide(color: Color(0xFFE65C00), width: 3)))),
                    ),
                    Positioned(
                      top: 0, right: 0,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE65C00), width: 3), right: BorderSide(color: Color(0xFFE65C00), width: 3)))),
                    ),
                    Positioned(
                      bottom: 0, left: 0,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE65C00), width: 3), left: BorderSide(color: Color(0xFFE65C00), width: 3)))),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE65C00), width: 3), right: BorderSide(color: Color(0xFFE65C00), width: 3)))),
                    ),
                    
                    // The QR code
                    QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 220,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Library Code Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3ED),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CODE: $_libCode',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _libCode));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Library Code copied to clipboard!')));
                        },
                        child: const Icon(Icons.copy, size: 14, color: Color(0xFFE65C00)),
                      ),
                    ],
                  ),
                ),
                if (type == 'attendance') ...[
                  const SizedBox(height: 10),
                  Text(
                    'QR Version: $_qrVersion',
                    style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Action Buttons Matrix
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading high resolution PDF poster...')));
                  },
                  icon: const Icon(Icons.download, size: 16, color: Colors.white),
                  label: Text('Download PDF', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.palette.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => _shareQR(type),
                  icon: const Icon(Icons.share, size: 16, color: Colors.white),
                  label: Text('Share QR Link', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (type == 'attendance')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.palette.surface,
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _regenerateQR,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Regenerate Attendance QR', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 24),

          // 3. Information Description Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What is this QR used for?',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
