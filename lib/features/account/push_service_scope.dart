import 'package:flutter/widgets.dart';
import '../../data/phase2/providers/hocalist_push_service.dart';

class PushServiceScope extends InheritedWidget {
  const PushServiceScope({
    required this.service,
    required super.child,
    super.key,
  });
  final HocalistPushService? service;
  static HocalistPushService? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PushServiceScope>()?.service;
  @override
  bool updateShouldNotify(PushServiceScope oldWidget) =>
      service != oldWidget.service;
}
