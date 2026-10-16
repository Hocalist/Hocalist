import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import 'photo_bytes.dart';

/// Browser camera uses an explicit live preview rather than an upload input
/// whose capture hint desktop browsers ignore. Audio is never requested.
class PhotoCameraPage extends StatefulWidget {
  const PhotoCameraPage({
    this.seller = false,
    this.autoStart = false,
    super.key,
  });
  final bool autoStart;
  final bool seller;
  @override
  State<PhotoCameraPage> createState() => _PhotoCameraPageState();
}

class _PhotoCameraPageState extends State<PhotoCameraPage> {
  final renderer = RTCVideoRenderer();
  MediaStream? stream;
  bool busy = false;
  bool ready = false;
  String? error;
  int generation = 0;
  bool rendererReady = false;

  Widget notice(String title, String body, {bool failed = false}) =>
      widget.seller
      ? SellerStateNotice(
          icon: Icons.camera_alt_outlined,
          title: title,
          body: body,
          tone: failed ? SellerNoticeTone.error : SellerNoticeTone.neutral,
        )
      : BuyerStateNotice(
          icon: Icons.camera_alt_outlined,
          title: title,
          body: body,
          tone: failed ? BuyerNoticeTone.error : BuyerNoticeTone.neutral,
        );

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(start());
      });
    }
  }

  Future<void> start() async {
    if (busy || ready) return;
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    MediaStream? opened;
    try {
      if (!rendererReady) {
        await renderer.initialize().timeout(const Duration(seconds: 10));
        rendererReady = true;
      }
      if (!mounted || run != generation) {
        await renderer.dispose();
        rendererReady = false;
        return;
      }
      var timedOut = false;
      final request = navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      // getUserMedia may remain pending while a browser permission prompt is
      // ignored. A stream returned after timeout must never start a preview.
      request.then((lateStream) async {
        if (!timedOut) return;
        for (final track in lateStream.getTracks()) {
          await track.stop();
        }
        await lateStream.dispose();
      }, onError: (_) {});
      opened = await request.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          timedOut = true;
          throw TimeoutException('camera_permission_pending');
        },
      );
      if (!mounted || run != generation) {
        for (final track in opened.getTracks()) {
          await track.stop();
        }
        await opened.dispose();
        return;
      }
      stream = opened;
      renderer.srcObject = opened;
      setState(() => ready = true);
    } catch (failure) {
      if (mounted && run == generation) {
        setState(
          () => error = failure is TimeoutException
              ? 'The camera did not respond. Allow camera access in your browser, then try again. You can also choose a saved photo.'
              : 'Camera access was not granted or no camera is available. '
                    'Check browser permissions, then try again. You can also upload a photo from your device.',
        );
      }
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  Future<void> capture() async {
    if (busy || !ready || stream == null) return;
    final run = generation;
    setState(() => busy = true);
    try {
      final frame = await stream!.getVideoTracks().first.captureFrame();
      final bytes = preparePrivatePhoto(frame.asUint8List());
      if (mounted && run == generation) {
        Navigator.of(context).pop<Uint8List>(bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The photo could not be captured. Try again or choose a saved photo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    if (rendererReady) renderer.srcObject = null;
    final opened = stream;
    stream = null;
    if (opened != null) {
      for (final track in opened.getTracks()) {
        track.stop();
      }
      opened.dispose();
    }
    if (rendererReady) renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Take photo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (error != null)
            notice('Camera needs attention', error!, failed: true),
          if (!ready && error == null)
            notice(
              'Take a profile photo',
              'Enable your camera to see a preview. Your microphone stays off. '
                  'Only the photo you choose is uploaded.',
            ),
          const SizedBox(height: 12),
          if (ready)
            HocalistExpand(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: RTCVideoView(renderer, mirror: true),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (widget.seller)
            SellerPrimaryButton(
              label: busy
                  ? 'Please wait…'
                  : ready
                  ? 'Use this photo'
                  : 'Enable camera',
              onPressed: busy
                  ? null
                  : ready
                  ? capture
                  : start,
            )
          else
            BuyerPrimaryButton(
              label: busy
                  ? 'Please wait…'
                  : ready
                  ? 'Use this photo'
                  : 'Enable camera',
              onPressed: busy
                  ? null
                  : ready
                  ? capture
                  : start,
            ),
          const SizedBox(height: 8),
          if (widget.seller)
            SellerSecondaryButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            BuyerSecondaryButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    ),
  );
}
