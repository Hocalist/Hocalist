import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/fresh_session_token.dart';

const hocalistSupabaseUrl = 'https://icqwbzswokoulatomgql.supabase.co';
const hocalistAuthCallback = 'com.hocalist.app://login-callback/';
const hocalistLocalWebTestEnabled = bool.fromEnvironment(
  'HOCALIST_LOCAL_WEB_TEST',
);

/// Real web access is limited to an explicitly flagged loopback preview.
/// The same build returns to mobile-only behavior on any hosted domain.
bool isHocalistLocalWebTestOrigin(Uri uri, {required bool enabled}) =>
    enabled &&
    uri.scheme == 'http' &&
    (uri.host == 'localhost' || uri.host == '127.0.0.1');

bool get hocalistLocalWebTest =>
    kIsWeb &&
    isHocalistLocalWebTestOrigin(
      Uri.base,
      enabled: hocalistLocalWebTestEnabled,
    );

String get hocalistAuthRedirect =>
    hocalistLocalWebTest ? '${Uri.base.origin}/' : hocalistAuthCallback;
const providerStorage = FlutterSecureStorage();

/// Safe for UI display/logging; never includes a provider response or input.
class ProviderOperationException implements Exception {
  const ProviderOperationException(this.code);
  final String code;
  @override
  String toString() => 'ProviderOperationException($code)';
}

String secureHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String providerRequestId() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Mobile sessions live in OS-backed secure storage, separately from demo data.
class HocalistSessionStorage extends LocalStorage {
  const HocalistSessionStorage();
  static const _key = 'hocalist.auth.session.v1';
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => providerStorage.read(key: _key);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) =>
      providerStorage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => providerStorage.delete(key: _key);
}

/// Explicit bootstrap for the real mobile composition. No env file is loaded.
/// Never pass the server env to --dart-define-from-file.
Future<SupabaseClient> initializeHocalistProviders({
  required String publicKey,
}) async {
  if ((kIsWeb && !hocalistLocalWebTest) ||
      (!kIsWeb &&
          ![
            TargetPlatform.android,
            TargetPlatform.iOS,
          ].contains(defaultTargetPlatform))) {
    throw const ProviderOperationException('mobile_only');
  }
  var allowed = publicKey.startsWith('sb_publishable_');
  if (!allowed) {
    try {
      final parts = publicKey.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      allowed =
          payload['role'] == 'anon' && payload['ref'] == 'icqwbzswokoulatomgql';
    } catch (_) {
      allowed = false;
    }
  }
  if (!allowed) {
    throw const ProviderOperationException('public_client_key_required');
  }
  await Supabase.initialize(
    url: hocalistSupabaseUrl,
    publishableKey: publicKey,
    debug: false,
    authOptions: hocalistLocalWebTest
        ? const FlutterAuthClientOptions()
        : const FlutterAuthClientOptions(
            localStorage: HocalistSessionStorage(),
          ),
  );
  return Supabase.instance.client;
}

/// Pins each data request to its initiating JWT and discards replaced sessions.
class ProviderSessionFence {
  ProviderSessionFence(this.client) {
    final session = client.auth.currentSession;
    if (session == null) {
      throw const ProviderOperationException('sign_in_required');
    }
    userId = session.user.id;
  }
  final SupabaseClient client;
  late final String userId;
  Future<String> freshToken() async {
    check();
    final token = await freshSessionToken(client);
    check();
    if (token == null) {
      throw const ProviderOperationException('session_changed');
    }
    return token;
  }

  void check() {
    if (client.auth.currentSession?.user.id != userId) {
      throw const ProviderOperationException('session_changed');
    }
  }
}
