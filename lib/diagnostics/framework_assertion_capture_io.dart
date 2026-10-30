import 'dart:io';
import 'package:flutter/foundation.dart';

bool _installed = false;

/// Keeps framework assertions in the debug app's private cache for USB diagnosis.
/// No network reporting, form contents, or ordinary auth/network errors are saved.
void installFrameworkAssertionCapture() {
  if (!kDebugMode || _installed) return;
  _installed = true;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception is AssertionError) {
      try {
        final file = File(
          '${Directory.systemTemp.path}/hocalist-assertions.log',
        );
        final entry =
            '${DateTime.now().toUtc().toIso8601String()}\n'
            '${details.exceptionAsString()}\n${details.stack ?? ''}\n\n';
        final old = file.existsSync() && file.lengthSync() < 65536
            ? file.readAsStringSync()
            : '';
        final combined = '$old$entry';
        file.writeAsStringSync(
          combined.length > 65536
              ? combined.substring(combined.length - 65536)
              : combined,
        );
      } catch (_) {
        // Diagnostics must never replace or interrupt Flutter's error handling.
      }
    }
    previous?.call(details);
  };
}
