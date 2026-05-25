import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:silence/core/calendar_picker.dart';

class AdminHomeScreen extends StatefulWidget {
  final bool startInSetupMode;
  const AdminHomeScreen({super.key, this.startInSetupMode = false});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late bool _inSetupMode;
  bool _isLoading = false;
  int _currentTab = 0; // Stateful Bottom Navigation Bar index

  // Step completion flags
  bool _step1Complete = false;
  bool _step2Complete = false;
  bool _step3Complete = false;
  bool _step4Complete = false;
  bool _step4aComplete = false;

  // Onboarding status text helper
  int get _stepsDoneCount {
    int count = 0;
    if (_step1Complete) count++;
    if (_step2Complete) count++;
    if (_step3Complete) count++;
    if (_step4Complete && _step4aComplete) count++;
    return count;
  }

  // Setup progress ratio
  double get _setupProgress {
    return _stepsDoneCount / 4.0;
  }

  // Loaded database references
  String? _libraryId;
  String _libraryCode = 'SIL-DTW-4829';
  String _libraryName = 'SILENCE Study Zone';
  String _libraryAddress = '123 Main Market, Sector 15, Your City';

  // Stats Counters
  int _totalMembers = 0;
  int _activeMembers = 0;
  int _totalSeats = 0;
  int _todayBookings = 0;
  int _pendingBookings = 0;

  // Form Controllers & State
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
          _libraryCode = libData['library_code'] ?? 'SIL-DTW-4829';
          _libraryName = libData['name'] ?? 'SILENCE Study Zone';
          
          final String street = libData['address_street'] ?? '';
          final String city = libData['address_city'] ?? 'Your City';
          _libraryAddress = street.isNotEmpty ? '$street, $city' : '123 Main Market, Sector 15, $city';

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

          final seats = await supabase.from('seats').select('id').eq('library_id', _libraryId!);
          if (seats.isNotEmpty) {
            _step3Complete = true;
            _totalSeats = seats.length;
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
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFE65C00),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatSpacedCode(String code) {
    return code.split('').join(' ');
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
              title: Text('Complete Admin Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Form(
                key: _profileFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person, color: Color(0xFFE65C00))),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone, color: Color(0xFFE65C00))),
                        validator: (v) => v == null || v.length < 10 ? 'Enter valid phone number' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.people, color: Color(0xFFE65C00))),
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
                          final selectedDate = await showCalendarGridBottomSheet(
                            context,
                            initialDate: _dob ?? DateTime(2000),
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
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20, color: Color(0xFFE65C00)),
                              const SizedBox(width: 12),
                              Text(
                                _dob == null
                                    ? 'Date of Birth (Optional)'
                                    : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700]),
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
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
              title: Text('Configure Library Basic Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Form(
                key: _libFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _libNameController,
                        decoration: const InputDecoration(labelText: 'Library Name *', prefixIcon: Icon(Icons.store, color: Color(0xFFE65C00))),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libStreetController,
                        decoration: const InputDecoration(labelText: 'Street/Area Address', prefixIcon: Icon(Icons.map, color: Color(0xFFE65C00))),
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
                        decoration: const InputDecoration(labelText: 'PIN Code', prefixIcon: Icon(Icons.pin_drop, color: Color(0xFFE65C00))),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libEmergencyPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Emergency Contact Phone *', prefixIcon: Icon(Icons.emergency, color: Color(0xFFE65C00))),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _libAboutController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'About Library (Description)'),
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
                            selectedColor: const Color(0xFFE65C00).withOpacity(0.15),
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
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!_libFormKey.currentState!.validate()) return;
                    Navigator.of(context).pop();

                    setState(() => _isLoading = true);
                    try {
                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser!;

                      if (_libraryCode.isEmpty || _libraryCode == 'SIL-DTW-4829') {
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
                      _showSuccessSnackBar('Library details saved! Code: $_libraryCode');
                    } catch (e) {
                      _showErrorSnackBar('Error saving library details: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
      _showErrorSnackBar('Please complete Step 2 (Library Details) first.');
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
              title: Text('Layout Setup (Floors & Seats)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Configure floors, sections and generate physical seats in shifts.',
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
                              icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE65C00)),
                              onPressed: _floorsCount > 1
                                  ? () => setDialogState(() => _floorsCount--)
                                  : null,
                            ),
                            Text('$_floorsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE65C00)),
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
                              icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE65C00)),
                              onPressed: _sectionsCount > 1
                                  ? () => setDialogState(() => _sectionsCount--)
                                  : null,
                            ),
                            Text('$_sectionsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE65C00)),
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
                              icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE65C00)),
                              onPressed: _seatsCount > 10
                                  ? () => setDialogState(() => _seatsCount -= 5)
                                  : null,
                            ),
                            Text('$_seatsCount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE65C00)),
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
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
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
                        _totalSeats = _floorsCount * _sectionsCount * _seatsCount;
                      });
                      _showSuccessSnackBar('Seats generated successfully! (Virtual layout mapped)');
                    } catch (e) {
                      _showErrorSnackBar('Error generating seats: $e');
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Generate', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
              title: Text('Customise Shift timings & Plans', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Form(
                key: _shiftFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _shiftNameController,
                        decoration: const InputDecoration(labelText: 'Shift Name *', prefixIcon: Icon(Icons.schedule, color: Color(0xFFE65C00))),
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
                        decoration: const InputDecoration(labelText: 'Monthly Subscription Price (₹) *', prefixIcon: Icon(Icons.currency_rupee, color: Color(0xFFE65C00))),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _trialDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Free Trial Days (0 for none)', prefixIcon: Icon(Icons.timer, color: Color(0xFFE65C00))),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _validateShiftOverlap() {
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
              title: Text('Payments Configuration', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
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
                      'Configure UPI Accounts (deep-link icons generated on invoice screen)',
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiPhonePeController,
                      decoration: const InputDecoration(
                        labelText: 'PhonePe UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFE65C00)),
                        suffixText: 'PhonePe',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiGPayController,
                      decoration: const InputDecoration(
                        labelText: 'Google Pay (GPay) UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFE65C00)),
                        suffixText: 'GPay',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _upiPaytmController,
                      decoration: const InputDecoration(
                        labelText: 'Paytm UPI ID',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFE65C00)),
                        suffixText: 'Paytm',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.bold)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
    if (_stepsDoneCount < 4) {
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
      _showSuccessSnackBar('Congratulations! Your library space is now operational!');
    } catch (e) {
      _showErrorSnackBar('Failed to launch library space: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- SUB-VIEWS BUILDERS (TABS) ---

  // TAB 0: HOME / DASHBOARD TAB
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Curved Gradient Banner Header (Matching Image 2)
          _buildCurvedHeader(),

          // 2. Onboarding Setup Card OR Operational Dashboard (Below Banner)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_inSetupMode) ...[
                  // Checklist Onboarding Card
                  _buildSetupOnboardingCard(),
                  const SizedBox(height: 16),
                  // Monospaced Code Card
                  _buildInvitationCodeCard(),
                  const SizedBox(height: 20),
                  // Statistics Grid Card (Inspired by bottom grid in Image 2)
                  _buildStatisticsGrid(),
                ] else ...[
                  // S010-B Operational Dashboard
                  _buildOperationalDashboard(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 4: MORE / LIBRARY SETTINGS & PROFILE TAB (Inspired by Image 1)
  Widget _buildMoreTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Covers Photo, Profile Pic, Title & Badges
          _buildLibraryProfileCard(),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Action Outline Buttons
                _buildProfileActionsRow(),
                const SizedBox(height: 20),

                // Progress Card
                _buildProfileCompletionCard(),
                const SizedBox(height: 20),

                // About Library Section
                _buildAboutLibraryCard(),
                const SizedBox(height: 20),

                // Micro stats row (120+ Members, 85% Occupancy, etc.)
                _buildMicroStatsRow(),
                const SizedBox(height: 24),

                // Settings List Items with Rounded Square Color Background Icons
                Text(
                  'Choose a section to edit',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),
                _buildSettingListItem(
                  icon: Icons.portrait,
                  title: 'Cover Photo & Gallery',
                  subtitle: 'Edit cover image and photo banners',
                  color: Colors.red[400]!,
                  onTap: () => _showSuccessSnackBar('Banners setup coming soon!'),
                ),
                _buildSettingListItem(
                  icon: Icons.info_outline,
                  title: 'Library Information',
                  subtitle: 'Edit name, address, emergency call lines',
                  color: Colors.blue[400]!,
                  onTap: _openLibrarySetupStage1Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.description_outlined,
                  title: 'About Library',
                  subtitle: 'Edit highlighting description texts',
                  color: Colors.deepPurple[400]!,
                  onTap: _openLibrarySetupStage1Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.checklist_rtl_rounded,
                  title: 'Amenities',
                  subtitle: 'Manage desk features and facilities list',
                  color: Colors.amber[600]!,
                  onTap: _openLibrarySetupStage1Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.access_time_outlined,
                  title: 'Timings & Shifts',
                  subtitle: 'Modify operational timings and hours configuration',
                  color: Colors.orange[400]!,
                  onTap: _openLibrarySetupStage3Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.receipt_long_outlined,
                  title: 'Membership Plans',
                  subtitle: 'Add pricing configuration and trial rules',
                  color: Colors.teal[400]!,
                  onTap: _openLibrarySetupStage3Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.rule_outlined,
                  title: 'Rules & Guidelines',
                  subtitle: 'Enforce study library code of conduct',
                  color: Colors.pink[400]!,
                  onTap: _openLibrarySetupStage1Dialog,
                ),
                _buildSettingListItem(
                  icon: Icons.link_outlined,
                  title: 'Social Links',
                  subtitle: 'Link Instagram, Whatsapp and emergency deep-links',
                  color: Colors.red[600]!,
                  onTap: _openPaymentSetupDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SUB-WIDGETS BUILDERS ---

  Widget _buildCurvedHeader() {
    final todayFormatted = DateFormat('EEE, d MMM').format(DateTime.now()).toUpperCase();
    
    return Container(
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF6B00), // Vibrant Bright Orange
            Color(0xFFE65C00), // Primary Brand Orange
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Circular Library Logo Picture
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                  color: Colors.white,
                  image: const DecorationImage(
                    image: AssetImage('assets/images/LOGO.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Library Dropdown Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _libraryName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white70, size: 12),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _libraryAddress,
                            style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white.withOpacity(0.85)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Date Pill Widget
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.0),
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      todayFormatted,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Greeting line
          Text(
            'Good morning, Demo 👏',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Here's what's happening today.",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupOnboardingCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFE65C00), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Complete Library setup',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                ),
                Text(
                  '$_stepsDoneCount/4 done',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _setupProgress,
                minHeight: 6,
                backgroundColor: Colors.grey[100],
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
              ),
            ),
            const SizedBox(height: 16),

            // Step List items
            _buildSetupStepItem(
              stepNum: 1,
              title: 'Admin Profile',
              subtitle: 'Add your personal details',
              isDone: _step1Complete,
              onTap: _openProfileDialog,
            ),
            _buildSetupStepItem(
              stepNum: 2,
              title: 'Library Basic Details',
              subtitle: 'Add library info & photos',
              isDone: _step2Complete,
              onTap: _openLibrarySetupStage1Dialog,
            ),
            _buildSetupStepItem(
              stepNum: 3,
              title: 'Shift & Plans',
              subtitle: 'Add shifts, plans & payment',
              isDone: _step4Complete && _step4aComplete,
              onTap: () {
                _openLibrarySetupStage3Dialog();
                Future.delayed(const Duration(milliseconds: 300), () {
                  _openPaymentSetupDialog();
                });
              },
            ),
            _buildSetupStepItem(
              stepNum: 4,
              title: 'Layout Setup',
              subtitle: 'Add floors, sections & seats',
              isDone: _step3Complete,
              onTap: _openLibrarySetupStage2Dialog,
            ),

            const SizedBox(height: 18),

            // Launch Library Button
            ElevatedButton(
              onPressed: _stepsDoneCount >= 4 ? _launchLibrary : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                disabledBackgroundColor: Colors.grey[200],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                'Launch Library',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _stepsDoneCount >= 4 ? Colors.white : Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupStepItem({
    required int stepNum,
    required String title,
    required String subtitle,
    required bool isDone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? const Color(0xFFE65C00).withOpacity(0.12) : Colors.transparent,
                border: Border.all(
                  color: isDone ? const Color(0xFFE65C00) : Colors.grey[300]!,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 16, color: Color(0xFFE65C00))
                    : Text(
                        '$stepNum',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 13),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationCodeCard() {
    final spacedCode = _formatSpacedCode(_libraryCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library Code',
                style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey[500], fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                spacedCode,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65C00),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => _showSuccessSnackBar('Library Code copied to clipboard!'),
            icon: const Icon(Icons.share, size: 16, color: Color(0xFFE65C00)),
            label: Text('Share', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: const Color(0xFFE65C00).withOpacity(0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          )
        ],
      ),
    );
  }

  // State variables for Operational Mode Dashboard
  int _carouselIndex = 0;
  String _selectedShiftFilter = 'All';

  final List<Map<String, String>> _mockAttendance = [
    {'name': 'Arjun', 'time': '09:15 AM', 'seat': 'G-12', 'status': 'in'},
    {'name': 'Sana', 'time': '10:02 AM', 'seat': 'A-05', 'status': 'in'},
    {'name': 'Rohan', 'time': '08:45 AM', 'seat': 'B-21', 'status': 'in'},
    {'name': 'Ananya', 'time': '11:15 AM', 'seat': 'C-02', 'status': 'in'},
    {'name': 'Vikram', 'time': '05:30 PM', 'seat': 'G-08', 'status': 'out'},
    {'name': 'Kabir', 'time': '09:00 AM', 'seat': 'D-15', 'status': 'expired'},
  ];

  final List<Map<String, dynamic>> _mockActivities = [
    {'type': 'in', 'desc': 'Arjun checked in – Seat G-12', 'time': '5 min ago'},
    {'type': 'req', 'desc': 'New join request from Sana', 'time': '2 hours ago'},
    {'type': 'pay', 'desc': 'Payment of ₹1,500 under review', 'time': '3 hours ago'},
    {'type': 'out', 'desc': 'Vikram checked out – Seat G-08', 'time': '4 hours ago'},
  ];

  Widget _buildOperationalDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Photo Carousel
        _buildPhotoCarousel(),
        const SizedBox(height: 16),

        // 2. Library Code Card
        _buildInvitationCodeCard(),
        const SizedBox(height: 20),

        // 3. Stats Section (Revenue, 2x2 grid, Live Occupancy)
        _buildOperationalStatsSection(),
        const SizedBox(height: 20),

        // 4. Action Required Banner (Conditional)
        _buildActionRequiredBanner(),
        const SizedBox(height: 20),

        // 5. Quick Actions Row
        _buildQuickActionsRow(),
        const SizedBox(height: 20),

        // 6. QR Codes Row (separate row below Quick Actions)
        _buildQRCodesRow(),
        const SizedBox(height: 20),

        // 7. Attendance Strip
        _buildAttendanceStrip(),
        const SizedBox(height: 20),

        // 8. Recent Activities Feed
        _buildRecentActivityFeed(),
      ],
    );
  }

  Widget _buildPhotoCarousel() {
    final List<String> carouselTitles = [
      'Silent Reading Zone',
      'Discussion Lounge',
      'Personal Locker Section',
    ];
    final List<List<Color>> carouselGradients = [
      [const Color(0xFFFF6B00), const Color(0xFFC44E00)],
      [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
      [const Color(0xFF10B981), const Color(0xFF047857)],
    ];

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView.builder(
            itemCount: 3,
            onPageChanged: (index) {
              setState(() {
                _carouselIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: carouselGradients[index],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.1,
                        child: Image.asset(
                          'assets/images/horizontal app logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Downtown Branch',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            carouselTitles[index],
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Premium ergonomically designed desking space',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _carouselIndex == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _carouselIndex == index
                    ? const Color(0xFFE65C00)
                    : const Color(0xFFE5E7EB),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildOperationalStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Revenue Card (Full Width)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '💰 Revenue This Month',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _currentTab = 2), // Go to Bookings/Analytics
                    child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '₹24,500',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  Text(
                    '+₹1,200 today',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF9CA3AF), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Text(
                    '₹3,200 pending',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 2x2 Stats Grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _buildOperationalStatCard(
              label: 'Active Today',
              value: '42',
              subtext: '/ 85 members',
              icon: Icons.people,
              iconColor: const Color(0xFF3B82F6),
            ),
            _buildOperationalStatCard(
              label: 'Expired',
              value: '8',
              subtext: 'needs renewal',
              icon: Icons.person_off,
              iconColor: const Color(0xFFEF4444),
            ),
            _buildOperationalStatCard(
              label: 'New Joinings',
              value: '12',
              subtext: 'this month',
              icon: Icons.person_add,
              iconColor: const Color(0xFF10B981),
            ),
            _buildOperationalStatCard(
              label: 'Expiring Soon',
              value: '5',
              subtext: 'within 7 days',
              icon: Icons.running_with_errors,
              iconColor: const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3. Live Occupancy donut (Full Width)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔵 Live Occupancy',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: 0.73,
                          strokeWidth: 10,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                        ),
                      ),
                      Text(
                        '73%',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(
                              'Occupied: 73 seats',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE5E7EB), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(
                              'Vacant: 27 seats',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalStatCard({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF9CA3AF)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
              Text(
                subtext,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionRequiredBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7), // Light amber
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: Color(0xFFF59E0B), width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 8),
              Text(
                'Action Required',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildActionRequiredRow('3 payment proofs pending review'),
          const Divider(color: Color(0xFFFCD34D), height: 12),
          _buildActionRequiredRow('2 join requests pending'),
        ],
      ),
    );
  }

  Widget _buildActionRequiredRow(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF92400E),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF92400E)),
      ],
    );
  }

  Widget _buildQuickActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildCircularActionButton(
              icon: Icons.person_add,
              label: 'Add Member',
              color: const Color(0xFF3B82F6), // Blue
              onTap: () => _showSuccessSnackBar('Add Member coming soon in Milestone 3!'),
            ),
            _buildCircularActionButton(
              icon: Icons.campaign,
              label: 'Announce',
              color: const Color(0xFF8B5CF6), // Purple
              onTap: () => _showSuccessSnackBar('Announcement composer coming in Milestone 3!'),
            ),
            _buildCircularActionButton(
              icon: Icons.chat_bubble,
              label: 'Queries',
              color: const Color(0xFF06B6D4), // Teal
              onTap: () => _showSuccessSnackBar('Manage Queries coming in Milestone 3!'),
            ),
            _buildCircularActionButton(
              icon: Icons.power_settings_new,
              label: 'Close Library',
              color: const Color(0xFFE65C00), // Orange
              onTap: () => _showSuccessSnackBar('Close Library action coming soon!'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF374151),
          ),
        ),
      ],
    );
  }

  Widget _buildQRCodesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QR Codes',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQRCard(
                title: 'Joining QR',
                description: 'Scan to apply & register',
                icon: Icons.person_add_alt_1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQRCard(
                title: 'Attendance QR',
                description: 'Laminate & stick on wall',
                icon: Icons.qr_code_scanner,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQRCard({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE65C00).withOpacity(0.2)),
            ),
            child: Icon(icon, color: const Color(0xFFE65C00), size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
          ),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    onPressed: () => _showSuccessSnackBar('Downloading QR PDF...'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text('PDF', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    onPressed: () => _showSuccessSnackBar('Sharing QR...'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: const Color(0xFFE65C00).withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text('Share', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAttendanceStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today's Attendance",
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            Text(
              'Present: 38/85',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Shift filter chips
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['All Shifts', 'Morning', 'Evening', 'Custom'].map((shift) {
              final isSelected = _selectedShiftFilter == shift;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedShiftFilter = shift;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFE65C00) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    shift,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Horizontal Avatars scroll
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _mockAttendance.length,
            itemBuilder: (context, index) {
              final student = _mockAttendance[index];
              Color ringColor = const Color(0xFFE5E7EB);
              bool hasOverlay = false;

              if (student['status'] == 'in') {
                ringColor = const Color(0xFF22C55E); // Green checked in
              } else if (student['status'] == 'out') {
                ringColor = const Color(0xFFEF4444); // Red checked out
              } else if (student['status'] == 'expired') {
                ringColor = const Color(0xFFEF4444);
                hasOverlay = true; // Red overlay expired
              }

              return Container(
                margin: const EdgeInsets.only(right: 16),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ringColor, width: 2.5),
                          ),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFFFFF3ED),
                            child: Text(
                              student['name']![0],
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFE65C00),
                              ),
                            ),
                          ),
                        ),
                        if (hasOverlay)
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFEF4444).withOpacity(0.4),
                            ),
                            child: const Center(
                              child: Icon(Icons.block, color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      student['name']!,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      student['seat']!,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: const Color(0xFFE65C00),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivityFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activities',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _currentTab = 1), // Go to Members
              child: Text(
                'View All →',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE65C00),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: _mockActivities.map((act) {
              Color dotColor = const Color(0xFFE5E7EB);
              if (act['type'] == 'in') dotColor = const Color(0xFF22C55E);
              if (act['type'] == 'out') dotColor = const Color(0xFFEF4444);
              if (act['type'] == 'req') dotColor = const Color(0xFF3B82F6);
              if (act['type'] == 'pay') dotColor = const Color(0xFFF59E0B);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        act['desc'],
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    Text(
                      act['time'],
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.25,
      children: [
        _buildStatCard(
          icon: Icons.people_outline,
          value: _totalMembers,
          label: 'Total Members',
        ),
        _buildStatCard(
          icon: Icons.person_add_disabled_outlined,
          value: _activeMembers,
          label: 'Active Members',
        ),
        _buildStatCard(
          icon: Icons.chair_alt_outlined,
          value: _totalSeats,
          label: 'Total Seats',
        ),
        _buildStatCard(
          icon: Icons.calendar_month_outlined,
          value: _todayBookings,
          label: "Today's Bookings",
        ),
        _buildStatCard(
          icon: Icons.watch_later_outlined,
          value: _pendingBookings,
          label: 'Pending Bookings',
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required int value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: const Color(0xFFE65C00), size: 22),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
            ],
          ),
          const Spacer(),
          Text(
            '$value',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFE65C00),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryProfileCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cover Banner Image (Inspired by Screenshot 1)
        Container(
          height: 180,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/horizontal app logo.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            color: Colors.black.withOpacity(0.4),
            alignment: Alignment.topRight,
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showSuccessSnackBar('Upload cover image coming soon!'),
              icon: const Icon(Icons.camera_alt, size: 14, color: Colors.black),
              label: Text('Edit Cover', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ),

        // Profile pic overlapping cover image
        Positioned(
          bottom: -50,
          left: 20,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 3),
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
              ],
              image: const DecorationImage(
                image: AssetImage('assets/images/LOGO.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // Space padding placeholder to offset overlapping logo
        const SizedBox(height: 230),
        
        // Open Indicator Pill badge
        Positioned(
          bottom: -32,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  'Open',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildProfileActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Library Title, verified indicator and statistics description text below
        Text(
          _libraryName,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              'Downtown Branch',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Color(0xFFE65C00), size: 16),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 18),
            const SizedBox(width: 4),
            Text('4.8', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(' (128 Reviews)', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(width: 16),
            const Icon(Icons.people_outline, color: Color(0xFFE65C00), size: 18),
            const SizedBox(width: 4),
            Text('120+ Members', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFFE65C00))),
          ],
        ),
        const SizedBox(height: 20),

        // Row of outline action buttons
        Row(
          children: [
            Expanded(child: _buildActionIconButton(Icons.share_outlined, 'Share')),
            const SizedBox(width: 8),
            Expanded(child: _buildActionIconButton(Icons.remove_red_eye_outlined, 'Preview')),
            const SizedBox(width: 8),
            Expanded(child: _buildActionIconButton(Icons.qr_code_2, 'QR Codes')),
            const SizedBox(width: 8),
            Expanded(child: _buildActionIconButton(Icons.edit_outlined, 'Customise', color: const Color(0xFFE65C00))),
          ],
        )
      ],
    );
  }

  Widget _buildActionIconButton(IconData icon, String label, {Color color = const Color(0xFF1E293B)}) {
    return OutlinedButton(
      onPressed: () => _showSuccessSnackBar('$label panel coming soon!'),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: Colors.white,
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildProfileCompletionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Profile Completion', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
              Text('80% Completed', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE65C00))),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const LinearProgressIndicator(
              value: 0.80,
              minHeight: 6,
              backgroundColor: Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAboutLibraryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('About Library', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B))),
              TextButton(
                onPressed: _openLibrarySetupStage1Dialog,
                child: Text('Edit', style: GoogleFonts.inter(color: const Color(0xFFE65C00), fontWeight: FontWeight.bold, fontSize: 13)),
              )
            ],
          ),
          Text(
            'Silence Study Zone is designed for serious learners who value peace, discipline and productivity. Well-equipped study space with comfortable seating and a calm environment.',
            style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[600], height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildMicroStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildMicroStatCard('120+', 'Members')),
        const SizedBox(width: 8),
        Expanded(child: _buildMicroStatCard('85%', 'Occupancy')),
        const SizedBox(width: 8),
        Expanded(child: _buildMicroStatCard('4', 'Shifts')),
        const SizedBox(width: 8),
        Expanded(child: _buildMicroStatCard('9', 'Years Active')),
      ],
    );
  }

  Widget _buildMicroStatCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: Colors.grey[500], fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSettingListItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Beautiful Custom Color Rounded Square Box (Inspired by Image 1)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
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

  Widget _buildPlaceholderTab(String title, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE65C00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: const Color(0xFFE65C00)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              'Operational screen view is being customized under Milestone 3.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine active tab screen body
    Widget bodyView;
    switch (_currentTab) {
      case 0:
        bodyView = _buildHomeTab();
        break;
      case 1:
        bodyView = _buildPlaceholderTab('Members Panel', Icons.people_outline);
        break;
      case 2:
        bodyView = _buildPlaceholderTab('Bookings Ledger', Icons.calendar_month_outlined);
        break;
      case 3:
        bodyView = _buildPlaceholderTab('Student Messages', Icons.chat_bubble_outline_rounded);
        break;
      case 4:
        bodyView = _buildMoreTab();
        break;
      default:
        bodyView = _buildHomeTab();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false, // Allows cover image to layout fully at top behind status bar
        child: bodyView,
      ),

      // STATE-OF-THE-ART BOTTOM NAVIGATION BAR (Matching Screenshots perfectly)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() {
            _currentTab = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFE65C00),
        unselectedItemColor: const Color(0xFF94A3B8), // slate-400
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Members',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz_outlined),
            activeIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
