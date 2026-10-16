import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:hocalist/features/media/photo_bytes.dart';

void main() {
  test(
    'browser PNG becomes bounded JPEG without retaining source metadata',
    () {
      final input = img.Image(width: 2100, height: 1400);
      input.textData = {'location': 'private source metadata'};
      final result = preparePrivatePhoto(
        Uint8List.fromList(img.encodePng(input)),
      );
      expect(result.take(2), [255, 216]);
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 1600);
      expect(decoded.height, lessThanOrEqualTo(1600));
      expect(decoded.textData, isNull);
      expect(result.length, lessThan(4 * 1024 * 1024));
    },
  );
  test('invalid and oversized inputs fail before upload', () {
    expect(
      () => preparePrivatePhoto(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
    expect(
      () => preparePrivatePhoto(Uint8List(8 * 1024 * 1024 + 1)),
      throwsStateError,
    );
  });
}
