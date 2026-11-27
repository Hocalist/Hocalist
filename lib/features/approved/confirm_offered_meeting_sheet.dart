import 'package:flutter/material.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../components/hocalist_motion.dart';
import 'approved_replica_metrics.dart';

TextStyle _confirmationText(BuildContext c, {required double size, FontWeight weight = FontWeight.w400}) => BuyerTypography.homeStyle(c, ApprovedReplicaScope.maybeOf(c) ?? ApprovedReplicaMetrics.resolve(brightness: Theme.of(c).brightness, availableWidth: MediaQuery.sizeOf(c).width, textScaler: MediaQuery.textScalerOf(c)), size: size, weight: weight, color: BuyerUiTokens.text);

/// Read-only confirmation of terms already supplied by the seller.
/// Cancel and dismissal never invoke the accepting action.
Future<bool> confirmOfferedMeeting(BuildContext context, {
  required String title,
  required String time,
  required String timezone,
  required String place,
  String? preferredPlace,
}) async => await showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  sheetAnimationStyle: HocalistMotion.sheetStyle(context),
  backgroundColor: Colors.transparent,
  builder: (sheet) => BuyerModalSheet(
    title: 'Accept offer and meet?',
    subtitle: title,
    onClose: () => Navigator.pop(sheet, false),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Meet at the time and place offered by the seller.',
        style: _confirmationText(sheet, size: 13)),
      const SizedBox(height: 16),
      Text('Meet-up', style: _confirmationText(sheet, size: 13, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(time, style: _confirmationText(sheet, size: 14)),
      Text(timezone, style: _confirmationText(sheet, size: 12)),
      const SizedBox(height: 12),
      Text('Meet-up place', style: _confirmationText(sheet, size: 13, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(place, style: _confirmationText(sheet, size: 14)),
      if (preferredPlace != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: BuyerUiTokens.softSurface,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: BuyerUiTokens.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Check the meeting place', style: _confirmationText(sheet, size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('You preferred: $preferredPlace', style: _confirmationText(sheet, size: 13)),
            const SizedBox(height: 6),
            Text('Confirming will use the seller’s place shown above. Check that it works for you, or cancel and discuss it in chat.',
              style: _confirmationText(sheet, size: 13)),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Text('This confirms your meeting. Check the item or agreed service first and pay the seller directly if you’re satisfied. Share your purchase PIN after completing the purchase.',
        style: _confirmationText(sheet, size: 12)),
      const SizedBox(height: 18),
      BuyerPrimaryButton(label: 'Confirm meeting', minimumHeight: 48,
        onPressed: () => Navigator.pop(sheet, true)),
      const SizedBox(height: 10),
      BuyerSecondaryButton(label: 'Cancel', minimumHeight: 48,
        onPressed: () => Navigator.pop(sheet, false)),
    ]),
  ),
) ?? false;
