import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/offline_db.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController _scannerController;
  late AnimationController _animationController;
  
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _isProcessingScan = false;
  int _failedScansCount = 0;
  String? _lastScannedValue;
  DateTime? _lastScanTime;

  // Modals/Cards display states
  bool _showSuccessCard = false;
  bool _isCheckInSuccess = true;
  String _successTimeText = '';
  String _successDurationText = '';
  String _successLibraryName = '';
  String _successSeatLabel = '';
  bool _isSuccessOffline = false;

  bool _showErrorCard = false;
  String _errorTitle = '';
  String _errorMsg = '';
  String? _errorWrongLibraryName;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    // 1. Viewfinder scanning line continuous sweep animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // 2. Connectivity check
    _checkInitialConnectivity();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool offline = results.contains(ConnectivityResult.none) || results.isEmpty;
      if (mounted) {
        setState(() {
          _isOffline = offline;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _scannerController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    final List<ConnectivityResult> result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = result.contains(ConnectivityResult.none) || result.isEmpty;
      });
    }
  }

  void _onCodeScanned(String rawValue) {
    if (_isProcessingScan) return;

    // Anti-spam filters (prevent double scanning within 3 seconds)
    final now = DateTime.now();
    if (_lastScannedValue == rawValue && _lastScanTime != null) {
      if (now.difference(_lastScanTime!).inSeconds < 3) {
        return;
      }
    }

    _lastScannedValue = rawValue;
    _lastScanTime = now;
    _isProcessingScan = true;

    // Vibrate/Beep simulation
    _processQRContent(rawValue);
  }

  Future<void> _processQRContent(String code) async {
    final parsed = _parseQR(code);
    if (parsed == null) {
      _handleFailure('Invalid Code', 'The scanned QR code is invalid. Make sure it is a valid SILENCE QR.');
      return;
    }

    final String libraryId = parsed['library_id'];
    final int qrVersion = parsed['qr_version'] ?? 1;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _handleFailure('Authentication Error', 'No active student session detected.');
      return;
    }

    if (_isOffline) {
      // ----------------------------------------
      // OFFLINE ATTENDANCE FLOW (SQLite Queue)
      // ----------------------------------------
      try {
        final db = await OfflineDatabase.instance.database;

        // Check offline capacity limit (500 items max)
        final List<Map<String, dynamic>> queueSize = await db.rawQuery('SELECT COUNT(*) as count FROM offline_scan_queue');
        final int count = queueSize.first['count'] as int? ?? 0;
        if (count >= 500) {
          _handleFailure('Storage Full', 'Offline queue has reached the 500-limit. Connect to internet to sync.');
          return;
        }

        // Check if checked in locally or based on last cached check-in
        final List<Map<String, dynamic>> localCheckins = await db.query(
          'offline_scan_queue',
          where: 'member_id = ? AND type = "checkin" AND synced = 0',
          limit: 1,
        );

        final bool isCurrentlyCheckedInOffline = localCheckins.isNotEmpty;

        final scanId = const Uuid().v4();
        final timestampStr = DateTime.now().toIso8601String();

        await db.insert('offline_scan_queue', {
          'id': scanId,
          'type': isCurrentlyCheckedInOffline ? 'checkout' : 'checkin',
          'library_id': libraryId,
          'member_id': user.id,
          'shift_id': 'offline_placeholder',
          'qr_version': qrVersion,
          'timestamp': timestampStr,
          'device_id': 'mobile',
          'synced': 0,
        });

        // Trigger success offline display
        _showSuccess(
          isCheckIn: !isCurrentlyCheckedInOffline,
          libraryName: 'SILENCE Study Zone (Offline)',
          seatLabel: 'Reserved Seat',
          timeStr: DateFormat('hh:mm a').format(DateTime.now()),
          durationStr: isCurrentlyCheckedInOffline ? 'Calculated on sync' : '',
          isOffline: true,
        );

      } catch (e) {
        _handleFailure('Offline Error', 'Failed to save offline scan: $e');
      }
      return;
    }

    // ----------------------------------------
    // ONLINE ATTENDANCE FLOW (Supabase RPC/Queries)
    // ----------------------------------------
    try {
      // 1. Fetch member active memberships
      final membershipRes = await supabase
          .from('memberships')
          .select('*, libraries(name, verified), shifts(name), seats(seat_label)')
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .inFilter('status', ['active', 'trial'])
          .maybeSingle();

      if (membershipRes == null) {
        // Wrong library scanned, or membership ended/expired
        // Fetch library name from QR code to display nice "Wrong Library" error card
        final wrongLib = await supabase
            .from('libraries')
            .select('name')
            .eq('id', libraryId)
            .maybeSingle();

        final name = wrongLib != null ? wrongLib['name'] : 'Another SILENCE Study Zone';
        _handleFailure('Not a member here', 'This QR code belongs to $name. Choose a correct library QR.', wrongLibName: name);
        return;
      }

      final membershipId = membershipRes['id'];
      final shift = membershipRes['shifts'] as Map<String, dynamic>? ?? {};
      final seat = membershipRes['seats'] as Map<String, dynamic>? ?? {};
      final libName = membershipRes['libraries']?['name'] ?? 'SILENCE Zone';
      final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'G-A-01') : 'Seat pending';

      // 2. Check if currently checked in (active session today)
      final activeSession = await supabase
          .from('attendance')
          .select()
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      if (activeSession == null) {
        // ------------------
        // PERFORM CHECK-IN
        // ------------------
        final nowStr = DateTime.now().toIso8601String();
        await supabase.from('attendance').insert({
          'membership_id': membershipId,
          'member_id': user.id,
          'library_id': libraryId,
          'shift_id': shift['id'] ?? membershipRes['shift_id'],
          'check_in_time': nowStr,
          'check_out_time': null,
          'session_type': 'normal',
          'qr_version': qrVersion,
          'device_id': 'mobile',
        });

        _showSuccess(
          isCheckIn: true,
          libraryName: libName,
          seatLabel: seatLabel,
          timeStr: DateFormat('hh:mm a').format(DateTime.now()),
          durationStr: '',
          isOffline: false,
        );

      } else {
        // ------------------
        // PERFORM CHECK-OUT
        // ------------------
        final checkInStr = activeSession['check_in_time'] as String;
        final checkInTime = DateTime.parse(checkInStr);
        final checkOutTime = DateTime.now();
        final durationMinutes = checkOutTime.difference(checkInTime).inMinutes;

        // Double scan check (checked in within 3 minutes - don't checkout, treat as confirmation)
        if (checkOutTime.difference(checkInTime).inMinutes < 3) {
          _showSuccess(
            isCheckIn: true,
            libraryName: libName,
            seatLabel: seatLabel,
            timeStr: DateFormat('hh:mm a').format(checkInTime),
            durationStr: 'Already Checked In',
            isOffline: false,
          );
          return;
        }

        await supabase.from('attendance').update({
          'check_out_time': checkOutTime.toIso8601String(),
          'duration_minutes': durationMinutes,
        }).eq('id', activeSession['id']);

        final hrs = durationMinutes ~/ 60;
        final mins = durationMinutes % 60;

        _showSuccess(
          isCheckIn: false,
          libraryName: libName,
          seatLabel: seatLabel,
          timeStr: DateFormat('hh:mm a').format(checkOutTime),
          durationStr: '${hrs}h ${mins}m',
          isOffline: false,
        );
      }

    } catch (e) {
      debugPrint('Error during Supabase scan verification: $e');
      _handleFailure('Scan Failed', 'An error occurred during verification. Try again or check internet.');
    }
  }

  Map<String, dynamic>? _parseQR(String code) {
    try {
      if (code.startsWith('{') && code.endsWith('}')) {
        // JSON structure
        return null; // parse JSON as needed
      }
      
      // Check for UUID format directly (if QR has just library UUID)
      if (RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(code)) {
        return {
          'library_id': code,
          'qr_version': 1,
        };
      }

      // Check for SILENCE_QR prefix
      if (code.contains(':')) {
        final parts = code.split(':');
        if (parts.length >= 2) {
          return {
            'library_id': parts[1],
            'qr_version': 1,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  void _showSuccess({
    required bool isCheckIn,
    required String libraryName,
    required String seatLabel,
    required String timeStr,
    required String durationStr,
    required bool isOffline,
  }) {
    if (!mounted) return;
    setState(() {
      _showSuccessCard = true;
      _isCheckInSuccess = isCheckIn;
      _successLibraryName = libraryName;
      _successSeatLabel = seatLabel;
      _successTimeText = timeStr;
      _successDurationText = durationStr;
      _isSuccessOffline = isOffline;
      _failedScansCount = 0; // Reset fails on success!
    });

    // Auto dismiss after 3 seconds when online
    if (!isOffline) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showSuccessCard) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _handleFailure(String title, String msg, {String? wrongLibName}) {
    if (!mounted) return;
    setState(() {
      _failedScansCount++;
      _showErrorCard = true;
      _errorTitle = title;
      _errorMsg = msg;
      _errorWrongLibraryName = wrongLibName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Premium Dark Slate Scanner background
      body: Stack(
        children: [
          // 1. Mobile QR Scanner
          Positioned.fill(
            child: _showSuccessCard || _showErrorCard
                ? Container(color: const Color(0xFF0D1B2A)) // Hide feed during active cards
                : MobileScanner(
                    controller: _scannerController,
                    onDetect: (BarcodeCapture capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final String? code = barcode.rawValue;
                        if (code != null) {
                          _onCodeScanned(code);
                        }
                      }
                    },
                  ),
          ),

          // 2. Viewfinder bracket overlay & Sweeping orange scan line
          if (!_showSuccessCard && !_showErrorCard)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ViewfinderPainter(scanLineOffsetPct: _animationController.value),
                  );
                },
              ),
            ),

          // 3. UI Indicators
          Positioned(
            top: 24,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          Positioned(
            top: 36,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Point at SILENCE QR Code',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),

          // Yellow Offline banner
          if (_isOffline)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7), // Yellow banner
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You are offline. Scans will be saved offline and synced later.',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                      ),
                    )
                  ],
                ),
              ),
            ),

          // 4. Check-in/out Success Cards (Slide up overlays)
          if (_showSuccessCard)
            _buildSuccessCardOverlay(),

          // 5. Error & Failure Cards
          if (_showErrorCard)
            _buildErrorCardOverlay(),
        ],
      ),
    );
  }

  Widget _buildSuccessCardOverlay() {
    final isCheckIn = _isCheckInSuccess;
    final color = isCheckIn ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.check, size: 48, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                isCheckIn ? 'Checked In!' : 'Checked Out!',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                _successTimeText,
                style: GoogleFonts.inter(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
              Text(
                _successLibraryName,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
              ),
              Text(
                'Seat: $_successSeatLabel',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
              
              if (_successDurationText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Session Duration: $_successDurationText',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                ),
              ],
              
              if (_isSuccessOffline) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '✓ Saved offline in queue',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCardOverlay() {
    final bool blockRetries = _failedScansCount >= 2;

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 48, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              Text(
                _errorTitle,
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 24),
              
              if (blockRetries) ...[
                // Manual Contact Options if fails >= 2
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contact details: Jaipur, Rajasthan')),
                      );
                    },
                    icon: const Icon(Icons.phone),
                    label: const Text('Contact Admin for Manual Check-in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Submit query report
                      try {
                        final supabase = Supabase.instance.client;
                        final user = supabase.auth.currentUser;
                        if (user != null) {
                          await supabase.from('queries').insert({
                            'member_id': user.id,
                            'library_id': widget.libraryIdOrFallback(),
                            'message': 'Failed QR Scans check-in reporting.',
                            'status': 'open',
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Query report submitted to Admin! ✓')),
                            );
                          }
                        }
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.report_problem),
                    label: const Text('Report via Queries'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showErrorCard = false;
                            _isProcessingScan = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFE65C00)),
                          foregroundColor: const Color(0xFFE65C00),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ),
                    if (_errorWrongLibraryName != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // Open explore/join
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Join Library'),
                        ),
                      )
                    ]
                  ],
                ),
              ],
              
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close Scanner', style: GoogleFonts.inter(color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }
}

extension QRScannerFallback on QRScannerScreen {
  String libraryIdOrFallback() {
    // Return standard default library ID if available, else standard fallback Jaipur library
    return '00000000-0000-0000-0000-000000000000';
  }
}

class ViewfinderPainter extends CustomPainter {
  final double scanLineOffsetPct; // 0.0 to 1.0
  ViewfinderPainter({required this.scanLineOffsetPct});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    
    const double rectSize = 260.0;
    final double left = (size.width - rectSize) / 2;
    final double top = (size.height - rectSize) / 2;
    final double right = left + rectSize;
    final double bottom = top + rectSize;
    const double bracketLen = 24.0;

    // Top-left
    canvas.drawLine(Offset(left, top), Offset(left + bracketLen, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + bracketLen), paint);
    
    // Top-right
    canvas.drawLine(Offset(right, top), Offset(right - bracketLen, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + bracketLen), paint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + bracketLen, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - bracketLen), paint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom), Offset(right - bracketLen, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - bracketLen), paint);

    // Scan line
    final scanLinePaint = Paint()
      ..color = const Color(0xFFE65C00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final double lineY = top + (rectSize * scanLineOffsetPct);
    canvas.drawLine(Offset(left + 8, lineY), Offset(right - 8, lineY), scanLinePaint);
  }

  @override
  bool shouldRepaint(covariant ViewfinderPainter oldDelegate) =>
      oldDelegate.scanLineOffsetPct != scanLineOffsetPct;
}
