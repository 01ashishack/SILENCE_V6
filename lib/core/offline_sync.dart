import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
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
      
      // Fetch all unsynced scans in FIFO order (older scans first)
      final List<Map<String, dynamic>> pending = await db.query(
        'offline_scan_queue',
        where: 'synced = 0',
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
        final String shiftId = scan['shift_id'];
        final String timestamp = scan['timestamp'];
        final int qrVersion = scan['qr_version'];
        final String? deviceId = scan['device_id'];

        try {
          if (type == 'checkin') {
            // Find user's active membership for this library & shift
            final activeMembership = await supabase
                .from('memberships')
                .select('id')
                .eq('member_id', memberId)
                .eq('library_id', libraryId)
                .eq('shift_id', shiftId)
                .inFilter('status', ['active', 'trial'])
                .maybeSingle();

            if (activeMembership == null) {
              // No valid membership, discard this scan as invalid
              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              continue;
            }

            final membershipId = activeMembership['id'];

            // Insert check-in record
            await supabase.from('attendance').insert({
              'membership_id': membershipId,
              'member_id': memberId,
              'library_id': libraryId,
              'shift_id': shiftId,
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
                .eq('library_id', libraryId)
                .eq('shift_id', shiftId)
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
              }).eq('id', sessionId);

              await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              successCount++;
            } else {
              // No active check-in found in Supabase!
              // In this case, let's find the latest attendance record and checkout there,
              // or create a complete attendance session with an assumed checkin
              final lastSession = await supabase
                  .from('attendance')
                  .select('id, check_in_time')
                  .eq('member_id', memberId)
                  .eq('library_id', libraryId)
                  .order('check_in_time', ascending: false)
                  .limit(1)
                  .maybeSingle();

              if (lastSession != null) {
                final String sessionId = lastSession['id'];
                final String checkInStr = lastSession['check_in_time'];
                final checkInTime = DateTime.parse(checkInStr);
                final checkOutTime = DateTime.parse(timestamp);
                final durationMinutes = checkOutTime.difference(checkInTime).inMinutes;

                await supabase.from('attendance').update({
                  'check_out_time': timestamp,
                  'duration_minutes': durationMinutes,
                  'offline_synced': true,
                }).eq('id', sessionId);

                await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
                successCount++;
              } else {
                // Completely orphaned checkout. Discard or insert as incomplete.
                await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
              }
            }
          }
        } catch (e) {
          debugPrint('Error syncing single scan $scanId: $e');
          // If duplicate key or check-in already matches, resolve conflict by deleting
          if (e.toString().contains('duplicate') || e.toString().contains('already')) {
            await db.delete('offline_scan_queue', where: 'id = ?', whereArgs: [scanId]);
          } else {
            // Keep in queue to retry later
            await db.update(
              'offline_scan_queue',
              {'retry_count': (scan['retry_count'] ?? 0) + 1},
              where: 'id = ?',
              whereArgs: [scanId],
            );
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
