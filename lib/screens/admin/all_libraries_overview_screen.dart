import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/active_library_store.dart';

/// Cross-library overview for a multi-library owner: one place that aggregates
/// the key metrics across ALL owned libraries (totals at the top) plus a
/// per-library breakdown. Tapping a library switches the admin shell to it.
///
/// Read-only + additive — it does not change any existing per-library flow.
/// Queries mirror the columns admin_home already uses (payments.payment_date/
/// status='confirmed', memberships.status/end_date, seats.status,
/// join_requests.status='pending') so behaviour matches the dashboard.
class AllLibrariesOverviewScreen extends StatefulWidget {
  const AllLibrariesOverviewScreen({super.key});

  @override
  State<AllLibrariesOverviewScreen> createState() =>
      _AllLibrariesOverviewScreenState();
}

class _LibStats {
  final String id;
  final String name;
  int activeMembers = 0;
  int totalSeats = 0;
  int occupiedSeats = 0;
  int revenueThisMonth = 0;
  int pendingRequests = 0;
  int expiringSoon = 0;

  _LibStats(this.id, this.name);

  int get occupancyPct =>
      totalSeats == 0 ? 0 : ((occupiedSeats / totalSeats) * 100).round();
}

class _AllLibrariesOverviewScreenState
    extends State<AllLibrariesOverviewScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  Object? _error;
  List<_LibStats> _stats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'Not signed in.';

      final libsRes = await _supabase
          .from('libraries')
          .select('id, name')
          .eq('owner_id', user.id)
          .order('created_at');
      final libs = List<Map<String, dynamic>>.from(libsRes);
      final Map<String, _LibStats> byId = {
        for (final l in libs)
          l['id'].toString(): _LibStats(
            l['id'].toString(),
            (l['name'] ?? 'Library').toString(),
          )
      };
      final ids = byId.keys.toList();

      if (ids.isNotEmpty) {
        final now = DateTime.now();
        final firstOfMonth = DateTime(now.year, now.month, 1);
        final firstOfMonthStr = firstOfMonth.toIso8601String();
        final today = DateTime(now.year, now.month, now.day);
        final in7Days = today.add(const Duration(days: 7));

        // One aggregate query per table; grouped in Dart (avoids N+1).
        final results = await Future.wait([
          _supabase
              .from('memberships')
              .select('library_id, status, end_date')
              .inFilter('library_id', ids),
          _supabase
              .from('seats')
              .select('library_id, status')
              .inFilter('library_id', ids),
          _supabase
              .from('payments')
              .select('library_id, amount, payment_date')
              .inFilter('library_id', ids)
              .eq('status', 'confirmed')
              .gte('payment_date', firstOfMonthStr),
          _supabase
              .from('join_requests')
              .select('library_id, status')
              .inFilter('library_id', ids)
              .eq('status', 'pending'),
        ]);

        for (final m in List<Map<String, dynamic>>.from(results[0])) {
          final s = byId[m['library_id']?.toString()];
          if (s == null) continue;
          final status = (m['status'] ?? '').toString();
          if (status == 'active' || status == 'trial') {
            s.activeMembers++;
            final endRaw = m['end_date']?.toString();
            if (endRaw != null && endRaw.isNotEmpty) {
              final end = DateTime.tryParse(endRaw);
              if (end != null &&
                  !end.isBefore(today) &&
                  !end.isAfter(in7Days)) {
                s.expiringSoon++;
              }
            }
          }
        }

        for (final seat in List<Map<String, dynamic>>.from(results[1])) {
          final s = byId[seat['library_id']?.toString()];
          if (s == null) continue;
          s.totalSeats++;
          final st = (seat['status'] ?? '').toString();
          if (st == 'occupied' || st == 'hold') s.occupiedSeats++;
        }

        for (final p in List<Map<String, dynamic>>.from(results[2])) {
          final s = byId[p['library_id']?.toString()];
          if (s == null) continue;
          final amt = p['amount'];
          if (amt is num) s.revenueThisMonth += amt.round();
        }

        for (final r in List<Map<String, dynamic>>.from(results[3])) {
          final s = byId[r['library_id']?.toString()];
          if (s == null) continue;
          s.pendingRequests++;
        }
      }

      if (!mounted) return;
      setState(() {
        _stats = byId.values.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  int get _totalMembers => _stats.fold(0, (a, s) => a + s.activeMembers);
  int get _totalRevenue => _stats.fold(0, (a, s) => a + s.revenueThisMonth);
  int get _totalPending => _stats.fold(0, (a, s) => a + s.pendingRequests);
  int get _totalExpiring => _stats.fold(0, (a, s) => a + s.expiringSoon);

  void _openLibrary(_LibStats s) {
    // Switch the admin shell to this library, then return to the dashboard.
    ActiveLibraryStore.requestSwitch(s.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('All Libraries',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text('Could not load the overview.',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFE65C00),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTotalsCard(),
          const SizedBox(height: 16),
          Text('Per library',
              style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary)),
          const SizedBox(height: 8),
          ..._stats.map(_buildLibraryCard),
        ],
      ),
    );
  }

  Widget _buildTotalsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE65C00), Color(0xFFC44E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Across ${_stats.length} libraries',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 12),
          Row(
            children: [
              _totalTile('₹$_totalRevenue', 'Revenue (mo)'),
              _totalTile('$_totalMembers', 'Active members'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _totalTile('$_totalPending', 'Pending requests'),
              _totalTile('$_totalExpiring', 'Expiring ≤7d'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalTile(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _buildLibraryCard(_LibStats s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openLibrary(s),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: context.palette.textPrimary)),
                    ),
                    if (s.pendingRequests > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65C00).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${s.pendingRequests} pending',
                            style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFE65C00))),
                      ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statTile('₹${s.revenueThisMonth}', 'Revenue (mo)'),
                    _statTile('${s.activeMembers}', 'Members'),
                    _statTile('${s.occupancyPct}%', 'Occupancy'),
                    _statTile('${s.expiringSoon}', 'Expiring'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary)),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 10.5, color: const Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}
