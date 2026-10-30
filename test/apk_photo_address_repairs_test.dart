import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/place_capture_sheet.dart';
import 'package:hocalist/features/media/private_image_picker.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

void main() {
  testWidgets('saved photos count toward the upload limit', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PrivateImagePicker(
      existingImageCount: 10,
      upload: (_, _) async => 'synthetic', onChanged: (_) {},
    ))));
    final button = tester.widget<SellerPrimaryButton>(find.byType(SellerPrimaryButton));
    expect(button.onPressed, isNull);
  });
  testWidgets('saved listing photos suppress the empty upload notice', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PrivateImagePicker(
      existingImageCount: 1,
      upload: (_, _) async => 'synthetic', onChanged: (_) {},
    ))));
    expect(find.text('Your photos'), findsNothing);
    expect(find.text('Add photo'), findsOneWidget);
  });
  testWidgets('private address picker has no meeting-sharing instructions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      PlaceCaptureSheet(privateAddress: true))));
    expect(find.text('Choose your saved address'), findsOneWidget);
    expect(find.textContaining('Your exact address stays private'), findsOneWidget);
    expect(find.text('Choose the meeting place'), findsNothing);
  });
}
