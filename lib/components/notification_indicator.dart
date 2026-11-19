import 'package:flutter/material.dart';

class NotificationIndicatorScope extends InheritedWidget {
  const NotificationIndicatorScope({required this.unreadCount, required super.child, super.key});
  final int? unreadCount;
  static bool showDot(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<NotificationIndicatorScope>()?.unreadCount ?? 0) > 0;
  @override
  bool updateShouldNotify(NotificationIndicatorScope oldWidget) => oldWidget.unreadCount != unreadCount;
}

/// The bell stays intact; unread status is a separate indicator.
class NotificationArtwork extends StatelessWidget {
  const NotificationArtwork({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (NotificationIndicatorScope.showDot(context))
        Positioned(top: 1, right: 1, child: Container(
          key: const Key('buyerNotificationUnreadDot'),
          width: 7, height: 7,
          decoration: const BoxDecoration(color: Color(0xffff263c), shape: BoxShape.circle),
        )),
    ],
  );
}
