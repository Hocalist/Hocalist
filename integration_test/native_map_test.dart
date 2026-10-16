import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hocalist/features/approved/hocalist_map_surface.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual confirmed-place surface initializes on Android', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => buildGoogleMapSurface(
              context,
              latitude: 41.8762,
              longitude: -87.6281,
              onMoved: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('hocalistGoogleMap')), findsOneWidget);
    // Allow the real emulator/network to finish loading remote map tiles.
    for (var frame = 0; frame < 160; frame++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('native-confirmed-place-map');
  });
}
