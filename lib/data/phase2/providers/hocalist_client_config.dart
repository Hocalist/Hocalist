/// Explicit public client configuration for real-provider mode.
///
/// Only the publishable/anon client key is accepted, and only through a
/// compile-time `--dart-define`:
///
/// ```
/// flutter run --dart-define=HOCALIST_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
///
/// Never pass `.env.hocalist.server.local` or any server/service credential to
/// `--dart-define-from-file`. An empty value keeps the app in explicit
/// prototype mode; there is no silent fallback from a configured value to
/// simulated authentication.
library;

class HocalistClientConfig {
  const HocalistClientConfig({required this.publishableKey});

  static const String publishableKeyEnvironmentName =
      'HOCALIST_SUPABASE_PUBLISHABLE_KEY';

  /// Empty when the app was built without a public key.
  static const HocalistClientConfig fromEnvironment = HocalistClientConfig(
    publishableKey: String.fromEnvironment(publishableKeyEnvironmentName),
  );

  final String publishableKey;

  /// Real-provider mode is requested when a public key was supplied.
  bool get isConfigured => publishableKey.trim().isNotEmpty;

  @override
  String toString() =>
      'HocalistClientConfig(configured: $isConfigured, key: [redacted])';
}
