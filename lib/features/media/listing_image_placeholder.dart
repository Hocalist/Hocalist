import 'package:flutter/material.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';

/// Neutral placeholder using the existing Store image-fallback treatment.
/// It never substitutes a photograph of an item the seller has not uploaded.
class ListingImagePlaceholder extends StatelessWidget {
  const ListingImagePlaceholder({required this.size, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'No photo uploaded',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_outlined, size: size * .38,
        color: HocalistPalette.text(context, BuyerUiTokens.action)),
    ),
  );
}
