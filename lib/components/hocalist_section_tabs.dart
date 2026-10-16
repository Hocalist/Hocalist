import '../features/approved/approved_replica_metrics.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'hocalist_motion.dart';

class HocalistTabPersistenceScope extends InheritedWidget {
  const HocalistTabPersistenceScope({
    required this.namespace,
    required super.child,
    super.key,
  });
  final String namespace;
  @override
  bool updateShouldNotify(HocalistTabPersistenceScope oldWidget) =>
      oldWidget.namespace != namespace;
}

/// Keeps inactive sections mounted without exposing their actions or semantics.
class HocalistSectionTabs extends StatefulWidget {
  const HocalistSectionTabs({
    required this.sections,
    required this.accent,
    this.persistenceId,
    super.key,
  });

  final Map<String, List<Widget>> sections;
  final Color accent;
  final String? persistenceId;

  @override
  State<HocalistSectionTabs> createState() => _HocalistSectionTabsState();
}

class _HocalistSectionTabsState extends State<HocalistSectionTabs> {
  int selected = 0;
  String? _storageKey;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .dependOnInheritedWidgetOfExactType<HocalistTabPersistenceScope>();
    final key = scope == null || widget.persistenceId == null
        ? null
        : 'hocalist.tabs.${scope.namespace}.${widget.persistenceId}';
    if (_storageKey == key) return;
    _storageKey = key;
    selected = 0;
    final generation = ++_generation;
    if (key != null) unawaited(_restore(key, generation));
  }

  Future<void> _restore(String key, int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || generation != _generation || key != _storageKey) return;
      final index = widget.sections.keys.toList().indexOf(
        prefs.getString(key) ?? '',
      );
      if (index >= 0) setState(() => selected = index);
    } catch (_) {
      /* Navigation stays usable when local preferences are unavailable. */
    }
  }

  Future<void> _select(int index, String label) async {
    ++_generation;
    setState(() => selected = index);
    final key = _storageKey;
    if (key == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(key, label);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.sections.keys.toList();
    if (selected >= labels.length) selected = 0;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final tabStyle = TextStyle(
      fontFamily: 'Nunito',
      fontSize: metrics.fontSize(13),
      fontWeight: FontWeight.w800,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.accent.withValues(alpha: .12)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widths = labels.map((label) {
                final painter = TextPainter(
                  text: TextSpan(text: label, style: tabStyle),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                return painter.width + 28;
              }).toList();
              final equalWidth = constraints.maxWidth / labels.length;
              final scrolls = widths.any((width) => width > equalWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      SizedBox(
                        width: scrolls ? widths[index] : equalWidth,
                        child: Semantics(
                          selected: selected == index,
                          child: HocalistPressFeedback(
                            child: AnimatedContainer(
                              duration: HocalistMotion.duration(context, 180),
                              decoration: BoxDecoration(
                                color: selected == index
                                    ? widget.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: TextButton(
                                key: ValueKey('section-tab-${labels[index]}'),
                                onPressed: () =>
                                    unawaited(_select(index, labels[index])),
                                style: TextButton.styleFrom(
                                  foregroundColor: selected == index
                                      ? Colors.white
                                      : Theme.of(context).brightness ==
                                            Brightness.dark
                                      ? Theme.of(context).colorScheme.onSurface
                                      : widget.accent,
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 12,
                                  ),
                                  textStyle: tabStyle,
                                ),
                                child: Text(
                                  labels[index],
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: tabStyle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        for (var index = 0; index < labels.length; index++)
          Offstage(
            offstage: selected != index,
            child: TickerMode(
              enabled: selected == index,
              child: HocalistStateTransition(
                stateKey: selected == index,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in widget.sections[labels[index]]!) ...[
                      child,
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
