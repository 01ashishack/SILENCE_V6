import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/member_draft.dart';
import '../core/cache_service.dart';
import 'package:uuid/uuid.dart';

class DraftService {
  static final DraftService instance = DraftService._init();
  DraftService._init();

  final _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  // Helper to check if a PostgrestException indicates the table doesn't exist.
  bool _isTableMissing(dynamic e) {
    if (e is PostgrestException) {
      return e.code == 'PGRST205' || (e.message.contains('Could not find the table') || e.message.contains('does not exist'));
    }
    return false;
  }

  /// Get all drafts for a library
  Future<List<MemberDraft>> getDrafts(String libraryId) async {
    try {
      var query = _supabase
          .from('draft_members')
          .select('id, admin_id, library_id, draft_data, created_at, updated_at');
      
      if (libraryId != 'all') {
        query = query.eq('library_id', libraryId);
      }
      
      final response = await query.order('updated_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      final remoteDrafts = data.map((json) => MemberDraft.fromJson(json as Map<String, dynamic>)).toList();
      
      // Update local cache with remote drafts
      await _saveDraftsToLocalCache(libraryId, remoteDrafts);
      return remoteDrafts;
    } catch (e) {
      debugPrint('Supabase getDrafts error: $e');
      if (_isTableMissing(e) || e is! PostgrestException) {
        // Fallback to local cache
        return _getDraftsFromLocalCache(libraryId);
      }
      rethrow;
    }
  }

  /// Save or update a draft
  Future<void> saveDraft(MemberDraft draft) async {
    final now = DateTime.now();
    final isNew = draft.id == null;
    final draftId = draft.id ?? _uuid.v4();

    final draftToSave = MemberDraft(
      id: draftId,
      adminId: draft.adminId,
      libraryId: draft.libraryId,
      draftData: draft.draftData,
      createdAt: draft.createdAt ?? now,
      updatedAt: now,
    );

    // Save to local cache first (as safety)
    final localDrafts = await _getDraftsFromLocalCache(draft.libraryId);
    final existingIndex = localDrafts.indexWhere((d) => d.id == draftId);
    if (existingIndex >= 0) {
      localDrafts[existingIndex] = draftToSave;
    } else {
      localDrafts.insert(0, draftToSave);
    }
    await _saveDraftsToLocalCache(draft.libraryId, localDrafts);

    // Also update in local cache for 'all'
    if (draft.libraryId != 'all') {
      final allDrafts = await _getDraftsFromLocalCache('all');
      final allIndex = allDrafts.indexWhere((d) => d.id == draftId);
      if (allIndex >= 0) {
        allDrafts[allIndex] = draftToSave;
      } else {
        allDrafts.insert(0, draftToSave);
      }
      await _saveDraftsToLocalCache('all', allDrafts);
    }

    try {
      if (isNew) {
        await _supabase.from('draft_members').insert({
          'id': draftId,
          'admin_id': draft.adminId,
          'library_id': draft.libraryId,
          'draft_data': draft.draftData,
          'created_at': draftToSave.createdAt!.toIso8601String(),
          'updated_at': draftToSave.updatedAt!.toIso8601String(),
        });
      } else {
        await _supabase.from('draft_members').update({
          'draft_data': draft.draftData,
          'updated_at': draftToSave.updatedAt!.toIso8601String(),
        }).eq('id', draftId);
      }
    } catch (e) {
      debugPrint('Supabase saveDraft error: $e');
      if (!_isTableMissing(e)) {
        rethrow;
      }
    }
  }

  /// Delete a draft
  Future<void> deleteDraft(String draftId, String libraryId) async {
    // Delete from local cache
    final localDrafts = await _getDraftsFromLocalCache(libraryId);
    localDrafts.removeWhere((d) => d.id == draftId);
    await _saveDraftsToLocalCache(libraryId, localDrafts);

    // Also delete from local cache for 'all'
    if (libraryId != 'all') {
      final allDrafts = await _getDraftsFromLocalCache('all');
      allDrafts.removeWhere((d) => d.id == draftId);
      await _saveDraftsToLocalCache('all', allDrafts);
    }

    try {
      await _supabase.from('draft_members').delete().eq('id', draftId);
    } catch (e) {
      debugPrint('Supabase deleteDraft error: $e');
      if (!_isTableMissing(e)) {
        rethrow;
      }
    }
  }

  // ── Local Cache Helpers ──────────────────────────────────────────────────

  Future<List<MemberDraft>> _getDraftsFromLocalCache(String libraryId) async {
    final cacheKey = 'draft_members_list_$libraryId';
    final cached = await CacheService.instance.readCache(cacheKey);
    if (cached == null || cached is! List) return [];
    
    try {
      return cached.map((item) => MemberDraft.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error parsing cached drafts: $e');
      return [];
    }
  }

  Future<void> _saveDraftsToLocalCache(String libraryId, List<MemberDraft> drafts) async {
    final cacheKey = 'draft_members_list_$libraryId';
    final serialized = drafts.map((d) => d.toJson()).toList();
    await CacheService.instance.writeCache(cacheKey, serialized);
  }
}
