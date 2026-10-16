import 'package:flutter/material.dart';

class NotificationIndicatorScope extends InheritedWidget {
  const NotificationIndicatorScope({
    required this.unreadCount,
    required super.child,
    super.key,
  });

  /// Null preserves the approved prototype artwork. Real inboxes use a count.
  final int? unreadCount;
  static bool showDot(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NotificationIndicatorScope>()
          ?.unreadCount !=
      0;
  @override
  bool updateShouldNotify(NotificationIndicatorScope oldWidget) =>
      oldWidget.unreadCount != unreadCount;
}

/// Keeps the supplied bell artwork and removes its embedded status dot when
/// the authoritative inbox has no unread events.
class NotificationArtwork extends StatelessWidget {
  const NotificationArtwork({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      NotificationIndicatorScope.showDot(context)
      ? child
      : ClipPath(clipper: const _UnreadDotClipper(), child: child);
}

class _UnreadDotClipper extends CustomClipper<Path> {
  const _UnreadDotClipper();
  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    Path()..addOval(
      Rect.fromLTRB(size.width * .61, 0, size.width * 1.04, size.height * .44),
    ),
  );
  @override
  bool shouldReclip(_UnreadDotClipper oldClipper) => false;
}
