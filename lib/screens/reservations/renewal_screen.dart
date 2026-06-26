import 'dart:async';
import '../../theme/app_palette.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/image_optimizer.dart';
import '../../theme/app_colors.dart';
import '../../utils/upi_launcher.dart';
import '../../utils/form_draft.dart';
import '../../utils/time_utils.dart';
import '../../widgets/states/states.dart';

class RenewalScreen extends StatefulWidget {
  final String libraryId;
  final String? initialPlan; // 'monthly', '3_month', '6_month'
  final String? initialShiftId;

  const RenewalScreen({
    super.key,
    required this.libraryId,
    this.initialPlan,
    this.initialShiftId,
  });

  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Fetched data
  Map<String, dynamic>? _library;
  List<Map<String, dynamic>> _shifts = [];

  // Current membership context (drives the 7-day renewal window gate).
  DateTime? _currentEndDate;
  int? _daysLeft; // null = no current membership (e.g. expired) → renewal allowed

  /// Renewal is only "open" within the last 7 days of a still-running plan, or
  /// once it has already expired. A member with > 7 days left is told to come
  /// back closer to expiry (prevents accidental early/stacked renewals).
  static const int _renewalWindowDays = 7;
  bool get _renewalOpen => _daysLeft == null || _daysLeft! <= _renewalWindowDays;

  // Selected values
  Map<String, dynamic>? _selectedShift;
  late String _selectedPlan;

  // Payment inputs
  String _paymentMethod = 'cash'; // 'cash' or 'upi'
  final TextEditingController _upiSenderCtrl = TextEditingController();
  File? _proofImageFile;
  bool _isUploadingProof = false;
  String? _proofUrl;
  bool _isSubmitting = false;
  bool _paymentDeclared = false; // member confirms "I have paid" (UPI)

  // Draft persistence (survives app restart until submitted/discarded)
  late final FormDraft _draft;
  Timer? _draftTimer;
  bool _restoringDraft = false;

  /// Admin-configured UPI IDs for this library (from libraries.social_links).
  List<String> get _upiIds {
    final sl = _library?['social_links'];
    if (sl is Map && sl['upi_ids'] is List) {
      return (sl['upi_ids'] as List)
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.initialPlan ?? 'monthly';
    _draft = FormDraft('renewal', widget.libraryId);
    _loadDetails();
    _upiSenderCtrl.addListener(_scheduleDraftSave);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _upiSenderCtrl.dispose();
    super.dispose();
  }

  // ── Draft save / restore ────────────────────────────────────────────────────
  void _scheduleDraftSave() {
    if (_restoringDraft || _isSubmitting) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_restoringDraft || _isSubmitting) return;
    await _draft.save({
      'selectedShiftId': _selectedShift?['id']?.toString(),
      'selectedPlan': _selectedPlan,
      'paymentMethod': _paymentMethod,
      'upiSender': _upiSenderCtrl.text,
      'paymentDeclared': _paymentDeclared,
    });
  }

  Future<void> _maybeOfferRestore() async {
    final raw = await _draft.load();
    if (raw == null) return;
    // Only offer when there's real payment progress worth not re-entering.
    final hasProgress = (raw['paymentMethod'] == 'upi') ||
        ((raw['upiSender'] ?? '') as String).trim().isNotEmpty ||
        raw['paymentDeclared'] == true;
    if (!hasProgress) {
      await _draft.clear();
      return;
    }
    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resume your renewal?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        content: Text(
          'You have an unfinished renewal for this library, saved ${FormDraft.savedAgo(raw['savedAt'])}. '
          'Continue where you left off, or start fresh?',
          style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: context.palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Start fresh', style: GoogleFonts.inter(color: context.palette.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: Text('Resume', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (resume == true) {
      _applyDraft(raw);
    } else if (resume == false) {
      await _draft.clear();
    }
  }

  void _applyDraft(Map<String, dynamic> raw) {
    _restoringDraft = true;
    setState(() {
      final shiftId = raw['selectedShiftId']?.toString();
      if (shiftId != null && _shifts.isNotEmpty) {
        final match = _shifts.where((s) => s['id'].toString() == shiftId).toList();
        if (match.isNotEmpty) _selectedShift = match.first;
      }
      _selectedPlan = (raw['selectedPlan'] ?? _selectedPlan) as String;
      _paymentMethod = (raw['paymentMethod'] ?? _paymentMethod) as String;
      _upiSenderCtrl.text = (raw['upiSender'] ?? '') as String;
      _paymentDeclared = raw['paymentDeclared'] == true;
    });
    _restoringDraft = false;
  }

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User authentication missing.');
      }

      // 1. Fetch library details
      final libRes = await _supabase
          .from('libraries')
          .select()
          .eq('id', widget.libraryId)
          .maybeSingle();

      if (libRes == null) {
        throw Exception('Library not found.');
      }
      _library = libRes;

      // 2. Fetch active shifts
      final shiftsRes = await _supabase
          .from('shifts')
          .select()
          .eq('library_id', widget.libraryId)
          .eq('is_archived', false);
      
      _shifts = List<Map<String, dynamic>>.from(shiftsRes);

      // 3. Current membership for this library → days-left for the renewal gate.
      try {
        final ms = await _supabase
            .from('memberships')
            .select('end_date, status')
            .eq('member_id', user.id)
            .eq('library_id', widget.libraryId)
            .neq('status', 'exited')
            .order('end_date', ascending: false)
            .limit(1)
            .maybeSingle();
        final endRaw = ms?['end_date']?.toString();
        if (endRaw != null && endRaw.isNotEmpty) {
          final end = DateTime.tryParse(endRaw);
          if (end != null) {
            _currentEndDate = end;
            final now = istNow();
            final today = DateTime(now.year, now.month, now.day);
            final endDay = DateTime(end.year, end.month, end.day);
            _daysLeft = endDay.difference(today).inDays;
          }
        }
      } catch (e) {
        debugPrint('renewal: current membership lookup failed: $e');
      }

      if (widget.initialShiftId != null && _shifts.isNotEmpty) {
        _selectedShift = _shifts.firstWhere(
          (s) => s['id'] == widget.initialShiftId,
          orElse: () => _shifts.first,
        );
      } else if (_shifts.isNotEmpty) {
        _selectedShift = _shifts.first;
      }
    } catch (e) {
      debugPrint('Error loading renewal details: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (_errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _maybeOfferRestore();
          });
        }
      }
    }
  }

  Future<void> _pickProofImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    if (image == null) return;

    setState(() {
      _proofImageFile = File(image.path);
    });
  }

  Future<bool> _uploadProofImage() async {
    if (_proofImageFile == null) return false;
    setState(() {
      _isUploadingProof = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final fileName = 'proof_renewal_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'payment_proofs/${user.id}/$fileName';

      final bytes = await ImageOptimizer.compressImage(_proofImageFile!.path);
      await _supabase.storage.from('silence_private').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: true,
            ),
          );

      // Payment proof is financial PII → private bucket + signed URL (member
      // detail re-signs it for the admin on view). Not the public bucket.
      final String publicUrl = await _supabase.storage.from('silence_private').createSignedUrl(path, 3600);
      _proofUrl = publicUrl;
      return true;
    } catch (e) {
      debugPrint('Error uploading proof photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload screenshot: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProof = false;
        });
      }
    }
  }

  double _calculateSelectedPlanPrice() {
    final shift = _selectedShift;
    if (shift == null) return 0;

    switch (_selectedPlan) {
      case '3_month':
        return (shift['price_3month'] as int? ?? ((shift['price_monthly'] as int? ?? 0) * 3)).toDouble();
      case '6_month':
        return (shift['price_6month'] as int? ?? ((shift['price_monthly'] as int? ?? 0) * 6)).toDouble();
      case 'monthly':
      default:
        return (shift['price_monthly'] as int? ?? 1200).toDouble();
    }
  }

  Future<void> _submitRenewalRequest() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Honest confirmation: tell the member what they have left before sending.
    final confirmed = await _confirmRenewal();
    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Check existing pending requests to prevent duplicate submission
      final existingReq = await _supabase
          .from('join_requests')
          .select('id')
          .eq('member_id', user.id)
          .eq('library_id', widget.libraryId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existingReq != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You already have a pending join or renewal request under review.')),
          );
        }
        return;
      }

      // Payment happens outside the app. For UPI, the member confirms they
      // paid; a screenshot is optional (uploaded only if one was attached).
      if (_paymentMethod == 'upi') {
        if (!_paymentDeclared) {
          throw Exception("Please confirm you've made the payment.");
        }
        if (_proofImageFile != null) {
          final uploadOk = await _uploadProofImage();
          if (!uploadOk) {
            throw Exception('Screenshot upload failed. Remove it or try again.');
          }
        }
      }

      final shift = _selectedShift;
      if (shift == null) {
        throw Exception('Please select a shift first.');
      }

      // Insert join_request flagged as a RENEWAL so the admin can tell it apart
      // and the approve flow extends the existing membership (not a duplicate).
      final requestPayload = {
        'member_id': user.id,
        'library_id': widget.libraryId,
        'shift_id': shift['id'],
        'plan_type': _selectedPlan,
        'payment_method': _paymentMethod,
        'payment_proof_url': _proofUrl,
        'upi_sender_name': _paymentMethod == 'upi' ? _upiSenderCtrl.text.trim() : null,
        'status': 'pending',
        'is_renewal': true,
      };

      await _supabase.from('join_requests').insert(requestPayload);

      _draftTimer?.cancel();
      await _draft.clear();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Request sent', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Text(
              "Your renewal request has been sent to the library admin. You'll be notified once your payment is verified and the renewal is approved.",
              style: GoogleFonts.inter(),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context, true); // Return success to home
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        );
      }

    } catch (e) {
      debugPrint('Error submitting renewal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: context.palette.scaffold,
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('Renew Membership', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
          body: _isLoading
              ? const LoadingState(kind: SkeletonKind.spinner, message: 'Loading renewal details…')
              : _errorMessage != null
                  ? ErrorState(error: _errorMessage, onRetry: _loadDetails)
                  : !_renewalOpen
                      ? _buildRenewalNotOpen()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLibrarySummaryCard(),
                              const SizedBox(height: 20),
                              if (_daysLeft != null) _buildDaysLeftNote(),
                              if (_daysLeft != null) const SizedBox(height: 20),
                              _buildShiftSelect(),
                              const SizedBox(height: 20),
                              _buildPlanSelect(),
                              const SizedBox(height: 20),
                              _buildPaymentSection(),
                              const SizedBox(height: 32),
                              _buildSubmitButton(),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }

  /// Shown when the member still has more than 7 days left — renewal opens
  /// closer to expiry so plans aren't accidentally stacked early.
  Widget _buildRenewalNotOpen() {
    final endStr = _currentEndDate != null
        ? DateFormat('dd MMM yyyy').format(_currentEndDate!)
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Color(0xFFFFF3ED), shape: BoxShape.circle),
              child: const Icon(Icons.schedule_rounded, color: Color(0xFFE65C00), size: 40),
            ),
            const SizedBox(height: 18),
            Text('Renewal not open yet',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Your plan is still active with $_daysLeft day${_daysLeft == 1 ? '' : 's'} left'
              '${endStr != null ? ' (till $endStr)' : ''}. '
              'Renewal opens in the last $_renewalWindowDays days before it expires — '
              'please come back then.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13.5, color: context.palette.textMuted, height: 1.45),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Got it', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small banner inside the form reminding the member how long is left.
  Widget _buildDaysLeftNote() {
    final endStr = _currentEndDate != null
        ? DateFormat('dd MMM yyyy').format(_currentEndDate!)
        : null;
    final msg = (_daysLeft != null && _daysLeft! <= 0)
        ? 'Your plan ends today. The new term starts from approval.'
        : 'Your plan has $_daysLeft day${_daysLeft == 1 ? '' : 's'} left'
            '${endStr != null ? ' (till $endStr)' : ''}. The new term is added on top.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD1B3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF92400E), height: 1.35)),
          ),
        ],
      ),
    );
  }

  /// Confirmation before sending the renewal request.
  Future<bool?> _confirmRenewal() async {
    final daysMsg = _daysLeft == null
        ? 'Your previous plan has ended.'
        : (_daysLeft! <= 0
            ? 'Your plan ends today.'
            : 'You currently have $_daysLeft day${_daysLeft == 1 ? '' : 's'} left.');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Send renewal request?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(
          '$daysMsg The new term will be added on top of your current plan once '
          'the admin approves and verifies the payment.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: context.palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65C00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Send request', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrarySummaryCard() {
    final libName = _library?['name'] ?? 'SILENCE Library';
    final address = _library?['address_city'] ?? 'Jaipur';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF3ED), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.business, color: Color(0xFFE65C00), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
                const SizedBox(height: 2),
                Text(address, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildShiftSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Shift', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        const SizedBox(height: 10),
        if (_shifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text('No shifts available', style: GoogleFonts.inter(color: Colors.grey)),
          )
        else
          ..._shifts.map((s) {
            final isSelected = _selectedShift?['id'] == s['id'];
            return InkWell(
              onTap: () {
                setState(() => _selectedShift = s);
                _scheduleDraftSave();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!,
                    width: isSelected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] ?? 'Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${s['start_time']} – ${s['end_time']}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Text(
                      '₹${s['price_monthly']}/mo',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFFE65C00)),
                    )
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPlanSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Plan Duration', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        const SizedBox(height: 10),
        _buildPlanPill('monthly', 'Monthly Plan', '₹${_selectedShift != null ? (_selectedShift!['price_monthly'] ?? 0) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('3_month', '3-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_3month'] ?? ((_selectedShift!['price_monthly'] as int? ?? 0) * 3)) : 0}'),
        const SizedBox(height: 8),
        _buildPlanPill('6_month', '6-Month Plan', '₹${_selectedShift != null ? (_selectedShift!['price_6month'] ?? ((_selectedShift!['price_monthly'] as int? ?? 0) * 6)) : 0}'),
      ],
    );
  }

  Widget _buildPlanPill(String planKey, String label, String priceLabel) {
    final isSelected = _selectedPlan == planKey;
    return InkWell(
      onTap: () {
        setState(() => _selectedPlan = planKey);
        _scheduleDraftSave();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
                ),
                const SizedBox(width: 12),
                Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            Text(priceLabel, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: context.palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    final total = _calculateSelectedPlanPrice();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
              Text('₹$total', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Select Payment Method', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
        const SizedBox(height: 10),
        _buildPaymentMethodOption('cash', '💵 Cash Payment', 'Pay the total amount in cash directly at the library.'),
        const SizedBox(height: 8),
        _buildPaymentMethodOption('upi', '📱 UPI / Online Transfer', 'Pay the admin via any UPI app, then confirm below.'),
        if (_paymentMethod == 'upi') ...[
          const SizedBox(height: 16),
          _buildUpiCard(total),
        ],
      ],
    );
  }

  /// UPI card: shows the admin's configured UPI IDs as tappable deep-link
  /// buttons (open the payer's UPI app pre-filled), an honest explanation that
  /// payment happens outside the app and the admin verifies it, the required
  /// "I have paid" confirmation, and an OPTIONAL reference + screenshot.
  Widget _buildUpiCard(double total) {
    final ids = _upiIds;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ids.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "This library hasn't added a UPI ID yet. Please pay by cash, or contact the admin.",
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppColors.orangeText),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Pay to the library',
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap an app to pay ₹${total.toStringAsFixed(0)}, or copy the UPI ID.',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.palette.textMuted),
            ),
            const SizedBox(height: 10),
            ...ids.map((id) => _buildUpiAppButton(id, total)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment happens in your UPI app. After paying, confirm below — the admin verifies it and activates your plan.',
                      style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: context.palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildDeclareCheck(),
            const SizedBox(height: 12),
            TextField(
              controller: _upiSenderCtrl,
              decoration: const InputDecoration(
                labelText: 'Reference / sender name (optional)',
                hintText: 'Helps the admin match your payment',
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionalScreenshot(),
          ],
        ],
      ),
    );
  }

  Widget _buildUpiAppButton(String upiId, double amount) {
    final app = detectUpiApp(upiId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _payViaUpi(upiId, amount),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: app.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(app.icon, size: 18, color: app.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay with ${app.name}',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.palette.textPrimary),
                    ),
                    Text(
                      upiId,
                      style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 18, color: context.palette.textMuted),
                tooltip: 'Copy UPI ID',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: upiId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('UPI ID copied')),
                  );
                },
              ),
              const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeclareCheck() {
    return InkWell(
      onTap: () {
        setState(() => _paymentDeclared = !_paymentDeclared);
        _scheduleDraftSave();
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _paymentDeclared ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: _paymentDeclared ? AppColors.primary : context.palette.textMuted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "I have made this payment to the library's UPI.",
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionalScreenshot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add payment screenshot (optional)',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.textSecondary),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickProofImage,
          child: Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: context.palette.border),
              borderRadius: BorderRadius.circular(8),
              color: context.palette.surfaceMuted,
            ),
            alignment: Alignment.center,
            child: _proofImageFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_proofImageFile!, fit: BoxFit.contain),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 28, color: context.palette.textMuted),
                      const SizedBox(height: 6),
                      Text('Tap to attach a screenshot', style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _payViaUpi(String upiId, double amount) async {
    final libName = (_library?['name'] as String?)?.trim();
    final result = await launchUpiPayment(
      payeeVpa: upiId,
      payeeName: (libName == null || libName.isEmpty) ? 'SILENCE Library' : libName,
      amount: amount,
      note: 'Membership renewal',
    );
    if (!mounted) return;
    if (result == UpiLaunchResult.noApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI app found. Copy the UPI ID and pay manually.')),
      );
    } else if (result == UpiLaunchResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a UPI app. Copy the UPI ID and pay manually.')),
      );
    }
  }

  Widget _buildPaymentMethodOption(String key, String label, String desc) {
    final isSelected = _paymentMethod == key;
    return InkWell(
      onTap: () {
        setState(() => _paymentMethod = key);
        _scheduleDraftSave();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? const Color(0xFFE65C00) : Colors.grey[300]!, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFFE65C00) : Colors.grey[400],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(desc, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: (_isSubmitting || _isUploadingProof) ? null : _submitRenewalRequest,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _isSubmitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text('Submit Renewal Request', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
