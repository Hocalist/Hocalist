import 'dart:async';
import 'package:flutter/material.dart';

class PullRefreshScrollBehavior extends MaterialScrollBehavior {
  const PullRefreshScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}

/// One refresh gesture per route; mounted sections contribute their own reads.
class PullRefreshHost extends StatefulWidget {
  const PullRefreshHost({
    required this.child,
    this.onRefresh,
    this.refreshAlongsideSections = false,
    super.key,
  });
  final Widget child;
  final Future<void> Function()? onRefresh;
  final bool refreshAlongsideSections;
  @override
  State<PullRefreshHost> createState() => _PullRefreshHostState();
}

class _PullRefreshHostState extends State<PullRefreshHost> {
  final callbacks = <Object, VoidCallback>{};
  RefreshIndicatorStatus? status;
  final indicatorKey = GlobalKey<RefreshIndicatorState>();
  double dragDistance = 0;
  Future<void> refresh() async {
    if (mounted) setState(() => status = RefreshIndicatorStatus.refresh);
    if (callbacks.isEmpty || widget.refreshAlongsideSections) {
      await widget.onRefresh?.call();
    }
    final seen = <VoidCallback>{};
    for (final entry in callbacks.entries.toList()) {
      if (callbacks[entry.key] != entry.value || !seen.add(entry.value)) {
        continue;
      }
      await Future.sync(entry.value);
    }
  }

  @override
  Widget build(BuildContext context) => _PullRefreshScope(
    owner: this,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => dragDistance = 0,
      onVerticalDragUpdate: (details) {
        if (widget.onRefresh == null && callbacks.isEmpty) return;
        dragDistance = (dragDistance + details.delta.dy).clamp(0, 200);
        if (status != RefreshIndicatorStatus.refresh) {
          setState(
            () =>
                status = dragDistance > 16 ? RefreshIndicatorStatus.drag : null,
          );
        }
      },
      onVerticalDragCancel: () {
        if (dragDistance > 0 && status == RefreshIndicatorStatus.drag) {
          setState(() => status = null);
        }
        dragDistance = 0;
      },
      onVerticalDragEnd: (_) {
        if (dragDistance >= 72 &&
            (widget.onRefresh != null || callbacks.isNotEmpty)) {
          indicatorKey.currentState?.show();
        } else if (status == RefreshIndicatorStatus.drag) {
          setState(() => status = null);
        }
        dragDistance = 0;
      },
      child: RefreshIndicator.noSpinner(
        key: indicatorKey,
        onStatusChange: (next) {
          if (mounted) {
            setState(
              () => status =
                  next == RefreshIndicatorStatus.done ||
                      next == RefreshIndicatorStatus.canceled
                  ? null
                  : next,
            );
          }
        },
        notificationPredicate: (event) =>
            (widget.onRefresh != null || callbacks.isNotEmpty) &&
            event.metrics.axis == Axis.vertical,
        onRefresh: refresh,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (status != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status == RefreshIndicatorStatus.refresh)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            Text(
                              status == RefreshIndicatorStatus.armed
                                  ? 'Release to refresh'
                                  : status == RefreshIndicatorStatus.refresh
                                  ? 'Refreshing…'
                                  : 'Pull to refresh',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PullRefreshScope extends InheritedWidget {
  const _PullRefreshScope({required this.owner, required super.child});
  final _PullRefreshHostState owner;
  @override
  bool updateShouldNotify(_PullRefreshScope oldWidget) =>
      owner != oldWidget.owner;
}

/// Registers a read without leaving a reload button or permanent instruction.
class PullRefreshAction extends StatefulWidget {
  const PullRefreshAction({
    required this.onRefresh,
    this.child = const SizedBox.shrink(),
    super.key,
  });
  final VoidCallback? onRefresh;
  final Widget child;
  @override
  State<PullRefreshAction> createState() => _PullRefreshActionState();
}

class _PullRefreshActionState extends State<PullRefreshAction> {
  _PullRefreshHostState? owner;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    owner?.callbacks.remove(this);
    owner = context
        .dependOnInheritedWidgetOfExactType<_PullRefreshScope>()
        ?.owner;
    _register();
  }

  void _register() {
    owner?.callbacks.remove(this);
    if (widget.onRefresh != null) owner?.callbacks[this] = widget.onRefresh!;
  }

  @override
  void didUpdateWidget(PullRefreshAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  @override
  void dispose() {
    owner?.callbacks.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
