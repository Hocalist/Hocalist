import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Views bytes already authorised by the owning media reader; no public URLs.
class PhotoPreview extends StatelessWidget {
  const PhotoPreview({required this.bytes, required this.child, super.key});
  final Uint8List bytes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open photo preview',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog.fullscreen(
              backgroundColor: Colors.transparent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Image.memory(bytes, fit: BoxFit.cover),
                    ),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: .65)),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 72, 24, 48),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final side = constraints.maxWidth < constraints.maxHeight
                              ? constraints.maxWidth
                              : constraints.maxHeight;
                          final image = Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            semanticLabel: 'Full photo',
                          );
                          return Center(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: SizedBox.square(
                                      dimension: side.clamp(0, 440),
                                      child: ClipOval(child: image),
                                    )
                                  ,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: IconButton.filled(
                          tooltip: 'Close photo preview',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: .35),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
