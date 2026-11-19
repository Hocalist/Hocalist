import 'package:flutter/material.dart';

/// Vector versions of the owner-approved small interface artwork. Keeping the
/// badge and glyph separate avoids raster matte fragments on dark surfaces.
class ApprovedInterfaceIcon extends StatelessWidget {
  const ApprovedInterfaceIcon({required this.asset, required this.size, this.color, this.semanticLabel, super.key});
  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  static String? kindFor(String asset) => switch (asset.split('/').last) {
    'notification.png' || 'header-bell.png' || 'header-notification.png' => 'bell',
    'buyer-mode-check.png' || 'header-buyer.png' => 'badge',
    'dashboard-plus.png' => 'plus',
    'activity-chat.png' => 'chat',
    'home-benefit-shield.png' => 'shield',
    'chat-send.png' => 'send',
    'chat-call.png' => 'phone',
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel == null,
    child: SizedBox.square(dimension: size, child: kindFor(asset) == 'bell'
      ? Icon(Icons.notifications_none_rounded, size: size * 27 / 32,
          color: color ?? (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xfff3f3ff) : const Color(0xff10145b)))
      : CustomPaint(
      painter: _InterfacePainter(kindFor(asset)!, color ??
        (Theme.of(context).brightness == Brightness.dark ? const Color(0xfff3f3ff) : const Color(0xff10145b))),
    )),
  );
}

class _InterfacePainter extends CustomPainter {
  const _InterfacePainter(this.kind, this.foreground);
  final String kind;
  final Color foreground;
  static const blue = Color(0xff3518ef);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final stroke = Paint()..color = foreground..style = PaintingStyle.stroke
      ..strokeWidth = 1.65..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = foreground;
    void line(List<Offset> points, {Color? color, double width = 1.8}) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
      canvas.drawPath(path, Paint()..color = color ?? foreground..style = PaintingStyle.stroke
        ..strokeWidth = width..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }
    switch (kind) {
      case 'plus':
        canvas.drawCircle(const Offset(16,16), 14.5, Paint()..shader = const LinearGradient(
          colors: [Color(0xff542cff), Color(0xff2600d9)], begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(const Rect.fromLTWH(1,1,30,30)));
        canvas.drawCircle(const Offset(16,16),14.5,stroke..color=const Color(0xffd8d2ff)..strokeWidth=1);
        line([const Offset(16,8),const Offset(16,24)], color:Colors.white,width:1.6);
        line([const Offset(8,16),const Offset(24,16)], color:Colors.white,width:1.6);
      case 'badge':
        canvas.drawCircle(const Offset(16,15),12.5,Paint()..color=const Color(0xfff0edff));
        canvas.drawCircle(const Offset(16,15),12.5,stroke..color=blue..strokeWidth=1.3);
        canvas.drawCircle(const Offset(16,15),10,stroke..strokeWidth=.8);
        line([const Offset(10,15),const Offset(14,19),const Offset(22,10)],color:blue,width:2);
        line([const Offset(12,29),const Offset(20,29)],color:blue,width:1.5);
      case 'shield':
        canvas.drawCircle(const Offset(16,16),15,Paint()..color=const Color(0xffe9e3ff));
        final path=Path()..moveTo(16,6)..quadraticBezierTo(21,9,25,9)..lineTo(24,20)
          ..quadraticBezierTo(22,25,16,28)..quadraticBezierTo(10,25,8,20)..lineTo(7,9)
          ..quadraticBezierTo(11,9,16,6)..close();
        canvas.drawPath(path,stroke..color=blue..strokeWidth=1.6);
        line([const Offset(12,16),const Offset(15,19),const Offset(21,12)],color:blue,width:1.8);
      case 'chat':
        final path=Path()..moveTo(6,6)..lineTo(26,6)..lineTo(26,23)..lineTo(15,23)
          ..lineTo(9,28)..lineTo(9,23)..lineTo(6,23)..close();
        canvas.drawPath(path,Paint()..color=const Color(0xfff1edff));
        canvas.drawPath(path,stroke..color=blue..strokeWidth=1.6);
        for(final x in [11.0,16.0,21.0]) { canvas.drawCircle(Offset(x,14),1.1,Paint()..color=blue); }
      case 'bell':
        final path=Path()..moveTo(6,24)..quadraticBezierTo(9,21,9,17)..lineTo(9,13)
          ..cubicTo(9,3,23,3,23,13)..lineTo(23,17)..quadraticBezierTo(23,21,26,24)..close();
        canvas.drawPath(path,fill);
        canvas.drawPath(path,stroke);
        canvas.drawArc(const Rect.fromLTWH(13,23,6,6),0,3.14159,false,stroke);
        canvas.drawCircle(const Offset(16,4),1.3,fill);
      case 'send':
        final path=Path()..moveTo(3,13)..lineTo(29,3)..lineTo(21,29)..lineTo(15,19)..close();
        canvas.drawPath(path,stroke);
        line([const Offset(15,19),const Offset(29,3)]);
        line([const Offset(15,19),const Offset(14,26),const Offset(18,23)],width:1.3);
      case 'phone':
        final path=Path()..moveTo(9,4)..lineTo(5,5)..cubicTo(0,10,8,25,20,28)
          ..quadraticBezierTo(25,30,28,24)..lineTo(23,19)..quadraticBezierTo(21,18,19,22)
          ..quadraticBezierTo(12,20,10,13)..quadraticBezierTo(14,11,13,9)..close();
        canvas.drawPath(path,stroke);
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _InterfacePainter old) => kind != old.kind || foreground != old.foreground;
}
