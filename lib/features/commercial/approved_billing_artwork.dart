import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Displays the supplied artwork directly; no substitute icons are generated.
class ApprovedBillingArtwork extends StatefulWidget {
  const ApprovedBillingArtwork({
    required this.source,
    required this.crop,
    this.size = 36,
    super.key,
  });
  final String source;
  final Rect crop;
  final double size;
  @override
  State<ApprovedBillingArtwork> createState() => _ApprovedBillingArtworkState();
}

class _ApprovedBillingArtworkState extends State<ApprovedBillingArtwork> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  ImageInfo? _info;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant ApprovedBillingArtwork old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _load();
  }

  void _load() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = AssetImage(
      widget.source,
    ).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, sync) {
      if (mounted) {
        setState(() {
          _info?.dispose();
          _info = info;
          _image = info.image;
        });
      } else {
        info.dispose();
      }
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _ArtworkPainter(_image, widget.crop)),
    ),
  );
}

class _ArtworkPainter extends CustomPainter {
  _ArtworkPainter(this.image, this.crop);
  final ui.Image? image;
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final source = image;
    if (source != null) {
      canvas.drawImageRect(
        source,
        crop,
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArtworkPainter old) =>
      image != old.image || crop != old.crop;
}
