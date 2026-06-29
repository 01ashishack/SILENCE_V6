import 'package:flutter_test/flutter_test.dart';
import 'package:silence/core/storage_urls.dart';

/// Pure-logic tests for the storage path/URL detection that backs the
/// signed-URL-on-view fix (Wave 2). `resolve()` itself needs Supabase, but the
/// path-vs-URL discrimination it relies on is pure and is the regression-prone
/// part (legacy full URLs must pass through; bare paths must be signed).
void main() {
  group('StorageUrls.isUrl', () {
    test('detects http and https URLs', () {
      expect(StorageUrls.isUrl('https://x.supabase.co/storage/v1/object/sign/a'),
          isTrue);
      expect(StorageUrls.isUrl('http://example.com/a.jpg'), isTrue);
    });

    test('treats bare storage object paths as non-URLs (to be signed)', () {
      expect(StorageUrls.isUrl('user-123/proof.jpg'), isFalse);
      expect(StorageUrls.isUrl('payments/2026/abc.png'), isFalse);
    });
  });

  group('StorageUrls.resolve (pure branches, no network)', () {
    test('null and empty resolve to null', () async {
      expect(await StorageUrls.resolve(null), isNull);
      expect(await StorageUrls.resolve(''), isNull);
      expect(await StorageUrls.resolve('   '), isNull);
    });

    test('a legacy full URL is returned as-is (trimmed)', () async {
      const url = 'https://x.supabase.co/storage/v1/object/sign/proof.jpg';
      expect(await StorageUrls.resolve(url), url);
      expect(await StorageUrls.resolve('  $url  '), url);
    });
  });
}
