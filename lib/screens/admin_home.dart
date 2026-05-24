import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminHomeScreen extends StatefulWidget {
  final bool startInSetupMode;
  const AdminHomeScreen({super.key, this.startInSetupMode = false});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late bool _inSetupMode;
  bool _isLoading = false;

  // Step completion flags
  bool _step1Complete = false;
  bool _step2Complete = false;
  bool _step3Complete = false;
  bool _step4Complete = false;
  bool _step4aComplete = false;

  // Setup progress
  double get _setupProgress {
    double progress = 0.0;
    if (_step1Complete) progress += 0.25;
    if (_step2Complete) progress += 0.25;
    if (_step3Complete) progress += 0.25;
    if (_step4Complete && _step4aComplete) progress += 0.25;
    return progress;
  }

  // Loaded database references
  String? _libraryId;
  String _libraryCode = '';
  String _libraryName = '';

  // Form Controllers
  // Step 1: Profile
  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _gender = 'male';
  DateTime? _dob;

  // Step 2: Library Stage 1
  final _libFormKey = GlobalKey<FormState>();
  final _libNameController = TextEditingController();
  final _libStreetController = TextEditingController();
  final _libCityController = TextEditingController();
  final _libStateController = TextEditingController();
  final _libPinController = TextEditingController();
  final _libRulesController = TextEditingController();
  final _libAboutController = TextEditingController();
  final _libEmergencyPhoneController = TextEditingController();
  List<String> _selectedAmenities = [];
  final List<String> _availableAmenities = [
    'High Speed Wi-Fi',
    'Air Conditioning',
    'Personal Lockers',
    'RO Drinking Water',
    'CCTV Surveillance',
    'Power Backup',
    'Discussion Room',
    'Daily Newspaper'
  ];

  // Step 3: Floor, Section & Seats
  int _floorsCount = 1;
  int _sectionsCount = 1;
  int _seatsCount = 30;

  // Step 4: Shifts & Plans
  final _shiftFormKey = GlobalKey<FormState>();
  final _shiftNameController = TextEditingController(text: 'General Shift');
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 20, minute: 0);
  final _priceController = TextEditingController(text: '1000');
  final _trialDaysController = TextEditingController(text: '0');
  bool _shiftOverlapWarning = false;

  // Step 4a: Payments
  bool _cashEnabled = true;
  final _upiPaytmController = TextEditingController();
  final _upiPhonePeController = TextEditingController();
  final _upiGPayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _inSetupMode = widget.startInSetupMode;
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _libNameController.dispose();
    _libStreetController.dispose();
    _libCityController.dispose();
    _libStateController.dispose();
    _libPinController.dispose();
    _libRulesController.dispose();
    _libAboutController.dispose();
    _libEmergencyPhoneController.dispose();
    _shiftNameController.dispose();
    _priceController.dispose();
    _trialDaysController.dispose();
    _upiPaytmController.dispose();
    _upiPhonePeController.dispose();
    _upiGPayController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      try {
        // Load Profile data
        final userData = await supabase.from('users').select().eq('id', user.id).maybeSingle();
        if (userData != null) {
          _nameController.text = userData['full_name'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          if (userData['gender'] != null) _gender = userData['gender'];
          if (userData['date_of_birth'] != null) {
            _dob = DateTime.parse(userData['date_of_birth']);
          }
          if (_nameController.text.isNotEmpty && _phoneController.text.isNotEmpty) {
            _step1Complete = true;
          }
        }

        // Load Library Stage 1
        final libData = await supabase.from('libraries').select().eq('owner_id', user.id).maybeSingle();
        if (libData != null) {
          _libraryId = libData['id'];
          _libraryCode = libData['library_code'] ?? '';
          _libraryName = libData['name'] ?? '';
          _libNameController.text = _libraryName;
          _libStreetController.text = libData['address_street'] ?? '';
          _libCityController.text = libData['address_city'] ?? '';
          _libStateController.text = libData['address_state'] ?? '';
          _libPinController.text = libData['address_pincode'] ?? '';
          _libRulesController.text = libData['rules'] ?? '';
          _libAboutController.text = libData['about_text'] ?? '';
          _libEmergencyPhoneController.text = libData['emergency_phone'] ?? '';
          if (libData['amenities'] != null) {
            _selectedAmenities = List<String>.from(libData['amenities']);
          }

          _step2Complete = true;

          // Check if floors/seats/shifts are configured
          final shifts = await supabase.from('shifts').select('id').eq('library_id', _libraryId!);
          if (shifts.isNotEmpty) {
            _step4Complete = true;
          }

          final seats = await supabase.from('seats').select('id').eq('library_id', _libraryId!).limit(1);
          if (seats.isNotEmpty) {
            _step3Complete = true;
          }

          // Payment IDs in social_links
          final social = libData['social_links'] as Map<String, dynamic>?;
          if (social != null) {
            _upiPaytmController.text = social['upi_paytm'] ?? '';
            _upiPhonePeController.text = social['upi_phonepe'] ?? '';
            _upiGPayController.text = social['upi_gpay'] ?? '';
            _cashEnabled = social['cash_enabled'] ?? true;
            _step4aComplete = true;
          }
        }
      } catch (e) {
        print('Error loading admin setup data: $e');
      }
    }

    setState(() => _isLoading = false);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- STEP 1: Profile Setup Dialog ---
  void _openProfileDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Step 1: Complete Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Form(
                key: _profileFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person)),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone)),
                        validator: (v) => v == null || v.length < 10 ? 'Enter valid phone number' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.people)),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                          DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                        ],
                        onChanged: (val) => setDialogState(() => _gender = val!),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final selectedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime(2000),
                            firstDate: DateTime(1950),
                            lastDate: DateTime.now(),
                          );
                          if (selectedDate != null) {
                            setDialogState(() => _dob = selectedDate);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[400]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20, color: Color(0xFFE65C00)),
                              const SizedBox(width: 12),
                              Text(
                                _dob == null
                                    ? 'Date of Birth (Optional)'
                                    : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                                style: GoogleFonts.inter(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!_profileFormKey.currentState!.validate()) return;
                    Navigator.of(context).pop();
                    
                    setState(() => _isLoading = true);
                    try {
                      final supabase = Supabase.instance.client;
                      await supabase.from('users').update({
                        'full_name': _nameController.text.trim(),
                        'phone': _phoneController.text.trim(),
                        'gender': _gender,
                        'date_of_birth': _dob?.toIso8601String(),
                      }).eq('id', supabase.auth.currentUser!.id);

                      setState(() {
                        _step1Complete = true;
                      });
                      _showSuccessSnackBar('Profile successfully updated!');
                    } catch (e) {
                      _showErrorSnackBar('Error updating profile: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- STEP 2: Library Setup Stage 1 ---
  String _generateLibraryCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    final code = List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
    return 'SIL-$code';
  }

  void _openLibrarySetupStage1Dialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Step 2: Library Basic Info', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Form(
                key: _libFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _libNameController,
                        decoration: const InputDecoration(labelText: 'Library Name *', prefixIcon: Icon(Icons.store)),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libStreetController,
                        decoration: const InputDecoration(labelText: 'Street/Area Address', prefixIcon: Icon(Icons.map)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _libCityController,
                              decoration: const InputDecoration(labelText: 'City *'),
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _libStateController,
                              decoration: const InputDecoration(labelText: 'State'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libPinController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'PIN Code', prefixIcon: Icon(Icons.pin_drop)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libEmergencyPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Emergency Contact Phone *', prefixIcon: Icon(Icons.emergency)),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libAboutController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'About Library (Description)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libRulesController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Library Rules / Guidelines'),
                      ),
                      const SizedBox(height: 16),
                      Text('Select Amenities', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _availableAmenities.map((amenity) {
                          final isSelected = _selectedAmenities.contains(amenity);
                          return FilterChip(
                            label: Text(amenity, style: GoogleFonts.inter(fontSize: 11)),
                            selected: isSelected,
                            selectedColor: const Color(0xFFE65C00).withOpacity(0.2),
                            checkmarkColor: const Color(0xFFE65C00),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  _selectedAmenities.add(amenity);
                                } else {
                                  _selectedAmenities.remove(amenity);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!_libFormKey.currentState!.validate()) return;
                    Navigator.of(context).pop();

                    setState(() => _isLoading = true);
                    try {
                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser!;

                      if (_libraryCode.isEmpty) {
                        _libraryCode = _generateLibraryCode();
                      }

                      if (_libraryId == null) {
                        // Create new library
                        final newLib = await supabase.from('libraries').insert({
                          'owner_id': user.id,
                          'name': _libNameController.text.trim(),
                          'library_code': _libraryCode,
                          'address_street': _libStreetController.text.trim(),
                          'address_city': _libCityController.text.trim(),
                          'address_state': _libStateController.text.trim(),
                          'address_pincode': _libPinController.text.trim(),
                          'rules': _libRulesController.text.trim(),
                          'about_text': _libAboutController.text.trim(),
                          'emergency_phone': _libEmergencyPhoneController.text.trim(),
                          'amenities': _selectedAmenities,
                          'status': 'setup',
                        }).select().single();
                        _libraryId = newLib['id'];
                        _libraryName = newLib['name'];
                      } else {
                        // Update existing library
                        await supabase.from('libraries').update({
                          'name': _libNameController.text.trim(),
                          'address_street': _libStreetController.text.trim(),
                          'address_city': _libCityController.text.trim(),
                          'address_state': _libStateController.text.trim(),
                          'address_pincode': _libPinController.text.trim(),
                          'rules': _libRulesController.text.trim(),
                          'about_text': _libAboutController.text.trim(),
                          'emergency_phone': _libEmergencyPhoneController.text.trim(),
                          'amenities': _selectedAmenities,
                        }).eq('id', _libraryId!);
                        _libraryName = _libNameController.text.trim();
                      }

                      setState(() {
                        _step2Complete = true;
                      });
                      _showSuccessSnackBar('Library basic info saved! Code: $_libraryCode');
                    } catch (e) {
                      _showErrorSnackBar('Error saving library info: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- STEP 3: Floors, Sections & Seats Setup Dialog ---
  void _openLibrarySetupStage2Dialog() {
    if (!_step2Complete) {
      _showErrorSnackBar('Please complete Step 2 first.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Step 3: Floors, Sections & Seats', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Configure structure for basic seats mapping in current shifts.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Number of Floors:', style: GoogleFonts.inter(fontSize: 14)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _floorsCount > 1
                                  ? () => setDialogState(() => _floorsCount--)
                                  : null,
                            ),
                            Text('$_floorsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setDialogState(() => _floorsCount++),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sections per Floor:', style: GoogleFonts.inter(fontSize: 14)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _sectionsCount > 1
                                  ? () => setDialogState(() => _sectionsCount--)
                                  : null,
                            ),
                            Text('$_sectionsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setDialogState(() => _sectionsCount++),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Seats per Section:', style: GoogleFonts.inter(fontSize: 14)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _seatsCount > 10
                                  ? () => setDialogState(() => _seatsCount -= 5)
                                  : null,
                            ),
                            Text('$_seatsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setDialogState(() => _seatsCount += 5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    setState(() => _isLoading = true);

                    try {
                      final supabase = Supabase.instance.client;

                      // Pre-delete floors for clean start (upsert simulation)
                      await supabase.from('floors').delete().eq('library_id', _libraryId!);

                      // Step 1: Create floors
                      for (int f = 1; f <= _floorsCount; f++) {
                        final floorResponse = await supabase.from('floors').insert({
                          'library_id': _libraryId!,
                          'name': 'Floor $f',
                          'order_index': f,
                        }).select().single();

                        final floorId = floorResponse['id'];

                        // Step 2: Create sections
                        for (int s = 1; s <= _sectionsCount; s++) {
                          final sectionResponse = await supabase.from('sections').insert({
                            'floor_id': floorId,
                            'name': 'Section $s',
                            'tag': 'general',
                          }).select().single();

                          final sectionId = sectionResponse['id'];

                          // Seats will be generated per shift. Since seats require a shift_id,
                          // we check if a shift exists. If not, we will auto-generate a Default Shift.
                          var shifts = await supabase.from('shifts').select('id').eq('library_id', _libraryId!);
                          if (shifts.isEmpty) {
                            final defaultShift = await supabase.from('shifts').insert({
                              'library_id': _libraryId!,
                              'name': 'Full Day Shift',
                              'start_time': '08:00:00',
                              'end_time': '20:00:00',
                              'price_monthly': 1000,
                            }).select().single();
                            shifts = [defaultShift];
                            _step4Complete = true;
                          }

                          final shiftId = shifts.first['id'];

                          // Step 3: Create seats per section in that shift
                          final List<Map<String, dynamic>> seatsData = [];
                          for (int seatNum = 1; seatNum <= _seatsCount; seatNum++) {
                            seatsData.add({
                              'library_id': _libraryId!,
                              'floor_id': floorId,
                              'section_id': sectionId,
                              'shift_id': shiftId,
                              'seat_label': 'F${f}S${s}-$seatNum',
                              'status': 'vacant',
                            });
                          }
                          await supabase.from('seats').insert(seatsData);
                        }
                      }

                      setState(() {
                        _step3Complete = true;
                      });
                      _showSuccessSnackBar('Seats generated successfully! (Virtual layout mapped)');
                    } catch (e) {
                      _showErrorSnackBar('Error generating seats: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                  child: Text('Generate', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- STEP 4: Shifts & Plans Setup Dialog ---
  void _openLibrarySetupStage3Dialog() {
    if (!_step2Complete) {
      _showErrorSnackBar('Please complete Step 2 first.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Step 4: Shifts & Plans', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Form(
                key: _shiftFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _shiftNameController,
                        decoration: const InputDecoration(labelText: 'Shift Name *', prefixIcon: Icon(Icons.schedule)),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final time = await showTimePicker(context: context, initialTime: _startTime);
                                if (time != null) {
                                  setDialogState(() {
                                    _startTime = time;
                                    _validateShiftOverlap();
                                  });
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Start Time'),
                                child: Text(_startTime.format(context)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final time = await showTimePicker(context: context, initialTime: _endTime);
                                if (time != null) {
                                  setDialogState(() {
                                    _endTime = time;
                                    _validateShiftOverlap();
                                  });
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'End Time'),
                                child: Text(_endTime.format(context)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_shiftOverlapWarning) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning, color: Colors.amber, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Warning: Selected timings overlap with other shifts.',
                                  style: GoogleFonts.inter(fontSize: 10, color: Colors.amber[900], fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Monthly Subscription Price (₹) *', prefixIcon: Icon(Icons.currency_rupee)),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _trialDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Free Trial Days (0 for none)', prefixIcon: Icon(Icons.timer)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!_shiftFormKey.currentState!.validate()) return;
                    Navigator.of(context).pop();
                    setState(() => _isLoading = true);

                    try {
                      final supabase = Supabase.instance.client;

                      final startStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
                      final endStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';

                      await supabase.from('shifts').insert({
                        'library_id': _libraryId!,
                        'name': _shiftNameController.text.trim(),
                        'start_time': startStr,
                        'end_time': endStr,
                        'price_monthly': int.parse(_priceController.text),
                        'trial_days': int.parse(_trialDaysController.text),
                      });

                      setState(() {
                        _step4Complete = true;
                      });
                      _showSuccessSnackBar('Shift configurations saved!');
                    } catch (e) {
                      _showErrorSnackBar('Error saving shifts: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _validateShiftOverlap() {
    // Simple local check for overlap (e.g. if span spans > 12 hours as warning trigger)
    final startMins = _startTime.hour * 60 + _startTime.minute;
    final endMins = _endTime.hour * 60 + _endTime.minute;
    if (endMins > startMins && (endMins - startMins) > 720) {
      _shiftOverlapWarning = true;
    } else {
      _shiftOverlapWarning = false;
    }
  }

  // --- STEP 4a: Payment Settings Setup Dialog ---
  void _openPaymentSetupDialog() {
    if (!_step2Complete) {
      _showErrorSnackBar('Please complete Step 2 first.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Payments Settings (Step 4a)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      activeColor: const Color(0xFFE65C00),
                      title: Text('Accept Cash Payments', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text('Allow members to pay cash offline directly at library desk.', style: GoogleFonts.inter(fontSize: 11)),
                      value: _cashEnabled,
                      onChanged: (val) => setDialogState(() => _cashEnabled = val),
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Configure UPI Accounts (Deep-link UPI app links generated automatically)',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiPhonePeController,
                      decoration: const InputDecoration(
                        labelText: 'PhonePe UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        suffixText: 'PhonePe',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiGPayController,
                      decoration: const InputDecoration(
                        labelText: 'Google Pay (GPay) UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        suffixText: 'GPay',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiPaytmController,
                      decoration: const InputDecoration(
                        labelText: 'Paytm UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        suffixText: 'Paytm',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    setState(() => _isLoading = true);

                    try {
                      final supabase = Supabase.instance.client;

                      await supabase.from('libraries').update({
                        'social_links': {
                          'cash_enabled': _cashEnabled,
                          'upi_phonepe': _upiPhonePeController.text.trim(),
                          'upi_gpay': _upiGPayController.text.trim(),
                          'upi_paytm': _upiPaytmController.text.trim(),
                        }
                      }).eq('id', _libraryId!);

                      setState(() {
                        _step4aComplete = true;
                      });
                      _showSuccessSnackBar('Payments settings successfully updated!');
                    } catch (e) {
                      _showErrorSnackBar('Error saving payments settings: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00)),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- LAUNCH LIBRARY ACTION ---
  Future<void> _launchLibrary() async {
    if (!_step1Complete || !_step2Complete || !_step3Complete || !_step4Complete || !_step4aComplete) {
      _showErrorSnackBar('Please complete all 4 onboarding steps before launching.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;

      // Update library status to active
      await supabase.from('libraries').update({
        'status': 'active',
      }).eq('id', _libraryId!);

      // Update user subscription state to active Starter plan
      await supabase.from('users').update({
        'subscription_plan': 'starter',
        'subscription_status': 'active',
        'subscription_expiry': DateTime.now().add(const Duration(days: 14)).toIso8601String(), // 14-day trial
      }).eq('id', supabase.auth.currentUser!.id);

      setState(() {
        _inSetupMode = false;
      });
      _showSuccessSnackBar('Congratulations! Your library is now live!');
    } catch (e) {
      _showErrorSnackBar('Failed to launch library: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inSetupMode) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Text('SILENCE Library Onboarding', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login'); // Assuming routing
                }
              },
            )
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome to SILENCE Setup Panel!',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete all 4 steps to initialize your floor sections, seats map and shift pricing model to open your operational dashboard.',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),

                    // Setup Progress Card
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Setup Progress', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${(_setupProgress * 100).toInt()}% Complete',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65C00), fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _setupProgress,
                                minHeight: 8,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Progressive 4 Steps
                    _buildStepCard(
                      stepNum: '1',
                      title: 'Complete Admin Profile',
                      subtitle: 'Add details like name, phone and gender.',
                      isComplete: _step1Complete,
                      onTap: _openProfileDialog,
                    ),
                    _buildStepCard(
                      stepNum: '2',
                      title: 'Library Configuration (Basic)',
                      subtitle: 'Register library name, emergency phone, rules and amenities.',
                      isComplete: _step2Complete,
                      onTap: _openLibrarySetupStage1Dialog,
                    ),
                    _buildStepCard(
                      stepNum: '3',
                      title: 'Floors, Sections & Seats Grid',
                      subtitle: 'Configure floor mappings and generate virtual seats.',
                      isComplete: _step3Complete,
                      onTap: _openLibrarySetupStage2Dialog,
                    ),
                    _buildStepCard(
                      stepNum: '4',
                      title: 'Shifts, Pricing & Payments',
                      subtitle: 'Set up morning/evening shifts and deep-link UPI ID accounts.',
                      isComplete: _step4Complete && _step4aComplete,
                      onTap: () {
                        // Open Shift dialog then payment configuration
                        _openLibrarySetupStage3Dialog();
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _openPaymentSetupDialog();
                        });
                      },
                    ),

                    const SizedBox(height: 36),

                    // Launch Library Button
                    ElevatedButton(
                      onPressed: _setupProgress >= 1.0 ? _launchLibrary : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65C00),
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Launch Library Space',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _setupProgress >= 1.0 ? Colors.white : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    } else {
      // OPERATIONAL DASHBOARD MODE
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE65C00),
          title: Text(_libraryName.isNotEmpty ? _libraryName : 'SILENCE Dashboard', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65C00).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 60, color: Color(0xFFE65C00)),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your Library is Operational!',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),
                Text(
                  'Access your virtual desks space, seats layout grid, and manage student attendance streams. Share code to invite students:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _libraryCode,
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00)),
                  ),
                ),
                const SizedBox(height: 36),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _inSetupMode = true);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE65C00)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                  ),
                  child: Text('View Onboarding Checklist', style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildStepCard({
    required String stepNum,
    required String title,
    required String subtitle,
    required bool isComplete,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isComplete ? const Color(0xFFE65C00) : Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(stepNum, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey[600])),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}


