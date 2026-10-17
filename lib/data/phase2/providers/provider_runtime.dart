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

const hocalistWifiTestOrigin = String.fromEnvironment(
  'HOCALIST_WIFI_TEST_ORIGIN',
);

const hocalistHttpsTestOrigin = String.fromEnvironment(
  'HOCALIST_HTTPS_TEST_ORIGIN',
);

/// Preview access requires an explicit build flag and an exact local/test origin.
/// Hosted production domains are not admitted by the default build.
bool isHocalistLocalWebTestOrigin(
  Uri uri, {
  required bool enabled,
  String httpsTestOrigin = hocalistHttpsTestOrigin,
}) {
  if (!enabled) return false;
  if (uri.scheme == 'http') {
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        (hocalistWifiTestOrigin.isNotEmpty &&
            uri.origin == hocalistWifiTestOrigin);
  }
  return uri.scheme == 'https' &&
      httpsTestOrigin.isNotEmpty &&
      uri.origin == httpsTestOrigin;
}

bool get hocalistLocalWebTest =>
    kIsWeb &&
    isHocalistLocalWebTestOrigin(
      Uri.base,
      enabled: hocalistLocalWebTestEnabled,
    );

/// Supabase rejects non-loopback IP callbacks before its allowlist is checked.
bool supportsHocalistOAuthReturn(Uri uri) =>
    uri.scheme == 'https' ||
    (uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1'));

/// Move an unsupported local preview to its configured HTTPS origin before
/// starting OAuth, so the PKCE verifier is created on the destination origin.
Uri? hocalistSecurePreviewHandoff(
  Uri current, {
  String secureOrigin = hocalistHttpsTestOrigin,
}) {
  if (supportsHocalistOAuthReturn(current) || secureOrigin.isEmpty) return null;
  final destination = Uri.tryParse(secureOrigin);
  if (destination == null ||
      destination.scheme != 'https' ||
      destination.host.isEmpty ||
      destination.userInfo.isNotEmpty ||
      destination.origin != secureOrigin) {
    return null;
  }
  return destination.replace(path: '/');
}

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
  Future<String> freshToken({Duration minimumValidity = Duration.zero}) async {
    check();
    final token = await freshSessionToken(
      client,
      minimumValidity: minimumValidity,
    );
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
