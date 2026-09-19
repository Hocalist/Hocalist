import 'package:flutter/material.dart';

import 'buyer_ui_foundation.dart';
import 'seller_ui_foundation.dart';

enum HocalistControlRole { buyer, seller }

ApprovedReplicaMetrics _controlMetrics(BuildContext context) {
  final media = MediaQuery.of(context);
  return ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        availableWidth: media.size.width,
        textScaler: media.textScaler,
      );
}

Color _controlAccent(HocalistControlRole role) =>
    role == HocalistControlRole.buyer
    ? BuyerUiTokens.action
    : SellerUiColors.primaryBright;

Color _controlText(HocalistControlRole role) =>
    role == HocalistControlRole.buyer ? BuyerUiTokens.text : SellerUiColors.ink;

Color _controlMuted(HocalistControlRole role) =>
    role == HocalistControlRole.buyer
    ? BuyerUiTokens.muted
    : SellerUiColors.muted;

Color _controlBorder(HocalistControlRole role) =>
    role == HocalistControlRole.buyer
    ? BuyerUiTokens.border
    : SellerUiColors.line;

Color _controlSurface(HocalistControlRole role) =>
    role == HocalistControlRole.buyer
    ? const Color(0xfffbfcff)
    : SellerUiColors.lavender;

TextStyle _controlTextStyle(
  BuildContext context,
  ApprovedReplicaMetrics metrics,
  HocalistControlRole role, {
  double size = 12.5,
  FontWeight weight = FontWeight.w700,
  Color? color,
}) {
  if (role == HocalistControlRole.seller) {
    return sellerText(
      metrics,
      size,
      weight: weight,
      color: color ?? SellerUiColors.ink,
    );
  }
  return BuyerTypography.style(
    context,
    metrics,
    BuyerTextRole.primaryBody,
    weight: weight,
    color: color ?? BuyerUiTokens.text,
  ).copyWith(fontSize: metrics.fontSize(size));
}

/// Shared searchable field for Buyer and Seller lists.
class HocalistSearchField extends StatelessWidget {
  const HocalistSearchField({
    required this.role,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.autofocus = false,
    super.key,
  });

  final HocalistControlRole role;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final metrics = _controlMetrics(context);
    final accent = _controlAccent(role);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(12)),
      borderSide: BorderSide(color: _controlBorder(role)),
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      style: _controlTextStyle(
        context,
        metrics,
        role,
        size: 12.5,
        weight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        constraints: BoxConstraints(minHeight: metrics.geometry(44)),
        hintText: hintText,
        hintStyle: _controlTextStyle(
          context,
          metrics,
          role,
          size: 12,
          weight: FontWeight.w500,
          color: _controlMuted(role),
        ),
        filled: true,
        fillColor: _controlSurface(role),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: metrics.artSize(19),
          color: _controlMuted(role),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.close_rounded,
                  size: metrics.artSize(18),
                  color: accent,
                ),
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.spacing(12),
          vertical: metrics.spacing(10),
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(12)),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }
}

/// Shared popup selection control with explicit Buyer/Seller visual variants.
class HocalistSelectMenu<T> extends StatelessWidget {
  const HocalistSelectMenu({
    required this.role,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
    this.selectedLabelBuilder,
    this.leading,
    this.expanded = false,
    this.compact = false,
    this.semanticLabel,
    super.key,
  });

  final HocalistControlRole role;
  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final String Function(T value)? selectedLabelBuilder;
  final ValueChanged<T> onSelected;
  final IconData? leading;
  final bool expanded;
  final bool compact;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = _controlMetrics(context);
    final accent = _controlAccent(role);
    final radius = metrics.geometry(11);
    final control = Container(
      width: expanded ? double.infinity : null,
      constraints: BoxConstraints(
        minHeight: metrics.geometry(compact ? 38 : 44),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(compact ? 9 : 11),
      ),
      decoration: BoxDecoration(
        color: _controlSurface(role),
        border: Border.all(color: _controlBorder(role)),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: metrics.artSize(18), color: accent),
            SizedBox(width: metrics.spacing(7)),
          ],
          if (expanded)
            Expanded(child: _label(context, metrics))
          else
            _label(context, metrics),
          SizedBox(width: metrics.spacing(7)),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: metrics.artSize(18),
            color: accent,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label:
          semanticLabel ??
          'Select ${(selectedLabelBuilder ?? labelBuilder)(value)}',
      child: PopupMenuButton<T>(
        initialValue: value,
        position: PopupMenuPosition.under,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(14)),
          side: BorderSide(color: _controlBorder(role)),
        ),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem<T>(
              value: option,
              height: metrics.geometry(44),
              child: Row(
                children: [
                  SizedBox(
                    width: metrics.artSize(22),
                    child: option == value
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: metrics.artSize(18),
                            color: accent,
                          )
                        : null,
                  ),
                  SizedBox(width: metrics.spacing(7)),
                  Expanded(
                    child: Text(
                      labelBuilder(option),
                      style: _controlTextStyle(
                        context,
                        metrics,
                        role,
                        size: 12.5,
                        weight: option == value
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: option == value ? accent : _controlText(role),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: control,
      ),
    );
  }

  Widget _label(BuildContext context, ApprovedReplicaMetrics metrics) {
    return Text(
      (selectedLabelBuilder ?? labelBuilder)(value),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _controlTextStyle(context, metrics, role),
    );
  }
}

class HocalistFilterChip extends StatelessWidget {
  const HocalistFilterChip({
    required this.role,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    super.key,
  });

  final HocalistControlRole role;
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final metrics = _controlMetrics(context);
    final accent = _controlAccent(role);
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      avatar: icon == null
          ? null
          : Icon(icon, size: metrics.artSize(16), color: accent),
      label: Text(label),
      labelStyle: _controlTextStyle(
        context,
        metrics,
        role,
        size: 11.5,
        color: selected ? accent : _controlText(role),
      ),
      selectedColor: _controlSurface(role),
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? accent : _controlBorder(role)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
