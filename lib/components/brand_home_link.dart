import 'package:flutter/material.dart';

class BrandHomeScope extends InheritedWidget {
  const BrandHomeScope({required this.onHome, required super.child, super.key});
  final VoidCallback? onHome;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrandHomeScope>()?.onHome;

  @override
  bool updateShouldNotify(BrandHomeScope oldWidget) => oldWidget.onHome != onHome;
}

class BrandHomeLink extends StatelessWidget {
  const BrandHomeLink({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onHome = BrandHomeScope.of(context);
    if (onHome == null) return child;
    return Semantics(
      container: true,
      button: true,
      label: 'Hocalist home',
      onTap: onHome,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onHome,
        child: child,
      ),
    );
  }
}
