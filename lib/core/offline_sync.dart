import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'offline_db.dart';

class OfflineSyncManager {
  static final OfflineSyncManager instance = OfflineSyncManager._init();
  OfflineSyncManager._init();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  void startListening(BuildContext context) {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool hasInternet = !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (hasInternet) {
        if (!context.mounted) return;
        syncPendingScans(context);
      }
    });
  }

  void stopListening() {
    _connectivitySubscription?.cancel();
  }

  Future<void> syncPendingScans(BuildContext context) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await OfflineDatabase.instance.database;
      
      // Fetch all unsynced scans in FIFO order (older scans first, max 3 retries)
      final List<Map<String, dynamic>> pending = await db.query(
        'offline_scan_queue',
        where: 'synced = 0 AND retry_count < 3',
        orderBy: 'created_at ASC',
      );

      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      final supabase = Supabase.instance.client;
      int successCount = 0;

      for (var scan in pending) {
        final String scanId = scan['id'];
        final String type = scan['type']; // 'checkin' or 'checkout'
        final String memberId = scan['member_id'];
        final String libraryId = scan['library_id'];
        final String timestamp = scan['timestamp'];
        final int qrVersion = scan['qr_version'];
        final String? deviceId = scan['device_id'];

        try {
          String resolvedLibraryId = libraryId;
          if (libraryId.startsWith('LIB-')) {
            debugPrint('[Offline Sync] Resolving library code: $libraryId');
            final resolvedLib = await supabase
                .from('libraries')
                .select('id')
                .eq('library_code', libraryId)
                .maybeSingle();
            debugPrint('[Offline Sync] Resolution response: $resolvedLib');
            if (resolvedLib != null) {
              resolvedLibraryId = resolvedLib['id'];
            } else {
              // Invalid library code, delete from queue
              debugPrint('[Offline Sync] Library code $libraryId could not be resolved. Discarding scan.');
              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              continue;
            }
          }

          if (type == 'checkin') {
            // Find user's active membership for this library
            final activeMembership = await supabase
                .from('memberships')
                .select('id, shift_id')
                .eq('member_id', memberId)
                .eq('library_id', resolvedLibraryId)
                .inFilter('status', ['active', 'trial'])
                .maybeSingle();

            if (activeMembership == null) {
              // No valid membership, discard this scan as invalid
              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              continue;
            }

            final membershipId = activeMembership['id'];
            final realShiftId = activeMembership['shift_id'];

            // C2 (interim): never sync attendance onto a day the library was
            // CLOSED. (Full shift-window/overtime re-validation is still TODO;
            // offline rows stay flagged via offline_synced=true so they can be
            // audited.) Discard a check-in that lands on a closure day.
            try {
              final ciDate = DateTime.tryParse(timestamp);
              if (ciDate != null) {
                final dStr = ciDate.toIso8601String().substring(0, 10);
                final closure = await supabase
                    .from('scheduled_closures')
                    .select('id')
                    .eq('library_id', resolvedLibraryId)
                    .lte('start_date', dStr)
                    .gte('end_date', dStr)
                    .limit(1)
                    .maybeSingle();
                if (closure != null) {
                  await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
                  continue;
                }
              }
            } catch (_) {
              // If the closure check fails, fall through and insert (best-effort).
            }

            // Insert check-in record (flagged offline_synced for audit).
            await supabase.from('attendance').insert({
              'membership_id': membershipId,
              'member_id': memberId,
              'library_id': resolvedLibraryId,
              'shift_id': realShiftId,
              'check_in_time': timestamp,
              'check_out_time': null,
              'session_type': 'normal',
              'qr_version': qrVersion,
              'offline_synced': true,
              'device_id': deviceId ?? 'mobile_offline',
            });

            // Mark local scan as synced
            await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
            successCount++;

          } else if (type == 'checkout') {
            // Find active check-in session for the user
            final activeSession = await supabase
                .from('attendance')
                .select('id, check_in_time')
                .eq('member_id', memberId)
                .eq('library_id', resolvedLibraryId)
                .isFilter('check_out_time', null)
                .order('check_in_time', ascending: false)
                .limit(1)
                .maybeSingle();

            if (activeSession != null) {
              final String sessionId = activeSession['id'];
              final String checkInStr = activeSession['check_in_time'];
              final checkInTime = DateTime.parse(checkInStr);
              final checkOutTime = DateTime.parse(timestamp);
              final durationMinutes = checkOutTime.difference(checkInTime).inMinutes;

              await supabase.from('attendance').update({
                'check_out_time': timestamp,
                'duration_minutes': durationMinutes,
                'offline_synced': true,
              }).eq('id', sessionId).isFilter('check_out_time', null);

              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              successCount++;
            } else {
              // C1: NO open session found. Do NOT fall back to the latest row —
              // re-closing an already-closed session corrupts its duration (the
              // old code stamped a new check-out onto a closed row, producing
              // multi-day phantom durations). FIFO sync guarantees a matching
              // offline check-in is processed BEFORE its check-out, so a genuine
              // pair always finds its open session above. A checkout with no open
              // session is therefore orphaned (e.g. the check-in was discarded as
              // invalid) → discard it instead of corrupting another session.
              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
            }
          }
        } catch (e) {
          debugPrint('Error syncing single scan $scanId: $e');
          // If duplicate key or check-in already matches, resolve conflict by deleting
          if (e.toString().contains('duplicate') || e.toString().contains('already')) {
            await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
          } else {
            // Keep in queue to retry later
            final currentRetry = scan['retry_count'] as int? ?? 0;
            if (currentRetry >= 2) {
              // Delete permanently after 3 attempts (attempt 0, 1, 2)
              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              debugPrint('Scan $scanId permanently failed and removed from queue after 3 attempts.');
            } else {
              await db.update(
                'offline_scan_queue',
                {'retry_count': currentRetry + 1},
                where: 'id = ?',
                whereArgs: [scanId],
              );
            }
          }
        }
      }

      if (successCount > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text(
              'Synced $successCount offline scan events to cloud! ✓',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }

    } catch (e) {
      debugPrint('Sync pending scans failed: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
