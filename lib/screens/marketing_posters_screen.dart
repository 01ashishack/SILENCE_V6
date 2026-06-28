import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_snackbar.dart';
import '../theme/app_palette.dart';
import '../utils/error_messages.dart';
import '../widgets/states/empty_state.dart';

/// Library-owner facing gallery of ready-made marketing posters that the app
/// owner uploads (manually — no AI in-app). Two scopes:
///   • Common        → visible to every library owner
///   • Personalised  → only the matching library owner sees it
/// RLS on `marketing_assets` does the filtering; this screen just renders what
/// it is allowed to read, grouped by category, with one-tap download to gallery.
class MarketingPostersScreen extends StatefulWidget {
  const MarketingPostersScreen({super.key});

  @override
  State<MarketingPostersScreen> createState() => _MarketingPostersScreenState();
}

class _MarketingPostersScreenState extends State<MarketingPostersScreen> {
  static const String _bucket = 'marketing';

  // Category key → display label, in the order we want to show them.
  static const List<MapEntry<String, String>> _categories = [
    MapEntry('wall_poster', 'Wall Posters'),
    MapEntry('pamphlet', 'Pamphlets'),
    MapEntry('banner', 'Banners'),
    MapEntry('social', 'Social / WhatsApp'),
    MapEntry('other', 'Other'),
  ];

  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _assets = [];
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _sb
          .from('marketing_assets')
          .select()
          .eq('active', true)
          .order('sort_order')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _assets = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  String _publicUrl(String path) => _sb.storage.from(_bucket).getPublicUrl(path);

  Future<void> _download(Map<String, dynamic> asset) async {
    final id = asset['id'].toString();
    final path = (asset['image_path'] ?? '').toString();
    if (path.isEmpty || _downloading.contains(id)) return;
    setState(() => _downloading.add(id));
    try {
      final bytes = await _sb.storage.from(_bucket).download(path);
      await Gal.putImageBytes(bytes, name: 'silence_${id.split('-').first}');
      if (!mounted) return;
      AppSnackbar.success(context, 'Saved to your gallery ✓');
    } on GalException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Could not save: ${e.type.message}');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _downloading.remove(id));
    }
  }

  void _openPreview(Map<String, dynamic> asset) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: _publicUrl((asset['image_path'] ?? '').toString()),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _download(asset);
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65C00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final common = _assets.where((a) => a['scope'] == 'general').toList();
    final personalised = _assets.where((a) => a['scope'] == 'personalised').toList();

    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE65C00),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Marketing & Posters', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 14, color: p.textSecondary)),
                  ),
                )
              : _assets.isEmpty
                  ? const EmptyState(
                      icon: Icons.image_outlined,
                      title: 'No posters yet',
                      message: 'Ready-to-print posters and banners for your library '
                          'will appear here. Check back soon.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFFE65C00),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          if (personalised.isNotEmpty)
                            _scopeSection('For Your Library', personalised, p, highlight: true),
                          _scopeSection('For Everyone', common, p),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }

  Widget _scopeSection(String title, List<Map<String, dynamic>> items, AppPalette p,
      {bool highlight = false}) {
    if (items.isEmpty) {
      // Only render the "For Everyone" header even when empty (so the screen
      // isn't blank if there are only personalised, or vice-versa we skip).
      return const SizedBox.shrink();
    }
    final cats = _categories.where((c) => items.any((a) => a['category'] == c.key)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              if (highlight) const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE65C00)),
              if (highlight) const SizedBox(width: 6),
              Text(title,
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.bold, color: p.textPrimary)),
            ],
          ),
        ),
        ...cats.map((c) {
          final catItems = items.where((a) => a['category'] == c.key).toList();
          return _categoryRow(c.value, catItems, p);
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _categoryRow(String label, List<Map<String, dynamic>> items, AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700, color: p.textSecondary)),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _posterCard(items[i], p),
          ),
        ),
      ],
    );
  }

  Widget _posterCard(Map<String, dynamic> asset, AppPalette p) {
    final id = asset['id'].toString();
    final title = (asset['title'] ?? '').toString();
    final busy = _downloading.contains(id);
    return GestureDetector(
      onTap: () => _openPreview(asset),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _publicUrl((asset['image_path'] ?? '').toString()),
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: p.surfaceMuted,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65C00))),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: p.surfaceMuted,
                      child: Icon(Icons.broken_image_outlined, color: p.textMuted),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Material(
                      color: const Color(0xFFE65C00),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: busy ? null : () => _download(asset),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                              : const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textPrimary)),
              ),
          ],
        ),
      ),
    );
  }
}
