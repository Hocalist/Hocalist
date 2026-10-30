import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/media/private_remote_image.dart';
import 'package:hocalist/features/media/photo_preview.dart';

void main() {
  testWidgets('authorised photo opens full preview and closes back to thumbnail', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PrivateRemoteImage(id: 'photo', read: (_) async => png))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Photo'), findsNothing);
    expect(find.text('Pinch to zoom'), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.bySemanticsLabel('Full photo'), findsOneWidget);
    expect(find.ancestor(of: find.bySemanticsLabel('Full photo'),
      matching: find.byType(ClipOval)), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo preview'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
  testWidgets(
    'replaced image waits for its own data and ignores the old completion',
    (tester) async {
      final a = Completer<Uint8List>(), b = Completer<Uint8List>();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      );
      Future<Uint8List> read(String id) => id == 'a' ? a.future : b.future;
      Widget page(String id) => MaterialApp(
        home: Scaffold(
          body: PrivateRemoteImage(id: id, read: read),
        ),
      );
      await tester.pumpWidget(page('a'));
      await tester.pumpWidget(page('b'));
      a.complete(png);
      await tester.pump();
      expect(find.byType(PhotoPreview), findsNothing);
      b.complete(png);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
