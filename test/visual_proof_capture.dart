import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class ProofAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (!key.startsWith('assets/')) return rootBundle.load(key);
    return SynchronousFuture(ByteData.sublistView(File(key).readAsBytesSync()));
  }
}

Directory get visualProofDirectory =>
    Directory('${Directory.systemTemp.path}/hocalist-design-proof')
      ..createSync(recursive: true);

Future<void> paintProofArtwork(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    final pending = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image == null);
    if (pending.isEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 16)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image == null),
    isEmpty,
    reason: 'Artwork must be painted before capturing.',
  );
}

Future<void> writeProofImage(
  WidgetTester tester,
  Finder surface,
  String name,
) async {
  await paintProofArtwork(tester);
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(surface));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${visualProofDirectory.path}/$name');
      await file.writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(file.lengthSync(), greaterThan(1000));
    } finally {
      image.dispose();
    }
  });
}
