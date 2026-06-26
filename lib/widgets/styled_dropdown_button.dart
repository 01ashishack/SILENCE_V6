import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_palette.dart';

class StyledDropdownButton<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) itemLabelBuilder;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final Widget? icon;
  final String? title;

  const StyledDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabelBuilder,
    required this.onChanged,
    this.hint,
    this.icon,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPickerSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.border, width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                itemLabelBuilder(value),
                style: GoogleFonts.inter(fontSize: 15, color: context.palette.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            icon ?? const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65C00), size: 20),
          ],
        ),
      ),
    );
  }

  void _showPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      elevation: 8,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title ?? hint ?? 'Select Option',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 0),
              Divider(height: 1, color: context.palette.divider),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = item == value;
                    return ListTile(
                      title: Text(
                        itemLabelBuilder(item),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFFE65C00) : context.palette.textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFFE65C00), size: 18)
                          : null,
                      onTap: () {
                        onChanged(item);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
