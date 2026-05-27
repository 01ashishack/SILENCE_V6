import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrandingAssetsScreen extends StatefulWidget {
  const BrandingAssetsScreen({super.key});

  @override
  State<BrandingAssetsScreen> createState() => _BrandingAssetsScreenState();
}

class _BrandingAssetsScreenState extends State<BrandingAssetsScreen> {
  bool _isLoading = false;
  String? _logoUrl;
  Color _selectedAccent = const Color(0xFFE65C00);

  final List<Color> _brandPalette = [
    const Color(0xFFE65C00), // Default Orange
    const Color(0xFF0F172A), // Slate Dark
    const Color(0xFF3B82F6), // Ocean Blue
    const Color(0xFF10B981), // Emerald Green
    const Color(0xFF7C3AED), // Indigo Purple
    const Color(0xFFEC4899), // Crimson Pink
  ];

  @override
  void initState() {
    super.initState();
    _loadBrandingSettings();
  }

  Future<void> _loadBrandingSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _logoUrl = prefs.getString('branding_logo_url');
    final colorVal = prefs.getInt('branding_accent_color');
    if (colorVal != null) {
      _selectedAccent = Color(colorVal);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveBrandingSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('branding_accent_color', _selectedAccent.value);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Branding assets updated successfully! ✓'), backgroundColor: Color(0xFFE65C00)),
    );
    setState(() => _isLoading = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65C00),
      body: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBF5EE),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65C00),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Branding & Print Collateral',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Logo & Identity section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Library Visual Assets',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Stack(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3ED),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: _selectedAccent, width: 1.5),
                                      image: _logoUrl != null
                                          ? DecorationImage(image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                                          : null,
                                    ),
                                    child: _logoUrl == null
                                        ? Center(child: Icon(Icons.palette_outlined, size: 28, color: _selectedAccent))
                                        : null,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: _selectedAccent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.add_photo_alternate, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Tap circle to upload brand logo',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Color Palette Accent Selection
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'App Primary Accent Color',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose the dominant secondary color used across your member portals.',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _brandPalette.map((color) {
                                final isSelected = color.value == _selectedAccent.value;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedAccent = color);
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        if (isSelected)
                                          BoxShadow(
                                            color: color.withOpacity(0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                      ],
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 3. Printable Collateral Templates
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Printable Assets & Collateral',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 12),
                            _buildCollateralRow('A4 Join QR Poster', 'Premium desk board / entry standee poster format', Icons.crop_portrait),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('A4 Attendance QR Poster', 'Printable Check-in scanner desk banner template', Icons.crop_portrait_outlined),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('Desk Allocation Tags', 'Printable stickers with desk labels & barcodes', Icons.tag),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _buildCollateralRow('Student Conduct Booklet', 'Rules & guidelines pamphlet blueprint', Icons.menu_book),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 4. Update Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _saveBrandingSettings,
                        child: Text(
                          'Save Branding Config',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCollateralRow(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFE65C00), size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 16, color: Color(0xFF64748B)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Generating $title PDF for sharing...')),
              );
            },
          ),
        ],
      ),
    );
  }
}
