import 'package:flutter/foundation.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Native Android compatibility settings; other platforms retain their defaults.
void configureAndroidPlugins() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
}
