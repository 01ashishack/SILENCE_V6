class MemberDraft {
  final String? id;
  final String adminId;
  final String libraryId;
  final Map<String, dynamic> draftData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MemberDraft({
    this.id,
    required this.adminId,
    required this.libraryId,
    required this.draftData,
    this.createdAt,
    this.updatedAt,
  });

  factory MemberDraft.fromJson(Map<String, dynamic> json) {
    return MemberDraft(
      id: json['id'] as String?,
      adminId: json['admin_id'] as String,
      libraryId: json['library_id'] as String,
      draftData: json['draft_data'] as Map<String, dynamic>,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'admin_id': adminId,
      'library_id': libraryId,
      'draft_data': draftData,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
