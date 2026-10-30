import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:hocalist/platform/android_plugin_configuration.dart';

void main() {
  test('Android uses the direct photo picker', () {
    final oldPicker = ImagePickerPlatform.instance;
    final picker = ImagePickerAndroid();
    ImagePickerPlatform.instance = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      ImagePickerPlatform.instance = oldPicker;
      debugDefaultTargetPlatformOverride = null;
    });
    configureAndroidPlugins();
    expect(picker.useAndroidPhotoPicker, isTrue);
  });
  test('iOS defaults remain untouched', () {
    final oldPicker = ImagePickerPlatform.instance;
    final picker = ImagePickerAndroid();
    ImagePickerPlatform.instance = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() { ImagePickerPlatform.instance = oldPicker; debugDefaultTargetPlatformOverride = null; });
    configureAndroidPlugins();
    expect(picker.useAndroidPhotoPicker, isFalse);
  });
}
