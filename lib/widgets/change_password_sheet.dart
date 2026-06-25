import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/error_messages.dart';

/// Shared "Change Password" bottom sheet used by BOTH the member and admin
/// profile screens (single implementation → no divergence).
///
/// Security: the CURRENT password is verified via re-authentication before the
/// new password is applied, so a borrowed/unlocked session can't silently reset
/// it. For accounts with no email/password (e.g. Google-only), it shows an
/// honest message instead of pretending to change a password.
Future<void> showChangePasswordSheet(BuildContext context) {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isUpdating = false;
  String? localError;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Change Password',
                        style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE65C00))),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Passwords must be at least 6 characters.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 16),
                if (localError != null) ...[
                  Text(localError!,
                      style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Current Password is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'New Password is required';
                    if (v.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                  validator: (v) =>
                      v != newPasswordController.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isUpdating
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setModalState(() {
                            isUpdating = true;
                            localError = null;
                          });
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final supabase = Supabase.instance.client;
                            final email = supabase.auth.currentUser?.email;
                            if (email == null || email.isEmpty) {
                              setModalState(() {
                                localError =
                                    'No email on this account — password change unavailable.';
                                isUpdating = false;
                              });
                              return;
                            }
                            // Verify CURRENT password by re-authenticating first.
                            try {
                              await supabase.auth.signInWithPassword(
                                email: email,
                                password: currentPasswordController.text.trim(),
                              );
                            } catch (_) {
                              setModalState(() {
                                localError = 'Current password is incorrect.';
                                isUpdating = false;
                              });
                              return;
                            }
                            await supabase.auth.updateUser(
                              UserAttributes(password: newPasswordController.text.trim()),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Password updated successfully ✓'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          } catch (e) {
                            setModalState(() {
                              localError = friendlyError(e);
                              isUpdating = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Update Password',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
