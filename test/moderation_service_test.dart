import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silence/services/moderation_service.dart';

/// Tests for the pure (no-network) moderation helpers. These cover the
/// design's correctness properties for client-side filtering and the domain
/// constants. Network methods (insert/update/delete) are exercised manually
/// on-device against RLS, per the spec's testing strategy.
void main() {
  Map<String, dynamic> review(String memberId, {bool? hidden}) =>
      {'id': 'r-$memberId', 'member_id': memberId, 'hidden': ?hidden};

  group('filterBlocked (Property 4)', () {
    test('removes exactly the reviews authored by blocked users', () {
      final reviews = [review('a'), review('b'), review('c')];
      final result = ModerationService.filterBlocked(reviews, {'b'});
      expect(result.map((r) => r['member_id']), ['a', 'c']);
    });

    test('empty block set returns the list unchanged', () {
      final reviews = [review('a'), review('b')];
      expect(ModerationService.filterBlocked(reviews, {}), reviews);
    });

    test('property: no surviving review has a blocked author, and only blocked are removed', () {
      final rng = Random(42);
      for (var iter = 0; iter < 200; iter++) {
        final authors = List.generate(rng.nextInt(12), (_) => 'u${rng.nextInt(6)}');
        final reviews = authors.map((a) => review(a)).toList();
        final blocked = {for (var i = 0; i < rng.nextInt(6); i++) 'u${rng.nextInt(6)}'};

        final result = ModerationService.filterBlocked(reviews, blocked);

        // No survivor is blocked.
        for (final r in result) {
          expect(blocked.contains(r['member_id']), isFalse);
        }
        // Every non-blocked input survives (count preserved per author).
        final expected = reviews.where((r) => !blocked.contains(r['member_id'])).length;
        expect(result.length, expected);
      }
    });
  });

  group('filterHidden (Property 5)', () {
    test('excludes hidden==true, keeps false and absent', () {
      final reviews = [
        review('a', hidden: true),
        review('b', hidden: false),
        review('c'), // hidden absent → visible
      ];
      final result = ModerationService.filterHidden(reviews);
      expect(result.map((r) => r['member_id']), ['b', 'c']);
    });

    test('property: result contains no hidden rows and preserves the rest', () {
      final rng = Random(7);
      for (var iter = 0; iter < 200; iter++) {
        final reviews = List.generate(rng.nextInt(15), (i) {
          final pick = rng.nextInt(3); // 0=hidden true, 1=false, 2=absent
          return review('u$i', hidden: pick == 2 ? null : pick == 0);
        });
        final result = ModerationService.filterHidden(reviews);
        expect(result.any((r) => r['hidden'] == true), isFalse);
        final expected = reviews.where((r) => r['hidden'] != true).length;
        expect(result.length, expected);
      }
    });
  });

  group('domain constants (Property 6)', () {
    test('reasons are the closed set', () {
      expect(ModerationService.reasons,
          ['spam', 'harassment', 'inappropriate', 'impersonation', 'copyright', 'other']);
    });

    test('target types are the closed set', () {
      expect(ModerationService.targetTypes, ['review', 'query', 'user', 'library']);
    });
  });
}
