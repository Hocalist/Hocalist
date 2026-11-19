import 'package:flutter/material.dart';

/// Uses the intact original image, retaining the full gift base.
/// Two complementary ink masks remove only the pale photographic backdrop.
class OriginalGiftArtwork extends StatelessWidget {
  const OriginalGiftArtwork({super.key, required this.asset,
    required this.width, required this.height});
  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: height,
    child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Stack(
      fit: StackFit.expand,
      children: [for (final direction in [-1.0, 1.0]) ColorFiltered(
        colorFilter: ColorFilter.matrix([
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          direction * 6, 0, direction * -6, 0, -100,
        ]),
        child: Image.asset(asset, fit: BoxFit.contain,
          filterQuality: FilterQuality.high, excludeFromSemantics: true),
      ),
      // Preserve the original white dollar mark inside the colored coin.
      ClipPath(clipper: _CoinInterior(asset.contains('dashboard')),
        child: Image.asset(asset, fit: BoxFit.contain,
          filterQuality: FilterQuality.high, excludeFromSemantics: true)),
      ],
    )),
  );
}

class _CoinInterior extends CustomClipper<Path> {
  const _CoinInterior(this.dashboard);
  final bool dashboard;
  @override
  Path getClip(Size size) {
    final source = dashboard ? const Size(285, 196) : const Size(270, 240);
    final fitted = applyBoxFit(BoxFit.contain, source, size).destination;
    final origin = Offset((size.width - fitted.width) / 2,
      (size.height - fitted.height) / 2);
    final scale = fitted.width / source.width;
    final center = dashboard ? const Offset(212, 142) : const Offset(188, 165);
    return Path()..addOval(Rect.fromCircle(center: origin + center * scale,
      radius: (dashboard ? 31 : 35) * scale));
  }
  @override
  bool shouldReclip(covariant _CoinInterior old) => old.dashboard != dashboard;
}
