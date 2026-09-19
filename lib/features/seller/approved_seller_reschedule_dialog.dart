import 'package:flutter/material.dart';

import '../../theme/seller_ui_foundation.dart';
import 'seller_schedule_controls.dart';

class ApprovedSellerRescheduleDialog extends StatefulWidget {
  const ApprovedSellerRescheduleDialog({
    required this.customerName,
    required this.currentDate,
    required this.currentTime,
    super.key,
  });

  final String customerName;
  final String currentDate;
  final String currentTime;

  @override
  State<ApprovedSellerRescheduleDialog> createState() =>
      _ApprovedSellerRescheduleDialogState();
}

class _ApprovedSellerRescheduleDialogState
    extends State<ApprovedSellerRescheduleDialog> {
  DateTime selectedDate = DateTime(2025, 5, 20);
  DateTime displayedMonth = DateTime(2025, 5);
  TimeOfDay selectedTime = const TimeOfDay(hour: 12, minute: 0);

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
        key: const Key('sellerRescheduleDialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        backgroundColor: SellerUiColors.white,
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
                        color: SellerUiColors.lavender,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        color: SellerUiColors.primaryBright,
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
                  displayedMonth: displayedMonth,
                  highlightedDate: DateTime(2025, 5, 19),
                  onSelected: (date) => setState(() => selectedDate = date),
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
                  onSelected: (time) => setState(() => selectedTime = time),
                ),
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
                SizedBox(height: metrics.spacing(10)),
                Container(
                  padding: EdgeInsets.all(metrics.spacing(10)),
                  decoration: BoxDecoration(
                    color: SellerUiColors.lavender,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: SellerUiColors.primaryBright,
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
                SellerPrimaryButton(
                  key: const Key('sellerSendReschedule'),
                  label: 'Send reschedule request',
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                SizedBox(height: metrics.spacing(8)),
                OutlinedButton(
                  key: const Key('sellerCancelMeeting'),
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SellerUiColors.red,
                    minimumSize: Size(0, metrics.geometry(44)),
                    fixedSize: Size.fromHeight(metrics.geometry(44)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.spacing(16),
                      vertical: metrics.spacing(9),
                    ),
                    textStyle: sellerText(metrics, 14, weight: FontWeight.w700),
                    side: const BorderSide(color: SellerUiColors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel meeting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
