import 'package:flutter/material.dart';
import '../domain/phase2/profiles.dart';
import '../theme/adaptive_palette.dart';

class AccountRoleSwitchScope extends InheritedWidget {
  const AccountRoleSwitchScope({
    required this.onSelect,
    this.onResetSampleDeal,
    required super.child,
    super.key,
  });
  final ValueChanged<HocalistRole>? onSelect;
  final VoidCallback? onResetSampleDeal;
  @override
  bool updateShouldNotify(AccountRoleSwitchScope oldWidget) =>
      onSelect != oldWidget.onSelect || onResetSampleDeal != oldWidget.onResetSampleDeal;
}

enum _RoleMenuAction { resetSampleDeal }

/// Keeps the approved header artwork while making its role label actionable.
class AccountRoleSwitch extends StatelessWidget {
  const AccountRoleSwitch({required this.role, required this.child, super.key});
  final HocalistRole role;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccountRoleSwitchScope>();
    final onSelect = scope?.onSelect;
    if (onSelect == null) return child;
    final accent = HocalistPalette.text(context, const Color(0xff2916ed));
    final ink = HocalistPalette.text(context, const Color(0xff0c123d));
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff262944)
        : const Color(0xfff1f0ff);
    final pillRadius = BorderRadius.circular(99);
    return PopupMenuButton<Object>(
      borderRadius: pillRadius,
      tooltip: 'Switch account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: HocalistPalette.surface(context, Colors.white),
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      menuPadding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 152, maxWidth: 224),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: HocalistPalette.border(context, const Color(0xffe2e4ef)),
        ),
      ),
      onSelected: (next) {
        if (next is HocalistRole && next != role) onSelect(next);
        if (next == _RoleMenuAction.resetSampleDeal) scope?.onResetSampleDeal?.call();
      },
      itemBuilder: (_) => [
        for (final value in HocalistRole.values)
          PopupMenuItem<Object>(
            value: value,
            padding: EdgeInsets.zero,
            child: Semantics(
              selected: value == role,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: value == role ? highlight : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value == HocalistRole.buyer ? 'Buyer' : 'Seller',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: value == role ? accent : ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (value == role)
                      Icon(Icons.check_rounded, size: 18, color: accent),
                  ],
                ),
              ),
            ),
          ),
        if (scope?.onResetSampleDeal != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(
            value: _RoleMenuAction.resetSampleDeal,
            child: Text('Reset sample deal'),
          ),
        ],
      ],
      child: Ink(
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, const Color(0xfff1f0ff)),
          borderRadius: pillRadius,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              Icon(Icons.expand_more_rounded, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
