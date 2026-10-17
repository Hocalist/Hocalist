import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';

/// Quiet reload action that can sit beside supporting copy.
class HocalistReloadLink extends StatelessWidget {
  const HocalistReloadLink({
    required this.onPressed,
    this.description = 'Reload',
    this.loading = false,
    this.color,
    super.key,
  });
  final VoidCallback? onPressed;
  final String description;
  final bool loading;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: description,
    child: TextButton(
      onPressed: loading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color == null
            ? null
            : HocalistPalette.text(context, color!),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(48, 40),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(
        loading
            ? 'Loading…'
            : description.toLowerCase().contains('discard')
            ? description
            : 'Reload',
      ),
    ),
  );
}
