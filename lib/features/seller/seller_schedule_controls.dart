import 'package:flutter/material.dart';

import '../../theme/seller_ui_foundation.dart';

@immutable
class SellerScheduleSelection {
  const SellerScheduleSelection({required this.date, required this.time});

  final DateTime date;
  final TimeOfDay time;
}

Future<SellerScheduleSelection?> showSellerSchedulePicker({
  required BuildContext context,
  required DateTime initialDate,
  required TimeOfDay initialTime,
}) {
  return showDialog<SellerScheduleSelection>(
    context: context,
    builder: (context) => _SellerSchedulePickerDialog(
      initialDate: initialDate,
      initialTime: initialTime,
    ),
  );
}

class _SellerSchedulePickerDialog extends StatefulWidget {
  const _SellerSchedulePickerDialog({
    required this.initialDate,
    required this.initialTime,
  });

  final DateTime initialDate;
  final TimeOfDay initialTime;

  @override
  State<_SellerSchedulePickerDialog> createState() =>
      _SellerSchedulePickerDialogState();
}

class _SellerSchedulePickerDialogState
    extends State<_SellerSchedulePickerDialog> {
  late DateTime selectedDate;
  late DateTime displayedMonth;
  late TimeOfDay selectedTime;

  @override
  void initState() {
    super.initState();
    selectedDate = DateUtils.dateOnly(widget.initialDate);
    displayedMonth = DateTime(selectedDate.year, selectedDate.month);
    selectedTime = widget.initialTime;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width - 28).clamp(292.0, 620.0);
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: dialogWidth,
      textScaler: media.textScaler,
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Dialog(
        key: const Key('sellerOfferScheduleDialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        backgroundColor: SellerUiColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: media.size.height * .88,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(metrics.spacing(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('sellerOfferScheduleBack'),
                      tooltip: 'Back to offer',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        'Choose date and time',
                        textAlign: TextAlign.center,
                        style: sellerText(metrics, 20, weight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(width: metrics.geometry(48)),
                  ],
                ),
                SizedBox(height: metrics.spacing(12)),
                Text(
                  '1. Select a date',
                  style: sellerText(metrics, 14, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(8)),
                SellerScheduleCalendar(
                  keyPrefix: 'sellerOfferSchedule',
                  selectedDate: selectedDate,
                  displayedMonth: displayedMonth,
                  onSelected: (date) => setState(() => selectedDate = date),
                  onDisplayedMonthChanged: (month) =>
                      setState(() => displayedMonth = month),
                ),
                SizedBox(height: metrics.spacing(14)),
                Text(
                  '2. Select arrival time',
                  style: sellerText(metrics, 14, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(8)),
                SellerScheduleTimeSelector(
                  keyPrefix: 'sellerOfferSchedule',
                  selectedTime: selectedTime,
                  onSelected: (time) => setState(() => selectedTime = time),
                ),
                SizedBox(height: metrics.spacing(16)),
                SellerPrimaryButton(
                  key: const Key('sellerOfferScheduleConfirm'),
                  label: 'Use this date & time',
                  onPressed: () => Navigator.pop(
                    context,
                    SellerScheduleSelection(
                      date: selectedDate,
                      time: selectedTime,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SellerScheduleCalendar extends StatelessWidget {
  const SellerScheduleCalendar({
    required this.keyPrefix,
    required this.selectedDate,
    required this.displayedMonth,
    required this.onSelected,
    required this.onDisplayedMonthChanged,
    this.highlightedDate,
    super.key,
  });

  final String keyPrefix;
  final DateTime selectedDate;
  final DateTime displayedMonth;
  final DateTime? highlightedDate;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<DateTime> onDisplayedMonthChanged;

  static const _monthNames = [
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
    'December',
  ];

  bool _sameDay(DateTime? left, DateTime right) =>
      left != null &&
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final month = DateTime(displayedMonth.year, displayedMonth.month);
    final firstWeekdayIndex = DateTime(month.year, month.month, 1).weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = firstWeekdayIndex + daysInMonth <= 35 ? 35 : 42;
    final cells = List<DateTime>.generate(
      cellCount,
      (index) =>
          DateTime(month.year, month.month, 1 - firstWeekdayIndex + index),
    );

    return Container(
      padding: EdgeInsets.all(metrics.spacing(10)),
      decoration: BoxDecoration(
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: Key('${keyPrefix}PreviousMonth'),
                tooltip: 'Previous month',
                visualDensity: VisualDensity.compact,
                onPressed: () => onDisplayedMonthChanged(
                  DateTime(month.year, month.month - 1),
                ),
                icon: const Icon(
                  Icons.chevron_left,
                  color: SellerUiColors.body,
                ),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: sellerText(metrics, 15, weight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: Key('${keyPrefix}NextMonth'),
                tooltip: 'Next month',
                visualDensity: VisualDensity.compact,
                onPressed: () => onDisplayedMonthChanged(
                  DateTime(month.year, month.month + 1),
                ),
                icon: const Icon(
                  Icons.chevron_right,
                  color: SellerUiColors.ink,
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.geometry(4)),
          Row(
            children: [
              for (final day in const [
                'SUN',
                'MON',
                'TUE',
                'WED',
                'THU',
                'FRI',
                'SAT',
              ])
                Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: sellerText(
                      metrics,
                      8.5,
                      weight: FontWeight.w700,
                      color: SellerUiColors.muted,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: metrics.geometry(4)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.08,
            ),
            itemBuilder: (context, index) {
              final date = cells[index];
              final inDisplayedMonth = date.month == month.month;
              final selected = _sameDay(selectedDate, date);
              final highlighted = _sameDay(highlightedDate, date);
              return Semantics(
                button: true,
                selected: selected,
                label:
                    '${_monthNames[date.month - 1]} ${date.day}, ${date.year}',
                child: InkWell(
                  key: inDisplayedMonth
                      ? Key('${keyPrefix}Day${date.day}')
                      : null,
                  onTap: () => onSelected(date),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? SellerUiColors.primaryBright
                          : highlighted
                          ? SellerUiColors.lavenderBorder
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${date.day}',
                      style: sellerText(
                        metrics,
                        10,
                        weight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : inDisplayedMonth
                            ? SellerUiColors.ink
                            : SellerUiColors.muted.withValues(alpha: .55),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class SellerScheduleTimeSelector extends StatelessWidget {
  const SellerScheduleTimeSelector({
    required this.keyPrefix,
    required this.selectedTime,
    required this.onSelected,
    super.key,
  });

  final String keyPrefix;
  final TimeOfDay selectedTime;
  final ValueChanged<TimeOfDay> onSelected;

  static const _times = [
    TimeOfDay(hour: 10, minute: 0),
    TimeOfDay(hour: 11, minute: 0),
    TimeOfDay(hour: 12, minute: 0),
    TimeOfDay(hour: 13, minute: 0),
    TimeOfDay(hour: 14, minute: 0),
    TimeOfDay(hour: 15, minute: 0),
    TimeOfDay(hour: 16, minute: 0),
  ];

  String _label(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  bool _sameTime(TimeOfDay left, TimeOfDay right) =>
      left.hour == right.hour && left.minute == right.minute;

  Future<void> _chooseCustomTime(BuildContext context) async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 330 ? 4 : 2;
        final gap = metrics.geometry(7);
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final time in _times)
              _SellerTimeButton(
                key: Key('$keyPrefix${_label(time)}'),
                width: itemWidth,
                label: _label(time),
                selected: _sameTime(selectedTime, time),
                onTap: () => onSelected(time),
              ),
            _SellerTimeButton(
              key: Key('${keyPrefix}CustomTime'),
              width: itemWidth,
              label: 'Custom time',
              icon: Icons.schedule_outlined,
              selected: !_times.any((time) => _sameTime(selectedTime, time)),
              onTap: () => _chooseCustomTime(context),
            ),
          ],
        );
      },
    );
  }
}

class _SellerTimeButton extends StatelessWidget {
  const _SellerTimeButton({
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return SizedBox(
      width: width,
      height: metrics.geometry(44),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: metrics.geometry(5)),
          foregroundColor: selected
              ? SellerUiColors.primaryBright
              : SellerUiColors.body,
          backgroundColor: selected
              ? SellerUiColors.lavender
              : SellerUiColors.white,
          side: BorderSide(
            color: selected
                ? SellerUiColors.primaryBright
                : SellerUiColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(9)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: metrics.artSize(15)),
              SizedBox(width: metrics.geometry(4)),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sellerText(
                  metrics,
                  10.5,
                  weight: FontWeight.w700,
                  color: selected
                      ? SellerUiColors.primaryBright
                      : SellerUiColors.body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
