import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The child's horizontal controls win the gesture arena before this parent.
/// Mounted inside the home route, so pushed maps and dialogs keep their gestures.
class PageSwipeNavigation extends StatefulWidget {
  const PageSwipeNavigation({super.key, required this.child,
    this.onNext, this.onPrevious, this.enabled = true});

  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final bool enabled;

  @override
  State<PageSwipeNavigation> createState() => _PageSwipeNavigationState();
}

class _PageSwipeNavigationState extends State<PageSwipeNavigation> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && MediaQuery.viewInsetsOf(context).bottom == 0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
      onHorizontalDragStart: active ? (_) => _distance = 0 : null,
      onHorizontalDragUpdate: active ? (event) => _distance += event.primaryDelta ?? 0 : null,
      onHorizontalDragCancel: active ? () => _distance = 0 : null,
      onHorizontalDragEnd: active ? (_) {
        final distance = _distance;
        _distance = 0;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        final threshold = (MediaQuery.sizeOf(context).width * .18).clamp(64.0, 110.0);
        if (distance >= threshold) widget.onPrevious?.call();
        if (distance <= -threshold) widget.onNext?.call();
      } : null,
      child: widget.child,
    );
  }
}
