import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/member_data.dart';

class AddMemberStep4 extends StatefulWidget {
  final MemberData memberData;

  const AddMemberStep4({
    super.key,
    required this.memberData,
  });

  @override
  State<AddMemberStep4> createState() => _AddMemberStep4State();
}

class _AddMemberStep4State extends State<AddMemberStep4> with AutomaticKeepAliveClientMixin {
  late TextEditingController _discountController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _discountController = TextEditingController(
      text: widget.memberData.discount > 0 ? widget.memberData.discount.toString() : '',
    );
  }

  @override
  void didUpdateWidget(covariant AddMemberStep4 oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.memberData.discount > 0 ? widget.memberData.discount.toString() : '';
    if (_discountController.text != text) {
      _discountController.text = text;
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final finalPrice = (widget.memberData.totalBasePrice - widget.memberData.discount).clamp(0, double.infinity).toInt();

    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE65C00), width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
          hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment Details *',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure fees, discounts, and payment method for this membership.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
  
            // Pricing Summary Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.01),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Plan & Add-ons Base Total', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                      Text('₹${widget.memberData.totalBasePrice}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    ],
                  ),
                  if (widget.memberData.discount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Discount/Adjustment Applied', style: GoogleFonts.inter(fontSize: 13, color: Colors.red[600])),
                        Text('-₹${widget.memberData.discount}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[600])),
                      ],
                    ),
                  ],
                  const Divider(height: 24, color: Color(0xFFE5E7EB)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Final Payable Amount', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      Row(
                        children: [
                          if (widget.memberData.discount > 0)
                            Text(
                              '₹${widget.memberData.totalBasePrice} ',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.grey[400],
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          Text(
                            '₹$finalPrice',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE65C00),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
  
            // Discount / Adjustment Input
            Text(
              'Discount / Fee Adjustment (₹)',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'Enter discount amount (e.g. 200)',
                prefixText: '₹ ',
              ),
              onChanged: (val) {
                final disc = int.tryParse(val) ?? 0;
                setState(() {
                  if (disc <= widget.memberData.totalBasePrice) {
                    widget.memberData.discount = disc;
                  } else {
                    widget.memberData.discount = widget.memberData.totalBasePrice;
                  }
                });
              },
            ),
            const SizedBox(height: 24),
  
            // Payment Flow selection (Only if New Member)
            if (widget.memberData.mode == 'new') ...[
              Text(
                'Payment Flow *',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Text('Mark as Paid Now', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      selected: widget.memberData.paymentFlow == 'paid',
                      selectedColor: const Color(0xFFE65C00),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: widget.memberData.paymentFlow == 'paid' ? Colors.transparent : const Color(0xFFE5E7EB)),
                      ),
                      labelStyle: TextStyle(color: widget.memberData.paymentFlow == 'paid' ? Colors.white : const Color(0xFF475569)),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            widget.memberData.paymentFlow = 'paid';
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Text('Send Payment Request', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      selected: widget.memberData.paymentFlow == 'request',
                      selectedColor: const Color(0xFFE65C00),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: widget.memberData.paymentFlow == 'request' ? Colors.transparent : const Color(0xFFE5E7EB)),
                      ),
                      labelStyle: TextStyle(color: widget.memberData.paymentFlow == 'request' ? Colors.white : const Color(0xFF475569)),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            widget.memberData.paymentFlow = 'request';
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue[800], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Existing Member Flow: Payments must be confirmed manually (immediate cash/UPI). Payment requests are not available.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.blue[900], height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
  
            // Payment Method Radio Buttons
            if (widget.memberData.paymentFlow == 'paid' || widget.memberData.mode == 'existing') ...[
              Text(
                'Received Payment Via *',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => widget.memberData.paymentMethod = 'cash'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: widget.memberData.paymentMethod == 'cash' ? const Color(0xFFFFF7ED) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.memberData.paymentMethod == 'cash' ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                            width: widget.memberData.paymentMethod == 'cash' ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.memberData.paymentMethod == 'cash' ? const Color(0xFFE65C00) : Colors.transparent,
                                border: Border.all(
                                  color: widget.memberData.paymentMethod == 'cash' ? const Color(0xFFE65C00) : const Color(0xFFCBD5E1),
                                  width: 2,
                                ),
                              ),
                              child: widget.memberData.paymentMethod == 'cash'
                                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                                  : null,
                            ),
                            Text('Cash', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => widget.memberData.paymentMethod = 'upi'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: widget.memberData.paymentMethod == 'upi' ? const Color(0xFFFFF7ED) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.memberData.paymentMethod == 'upi' ? const Color(0xFFE65C00) : const Color(0xFFE5E7EB),
                            width: widget.memberData.paymentMethod == 'upi' ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.memberData.paymentMethod == 'upi' ? const Color(0xFFE65C00) : Colors.transparent,
                                border: Border.all(
                                  color: widget.memberData.paymentMethod == 'upi' ? const Color(0xFFE65C00) : const Color(0xFFCBD5E1),
                                  width: 2,
                                ),
                              ),
                              child: widget.memberData.paymentMethod == 'upi'
                                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                                  : null,
                            ),
                            Text('UPI', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.send_to_mobile, color: Colors.green[800], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A digital payment link request will be generated and can be sent to the member on Step 5.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.green[900], height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
