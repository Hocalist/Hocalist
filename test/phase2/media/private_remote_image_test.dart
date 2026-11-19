import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/media/private_remote_image.dart';
import 'package:hocalist/features/media/photo_preview.dart';

void main() {
  testWidgets('photo preview has its own accessible action apart from removal', (tester) async {
    final semantics = tester.ensureSemantics();
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const Text('Private review'),
      PrivateRemoteImage(id: 'photo', read: (_) async => png),
      TextButton(onPressed: () {}, child: const Text('Remove saved photo')),
    ]))));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open photo preview'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Open photo preview')).label, 'Open photo preview');
    await tester.tap(find.bySemanticsLabel('Open photo preview'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('failed small avatar has a readable retry control', (tester) async {
    var reads=0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width:40,height:40,
      child:PrivateRemoteImage(id:'failed',read:(_) async {reads++;throw Exception('unavailable');})))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Retry photo'),findsOneWidget);
    expect(find.text('Retry photo'),findsNothing);
    await tester.tap(find.byTooltip('Retry photo'));await tester.pumpAndSettle();
    expect(reads,2);expect(tester.takeException(),isNull);
  });

  testWidgets('document preview shows the entire image without circular cropping', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PrivateRemoteImage(id: 'evidence', read: (_) async => png, showWholeImage: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    final full = find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'Full photo');
    expect(tester.widget<Image>(full).fit, BoxFit.contain);
    expect(find.ancestor(of: full, matching: find.byType(ClipOval)), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

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
