import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

Future<DateTime?> showCalendarGridBottomSheet(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final resolvedInitial = initialDate ?? now;
  final resolvedFirst = firstDate ?? DateTime(now.year - 100);
  final resolvedLast = lastDate ?? DateTime(now.year + 100);

  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(16),
          child: _CalendarDialogPicker(
            initialDate: resolvedInitial,
            firstDate: resolvedFirst,
            lastDate: resolvedLast,
          ),
        ),
      );
    },
  );
}

// Semantic alias for clean reference in screens
Future<DateTime?> showCustomCalendarDialog(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showCalendarGridBottomSheet(
    context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}

class _CalendarDialogPicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _CalendarDialogPicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_CalendarDialogPicker> createState() => _CalendarDialogPickerState();
}

class _CalendarDialogPickerState extends State<_CalendarDialogPicker> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
    _selectedDate = DateTime(widget.initialDate.year, widget.initialDate.month, widget.initialDate.day);
  }

  List<String> get _weekdays => ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  int _daysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  void _prevMonth() {
    final prev = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    if (prev.isAfter(widget.firstDate) || (prev.month == widget.firstDate.month && prev.year == widget.firstDate.year)) {
      setState(() {
        _currentMonth = prev;
      });
    }
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (next.isBefore(widget.lastDate) || (next.month == widget.lastDate.month && next.year == widget.lastDate.year)) {
      setState(() {
        _currentMonth = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysCount = _daysInMonth(_currentMonth);
    final firstWeekday = _currentMonth.weekday % 7; // Sunday = 0, Monday = 1, etc.
    final totalCells = daysCount + firstWeekday;

    final today = DateTime.now();

    // Prepare robust list of years for dropdown
    final years = List<int>.generate(
      widget.lastDate.year - widget.firstDate.year + 1,
      (index) => widget.firstDate.year + index,
    );
    if (!years.contains(_currentMonth.year)) {
      years.add(_currentMonth.year);
      years.sort();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Premium Header: Month & Year Selectors with Chevrons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Color(0xFF1A1A2E), size: 20),
              onPressed: _prevMonth,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Month Selector
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentMonth.month,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                    items: List.generate(12, (index) => index + 1).map((m) {
                      return DropdownMenuItem<int>(
                        value: m,
                        child: Text(_getMonthName(m)),
                      );
                    }).toList(),
                    onChanged: (newMonth) {
                      if (newMonth != null) {
                        setState(() {
                          _currentMonth = DateTime(_currentMonth.year, newMonth, 1);
                        });
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFE65C00), size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                // Year Selector
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentMonth.year,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E),
                    ),
                    items: years.map((y) {
                      return DropdownMenuItem<int>(
                        value: y,
                        child: Text('$y'),
                      );
                    }).toList(),
                    onChanged: (newYear) {
                      if (newYear != null) {
                        setState(() {
                          _currentMonth = DateTime(newYear, _currentMonth.month, 1);
                        });
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFE65C00), size: 18),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Color(0xFF1A1A2E), size: 20),
              onPressed: _nextMonth,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Weekdays Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _weekdays.map((day) {
            return SizedBox(
              width: 32,
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7280),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),

        // 7-column calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.0,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            if (index < firstWeekday) {
              return const SizedBox.shrink();
            }

            final dayNum = index - firstWeekday + 1;
            final cellDate = DateTime(_currentMonth.year, _currentMonth.month, dayNum);

            final isSelected = cellDate.day == _selectedDate.day &&
                cellDate.month == _selectedDate.month &&
                cellDate.year == _selectedDate.year;

            final isToday = cellDate.day == today.day &&
                cellDate.month == today.month &&
                cellDate.year == today.year;

            final isEnabled = (cellDate.isAfter(widget.firstDate) ||
                    (cellDate.day == widget.firstDate.day &&
                        cellDate.month == widget.firstDate.month &&
                        cellDate.year == widget.firstDate.year)) &&
                (cellDate.isBefore(widget.lastDate) ||
                    (cellDate.day == widget.lastDate.day &&
                        cellDate.month == widget.lastDate.month &&
                        cellDate.year == widget.lastDate.year));

            return GestureDetector(
              onTap: isEnabled
                  ? () {
                      setState(() {
                        _selectedDate = cellDate;
                      });
                    }
                  : null,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? const Color(0xFFE65C00) // Selected brand orange
                      : Colors.transparent,
                  border: isToday && !isSelected
                      ? Border.all(color: const Color(0xFFE65C00), width: 1.5)
                      : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                        color: !isEnabled
                            ? const Color(0xFFD1D5DB)
                            : isSelected
                                ? Colors.white
                                : const Color(0xFF1A1A2E),
                      ),
                    ),
                    if (isToday)
                      Positioned(
                        bottom: 4,
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? Colors.white : const Color(0xFFE65C00),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Action Buttons: Cancel and Select
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _selectedDate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65C00),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                ),
                child: Text(
                  'Select',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }
}
