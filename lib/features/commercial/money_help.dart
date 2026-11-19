import 'package:flutter/material.dart';

import '../../components/account_role_components.dart';
import '../../components/hocalist_motion.dart';

void showMoneyHelp(
  BuildContext context, {
  required String title,
  required Map<String, String> answers,
  String subtitle = '',
  bool seller = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: HocalistMotion.sheetStyle(context),
    builder: (sheet) => AccountModalSheet(
      seller: seller,
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      icon: Icons.help_outline_rounded,
      onClose: () => Navigator.pop(sheet),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in answers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key, style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(entry.value),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
