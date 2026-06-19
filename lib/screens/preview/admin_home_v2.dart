import 'package:flutter/material.dart';
import 'glass_kit.dart';
import 'admin_analytics_v2.dart';

/// Midnight Focus (V2) preview of Admin Home + Analytics — SAMPLE DATA only,
/// to evaluate the dark/glassmorphism look. Open via /preview/admin-v2.
/// The live Warm Sunrise screens are untouched.
class AdminHomeV2 extends StatefulWidget {
  const AdminHomeV2({super.key});

  @override
  State<AdminHomeV2> createState() => _AdminHomeV2State();
}

class _AdminHomeV2State extends State<AdminHomeV2> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Midnight.bg0,
      body: MidnightBackground(
        child: SafeArea(
          bottom: false,
          child: _tab == 2 ? const AdminAnalyticsV2Body() : _home(),
        ),
      ),
      bottomNavigationBar: _glassNav(),
      floatingActionButton: _tab == 0 ? _addMemberFab() : null,
    );
  }

  // ── HOME ──────────────────────────────────────────────────────────────────
  Widget _home() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        _topBar(),
        const SizedBox(height: 18),
        Text('Good morning, Harshit', style: Midnight.head(24, w: FontWeight.w700)),
        const SizedBox(height: 2),
        Text("Here's what's happening today.", style: Midnight.body(13)),
        const SizedBox(height: 18),
        _statusHero(),
        const SizedBox(height: 14),
        _attendanceCard(),
        const SizedBox(height: 14),
        _statGrid(),
      ],
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: Midnight.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text('H', style: Midnight.head(20, w: FontWeight.w800, c: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Harshit Library', style: Midnight.head(15, w: FontWeight.w700)),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Midnight.textSecondary, size: 20),
              ]),
              Row(children: [
                const Icon(Icons.place_outlined, size: 12, color: Midnight.textFaint),
                const SizedBox(width: 3),
                Text('Alwar, Rajasthan', style: Midnight.body(11.5, c: Midnight.textFaint)),
              ]),
            ],
          ),
        ),
        _glassIcon(Icons.notifications_none_rounded, dot: true),
      ],
    );
  }

  Widget _glassIcon(IconData icon, {bool dot = false}) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      radius: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: Midnight.textPrimary, size: 22),
          if (dot)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: Midnight.danger, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusHero() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GradientRing(
            value: 1.0,
            size: 88,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('4/4', style: Midnight.head(20, w: FontWeight.w800)),
                Text('setup', style: Midnight.body(10, c: Midnight.textFaint)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: Midnight.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('LIVE', style: Midnight.body(10.5, w: FontWeight.w800, c: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 10),
                Text('Library is launched', style: Midnight.head(16, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Everything is set up and running.', style: Midnight.body(12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCard() {
    const members = [
      ['AR', 'Ansul R.', 'In 9:02 AM'],
      ['PK', 'Priya K.', 'In 9:14 AM'],
      ['SM', 'Sahil M.', 'Out 1:40 PM'],
      ['NV', 'Neha V.', 'In 10:05 AM'],
    ];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text("Today's Attendance", style: Midnight.head(15, w: FontWeight.w700)),
            const Spacer(),
            Text('12 in', style: Midnight.body(12.5, w: FontWeight.w700, c: Midnight.success)),
          ]),
          const SizedBox(height: 16),
          Column(
            children: members.map((m) {
              final out = m[2].startsWith('Out');
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Midnight.accentA.withValues(alpha: 0.6),
                        Midnight.accentB.withValues(alpha: 0.6),
                      ]),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(m[0], style: Midnight.body(13, w: FontWeight.w700, c: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m[1], style: Midnight.body(13.5, w: FontWeight.w600, c: Midnight.textPrimary))),
                  Text(m[2],
                      style: Midnight.body(11.5,
                          w: FontWeight.w600, c: out ? Midnight.textFaint : Midnight.success)),
                ]),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _statGrid() {
    final tiles = [
      _StatData('Active Members', '42', Icons.groups_rounded, '+3', true),
      _StatData('Seats Filled', '38/50', Icons.event_seat_rounded, '76%', true),
      _StatData("Today's Revenue", '₹12,400', Icons.payments_rounded, '+18%', true),
      _StatData('Pending Requests', '3', Icons.how_to_reg_rounded, 'new', false),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: tiles.map(_statTile).toList(),
    );
  }

  Widget _statTile(_StatData d) {
    return GlassCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ShaderMask(
                  shaderCallback: (r) => Midnight.accent.createShader(r),
                  child: Icon(d.icon, size: 18, color: Colors.white),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (d.up ? Midnight.success : Midnight.accentB).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(d.delta,
                    style: Midnight.body(10.5,
                        w: FontWeight.w700, c: d.up ? Midnight.success : Midnight.accentB)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.value, style: Midnight.head(22, w: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(d.label, style: Midnight.body(12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addMemberFab() {
    return Container(
      decoration: BoxDecoration(
        gradient: Midnight.accent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Midnight.accentA.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {},
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Add Member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _glassNav() {
    const items = [
      [Icons.home_rounded, 'Home'],
      [Icons.event_seat_rounded, 'Reservations'],
      [Icons.bar_chart_rounded, 'Analytics'],
      [Icons.person_rounded, 'Profile'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        radius: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final active = i == _tab;
            return GestureDetector(
              onTap: () => setState(() => _tab = i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: EdgeInsets.symmetric(horizontal: active ? 16 : 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: active ? Midnight.accent : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Icon(items[i][0] as IconData,
                      size: 22, color: active ? Colors.white : Midnight.textFaint),
                  if (active) ...[
                    const SizedBox(width: 6),
                    Text(items[i][1] as String,
                        style: Midnight.body(12, w: FontWeight.w700, c: Colors.white)),
                  ],
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StatData {
  final String label, value, delta;
  final IconData icon;
  final bool up;
  _StatData(this.label, this.value, this.icon, this.delta, this.up);
}
