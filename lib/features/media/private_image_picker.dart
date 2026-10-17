import 'package:hocalist/theme/adaptive_palette.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/phase2/media/image_gateway.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../components/hocalist_motion.dart';
import 'photo_bytes.dart';

/// Private-purpose image picker with role-aware approved controls.
///
/// The picker is embedded by both role surfaces; [role] selects the existing
/// approved component variants without changing either role's design. Uploads
/// keep their retry/discard identity and never fake a completed upload.
class PrivateImagePicker extends StatefulWidget {
  const PrivateImagePicker({
    required this.upload,
    required this.onChanged,
    this.enabled = true,
    this.maxImages = 10,
    this.role = HocalistControlRole.seller,
    this.onPendingChanged,
    super.key,
  });
  final ImageUpload upload;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final int maxImages;
  final HocalistControlRole role;
  final ValueChanged<bool>? onPendingChanged;
  @override
  State<PrivateImagePicker> createState() => _PrivateImagePickerState();
}

class _PrivateImagePickerState extends State<PrivateImagePicker> {
  final images = <String, Uint8List>{};
  Uint8List? pending;
  String? pendingKey, error;
  bool busy = false;

  Future<void> add() async {
    if (busy || !widget.enabled || images.length >= widget.maxImages) return;
    widget.onPendingChanged?.call(true);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (pending == null) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        pending = preparePrivatePhoto(bytes);
        pendingKey = newMediaUploadKey();
      }
      if (!mounted) return;
      final id = await widget.upload(pending!, pendingKey!);
      if (!mounted) return;
      setState(() {
        images[id] = pending!;
        pending = null;
        pendingKey = null;
      });
      widget.onChanged(List.unmodifiable(images.keys));
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Photo could not be uploaded. Retry to finish the same upload.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onPendingChanged?.call(pending != null);
      }
    }
  }

  @override
  void dispose() {
    for (final bytes in images.values) {
      MemoryImage(bytes).evict();
    }
    images.clear();
    pending = null;
    super.dispose();
  }

  bool get _seller => widget.role == HocalistControlRole.seller;

  Widget _progress(String label) => _seller
      ? SellerProgressStrip(label: label)
      : BuyerProgressStrip(label: label);

  Widget _notice({
    required Key key,
    required IconData icon,
    required String title,
    required String body,
  }) => _seller
      ? SellerStateNotice(
          key: key,
          icon: icon,
          tone: SellerNoticeTone.error,
          title: title,
          body: body,
        )
      : BuyerStateNotice(
          key: key,
          icon: icon,
          tone: BuyerNoticeTone.error,
          title: title,
          body: body,
        );

  Widget _primary(String label, VoidCallback? onPressed) => _seller
      ? SellerPrimaryButton(label: label, onPressed: onPressed)
      : BuyerPrimaryButton(label: label, onPressed: onPressed);

  Widget _secondary(String label, VoidCallback? onPressed) => _seller
      ? SellerSecondaryButton(label: label, onPressed: onPressed)
      : BuyerSecondaryButton(label: label, onPressed: onPressed);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isEmpty && !busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _seller
                ? const SellerStateNotice(
                    icon: Icons.photo_library_outlined,
                    tone: SellerNoticeTone.brand,
                    title: 'Your photos',
                    body:
                        'Choose a clear photo using the button below. Uploaded photos will appear here for you to review or remove.',
                  )
                : const BuyerStateNotice(
                    icon: Icons.photo_library_outlined,
                    tone: BuyerNoticeTone.brand,
                    title: 'Your photos',
                    body:
                        'Choose a clear photo using the button below. Uploaded photos will appear here for you to review or remove.',
                  ),
          ),
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: images.entries
                .map(
                  (e) => HocalistEntrance(
                    key: ValueKey(e.key),
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  e.value,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: -6,
                                top: -6,
                                child: Semantics(
                                  button: true,
                                  label: 'Remove photo',
                                  child: SizedBox.square(
                                    dimension: 30,
                                    child: Material(
                                      color: HocalistPalette.surface(
                                        context,
                                        Colors.white,
                                      ),
                                      shape: const CircleBorder(),
                                      elevation: 1,
                                      child: IconButton(
                                        tooltip: 'Remove photo',
                                        padding: EdgeInsets.zero,
                                        onPressed: !widget.enabled || busy
                                            ? null
                                            : () {
                                                MemoryImage(e.value).evict();
                                                setState(
                                                  () => images.remove(e.key),
                                                );
                                                widget.onChanged(
                                                  List.unmodifiable(
                                                    images.keys,
                                                  ),
                                                );
                                              },
                                        icon: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: HocalistPalette.text(
                                            context,
                                            _seller
                                                ? SellerUiColors.primary
                                                : BuyerUiTokens.action,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Uploaded',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: HocalistPalette.text(
                                context,
                                _seller
                                    ? SellerUiColors.muted
                                    : BuyerUiTokens.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        if (error != null) ...[
          const SizedBox(height: 10),
          _notice(
            key: const Key('privateImagePickerError'),
            icon: Icons.error_outline_rounded,
            title: 'Photo could not be uploaded',
            body: error!,
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 10),
          _progress('Uploading photo…'),
        ],
        const SizedBox(height: 10),
        _primary(
          pending == null ? 'Add photo' : 'Retry photo upload',
          busy || !widget.enabled || images.length >= widget.maxImages
              ? null
              : add,
        ),
        if (pending != null && !busy) ...[
          const SizedBox(height: 8),
          _secondary('Discard upload', () {
            if (!widget.enabled) return;
            setState(() {
              pending = null;
              pendingKey = null;
              error = null;
            });
            widget.onPendingChanged?.call(false);
          }),
        ],
      ],
    );
  }
}
