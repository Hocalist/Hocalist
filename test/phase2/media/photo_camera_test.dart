import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/media/photo_camera_page.dart';

void main() {
  testWidgets('opening the camera prompt requests video without a setup page', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async {
        calls.add(call);
        if (call.method == 'createVideoRenderer') return {'textureId': 1};
        if (call.method == 'getUserMedia') {
          throw PlatformException(code: 'NotAllowedError');
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: PhotoCameraPage(autoStart: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(calls.where((c) => c.method == 'getUserMedia'), hasLength(1));
    expect(find.text('Camera needs attention'), findsOneWidget);
  });

  testWidgets(
    'permission timeout is retryable and late camera streams are stopped',
    (tester) async {
      final media = Completer<Object?>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        (call) async {
          calls.add(call.method);
          if (call.method == 'createVideoRenderer') return {'textureId': 1};
          if (call.method == 'getUserMedia') return media.future;
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: PhotoCameraPage()));
      await tester.tap(find.text('Enable camera'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.textContaining('The camera did not respond'), findsOneWidget);
      expect(find.text('Enable camera'), findsOneWidget);
      media.complete({
        'streamId': 'late-camera',
        'audioTracks': [],
        'videoTracks': [
          {
            'id': 'video',
            'label': 'camera',
            'kind': 'video',
            'enabled': true,
            'settings': <String, Object?>{},
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(calls, contains('trackDispose'));
      expect(calls, contains('streamDispose'));
      expect(find.text('Use this photo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera and denied-permission states fit phone widths and text scales',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        (call) async {
          if (call.method == 'createVideoRenderer') return {'textureId': 1};
          if (call.method == 'getUserMedia') {
            throw PlatformException(code: 'NotAllowedError');
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          null,
        ),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.15, 1.3, 1.6]) {
          tester.view.physicalSize = Size(width, 640);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: PhotoCameraPage(key: UniqueKey(), seller: true),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Enable camera'),
            160,
            scrollable: find.byType(Scrollable),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Enable camera'));
          await tester.pumpAndSettle();
          expect(find.text('Camera needs attention'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$width/$scale');
        }
      }
    },
  );
  testWidgets('camera is explicit, audio stays off, denial is retryable', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async {
        calls.add(call);
        if (call.method == 'createVideoRenderer') return {'textureId': 1};
        if (call.method == 'getUserMedia') {
          throw PlatformException(code: 'NotAllowedError');
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: PhotoCameraPage()));
    expect(calls, isEmpty);
    await tester.tap(find.text('Enable camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera needs attention'), findsOneWidget);
    final constraints =
        (calls.singleWhere((c) => c.method == 'getUserMedia').arguments
                as Map)['constraints']
            as Map;
    expect(constraints['audio'], false);
    await tester.tap(find.text('Enable camera'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'createVideoRenderer').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a camera opened after cancellation is stopped and never mounted',
    (tester) async {
      final media = Completer<Object?>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        (call) async {
          calls.add(call.method);
          if (call.method == 'createVideoRenderer') return {'textureId': 1};
          if (call.method == 'getUserMedia') return media.future;
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: PhotoCameraPage()));
      await tester.tap(find.text('Enable camera'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      media.complete({
        'streamId': 'camera',
        'audioTracks': [],
        'videoTracks': [
          {
            'id': 'video',
            'label': 'camera',
            'kind': 'video',
            'enabled': true,
            'settings': <String, Object?>{},
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(calls, contains('trackDispose'));
      expect(calls, contains('streamDispose'));
      expect(tester.takeException(), isNull);
    },
  );
}
