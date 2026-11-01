import 'package:flutter/material.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';

/// Saved places use the same grouped rows and icon treatment as More.
class SavedPlaceList extends StatelessWidget {
  const SavedPlaceList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: HocalistPalette.surface(context, BuyerUiTokens.surface),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: HocalistPalette.border(context, BuyerUiTokens.border))),
    clipBehavior: Clip.antiAlias,
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1) Divider(height: 1, indent: 56,
          color: HocalistPalette.border(context, BuyerUiTokens.border)),
      ],
    ]),
  );
}

class SavedPlaceRow extends StatelessWidget {
  const SavedPlaceRow({super.key, required this.title, required this.address,
    this.onTap, this.onEdit, this.onRemove, this.selectable = false, this.selected = false});
  final String title, address;
  final VoidCallback? onTap, onEdit, onRemove;
  final bool selectable, selected;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Ink(
      color: selected ? HocalistPalette.surface(context, BuyerUiTokens.activeSurface) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: HocalistPalette.surface(context, BuyerUiTokens.softSurface)),
          child: Icon(Icons.location_on_outlined, size: 19,
            color: HocalistPalette.text(context, BuyerUiTokens.action))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontFamily: 'Nunito', fontSize: 13, fontWeight: FontWeight.w700,
            color: HocalistPalette.text(context, BuyerUiTokens.text))),
          const SizedBox(height: 3),
          Text(address, style: TextStyle(fontFamily: 'Nunito', fontSize: 12, height: 1.4,
            color: HocalistPalette.text(context, BuyerUiTokens.muted))),
        ])),
        const SizedBox(width: 8),
        if (onEdit != null || onRemove != null)
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Edit', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 19)),
            IconButton(tooltip: 'Remove', onPressed: onRemove, icon: const Icon(Icons.delete_outline, size: 19)),
          ])
        else Icon(selectable ? (selected ? Icons.check_circle_outline : Icons.radio_button_unchecked) : Icons.chevron_right,
          size: 20, color: HocalistPalette.text(context, selected ? BuyerUiTokens.action : BuyerUiTokens.muted)),
      ]),
    ),
  );
}
