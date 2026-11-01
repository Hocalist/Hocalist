import 'package:flutter/material.dart';

/// Retains the source glyph silhouette while removing its pale raster matte.
class PreservedRasterGlyph extends StatelessWidget {
  const PreservedRasterGlyph({super.key, required this.asset,
    required this.width, required this.height, required this.color,
    this.fit = BoxFit.contain, this.semanticLabel});
  final String asset;
  final double width;
  final double height;
  final Color color;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => ColorFiltered(
    // Preserve dark source ink while suppressing the pale matte and its fringe.
    colorFilter: ColorFilter.matrix([
      0, 0, 0, 0, color.r * 255,
      0, 0, 0, 0, color.g * 255,
      0, 0, 0, 0, color.b * 255,
      -2, 0, 0, 2, -90,
    ]),
    child: Image.asset(asset, width: width, height: height, fit: fit,
      filterQuality: FilterQuality.high, semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null),
  );
}
