import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../theme/buyer_ui_foundation.dart';
import 'hocalist_motion.dart';

/// A visible guide driven by the actual form state, not a completion claim.
class HocalistFlowStages extends StatelessWidget {
  const HocalistFlowStages({
    required this.labels,
    required this.active,
    super.key,
  });
  final List<String> labels;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < labels.length; index++) ...[
        if (index > 0) const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            selected: index == active,
            label: 'Step ${index + 1}: ${labels[index]}',
            child: AnimatedContainer(
              duration: HocalistMotion.duration(context),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  index == active
                      ? BuyerUiTokens.softSurface
                      : const Color(0xfffafaff),
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: HocalistPalette.border(
                    context,
                    index == active
                        ? const Color(0xffd9d5ff)
                        : BuyerUiTokens.border,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: HocalistPalette.text(
                          context,
                          BuyerUiTokens.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
