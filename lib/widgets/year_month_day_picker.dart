import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

Future<DateTime?> showYearMonthDayPicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Select Date',
}) {
  final now = DateTime.now();
  final defaultDate = initialDate ?? now;
  final startYear = firstDate?.year ?? 1950;
  final endYear = lastDate?.year ?? (now.year + 10);

  int selectedYear = defaultDate.year;
  int selectedMonth = defaultDate.month;
  int selectedDay = defaultDate.day;

  // Ensure year is within range
  if (selectedYear < startYear) selectedYear = startYear;
  if (selectedYear > endYear) selectedYear = endYear;

  final months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.white,
    elevation: 5,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          // Calculate max days for the currently selected year and month
          int maxDays = 31;
          if (selectedMonth == 4 || selectedMonth == 6 || selectedMonth == 9 || selectedMonth == 11) {
            maxDays = 30;
          } else if (selectedMonth == 2) {
            final isLeap = (selectedYear % 4 == 0 && selectedYear % 100 != 0) || (selectedYear % 400 == 0);
            maxDays = isLeap ? 29 : 28;
          }

          if (selectedDay > maxDays) {
            selectedDay = maxDays;
          }

          final List<int> yearsList = List.generate(endYear - startYear + 1, (i) => startYear + i);
          final List<int> daysList = List.generate(maxDays, (i) => i + 1);

          return Container(
            height: 330,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65C00).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.calendar_month, color: Color(0xFFE65C00), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Dropdowns Row
                Row(
                  children: [
                    // Day
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: selectedDay,
                        decoration: InputDecoration(
                          labelText: 'Day',
                          labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: GoogleFonts.inter(color: const Color(0xFF1A1A2E), fontSize: 14),
                        dropdownColor: Colors.white,
                        items: daysList.map((day) {
                          return DropdownMenuItem<int>(
                            value: day,
                            child: Text(day.toString().padLeft(2, '0')),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedDay = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Month
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<int>(
                        value: selectedMonth,
                        decoration: InputDecoration(
                          labelText: 'Month',
                          labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: GoogleFonts.inter(color: const Color(0xFF1A1A2E), fontSize: 14),
                        dropdownColor: Colors.white,
                        items: List.generate(12, (index) {
                          return DropdownMenuItem<int>(
                            value: index + 1,
                            child: Text(
                              months[index],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedMonth = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Year
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: InputDecoration(
                          labelText: 'Year',
                          labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: GoogleFonts.inter(color: const Color(0xFF1A1A2E), fontSize: 14),
                        dropdownColor: Colors.white,
                        items: yearsList.map((year) {
                          return DropdownMenuItem<int>(
                            value: year,
                            child: Text(year.toString()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedYear = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Buttons Row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
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
                          Navigator.pop(
                            context,
                            DateTime(selectedYear, selectedMonth, selectedDay),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Select',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
