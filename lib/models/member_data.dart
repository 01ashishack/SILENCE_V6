import 'dart:io';
import 'package:flutter/foundation.dart';

class MemberData {
  String? mode; // 'new' or 'existing'
  String name = '';
  String fatherName = '';
  DateTime? dob;
  String? gender;
  String phone = '';
  String email = '';
  String address = '';
  String? preparingFor;
  DateTime joiningDate = DateTime.now();
  File? profilePhoto;
  String? existingPhotoUrl;
  String? idProof1Type = 'Aadhaar';
  File? idProof1File;
  String? idProof2Type = 'PAN';
  File? idProof2File;

  // Plan configuration
  String? selectedShiftId;
  String selectedShiftName = '';
  int selectedShiftPrice = 1500;
  String planType = 'monthly';
  int trialDays = 0;
  bool customPlanStart = false;
  DateTime? planStartDate;
  Set<String> selectedAddonIds = {};
  int totalBasePrice = 1500;

  // Seat assignment
  String? selectedSeatId;
  String? selectedSeatLabel;
  String? selectedFloorId;
  String? selectedFloorName;
  String? selectedSectionId;
  String? selectedSectionName;

  // Payment details
  int discount = 0;
  String paymentFlow = 'paid'; // 'paid' or 'request'
  String paymentMethod = 'cash'; // 'cash', 'upi', 'card'

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'name': name,
      'fatherName': fatherName,
      'dob': dob?.toIso8601String(),
      'gender': gender,
      'phone': phone,
      'email': email,
      'address': address,
      'preparingFor': preparingFor,
      'joiningDate': joiningDate.toIso8601String(),
      'profilePhotoPath': profilePhoto?.path,
      'existingPhotoUrl': existingPhotoUrl,
      'idProof1Type': idProof1Type,
      'idProof1Path': idProof1File?.path,
      'idProof2Type': idProof2Type,
      'idProof2Path': idProof2File?.path,
      'selectedShiftId': selectedShiftId,
      'selectedShiftName': selectedShiftName,
      'selectedShiftPrice': selectedShiftPrice,
      'planType': planType,
      'trialDays': trialDays,
      'customPlanStart': customPlanStart,
      'planStartDate': planStartDate?.toIso8601String(),
      'selectedAddonIds': selectedAddonIds.toList(),
      'totalBasePrice': totalBasePrice,
      'selectedSeatId': selectedSeatId,
      'selectedSeatLabel': selectedSeatLabel,
      'selectedFloorId': selectedFloorId,
      'selectedFloorName': selectedFloorName,
      'selectedSectionId': selectedSectionId,
      'selectedSectionName': selectedSectionName,
      'discount': discount,
      'paymentFlow': paymentFlow,
      'paymentMethod': paymentMethod,
    };
  }

  void fromJson(Map<String, dynamic> data) {
    mode = data['mode'] as String?;
    name = data['name'] as String? ?? '';
    fatherName = data['fatherName'] as String? ?? '';
    if (data['dob'] != null) dob = DateTime.tryParse(data['dob'] as String);
    gender = data['gender'] as String?;
    phone = data['phone'] as String? ?? '';
    email = data['email'] as String? ?? '';
    address = data['address'] as String? ?? '';
    preparingFor = data['preparingFor'] as String?;
    if (data['joiningDate'] != null) joiningDate = DateTime.tryParse(data['joiningDate'] as String) ?? DateTime.now();
    existingPhotoUrl = data['existingPhotoUrl'] as String?;

    if (data['profilePhotoPath'] != null) {
      final file = File(data['profilePhotoPath'] as String);
      if (kIsWeb || file.existsSync()) profilePhoto = file;
    }
    idProof1Type = data['idProof1Type'] as String? ?? 'Aadhaar';
    if (data['idProof1Path'] != null) {
      final file = File(data['idProof1Path'] as String);
      if (kIsWeb || file.existsSync()) idProof1File = file;
    }
    idProof2Type = data['idProof2Type'] as String? ?? 'PAN';
    if (data['idProof2Path'] != null) {
      final file = File(data['idProof2Path'] as String);
      if (kIsWeb || file.existsSync()) idProof2File = file;
    }

    selectedShiftId = data['selectedShiftId'] as String?;
    selectedShiftName = data['selectedShiftName'] as String? ?? '';
    selectedShiftPrice = data['selectedShiftPrice'] as int? ?? 1500;
    planType = data['planType'] as String? ?? 'monthly';
    trialDays = data['trialDays'] as int? ?? 0;
    customPlanStart = data['customPlanStart'] as bool? ?? false;
    if (data['planStartDate'] != null) {
      planStartDate = DateTime.tryParse(data['planStartDate'] as String);
    }
    if (data['selectedAddonIds'] != null) {
      selectedAddonIds = Set<String>.from(data['selectedAddonIds'] as List);
    }
    totalBasePrice = data['totalBasePrice'] as int? ?? 1500;

    selectedSeatId = data['selectedSeatId'] as String?;
    selectedSeatLabel = data['selectedSeatLabel'] as String?;
    selectedFloorId = data['selectedFloorId'] as String?;
    selectedFloorName = data['selectedFloorName'] as String?;
    selectedSectionId = data['selectedSectionId'] as String?;
    selectedSectionName = data['selectedSectionName'] as String?;

    discount = data['discount'] as int? ?? 0;
    paymentFlow = data['paymentFlow'] as String? ?? 'paid';
    paymentMethod = data['paymentMethod'] as String? ?? 'cash';
  }
}
