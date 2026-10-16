import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// All picker sources become bounded JPEGs without original metadata.
/// Browser image pickers ignore quality/resize options and may return PNGs.
Uint8List preparePrivatePhoto(Uint8List bytes) {
  if (bytes.length < 32) throw StateError('invalid_image');
  if (bytes.length > 8 * 1024 * 1024) {
    throw StateError('image_too_large');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24 * 1024 * 1024) {
    throw StateError('invalid_image');
  }
  var image = decoder!.decodeFrame(0);
  if (image == null) throw StateError('invalid_image');
  image = img.bakeOrientation(image);
  if (image.width > 1600 || image.height > 1600) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1600 : null,
      height: image.height > image.width ? 1600 : null,
    );
  }
  // Copy pixels rather than retaining EXIF/GPS or container metadata.
  final clean = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  img.compositeImage(clean, image);
  final result = Uint8List.fromList(img.encodeJpg(clean, quality: 82));
  if (result.length > 4 * 1024 * 1024) throw StateError('image_too_large');
  return result;
}
