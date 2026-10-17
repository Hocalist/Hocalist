import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/schedule.dart';

import '../../theme/seller_ui_foundation.dart';
import 'seller_schedule_controls.dart';

class ApprovedSellerRescheduleDialog extends StatefulWidget {
  const ApprovedSellerRescheduleDialog({
    required this.customerName,
    required this.currentDate,
    required this.currentTime,
    this.initialDate,
    this.initialTime,
    this.timezoneId,
    this.onSubmit,
    super.key,
  });

  final String customerName;
  final String currentDate;
  final String currentTime;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? timezoneId;
  final Future<MeetingActionResult> Function(
    DateTime,
    TimeOfDay,
    RepeatedTimeOccurrence?,
    String,
  )?
  onSubmit;

  @override
  State<ApprovedSellerRescheduleDialog> createState() =>
      _ApprovedSellerRescheduleDialogState();
}

class _ApprovedSellerRescheduleDialogState
    extends State<ApprovedSellerRescheduleDialog> {
  DateTime selectedDate = DateTime(2025, 5, 20);
  DateTime displayedMonth = DateTime(2025, 5);
  TimeOfDay selectedTime = const TimeOfDay(hour: 12, minute: 0);
  bool _busy = false;
  bool _uncertain = false;
  String? _error;
  String? _operationKey;
  RepeatedTimeOccurrence? _occurrence;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate ?? selectedDate;
    if (widget.onSubmit != null &&
        selectedDate.isBefore(DateUtils.dateOnly(DateTime.now()))) {
      selectedDate = DateUtils.dateOnly(DateTime.now());
    }
    displayedMonth = DateTime(selectedDate.year, selectedDate.month);
    selectedTime = widget.initialTime ?? selectedTime;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_uncertain &&
        widget.onSubmit != null &&
        DateUtils.dateOnly(
          selectedDate,
        ).isBefore(DateUtils.dateOnly(DateTime.now()))) {
      setState(() => _error = 'Choose today or a future meeting date.');
      return;
    }
    if (widget.onSubmit == null) {
      Navigator.of(context).pop(true);
      return;
    }
    _operationKey ??= LocalMarketplaceRepository.newStoreOperationKey(
      'meeting-reschedule',
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    MeetingActionResult result;
    try {
      result = await widget.onSubmit!(
        selectedDate,
        selectedTime,
        _occurrence,
        _operationKey!,
      );
    } catch (_) {
      result = const MeetingActionResult.failure(
        'Could not confirm the change. Retry the same request.',
        outcomeUncertain: true,
      );
    }
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _uncertain = result.outcomeUncertain;
      _error = result.error;
      if (!_uncertain) _operationKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width - 28).clamp(292.0, 620.0);
    final metrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: dialogWidth,
      textScaler: media.textScaler,
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Dialog(
        key: const Key('sellerRescheduleDialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        backgroundColor: HocalistPalette.surface(context, SellerUiColors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: media.size.height * .9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(metrics.spacing(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: metrics.artSize(44),
                      height: metrics.artSize(44),
                      decoration: BoxDecoration(
                        color: HocalistPalette.surface(
                          context,
                          SellerUiColors.lavender,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_month_outlined,
                        color: HocalistPalette.text(
                          context,
                          SellerUiColors.primaryBright,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('sellerRescheduleClose'),
                      tooltip: 'Close reschedule dialog',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: metrics.spacing(8)),
                Text(
                  'Reschedule meeting',
                  style: sellerText(metrics, 24, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.geometry(4)),
                Text(
                  'Choose a new date and arrival time for your meeting with ${widget.customerName}.',
                  style: sellerText(metrics, 12, color: SellerUiColors.body),
                ),
                SizedBox(height: metrics.spacing(14)),
                Text(
                  '1. Select a date',
                  style: sellerText(metrics, 15, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(8)),
                SellerScheduleCalendar(
                  keyPrefix: 'sellerReschedule',
                  selectedDate: selectedDate,
                  earliestDate: widget.onSubmit == null ? null : DateTime.now(),
                  displayedMonth: displayedMonth,
                  highlightedDate: widget.initialDate ?? DateTime(2025, 5, 19),
                  onSelected: (date) {
                    if (!_busy && !_uncertain) {
                      setState(() {
                        selectedDate = date;
                        _occurrence = null;
                      });
                    }
                  },
                  onDisplayedMonthChanged: (month) =>
                      setState(() => displayedMonth = month),
                ),
                SizedBox(height: metrics.spacing(14)),
                Text(
                  '2. Select arrival time',
                  style: sellerText(metrics, 15, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(8)),
                SellerScheduleTimeSelector(
                  keyPrefix: 'sellerRescheduleTime',
                  selectedTime: selectedTime,
                  onSelected: (time) {
                    if (!_busy && !_uncertain) {
                      setState(() {
                        selectedTime = time;
                        _occurrence = null;
                      });
                    }
                  },
                ),
                if (widget.timezoneId != null) ...[
                  Text('Meeting timezone: ${widget.timezoneId}'),
                  DropdownButtonFormField<RepeatedTimeOccurrence>(
                    isExpanded: true,
                    key: ValueKey(_occurrence),
                    initialValue: _occurrence,
                    decoration: const InputDecoration(
                      labelText: 'Repeated time',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: RepeatedTimeOccurrence.earlier,
                        child: Text('Earlier occurrence'),
                      ),
                      DropdownMenuItem(
                        value: RepeatedTimeOccurrence.later,
                        child: Text('Later occurrence'),
                      ),
                    ],
                    onChanged: _busy || _uncertain
                        ? null
                        : (value) => setState(() => _occurrence = value),
                  ),
                  TextButton(
                    onPressed: _busy || _uncertain
                        ? null
                        : () => setState(() => _occurrence = null),
                    child: const Text('Use ordinary time'),
                  ),
                ],
                if (widget.onSubmit == null) ...[
                  SizedBox(height: metrics.spacing(12)),
                  Text(
                    '3. Add a note (optional)',
                    style: sellerText(metrics, 15, weight: FontWeight.w800),
                  ),
                  SizedBox(height: metrics.spacing(8)),
                  TextField(
                    key: const Key('sellerRescheduleNote'),
                    minLines: 2,
                    maxLines: 2,
                    style: sellerInputText(metrics),
                    decoration: InputDecoration(
                      hintText: 'Add notes (optional)',
                      hintStyle: sellerInputPlaceholder(metrics),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: metrics.spacing(12),
                        vertical: metrics.spacing(12),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: metrics.spacing(10)),
                Container(
                  padding: EdgeInsets.all(metrics.spacing(10)),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      SellerUiColors.lavender,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: HocalistPalette.text(
                          context,
                          SellerUiColors.primaryBright,
                        ),
                      ),
                      SizedBox(width: metrics.geometry(8)),
                      Expanded(
                        child: Text(
                          'The customer will receive your request and can confirm the new time.',
                          style: sellerText(
                            metrics,
                            11,
                            color: SellerUiColors.body,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: metrics.spacing(12)),
                if (_error != null)
                  Text(_error!, key: const Key('rescheduleError')),
                if (_uncertain)
                  const Text(
                    'The outcome is unconfirmed. Retry keeps the exact date, time and request.',
                  ),
                SellerPrimaryButton(
                  key: const Key('sellerSendReschedule'),
                  label: _busy
                      ? 'Sending…'
                      : _uncertain
                      ? 'Retry same request'
                      : 'Send reschedule request',
                  onPressed: _submit,
                ),
                SizedBox(height: metrics.spacing(8)),
                OutlinedButton(
                  key: const Key('sellerCancelMeeting'),
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HocalistPalette.text(
                      context,
                      SellerUiColors.red,
                    ),
                    minimumSize: Size(0, metrics.geometry(44)),
                    fixedSize: Size.fromHeight(metrics.geometry(44)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.spacing(16),
                      vertical: metrics.spacing(9),
                    ),
                    textStyle: sellerText(metrics, 14, weight: FontWeight.w700),
                    side: BorderSide(
                      color: HocalistPalette.border(
                        context,
                        SellerUiColors.red,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    widget.onSubmit == null ? 'Cancel meeting' : 'Close',
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
