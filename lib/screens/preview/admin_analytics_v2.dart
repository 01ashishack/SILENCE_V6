import 'package:flutter/material.dart';
import 'glass_kit.dart';

/// Midnight Focus (V2) preview of the Admin Analytics tab — SAMPLE DATA only,
/// to evaluate the look & feel. Not wired to live data.
class AdminAnalyticsV2Body extends StatefulWidget {
  const AdminAnalyticsV2Body({super.key});

  @override
  State<AdminAnalyticsV2Body> createState() => _AdminAnalyticsV2BodyState();
}

class _AdminAnalyticsV2BodyState extends State<AdminAnalyticsV2Body> {
  int _period = 1; // 0 Today · 1 Week · 2 Month
  static const _periods = ['Today', 'Week', 'Month'];

  // Sample daily revenue (₹ in hundreds) for the bar chart.
  static const _bars = [42.0, 58.0, 35.0, 70.0, 64.0, 88.0, 51.0];
  static const _barLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Text('Analytics', style: Midnight.head(26, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Harshit Library · this week', style: Midnight.body(13)),
        const SizedBox(height: 16),
        _segmented(),
        const SizedBox(height: 16),
        _revenueHero(),
        const SizedBox(height: 14),
        _statRow(),
        const SizedBox(height: 14),
        _chartCard(),
        const SizedBox(height: 14),
        _occupancyCard(),
      ],
    );
  }

  Widget _segmented() {
    return GlassCard(
      padding: const EdgeInsets.all(5),
      radius: 16,
      child: Row(
        children: List.generate(_periods.length, (i) {
          final active = i == _period;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _period = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: active ? Midnight.accent : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  _periods[i],
                  style: Midnight.body(13,
                      w: FontWeight.w700,
                      c: active ? Colors.white : Midnight.textSecondary),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _revenueHero() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Total Revenue', style: Midnight.body(13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Midnight.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  const Icon(Icons.arrow_upward_rounded, size: 12, color: Midnight.success),
                  const SizedBox(width: 3),
                  Text('18.4%', style: Midnight.body(11, w: FontWeight.w700, c: Midnight.success)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (r) => Midnight.accent.createShader(r),
            child: Text('₹ 64,200',
                style: Midnight.head(38, w: FontWeight.w800, c: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text('vs ₹54,200 last week', style: Midnight.body(12, c: Midnight.textFaint)),
        ],
      ),
    );
  }

  Widget _statRow() {
    return Row(
      children: [
        Expanded(child: _miniStat('Expenses', '₹ 9,800', Icons.receipt_long_rounded, Midnight.danger)),
        const SizedBox(width: 12),
        Expanded(child: _miniStat('Net Profit', '₹ 54,400', Icons.trending_up_rounded, Midnight.success)),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color tint) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(height: 12),
          Text(value, style: Midnight.head(18, w: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: Midnight.body(12)),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final maxV = _bars.reduce((a, b) => a > b ? a : b);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily Revenue', style: Midnight.head(15, w: FontWeight.w700)),
          const SizedBox(height: 18),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_bars.length, (i) {
                final h = (_bars[i] / maxV) * 110.0;
                final peak = _bars[i] == maxV;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 400 + i * 60),
                        curve: Curves.easeOutCubic,
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          gradient: peak
                              ? Midnight.accent
                              : LinearGradient(
                                  colors: [
                                    Midnight.accentA.withValues(alpha: 0.5),
                                    Midnight.accentB.withValues(alpha: 0.5),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_barLabels[i], style: Midnight.body(11, c: Midnight.textFaint)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _occupancyCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          GradientRing(
            value: 0.76,
            size: 72,
            center: Text('76%', style: Midnight.head(16, w: FontWeight.w800)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seat Occupancy', style: Midnight.head(15, w: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('38 of 50 seats filled this week',
                    style: Midnight.body(12.5)),
                const SizedBox(height: 4),
                Text('Peak: Fri 6–9 PM', style: Midnight.body(12, c: Midnight.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
