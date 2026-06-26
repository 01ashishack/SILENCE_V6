import 'dart:async';
import '../../theme/app_palette.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/offline_db.dart';
import '../library_public_profile_screen.dart';
import '../../utils/time_utils.dart';

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

  int _cooldownScansCount = 0;

  // Modals/Cards display states
  bool _showSuccessCard = false;
  bool _isCheckInSuccess = true;
  String _successTimeText = '';
  String _successDurationText = '';
  String _successLibraryName = '';
  String _successSeatLabel = '';
  bool _isSuccessOffline = false;

  String _successCheckInTimeText = '';
  String _successCheckOutTimeText = '';
  String _successShiftEndTimeText = '';
  String _successOvertimeText = '';
  String _successShiftName = '';

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
    debugPrint('[QR Scan Audit] QR scan success. Code: $code');
    final parsed = _parseQR(code);
    if (parsed == null) {
      debugPrint('[QR Scan] Failed parsing code: $code');
      _handleFailure('Invalid Code', 'The scanned QR code is invalid. Make sure it is a valid SILENCE QR.');
      return;
    }

    final String? parsedLibId = parsed['library_id'];
    final String? libraryCode = parsed['library_code'];
    final int qrVersion = parsed['qr_version'] ?? 1;
    final bool isJoining = parsed['is_joining'] ?? false;

    debugPrint('[QR Scan] Raw QR code: $code');
    debugPrint('[QR Scan] Parsed properties: $parsed');

    // Check connectivity before any Supabase queries
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final isOffline = connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty;
      if (isOffline) {
        setState(() {
          _isOffline = true;
        });
      }
    } catch (e) {
      debugPrint('[QR Scan] Error checking connectivity: $e');
    }

    String libraryId = parsedLibId ?? '';
    final supabase = Supabase.instance.client;

    // Online Resolution for short code (e.g. "LIB-ABC123")
    if (libraryId.isEmpty && libraryCode != null && libraryCode.isNotEmpty) {
      if (_isOffline) {
        // Offline mode: store short code directly in library_id, will be resolved during offline sync.
        libraryId = libraryCode;
        debugPrint('[QR Scan] Offline mode. Queuing short code: $libraryCode');
      } else {
        try {
          debugPrint('[CHECKOUT STEP] Starting: library lookup');
          debugPrint('[QR Scan] Querying Supabase for library_code: $libraryCode');
          final resolvedLib = await supabase
              .from('libraries')
              .select('id')
              .eq('library_code', libraryCode)
              .maybeSingle();
          debugPrint('[CHECKOUT STEP] Success: library lookup');
          debugPrint('[QR Scan] Supabase library resolution response: $resolvedLib');
          if (resolvedLib != null) {
            libraryId = resolvedLib['id'];
          } else {
            _handleFailure('Not a member here', 'No active membership found for this library.');
            return;
          }
        } catch (e, stackTrace) {
          debugPrint('[CHECKOUT ERROR] ${e.toString()}');
          debugPrint('[CHECKOUT STACK] $stackTrace');
          debugPrint('[QR Scan] Exception resolving library code: $e');
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('socket') || 
              errorStr.contains('network') || 
              errorStr.contains('timeout') || 
              errorStr.contains('connection failed') || 
              errorStr.contains('failed host lookup')) {
            _handleFailure('Network Error', 'Network error. Please try again.');
          } else {
            _handleFailure('Scan Failed', 'An error occurred during verification. Try again or check internet: ${e.toString()}');
          }
          return;
        }
      }
    }

    debugPrint('[QR Scan] Target Library ID: $libraryId');

    if (isJoining) {
      // Direct Join Flow Navigation -> Changed to show Library Public Profile first
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LibraryPublicProfileScreen(
            libraryId: libraryId,
            isAdmin: false,
            showProceedButton: true,
          ),
        ),
      );
      return;
    }

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
        if (!mounted) return;

        // Trigger success offline display
        _showSuccess(
          isCheckIn: !isCurrentlyCheckedInOffline,
          libraryName: 'SILENCE Study Zone (Offline)',
          seatLabel: 'Reserved Seat',
          timeStr: DateFormat('hh:mm a').format(DateTime.now()),
          durationStr: 'Saved offline. Will sync when online.',
          isOffline: true,
        );

      } catch (e) {
        debugPrint('[QR Scan] Exception in offline flow: $e');
        _handleFailure('Offline Error', 'Failed to save offline scan: $e');
      }
      return;
    }

    // ----------------------------------------
    // ONLINE ATTENDANCE FLOW (Supabase RPC/Queries)
    // ----------------------------------------
    try {
      // 1. Check if library is closed today (range-aware holiday).
      //    Canonical table: scheduled_closures(start_date..end_date inclusive).
      try {
        debugPrint('[CHECKOUT STEP] Starting: closure lookup');
        final todayStr = istTodayKey();
        debugPrint('[QR Scan] Checking library closure for date: $todayStr');
        final closureRows = await supabase
            .from('scheduled_closures')
            .select('reason, start_date, end_date')
            .eq('library_id', libraryId)
            .lte('start_date', todayStr)
            .gte('end_date', todayStr)
            .limit(1);
        debugPrint('[CHECKOUT STEP] Success: closure lookup');
        debugPrint('[QR Scan] Closure check result: $closureRows');
        if (closureRows.isNotEmpty) {
          final reason = (closureRows.first['reason'] ?? '').toString();
          _handleFailure(
            'Library Closed',
            reason.isEmpty
                ? 'This library is closed today (holiday).'
                : 'Closed today: $reason',
          );
          return;
        }
      } catch (e, stackTrace) {
        debugPrint('[CHECKOUT ERROR] ${e.toString()}');
        debugPrint('[CHECKOUT STACK] $stackTrace');
        debugPrint('[QR Scan] Ignored error while checking library closures: $e');
      }

      // 2. Fetch member active memberships
      debugPrint('[QR Scan] Checking membership for member: ${user.id} and library: $libraryId');
      debugPrint('[CHECKOUT STEP] Starting: membership lookup');
      debugPrint('[CHECKOUT STEP] Starting: shift lookup');
      // Pick the live membership only. Using .maybeSingle() over ALL of the
      // member's rows for this library crashes with 406 ("2 rows") when an old
      // exited/expired membership also exists — so scope to active/trial and
      // take the latest.
      final membershipRows = await supabase
          .from('memberships')
          .select('*, libraries(name, verified, qr_version), shifts(id, name, start_time, end_time), seats(seat_label)')
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .inFilter('status', ['active', 'trial'])
          .order('end_date', ascending: false)
          .limit(1);
      final membershipRes = (membershipRows as List).isNotEmpty
          ? Map<String, dynamic>.from(membershipRows.first as Map)
          : null;
      debugPrint('[CHECKOUT STEP] Success: membership lookup');
      debugPrint('[CHECKOUT STEP] Success: shift lookup');

      debugPrint('[QR Scan] Membership query result: $membershipRes');

      if (membershipRes == null) {
        _handleFailure('Not a member here', 'No active membership found for this library.');
        return;
      }

      final String membershipStatus = membershipRes['status'] ?? '';
      if (membershipStatus != 'active' && membershipStatus != 'trial') {
        _handleFailure('Not a member here', 'No active membership found for this library.');
        return;
      }

      final int dbQrVersion = membershipRes['libraries']?['qr_version'] ?? 1;
      // QR regeneration grace: accept the current version AND the immediately
      // previous one, so regenerating a QR doesn't instantly break every
      // already-printed/laminated copy (the "print once, use forever" promise).
      // Anything older than one version back is rejected as truly outdated.
      if (qrVersion != dbQrVersion && qrVersion != dbQrVersion - 1) {
        _handleFailure(
          'Outdated QR Code',
          'This QR code is no longer valid — the admin has regenerated it. Please scan the latest printed QR code.',
        );
        return;
      }

      final membershipId = membershipRes['id'];
      final shift = membershipRes['shifts'] as Map<String, dynamic>? ?? {};
      final seat = membershipRes['seats'] as Map<String, dynamic>? ?? {};
      final libName = membershipRes['libraries']?['name'] ?? 'SILENCE Zone';
      final seatLabel = seat.isNotEmpty ? (seat['seat_label'] ?? 'G-A-01') : 'Seat pending';

      // 2.5. Defensive Seat Occupancy Verification
      final seatId = seat['id'] ?? membershipRes['seat_id'];
      if (seatId != null) {
        try {
          debugPrint('[CHECKOUT STEP] Starting: seat lookup');
          debugPrint('[QR Scan] Checking seat occupancy status for seat: $seatId');
          final seatCheck = await supabase
              .from('seats')
              .select('status, occupied_by_member_id')
              .eq('id', seatId)
              .maybeSingle();
          debugPrint('[CHECKOUT STEP] Success: seat lookup');
          debugPrint('[QR Scan] Seat check result: $seatCheck');

          if (seatCheck != null) {
            final String? seatStatus = seatCheck['status'] as String?;
            final String? occupiedBy = seatCheck['occupied_by_member_id'] as String?;
            if ((seatStatus == 'occupied' && occupiedBy != user.id) || seatStatus == 'maintenance') {
              _handleFailure(
                'Seat Unavailable',
                'Seat is not available for check‑in.',
              );
              return;
            }
          }
        } catch (e, stackTrace) {
          debugPrint('[CHECKOUT ERROR] ${e.toString()}');
          debugPrint('[CHECKOUT STACK] $stackTrace');
          debugPrint('[QR Scan] Error verifying seat status: $e');
        }
      }

      // 3. Check if currently checked in (active session today)
      debugPrint('[QR Scan] Fetching active session for member: ${user.id}');
      debugPrint('[CHECKOUT STEP] Starting: attendance lookup');
      final activeSession = await supabase
          .from('attendance')
          .select()
          .eq('member_id', user.id)
          .eq('library_id', libraryId)
          .isFilter('check_out_time', null)
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();
      debugPrint('[CHECKOUT STEP] Success: attendance lookup');
      debugPrint('[QR Scan] Active session result: $activeSession');

      if (activeSession == null) {
        // Reset cooldown count on new check-in flow
        _cooldownScansCount = 0;

        // Multiple sessions per day are allowed: after checking out, a member
        // may check in again. A second open session is prevented by the
        // activeSession != null branch (checkout), so no duplicate-open risk.

        // ------------------
        // SHIFT-WINDOW GATE (out-of-shift check-in needs admin approval)
        // ------------------
        // Allowed without approval = from 15 min before shift start until shift
        // end. Outside that, the member needs the admin to approve this check-in,
        // and the time then counts as OVERTIME.
        final nowUtc = DateTime.now().toUtc();
        final nowIst = toIST(nowUtc);
        final shiftStartTimeStr = shift['start_time'] as String? ?? '06:00:00';
        final shiftEndTimeStr = shift['end_time'] as String? ?? '14:00:00';
        final shiftStartIst = _shiftDateTimeIst(shiftStartTimeStr, nowIst);
        final shiftEndIst = _shiftDateTimeIst(shiftEndTimeStr, nowIst);
        final windowOpenIst = shiftStartIst.subtract(const Duration(minutes: 15));
        final bool withinWindow =
            !nowIst.isBefore(windowOpenIst) && !nowIst.isAfter(shiftEndIst);

        bool isOvertimeCheckin = false;
        String? approvalToConsume;

        if (!withinWindow) {
          // Is there an APPROVED, unexpired approval to ride in on?
          final approved = await supabase
              .from('checkin_approvals')
              .select('id, approval_expires_at')
              .eq('member_id', user.id)
              .eq('library_id', libraryId)
              .eq('status', 'approved')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          final String? expiresStr = approved?['approval_expires_at'] as String?;
          final bool approvedValid = approved != null &&
              (expiresStr == null ||
                  parseDBTimeToUtc(expiresStr).isAfter(nowUtc));

          if (approvedValid) {
            // Ride the approval in — counts as overtime; mark it used after.
            isOvertimeCheckin = true;
            approvalToConsume = approved['id']?.toString();
          } else {
            // No valid approval → file/await one and STOP (no check-in yet).
            await _requestOutOfShiftApproval(
              membershipId: membershipId,
              libraryId: libraryId,
              shiftId: shift['id'] ?? membershipRes['shift_id'],
              shiftName: shift['name']?.toString() ?? 'your',
              attemptedIst: nowIst,
              beforeStart: nowIst.isBefore(windowOpenIst),
            );
            return;
          }
        }

        // ------------------
        // PERFORM CHECK-IN
        // ------------------
        final nowStr = nowUtc.toIso8601String();
        debugPrint('[QR Scan] Performing check-in with membershipId: $membershipId (overtime=$isOvertimeCheckin)');
        List<dynamic> insertResponse;
        try {
          insertResponse = await supabase.from('attendance').insert({
            'membership_id': membershipId,
            'member_id': user.id,
            'library_id': libraryId,
            'shift_id': shift['id'] ?? membershipRes['shift_id'],
            'check_in_time': nowStr,
            'check_out_time': null,
            'session_type': 'normal',
            'is_overtime': isOvertimeCheckin,
            'qr_version': qrVersion,
            'device_id': 'mobile',
          }).select();
        } on PostgrestException catch (e) {
          // C4: the partial-unique index (uq_attendance_open_session) rejected a
          // second concurrent open session — the member is already checked in
          // (another device / a double-tap won the race). Treat it honestly.
          if (e.code == '23505') {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You are already checked in for this library.'),
                backgroundColor: Color(0xFFF59E0B),
              ),
            );
            setState(() => _isProcessingScan = false);
            return;
          }
          rethrow;
        }
        debugPrint('[QR Scan] Check-in insert response: $insertResponse');

        // An approved out-of-shift check-in: burn the approval so it can't be
        // reused (best-effort, non-blocking).
        if (approvalToConsume != null) {
          try {
            await supabase.rpc('consume_checkin_approval', params: {'p_id': approvalToConsume});
          } catch (e) {
            debugPrint('[QR Scan] consume_checkin_approval failed: $e');
          }
        }
        if (!mounted) return;

        _showSuccess(
          isCheckIn: true,
          libraryName: libName,
          seatLabel: seatLabel,
          timeStr: DateFormat('hh:mm a').format(nowIst),
          durationStr: isOvertimeCheckin
              ? 'Outside shift hours — this session is tagged as overtime.'
              : '',
          isOffline: false,
          checkInTimeStr: DateFormat('hh:mm a').format(nowIst),
          shiftName: shift['name'] ?? 'N/A',
        );

        // Notify the library owner that a member checked in (non-blocking).
        _notifyOwnerAttendance(libraryId, true);

      } else {
        // ------------------
        // CHECK-OUT COOLDOWN & CONFIRMATION
        // ------------------
        final checkInStr = activeSession['check_in_time'] as String;
        final checkInTimeUtc = parseDBTimeToUtc(checkInStr);
        final nowUtc = DateTime.now().toUtc();
        final durationMinutes = nowUtc.difference(checkInTimeUtc).inMinutes;

        // Minimum-session-length cooldown before checkout.
        // TEMPORARILY DISABLED: set _minCheckoutMinutes back to 10 to re-enable.
        const int minCheckoutMinutes = 0;
        if (durationMinutes < minCheckoutMinutes) {
          _cooldownScansCount++;
          final timeRemaining = minCheckoutMinutes - durationMinutes;
          if (_cooldownScansCount == 1) {
            _handleFailure(
              'Checkout Restricted',
              'Already checked in. Checkout not allowed until $timeRemaining minutes have passed.',
            );
          } else {
            _handleFailure(
              'Checkout Restricted',
              'Checkout is restricted for another $timeRemaining minutes. Please wait.',
            );
          }
          return;
        }

        // Reset cooldown count since cooldown has expired
        _cooldownScansCount = 0;

        // Past 10 minutes: show check-out confirmation dialog
        final shiftEndTimeStr = shift['end_time'] as String? ?? '18:00:00';
        if (!mounted) return;
        await _showCheckoutConfirmDialog(
          activeSession: activeSession,
          libName: libName,
          seatLabel: seatLabel,
          shiftName: shift['name'] ?? 'N/A',
          shiftEndTimeStr: shiftEndTimeStr,
          checkInTime: checkInTimeUtc,
        );
      }

    } catch (e, stackTrace) {
      debugPrint('[CHECKOUT ERROR] ${e.toString()}');
      debugPrint('[CHECKOUT STACK] $stackTrace');
      debugPrint('[QR Scan] Exception in online flow: $e');
      debugPrint('[QR Scan] StackTrace: $stackTrace');
      
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socket') || 
          errorStr.contains('network') || 
          errorStr.contains('timeout') || 
          errorStr.contains('connection failed') || 
          errorStr.contains('failed host lookup')) {
        _handleFailure('Network Error', 'Network error. Please try again.');
      } else {
        _handleFailure('Scan Failed', 'An error occurred during verification. Try again or check internet: ${e.toString()}');
      }
    }
  }

  Map<String, dynamic>? _parseQR(String code) {
    try {
      final trimmed = code.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final Map<String, dynamic> parsedJson = jsonDecode(trimmed);
        if (parsedJson['type'] == 'join') {
          return {
            'library_id': parsedJson['library_id'],
            'qr_version': 1,
            'is_joining': true,
          };
        }
        return null;
      }
      
      // Check for UUID format directly (if QR has just library UUID)
      if (RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(trimmed)) {
        return {
          'library_id': trimmed,
          'qr_version': 1,
        };
      }

      // Check for SILENCE_QR prefix or attendance:library_id:qr_version
      if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          int version = 1;
          if (parts.length >= 3) {
            version = int.tryParse(parts[2]) ?? 1;
          }
          final String potentialId = parts[1].trim();
          if (RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(potentialId)) {
            return {
              'library_id': potentialId,
              'qr_version': version,
            };
          } else if (potentialId.toUpperCase().startsWith('LIB-')) {
            return {
              'library_code': potentialId.toUpperCase(),
              'qr_version': version,
            };
          }
        }
      }

      // Check for short code prefix (e.g. LIB-ABC123)
      if (trimmed.toUpperCase().startsWith('LIB-')) {
        return {
          'library_code': trimmed.toUpperCase(),
          'qr_version': 1,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showCheckoutConfirmDialog({
    required Map<String, dynamic> activeSession,
    required String libName,
    required String seatLabel,
    required String shiftName,
    required String shiftEndTimeStr,
    required DateTime checkInTime,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final nowIst = toIST(nowUtc);
    
    final parts = shiftEndTimeStr.split(':');
    int endHour = 14;
    int endMinute = 0;
    if (parts.length >= 2) {
      endHour = int.tryParse(parts[0]) ?? 14;
      endMinute = int.tryParse(parts[1]) ?? 0;
      if (shiftEndTimeStr.toLowerCase().contains('pm') && endHour < 12) {
        endHour += 12;
      } else if (shiftEndTimeStr.toLowerCase().contains('am') && endHour == 12) {
        endHour = 0;
      }
    }
    final shiftEndIst = DateTime.utc(
      nowIst.year,
      nowIst.month,
      nowIst.day,
      endHour,
      endMinute,
    );
    
    // Duration in library
    final duration = nowUtc.difference(checkInTime);
    final isOvertime = nowIst.isAfter(shiftEndIst);
    final overtimeDuration = isOvertime ? nowIst.difference(shiftEndIst) : Duration.zero;
    final overtimeStr = formatDurationHuman(overtimeDuration);

    final bool? confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.palette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirm Check-Out',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to check out from the library?',
                style: GoogleFonts.inter(fontSize: 14, color: context.palette.textMuted),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              
              // Details
              _buildDialogDetailRow('Library', libName),
              _buildDialogDetailRow('Seat', seatLabel),
              _buildDialogDetailRow('Shift', shiftName),
              _buildDialogDetailRow('Check-In Time', formatTimeIST(checkInTime)),
              _buildDialogDetailRow('Current Duration', formatDurationHuman(duration)),
              _buildDialogDetailRow('Shift End Time', DateFormat('hh:mm a').format(shiftEndIst)),
              
              if (isOvertime) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Overtime: $overtimeStr beyond shift end.',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFE65C00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Confirm Check-Out',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirm == true) {
      await _performCheckout(
        activeSession: activeSession,
        libName: libName,
        seatLabel: seatLabel,
        shiftName: shiftName,
        shiftEndTimeStr: shiftEndTimeStr,
        checkInTime: checkInTime,
      );
    } else {
      setState(() {
        _isProcessingScan = false;
      });
    }
  }

  Widget _buildDialogDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
          ),
        ],
      ),
    );
  }

  Future<void> _performCheckout({
    required Map<String, dynamic> activeSession,
    required String libName,
    required String seatLabel,
    required String shiftName,
    required String shiftEndTimeStr,
    required DateTime checkInTime,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      // Overtime is HARD-capped at 30 min. Compute the shift end on the
      // CHECK-IN's IST date (so a session left open across days caps correctly),
      // then cap the recorded check-out at  greatest(shiftEnd, checkIn) + 30min.
      final parts = shiftEndTimeStr.split(':');
      int endHour = 14;
      int endMinute = 0;
      if (parts.length >= 2) {
        endHour = int.tryParse(parts[0]) ?? 14;
        endMinute = int.tryParse(parts[1].split(' ').first) ?? 0;
        if (shiftEndTimeStr.toLowerCase().contains('pm') && endHour < 12) {
          endHour += 12;
        } else if (shiftEndTimeStr.toLowerCase().contains('am') && endHour == 12) {
          endHour = 0;
        }
      }
      final checkInIst = toIST(checkInTime);
      // IST wall-clock of shift end (isUtc, IST numbers) → true UTC instant.
      final shiftEndIstWall = DateTime.utc(checkInIst.year, checkInIst.month, checkInIst.day, endHour, endMinute);
      final shiftEndUtc = shiftEndIstWall.subtract(const Duration(hours: 5, minutes: 30));

      final nowUtc = DateTime.now().toUtc();
      final overtimeAnchorUtc = checkInTime.isAfter(shiftEndUtc) ? checkInTime : shiftEndUtc;
      final capCheckoutUtc = overtimeAnchorUtc.add(const Duration(minutes: 30));
      final checkOutTimeUtc = nowUtc.isAfter(capCheckoutUtc) ? capCheckoutUtc : nowUtc;

      int durationMinutes = checkOutTimeUtc.difference(checkInTime).inMinutes;
      if (durationMinutes < 0) durationMinutes = 0;

      final bool beyondShiftEnd = checkOutTimeUtc.isAfter(shiftEndUtc);
      final bool wasOvertimeCheckin = activeSession['is_overtime'] == true;
      final bool isOvertime = beyondShiftEnd || wasOvertimeCheckin;
      int overtimeMinutes = beyondShiftEnd ? checkOutTimeUtc.difference(shiftEndUtc).inMinutes : 0;
      if (overtimeMinutes < 0) overtimeMinutes = 0;
      if (overtimeMinutes > 30) overtimeMinutes = 30;

      debugPrint('[CHECKOUT STEP] Starting: attendance update');
      debugPrint('[QR Scan Audit] Checkout API call initiated for session: ${activeSession['id']}');
      debugPrint('[QR Scan] Performing check-out database update for session: ${activeSession['id']}');
      final updateResponse = await supabase.from('attendance').update({
        'check_out_time': checkOutTimeUtc.toIso8601String(),
        'duration_minutes': durationMinutes,
        'is_overtime': isOvertime,
        'overtime_minutes': overtimeMinutes,
      }).eq('id', activeSession['id']).select();
      debugPrint('[CHECKOUT STEP] Success: attendance update');
      debugPrint('[QR Scan Audit] Supabase response received: $updateResponse');
      debugPrint('[QR Scan] Check-out database response: $updateResponse');

      if ((updateResponse as List).isEmpty) {
        throw Exception('Database update returned empty list (0 rows updated). Check activeSession id: ${activeSession['id']}');
      }

      if (!mounted) return;

      // Reset scan counters
      _cooldownScansCount = 0;

      // Notify the library owner that a member checked out (non-blocking).
      _notifyOwnerAttendance(
        activeSession['library_id']?.toString() ?? '',
        false,
        overtimeMinutes: overtimeMinutes,
        afterShift: beyondShiftEnd,
      );

      final overtimeStr = overtimeMinutes > 0 ? formatDurationHuman(Duration(minutes: overtimeMinutes)) : '';

      final checkInTimeIst = toIST(checkInTime);
      final checkOutTimeIst = toIST(checkOutTimeUtc);
      final hrs = durationMinutes ~/ 60;
      final mins = durationMinutes % 60;

      _showSuccess(
        isCheckIn: false,
        libraryName: libName,
        seatLabel: seatLabel,
        timeStr: DateFormat('hh:mm a').format(checkOutTimeIst),
        durationStr: '${hrs}h ${mins}m',
        isOffline: false,
        checkInTimeStr: DateFormat('hh:mm a').format(checkInTimeIst),
        checkOutTimeStr: DateFormat('hh:mm a').format(checkOutTimeIst),
        shiftEndTimeStr: DateFormat('hh:mm a').format(shiftEndIstWall),
        overtimeStr: overtimeStr,
        shiftName: shiftName,
      );

    } catch (e, stackTrace) {
      debugPrint('[CHECKOUT ERROR] ${e.toString()}');
      debugPrint('[CHECKOUT STACK] $stackTrace');
      debugPrint('[QR Scan] Error in checkout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() {
          _isProcessingScan = false;
        });
      }
    }
  }

  // Notify the library owner when a member checks in/out. RLS allows a member
  // with a membership at the library to notify that library's owner. Best-effort
  // and non-blocking — a failure never affects the scan result.
  Future<void> _notifyOwnerAttendance(
    String libraryId,
    bool isCheckIn, {
    int overtimeMinutes = 0,
    bool afterShift = false,
  }) async {
    if (libraryId.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final lib = await supabase.from('libraries').select('owner_id').eq('id', libraryId).maybeSingle();
      final ownerId = lib?['owner_id'];
      if (ownerId == null) return;

      String name = 'A member';
      try {
        final u = await supabase.from('users').select('full_name').eq('id', user.id).maybeSingle();
        final fn = (u?['full_name'] ?? '').toString().trim();
        if (fn.isNotEmpty) name = fn;
      } catch (_) {}

      // Honest, specific body: flag late / overtime check-outs for the admin.
      String body;
      if (isCheckIn) {
        body = '$name just checked in.';
      } else if (overtimeMinutes > 0) {
        body = '$name checked out after their shift ended — $overtimeMinutes min of overtime.';
      } else if (afterShift) {
        body = '$name checked out after their shift ended.';
      } else {
        body = '$name just checked out.';
      }

      await supabase.from('notifications').insert({
        'user_id': ownerId,
        'title': isCheckIn ? 'Member checked in' : 'Member checked out',
        'body': body,
        'data': {
          'type': isCheckIn ? 'check_in' : 'check_out',
          'route': '/admin/home',
          if (!isCheckIn && (overtimeMinutes > 0 || afterShift)) 'overtime_minutes': overtimeMinutes,
        },
      });
    } catch (e) {
      debugPrint('Owner attendance notification failed: $e');
    }
  }

  /// Build a shift TIME ('HH:mm[:ss][ am/pm]') as an IST wall-clock instant on
  /// [dateInIst]'s date. Returned as a `DateTime.utc` whose Y/M/D/H/M are the IST
  /// values, so it compares directly against `toIST(...)` results (which are also
  /// isUtc with IST wall-clock numbers) — matching the rest of this screen.
  DateTime _shiftDateTimeIst(String timeStr, DateTime dateInIst) {
    final parts = timeStr.split(':');
    int hour = 0, minute = 0;
    if (parts.isNotEmpty) hour = int.tryParse(parts[0]) ?? 0;
    if (parts.length >= 2) minute = int.tryParse(parts[1].split(' ').first) ?? 0;
    final lower = timeStr.toLowerCase();
    if (lower.contains('pm') && hour < 12) {
      hour += 12;
    } else if (lower.contains('am') && hour == 12) {
      hour = 0;
    }
    return DateTime.utc(dateInIst.year, dateInIst.month, dateInIst.day, hour, minute);
  }

  /// Member scanned to check in OUTSIDE their shift window and has no valid
  /// approval. File a PENDING checkin_approval (unless one is already pending) +
  /// notify the library owner, then show the member a warning card telling them
  /// to wait for approval or contact the admin. No attendance row is written.
  Future<void> _requestOutOfShiftApproval({
    required dynamic membershipId,
    required String libraryId,
    required dynamic shiftId,
    required String shiftName,
    required DateTime attemptedIst,
    required bool beforeStart,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    final whenStr = DateFormat('hh:mm a').format(attemptedIst);
    try {
      if (user != null) {
        // Don't pile up duplicate pending requests.
        final existing = await supabase
            .from('checkin_approvals')
            .select('id')
            .eq('member_id', user.id)
            .eq('library_id', libraryId)
            .eq('status', 'pending')
            .limit(1)
            .maybeSingle();

        if (existing == null) {
          await supabase.from('checkin_approvals').insert({
            'membership_id': membershipId,
            'member_id': user.id,
            'library_id': libraryId,
            'shift_id': shiftId,
            // attemptedIst is IST wall-clock carried in an isUtc DateTime → take
            // it back to the true UTC instant before storing the timestamptz.
            'attempted_at': attemptedIst.subtract(const Duration(hours: 5, minutes: 30)).toIso8601String(),
            'status': 'pending',
          });
          // Notify the owner (member → owner is allowed by RLS).
          await _notifyOwnerCheckinRequest(libraryId, whenStr, shiftName);
        }
      }
    } catch (e) {
      debugPrint('[QR Scan] Out-of-shift approval request failed: $e');
    }

    if (!mounted) return;
    _handleFailure(
      'Approval Needed',
      beforeStart
          ? 'You are trying to check in before your $shiftName shift hours ($whenStr). '
              'We have asked the admin to approve this check-in. Once approved you will get a '
              'notification — then scan again. This time will count as overtime. '
              'You can also contact the admin.'
          : 'You are trying to check in outside your $shiftName shift hours ($whenStr). '
              'We have asked the admin to approve this check-in. Once approved you will get a '
              'notification — then scan again. This time will count as overtime. '
              'You can also contact the admin.',
    );
  }

  /// Notify the library owner that a member is requesting an out-of-shift
  /// check-in approval. Best-effort + non-blocking.
  Future<void> _notifyOwnerCheckinRequest(
      String libraryId, String whenStr, String shiftName) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final lib = await supabase.from('libraries').select('owner_id').eq('id', libraryId).maybeSingle();
      final ownerId = lib?['owner_id'];
      if (ownerId == null) return;

      String name = 'A member';
      try {
        final u = await supabase.from('users').select('full_name').eq('id', user.id).maybeSingle();
        final fn = (u?['full_name'] ?? '').toString().trim();
        if (fn.isNotEmpty) name = fn;
      } catch (_) {}

      await supabase.from('notifications').insert({
        'user_id': ownerId,
        'title': 'Check-in approval needed',
        'body': '$name is trying to check in for the $shiftName shift at $whenStr, '
            'outside their shift hours. Approve or reject it in Requests.',
        'data': {'type': 'checkin_approval_request'},
      });
    } catch (e) {
      debugPrint('Owner check-in approval notification failed: $e');
    }
  }

  void _showSuccess({
    required bool isCheckIn,
    required String libraryName,
    required String seatLabel,
    required String timeStr,
    required String durationStr,
    required bool isOffline,
    String checkInTimeStr = '',
    String checkOutTimeStr = '',
    String shiftEndTimeStr = '',
    String overtimeStr = '',
    String shiftName = '',
  }) {
    if (!isCheckIn) {
      debugPrint('[CHECKOUT STEP] Starting: success card generation');
      debugPrint('[CHECKOUT] Success card displayed');
      debugPrint('[CHECKOUT STEP] Success: success card generation');
    }
    if (!mounted) return;
    setState(() {
      _showSuccessCard = true;
      _isCheckInSuccess = isCheckIn;
      _successLibraryName = libraryName;
      _successSeatLabel = seatLabel;
      _successTimeText = timeStr;
      _successDurationText = durationStr;
      _isSuccessOffline = isOffline;
      _successCheckInTimeText = checkInTimeStr;
      _successCheckOutTimeText = checkOutTimeStr;
      _successShiftEndTimeText = shiftEndTimeStr;
      _successOvertimeText = overtimeStr;
      _successShiftName = shiftName;
      _failedScansCount = 0; // Reset fails on success!
    });

    // Auto dismiss after 5 seconds when online (only for check-in)
    if (!isOffline && isCheckIn) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _showSuccessCard) {
          Navigator.pop(context, true);
        }
      });
    }
  }

  void _handleFailure(String title, String msg, {String? wrongLibName}) {
    if (!mounted) return;
    setState(() {
      if (title != 'Network Error') {
        _failedScansCount++;
      }
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
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(
                  isCheckIn ? Icons.check : Icons.logout,
                  size: 48,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isCheckIn ? 'Checked In Successfully ✓' : 'Checked Out Successfully ✓',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              
              if (isCheckIn) ...[
                Text(
                  _successLibraryName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Seat: $_successSeatLabel  ·  Shift: $_successShiftName',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  'In: $_successTimeText',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Scan the QR again anytime to check out.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Check Out Summary Screen
                Text(
                  '$_successLibraryName  ·  Seat $_successSeatLabel',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                
                _buildSummaryDetailRow('In:', _successCheckInTimeText),
                _buildSummaryDetailRow('Out:', _successCheckOutTimeText),
                _buildSummaryDetailRow('Duration:', _successDurationText),
                
                if (_successOvertimeText.isNotEmpty)
                  _buildSummaryDetailRow(
                    'Shift ended at:',
                    '$_successShiftEndTimeText (+$_successOvertimeText overtime)',
                    valueColor: Colors.redAccent,
                  )
                else
                  _buildSummaryDetailRow('Shift ended at:', _successShiftEndTimeText),
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
                    if (!_isCheckInSuccess) {
                      debugPrint('[CHECKOUT STEP] Starting: navigator return');
                      debugPrint('[CHECKOUT] Done pressed');
                      debugPrint('[CHECKOUT] Navigator.pop(true)');
                      debugPrint('[CHECKOUT STEP] Success: navigator return');
                    }
                    Navigator.pop(context, true);
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

  Widget _buildSummaryDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? context.palette.textPrimary,
            ),
          ),
        ],
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
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
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
                      backgroundColor: context.palette.textPrimary,
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
                          if (_errorTitle == 'Network Error' && _lastScannedValue != null) {
                            setState(() {
                              _showErrorCard = false;
                              _isProcessingScan = true;
                            });
                            _processQRContent(_lastScannedValue!);
                          } else {
                            setState(() {
                              _showErrorCard = false;
                              _isProcessingScan = false;
                            });
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFE65C00)),
                          foregroundColor: const Color(0xFFE65C00),
                        ),
                        child: Text(_errorTitle == 'Network Error' ? 'Retry' : 'Try Again'),
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
