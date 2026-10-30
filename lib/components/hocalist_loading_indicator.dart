import 'package:flutter/material.dart';

/// One branded loading treatment for full screens and compact controls.
class HocalistLoadingIndicator extends StatefulWidget {
  const HocalistLoadingIndicator({this.color, this.strokeWidth = 2, super.key});
  final Color? color;
  final double strokeWidth;

  @override
  State<HocalistLoadingIndicator> createState() =>
      _HocalistLoadingIndicatorState();
}

class _HocalistLoadingIndicatorState extends State<HocalistLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    liveRegion: true,
    child: SizedBox.square(
      dimension: 28,
      child: RotationTransition(
        turns: _pulse,
        child: Image.asset(
          'assets/brand/hocalist-icon.png',
          cacheWidth: 128,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}
