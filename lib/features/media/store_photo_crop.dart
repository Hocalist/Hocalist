import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

Future<Uint8List?> cropStorePhoto(BuildContext context, Uint8List jpeg) async {
  final image = img.decodeJpg(jpeg);
  if (image == null) throw StateError('invalid_image');
  final crop = await showDialog<Rect>(
    context: context,
    builder: (_) => _StorePhotoCropDialog(
      bytes: jpeg,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    ),
  );
  if (crop == null) return null;
  final side = crop.width
      .round()
      .clamp(1, math.min(image.width, image.height))
      .toInt();
  final square = img.copyCrop(
    image,
    x: crop.left.round().clamp(0, image.width - side).toInt(),
    y: crop.top.round().clamp(0, image.height - side).toInt(),
    width: side,
    height: side,
  );
  return img.encodeJpg(square, quality: 88);
}

class _StorePhotoCropDialog extends StatefulWidget {
  const _StorePhotoCropDialog({required this.bytes, required this.imageSize});

  final Uint8List bytes;
  final Size imageSize;

  @override
  State<_StorePhotoCropDialog> createState() => _StorePhotoCropDialogState();
}

class _StorePhotoCropDialogState extends State<_StorePhotoCropDialog> {
  static const double _maxZoom = 3;
  double _zoom = 1;
  late Offset _center = widget.imageSize.center(Offset.zero);
  late Offset _gestureAnchor;
  late double _gestureZoom;

  double get _sourceSide => widget.imageSize.shortestSide / _zoom;

  Rect get _crop =>
      Rect.fromCenter(center: _center, width: _sourceSide, height: _sourceSide);

  void _position(double zoom, Offset center) {
    setState(() {
      _zoom = zoom;
      final half = _sourceSide / 2;
      _center = Offset(
        center.dx.clamp(half, widget.imageSize.width - half),
        center.dy.clamp(half, widget.imageSize.height - half),
      );
    });
  }

  Widget _preview(double side) {
    final crop = _crop;
    final scale = side / crop.width;
    final viewportCenter = Offset(side / 2, side / 2);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _gestureZoom = _zoom;
          _gestureAnchor =
              _center + (details.localFocalPoint - viewportCenter) / scale;
        },
        onScaleUpdate: (details) {
          final zoom = (_gestureZoom * details.scale).clamp(1.0, _maxZoom);
          final sourcePerPixel = widget.imageSize.shortestSide / (zoom * side);
          _position(
            zoom,
            _gestureAnchor -
                (details.localFocalPoint - viewportCenter) * sourcePerPixel,
          );
        },
        child: SizedBox.square(
          key: const Key('storePhotoCropPreview'),
          dimension: side,
          child: Stack(
            children: [
              Positioned(
                left: -crop.left * scale,
                top: -crop.top * scale,
                width: widget.imageSize.width * scale,
                height: widget.imageSize.height * scale,
                child: Image.memory(widget.bytes, fit: BoxFit.fill),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(
        380.0,
        math.min(constraints.maxWidth - 96, constraints.maxHeight * .42),
      );
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        title: const Text('Crop listing photo'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Drag to move the photo. Pinch or use the slider to zoom. '
                'The square shown here is what’s saved to the listing.',
              ),
              const SizedBox(height: 12),
              Center(child: _preview(side)),
              const SizedBox(height: 8),
              const Text('Zoom'),
              Slider(
                value: _zoom,
                min: 1,
                max: _maxZoom,
                onChanged: (zoom) => _position(zoom, _center),
                semanticFormatterCallback: (zoom) =>
                    '${zoom.toStringAsFixed(1)}×',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _position(1, widget.imageSize.center(Offset.zero)),
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_crop),
            child: const Text('Use crop'),
          ),
        ],
      );
    },
  );
}
