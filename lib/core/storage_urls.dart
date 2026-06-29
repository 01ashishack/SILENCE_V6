import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves a stored private-storage reference to a displayable URL.
///
/// Background (audit P0): payment proofs and ID documents used to be stored as
/// one-hour **signed URLs** in the DB, which expired before an admin could
/// review them. New code stores the bare storage **object path** instead and
/// mints a fresh signed URL on demand (sign-on-view).
///
/// This resolver is backward compatible: if the stored value already looks like
/// an http(s) URL (a legacy signed URL or a public-bucket URL) it is returned
/// as-is; otherwise it is treated as a private-bucket object path and signed.
class StorageUrls {
  StorageUrls._();

  static const String privateBucket = 'silence_private';

  static bool isUrl(String v) =>
      v.startsWith('http://') || v.startsWith('https://');

  /// Returns a usable image URL for [value], or null if it can't be resolved.
  static Future<String?> resolve(
    String? value, {
    String bucket = privateBucket,
    int expiresIn = 3600,
  }) async {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    if (isUrl(v)) return v; // legacy signed URL or public URL — use as-is
    try {
      return await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(v, expiresIn);
    } catch (_) {
      return null; // path missing / no access — caller shows a fallback
    }
  }
}
