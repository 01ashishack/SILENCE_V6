import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

/// Metadata about the UPI app a handle belongs to — used to render a payment
/// button with the right label, icon and brand color. Detection mirrors the
/// logic already used in `library_setup_stage3.dart` so admin-side and
/// member-side stay in sync.
class UpiApp {
  final String name; // 'Paytm' | 'PhonePe' | 'GPay' | 'BHIM' | 'UPI'
  final IconData icon;
  final Color color;
  const UpiApp(this.name, this.icon, this.color);
}

/// The result of attempting to open a UPI app.
enum UpiLaunchResult {
  /// A UPI app was opened with the payment pre-filled.
  launched,

  /// No app could handle the UPI intent (e.g. no UPI app installed).
  noApp,

  /// The intent failed for another reason.
  failed,
}

/// Detects which UPI app a handle (`name@paytm`, `name@ybl`, …) belongs to.
UpiApp detectUpiApp(String upiId) {
  final handle = upiId.contains('@') ? upiId.split('@').last.toLowerCase() : '';
  if (handle == 'paytm') {
    return const UpiApp('Paytm', Icons.account_balance_wallet_outlined, Color(0xFF00BAF2));
  }
  if (['ybl', 'ibl', 'axl'].contains(handle)) {
    return const UpiApp('PhonePe', Icons.phone_android_outlined, Color(0xFF5F259F));
  }
  if (['oksbi', 'okaxis', 'okicici', 'okhdfcbank'].contains(handle)) {
    return const UpiApp('GPay', Icons.g_mobiledata_outlined, Color(0xFF4285F4));
  }
  if (handle == 'upi') {
    return const UpiApp('BHIM', Icons.account_balance_outlined, AppColors.secondary);
  }
  return const UpiApp('UPI', Icons.payments_outlined, AppColors.primary);
}

/// Builds a standard UPI deep-link URI. Amount is optional (some flows let the
/// payer enter it). `tn` is a short transaction note shown in the UPI app.
Uri buildUpiUri({
  required String payeeVpa,
  required String payeeName,
  double? amount,
  String? note,
}) {
  final params = <String, String>{
    'pa': payeeVpa,
    'pn': payeeName,
    'cu': 'INR',
  };
  if (amount != null && amount > 0) {
    params['am'] = amount.toStringAsFixed(2);
  }
  if (note != null && note.trim().isNotEmpty) {
    params['tn'] = note.trim();
  }
  return Uri(scheme: 'upi', host: 'pay', queryParameters: params);
}

/// Opens the device's UPI app(s) with the payment pre-filled. Because Android
/// resolves `upi://pay` to whichever UPI apps are installed, this may show an
/// app chooser rather than forcing one specific app — that is expected and
/// honest. Returns a [UpiLaunchResult] so the caller can show a manual-pay
/// fallback when no app is available. This does NOT confirm payment — the
/// member still declares "I have paid" and the admin verifies externally.
Future<UpiLaunchResult> launchUpiPayment({
  required String payeeVpa,
  required String payeeName,
  double? amount,
  String? note,
}) async {
  final uri = buildUpiUri(
    payeeVpa: payeeVpa,
    payeeName: payeeName,
    amount: amount,
    note: note,
  );
  try {
    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) return UpiLaunchResult.noApp;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return ok ? UpiLaunchResult.launched : UpiLaunchResult.failed;
  } catch (_) {
    return UpiLaunchResult.failed;
  }
}
