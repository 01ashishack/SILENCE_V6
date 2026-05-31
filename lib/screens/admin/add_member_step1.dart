import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/calendar_picker.dart';
import '../../models/member_data.dart';

class AddMemberStep1 extends StatefulWidget {
  final MemberData memberData;
  final Function(Map<String, dynamic>) onAutofillDetails;

  const AddMemberStep1({
    super.key,
    required this.memberData,
    required this.onAutofillDetails,
  });

  @override
  State<AddMemberStep1> createState() => _AddMemberStep1State();
}

class _AddMemberStep1State extends State<AddMemberStep1> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  Timer? _debounce;
  final _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.memberData.name);
    _fatherNameController = TextEditingController(text: widget.memberData.fatherName);
    _phoneController = TextEditingController(text: widget.memberData.phone);
    _emailController = TextEditingController(text: widget.memberData.email);
    _addressController = TextEditingController(text: widget.memberData.address);

    _nameController.addListener(() => widget.memberData.name = _nameController.text.trim());
    _fatherNameController.addListener(() => widget.memberData.fatherName = _fatherNameController.text.trim());
    _phoneController.addListener(() => widget.memberData.phone = _phoneController.text.trim());
    _emailController.addListener(() => widget.memberData.email = _emailController.text.trim());
    _addressController.addListener(() => widget.memberData.address = _addressController.text.trim());
  }

  @override
  void didUpdateWidget(covariant AddMemberStep1 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memberData.name != _nameController.text) {
      _nameController.text = widget.memberData.name;
    }
    if (widget.memberData.fatherName != _fatherNameController.text) {
      _fatherNameController.text = widget.memberData.fatherName;
    }
    if (widget.memberData.phone != _phoneController.text) {
      _phoneController.text = widget.memberData.phone;
    }
    if (widget.memberData.email != _emailController.text) {
      _emailController.text = widget.memberData.email;
    }
    if (widget.memberData.address != _addressController.text) {
      _addressController.text = widget.memberData.address;
    }
  }


  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onEmailChanged(String email) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final emailVal = email.trim();
      if (emailVal.isNotEmpty && emailVal.contains('@')) {
        _lookupUserByEmail(emailVal);
      }
    });
  }

  Future<void> _lookupUserByEmail(String email) async {
    try {
      final userObj = await _supabase
          .from('users')
          .select('id, full_name, phone, gender, date_of_birth, address, exam_category, photo_url')
          .eq('email', email)
          .maybeSingle();

      if (userObj != null && mounted) {
        _showAutofillBottomSheet(userObj);
      }
    } catch (e) {
      debugPrint('Error looking up email: $e');
    }
  }

  void _showAutofillBottomSheet(Map<String, dynamic> userObj) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Existing User Found',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A user with this email already exists in the system:\n'
              '• Name: ${userObj['full_name'] ?? 'N/A'}\n'
              '• Phone: ${userObj['phone'] ?? 'N/A'}',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF475569),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _autofillDetails(userObj);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65C00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: Text(
                      'Copy Details',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _autofillDetails(Map<String, dynamic> userObj) {
    setState(() {
      _nameController.text = userObj['full_name'] ?? '';
      _phoneController.text = userObj['phone'] ?? '';
      widget.memberData.gender = userObj['gender'];
      if (userObj['date_of_birth'] != null) {
        widget.memberData.dob = DateTime.tryParse(userObj['date_of_birth']);
      }
      _addressController.text = userObj['address'] ?? '';
      widget.memberData.preparingFor = userObj['exam_category'];
      widget.memberData.existingPhotoUrl = userObj['photo_url'];
    });
    widget.onAutofillDetails(userObj);
  }

  Future<void> _pickImage(bool isProfile, {bool isId1 = false, bool isId2 = false}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final pickedFile = await _picker.pickImage(source: source, maxWidth: 1024, imageQuality: 85);
    if (pickedFile != null) {
      if (isProfile) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Profile Photo',
              toolbarColor: const Color(0xFFE65C00),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Crop Profile Photo',
              aspectRatioLockEnabled: true,
            ),
          ],
        );
        if (croppedFile != null) {
          setState(() {
            widget.memberData.profilePhoto = File(croppedFile.path);
          });
        }
      } else {
        final file = File(pickedFile.path);
        setState(() {
          if (isId1) {
            widget.memberData.idProof1File = file;
          } else if (isId2) {
            widget.memberData.idProof2File = file;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

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
            // Mode indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.memberData.mode == 'existing' ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.memberData.mode == 'existing' ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.memberData.mode == 'existing' ? Icons.history : Icons.person_add,
                    color: widget.memberData.mode == 'existing' ? Colors.blue[700] : Colors.green[700],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.memberData.mode == 'existing'
                          ? 'Mode: Existing Member (No Trial, No Payment Request)'
                          : 'Mode: New Member (Trial Allowed, Payment Request Allowed)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.memberData.mode == 'existing' ? Colors.blue[800] : Colors.green[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Profile Photo Slot
            Center(
              child: GestureDetector(
                onTap: () => _pickImage(true),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: Colors.white,
                      backgroundImage: widget.memberData.profilePhoto != null
                          ? (kIsWeb ? NetworkImage(widget.memberData.profilePhoto!.path) : FileImage(widget.memberData.profilePhoto!) as ImageProvider)
                          : (widget.memberData.existingPhotoUrl != null
                              ? NetworkImage(widget.memberData.existingPhotoUrl!)
                              : null),
                      child: widget.memberData.profilePhoto == null && widget.memberData.existingPhotoUrl == null
                          ? Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                              ),
                              child: const Center(
                                child: Icon(Icons.add_a_photo_outlined, size: 36, color: Color(0xFFE65C00)),
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE65C00),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Full Name Field
            TextField(
              controller: _nameController,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                hintText: 'Enter full name',
              ),
            ),
            const SizedBox(height: 16),

            // Father's Name Field
            TextField(
              controller: _fatherNameController,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              decoration: const InputDecoration(
                labelText: 'Father\'s Name',
                hintText: 'Enter father\'s name',
              ),
            ),
            const SizedBox(height: 16),

            // DOB calendar picker
            InkWell(
              onTap: () async {
                final selected = await showCalendarGridBottomSheet(
                  context,
                  initialDate: widget.memberData.dob ?? DateTime(2000, 1, 1),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (selected != null) {
                  setState(() {
                    widget.memberData.dob = selected;
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of Birth *',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF64748B)),
                ),
                child: Text(
                  widget.memberData.dob != null
                      ? '${widget.memberData.dob!.day}/${widget.memberData.dob!.month}/${widget.memberData.dob!.year}'
                      : 'Select date of birth',
                  style: GoogleFonts.inter(
                    color: widget.memberData.dob != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Gender Dropdown
            DropdownButtonFormField<String>(
              value: widget.memberData.gender,
              decoration: const InputDecoration(labelText: 'Gender *'),
              style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (val) {
                setState(() {
                  widget.memberData.gender = val;
                });
              },
            ),
            const SizedBox(height: 16),

            // Email address with onChanges debounced lookup
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              onChanged: _onEmailChanged,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'name@example.com (autofills if user exists)',
              ),
            ),
            const SizedBox(height: 16),

            // Contact Number
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              decoration: const InputDecoration(
                labelText: 'Contact Number *',
                prefixText: '+91 ',
                hintText: '10 digit mobile number',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            // Address Field
            TextField(
              controller: _addressController,
              maxLines: 2,
              style: GoogleFonts.inter(color: const Color(0xFF1E293B)),
              decoration: const InputDecoration(
                labelText: 'Address *',
                hintText: 'Enter full correspondence address',
              ),
            ),
            const SizedBox(height: 16),

            // Preparing For Dropdown
            DropdownButtonFormField<String>(
              value: widget.memberData.preparingFor,
              decoration: const InputDecoration(labelText: 'Preparing For *'),
              style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
              items: const [
                DropdownMenuItem(value: 'UPSC', child: Text('UPSC')),
                DropdownMenuItem(value: 'NEET', child: Text('NEET')),
                DropdownMenuItem(value: 'JEE', child: Text('JEE')),
                DropdownMenuItem(value: 'SSC', child: Text('SSC')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (val) {
                setState(() {
                  widget.memberData.preparingFor = val;
                });
              },
            ),
            const SizedBox(height: 16),

            // Joining Date picker
            InkWell(
              onTap: () async {
                final selected = await showCalendarGridBottomSheet(
                  context,
                  initialDate: widget.memberData.joiningDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (selected != null) {
                  setState(() {
                    widget.memberData.joiningDate = selected;
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Joining Date *',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF64748B)),
                ),
                child: Text(
                  '${widget.memberData.joiningDate.day}/${widget.memberData.joiningDate.month}/${widget.memberData.joiningDate.year}',
                  style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ID Documents header
            Text(
              'ID Document Verification (At least one required) *',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),

            // Document slot 1
            _buildDocumentSlot(
              slotNum: 1,
              selectedType: widget.memberData.idProof1Type,
              file: widget.memberData.idProof1File,
              onTypeChanged: (type) {
                setState(() {
                  widget.memberData.idProof1Type = type;
                });
              },
              onPick: () => _pickImage(false, isId1: true),
              onClear: () {
                setState(() {
                  widget.memberData.idProof1File = null;
                });
              },
            ),
            const SizedBox(height: 12),

            // Document slot 2
            _buildDocumentSlot(
              slotNum: 2,
              selectedType: widget.memberData.idProof2Type,
              file: widget.memberData.idProof2File,
              onTypeChanged: (type) {
                setState(() {
                  widget.memberData.idProof2Type = type;
                });
              },
              onPick: () => _pickImage(false, isId2: true),
              onClear: () {
                setState(() {
                  widget.memberData.idProof2File = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentSlot({
    required int slotNum,
    required String? selectedType,
    required File? file,
    required ValueChanged<String?> onTypeChanged,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedType ?? (slotNum == 1 ? 'Aadhaar' : 'PAN'),
                  decoration: InputDecoration(
                    labelText: 'Doc $slotNum Type',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'Aadhaar', child: Text('Aadhaar Card')),
                    DropdownMenuItem(value: 'PAN', child: Text('PAN Card')),
                    DropdownMenuItem(value: 'Passport', child: Text('Passport')),
                    DropdownMenuItem(value: 'Driving License', child: Text('Driving License')),
                    DropdownMenuItem(value: 'Student ID', child: Text('Student ID')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: onTypeChanged,
                ),
              ),
              const SizedBox(width: 12),
              if (file == null)
                ElevatedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Pick Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF7ED),
                    foregroundColor: const Color(0xFFE65C00),
                    side: const BorderSide(color: Color(0xFFFFE0C2)),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 24),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
                      onPressed: onClear,
                    ),
                  ],
                ),
            ],
          ),
          if (file != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(
                      file.path,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      file,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
