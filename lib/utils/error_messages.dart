import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps raw exceptions (PostgREST / Supabase / network / Dart) to short,
/// human-friendly messages safe to show end users. Never put a raw `$e`
/// (stack-traceish, leaks internals) into the UI — pass it through here and log
/// the original separately.
///
/// ```dart
/// } catch (e) {
///   setState(() => _error = e);                 // keep raw for ErrorState/log
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text(friendlyError(e))),
///   );
/// }
/// ```
String friendlyError(Object? error) {
  if (error == null) return 'Something went wrong. Please try again.';

  // Already a clean, short, user-facing string.
  if (error is String) {
    return _looksTechnical(error) ? 'Something went wrong. Please try again.' : error;
  }

  // Connectivity problems can arrive wrapped in AuthException / ClientException
  // etc., so detect them up-front before the typed branches — otherwise a
  // network failure leaks a raw "SocketException: Failed host lookup" to the UI.
  if (_isNetworkError(error.toString().toLowerCase())) {
    return 'No internet connection. Please check your network and try again.';
  }

  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Incorrect email or password.';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  if (error is PostgrestException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == '23505' || msg.contains('duplicate')) {
      return 'This already exists.';
    }
    if (code == '23503' || msg.contains('foreign key')) {
      return "This can't be done because related data is missing.";
    }
    if (code == '42501' || msg.contains('row-level security') || msg.contains('permission')) {
      return "You don't have permission to do this.";
    }
    if (msg.contains('jwt') || msg.contains('expired')) {
      return 'Your session expired. Please sign in again.';
    }
    return 'Could not save your changes. Please try again.';
  }

  if (error is StorageException) {
    return 'File upload failed. Please check the file and try again.';
  }

  final text = error.toString().toLowerCase();
  if (_isNetworkError(text)) {
    return 'No internet connection. Please check your network and try again.';
  }

  return 'Something went wrong. Please try again.';
}

/// True when the error is (likely) a connectivity problem — callers can use
/// this to decide between an "offline" affordance and a generic error.
bool isNetworkError(Object? error) {
  if (error == null) return false;
  return _isNetworkError(error.toString().toLowerCase());
}

bool _isNetworkError(String text) {
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('clientexception') ||
      text.contains('handshakeexception');
}

bool _looksTechnical(String s) {
  final t = s.toLowerCase();
  return t.contains('exception') ||
      t.contains('postgrest') ||
      t.contains('stacktrace') ||
      t.contains('#0') ||
      t.contains('null check operator') ||
      t.contains('errordetails');
}
