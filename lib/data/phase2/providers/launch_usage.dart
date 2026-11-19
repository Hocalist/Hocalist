import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Counts the first authenticated mobile open, not a download or device install.
/// Failure never blocks navigation. Server uniqueness survives reinstall/retry.
Future<void> recordFirstSignedInAppOpen() async {
  if (kIsWeb || ![TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform)) return;
  try {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser?.id;
    if (user == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final prefs = await SharedPreferences.getInstance();
    final key = 'launch-first-open-$user-$platform';
    if (prefs.getBool(key) == true || client.auth.currentUser?.id != user) return;
    await client.schema('hocalist').rpc('launch_record_app_open', params: {'p_platform': platform});
    if (client.auth.currentUser?.id == user) await prefs.setBool(key, true);
  } catch (_) {
    // Retrying next launch is safe; telemetry cannot prevent use of the app.
  }
}
