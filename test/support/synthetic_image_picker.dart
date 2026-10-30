import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class SyntheticImagePicker extends ImagePickerPlatform {
  int calls = 0;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    final image = img.Image(width: 16, height: 16);
    img.fill(image, color: img.ColorRgb8(0, 3, 108));
    return XFile.fromData(
      Uint8List.fromList(img.encodePng(image)),
      name: 'synthetic.png',
      mimeType: 'image/png',
    );
  }
}
