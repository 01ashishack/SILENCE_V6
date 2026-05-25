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

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: const Color(0xFFFBF5EE), // warm cream background
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) {
      return _CalendarGridPicker(
        initialDate: resolvedInitial,
        firstDate: resolvedFirst,
        lastDate: resolvedLast,
      );
    },
  );
}

class _CalendarGridPicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _CalendarGridPicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_CalendarGridPicker> createState() => _CalendarGridPickerState();
}

class _CalendarGridPickerState extends State<_CalendarGridPicker> {
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
    if (prev.isAfter(widget.firstDate) || prev.month == widget.firstDate.month && prev.year == widget.firstDate.year) {
      setState(() {
        _currentMonth = prev;
      });
    }
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (next.isBefore(widget.lastDate) || next.month == widget.lastDate.month && next.year == widget.lastDate.year) {
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

    final monthName = _getMonthName(_currentMonth.month);
    final yearString = _currentMonth.year.toString();

    final today = DateTime.now();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: Month & Year Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Color(0xFF1A1A2E)),
                onPressed: _prevMonth,
              ),
              Text(
                '$monthName $yearString',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Color(0xFF1A1A2E)),
                onPressed: _nextMonth,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekdays header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _weekdays.map((day) {
              return SizedBox(
                width: 40,
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // 7-column calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
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
                      cellDate.day == widget.firstDate.day &&
                          cellDate.month == widget.firstDate.month &&
                          cellDate.year == widget.firstDate.year) &&
                  (cellDate.isBefore(widget.lastDate) ||
                      cellDate.day == widget.lastDate.day &&
                          cellDate.month == widget.lastDate.month &&
                          cellDate.year == widget.lastDate.year);

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
                          fontSize: 14,
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: !isEnabled
                              ? const Color(0xFF9CA3AF)
                              : isSelected
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (isToday)
                        Positioned(
                          bottom: 4,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFFE65C00),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Action Buttons: Cancel and Select
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: Text(
                    'Select',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
