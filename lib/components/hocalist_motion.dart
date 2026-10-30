import 'package:flutter/material.dart';

/// Motion changes presentation only, never the approved resting geometry.
abstract final class HocalistMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, [int milliseconds = 200]) =>
      reduced(context) ? Duration.zero : Duration(milliseconds: milliseconds);

  static AnimationStyle sheetStyle(BuildContext context) => AnimationStyle(
    duration: duration(context, 260),
    reverseDuration: duration(context, 180),
  );

  static AnimationStyle dialogStyle(BuildContext context) => AnimationStyle(
    duration: duration(context, 200),
    reverseDuration: duration(context, 150),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
}

/// Restarts presentation for a new state without disposing retained forms or
/// keeping outgoing actions alive. The child is always the current child.
class HocalistStateTransition extends StatefulWidget {
  const HocalistStateTransition({
    required this.stateKey,
    required this.child,
    super.key,
  });
  final Object? stateKey;
  final Widget child;

  @override
  State<HocalistStateTransition> createState() =>
      _HocalistStateTransitionState();
}

class _HocalistStateTransitionState extends State<HocalistStateTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(HocalistStateTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateKey != widget.stateKey) {
      if (HocalistMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final value = HocalistMotion.reduced(context)
          ? 1.0
          : Curves.easeOutCubic.transform(_controller.value);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      );
    },
  );
}

/// Pointer feedback without replacing the child's gestures or semantics.
class HocalistPressFeedback extends StatefulWidget {
  const HocalistPressFeedback({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  State<HocalistPressFeedback> createState() => _HocalistPressFeedbackState();
}

class _HocalistPressFeedbackState extends State<HocalistPressFeedback> {
  final Set<int> _pointers = {};

  void _release(int pointer) {
    if (_pointers.remove(pointer)) setState(() {});
  }

  @override
  void didUpdateWidget(HocalistPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pointers.clear();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled
        ? (event) => setState(() => _pointers.add(event.pointer))
        : null,
    onPointerUp: (event) => _release(event.pointer),
    onPointerCancel: (event) => _release(event.pointer),
    child: AnimatedScale(
      scale:
          widget.enabled &&
              _pointers.isNotEmpty &&
              !HocalistMotion.reduced(context)
          ? .985
          : 1,
      duration: HocalistMotion.duration(context, 100),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class HocalistExpand extends StatelessWidget {
  const HocalistExpand({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => HocalistMotion.reduced(context)
      ? child
      : AnimatedSize(
          duration: HocalistMotion.duration(context),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: child,
        );
}

/// Only the incoming state is kept: old balances, errors and actions never
/// remain in the tree while the new state becomes visible.
class HocalistEntrance extends StatefulWidget {
  const HocalistEntrance({required this.child, super.key});
  final Widget child;
  @override
  State<HocalistEntrance> createState() => _HocalistEntranceState();
}

class _HocalistEntranceState extends State<HocalistEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  bool _revealed = false;
  bool _checkScheduled = false;
  bool _presentationEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retained tabs are laid out offstage. Observe their TickerMode so a card
    // gets another visibility check when its tab becomes active.
    _presentationEnabled = TickerMode.valuesOf(context).enabled;
    if (HocalistMotion.reduced(context)) {
      _revealed = true;
      _controller.value = 1;
    } else {
      _scheduleCheck();
    }
  }

  void _scheduleCheck() {
    if (_revealed || _checkScheduled || !_presentationEnabled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted || _revealed || !_presentationEnabled) return;
      // Ancestor route/layout animations can move a card into view without a
      // scroll notification. Content must never remain transparent waiting for
      // a gesture: enter on the first active frame instead of gating visibility
      // on a single measurement of the ancestor's transient geometry.
      _revealed = true;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (HocalistMotion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}
