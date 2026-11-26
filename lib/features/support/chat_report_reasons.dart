import 'package:flutter/material.dart';

import '../../components/account_role_components.dart';
import '../../components/hocalist_choice_sheet.dart';
import '../../components/hocalist_motion.dart';

class ChatReportReason {
  const ChatReportReason(this.label, this.category, {this.safety = false});

  final String label;
  final String category;
  final bool safety;

  bool get requiresDetails => category == 'other_conduct';
  String get supportCode => safety ? 'safety' : 'deal';

  String reportBody(String notes) {
    if (requiresDetails) return notes;
    return 'Reported reason: $label${notes.isEmpty ? '' : '\n\n$notes'}';
  }
}

const _harassment = ChatReportReason(
  'Threats, harassment, or abuse',
  'threats_or_harassment',
  safety: true,
);
const _scam = ChatReportReason(
  'Suspected scam or suspicious link',
  'fraud',
  safety: true,
);
const _pin = ChatReportReason(
  'Misuse of the purchase PIN',
  'pin_abuse',
  safety: true,
);
const _bypass = ChatReportReason(
  'Pressured me to bypass Hocalist’s purchase confirmation',
  'off_platform_evasion',
  safety: true,
);
const _other = ChatReportReason('Something else', 'other_conduct');

List<ChatReportReason> chatReportReasons({required bool seller}) => seller
    ? const [
        _harassment,
        _scam,
        ChatReportReason(
          'Requested an illegal product or service',
          'illegal_listing',
          safety: true,
        ),
        ChatReportReason('Buyer missed a confirmed meetup', 'missed_meetup'),
        ChatReportReason('Buyer changed the agreed terms', 'changed_terms'),
        _pin,
        _bypass,
        _other,
      ]
    : const [
        _harassment,
        _scam,
        ChatReportReason(
          'Offered an illegal product or service',
          'illegal_listing',
          safety: true,
        ),
        ChatReportReason('Seller missed a confirmed meetup', 'missed_meetup'),
        ChatReportReason(
          'Seller changed the agreed price or terms',
          'changed_terms',
        ),
        _pin,
        _bypass,
        _other,
      ];

Future<ChatReportReason?> pickChatReportReason(
  BuildContext context, {
  required bool seller,
  required Iterable<ChatReportReason> reasons,
  ChatReportReason? selected,
}) => showModalBottomSheet<ChatReportReason>(
  context: context,
  sheetAnimationStyle: HocalistMotion.sheetStyle(context),
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (sheet) => AccountModalSheet(
    seller: seller,
    title: seller ? 'Report buyer' : 'Report seller',
    subtitle: 'Choose the reason that best fits.',
    icon: Icons.flag_outlined,
    onClose: () => Navigator.pop(sheet),
    child: Column(
      children: [
        for (final reason in reasons)
          HocalistSheetChoice(
            seller: seller,
            label: reason.label,
            selected: selected == reason,
            onTap: () => Navigator.pop(sheet, reason),
          ),
      ],
    ),
  ),
);
