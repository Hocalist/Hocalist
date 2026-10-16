import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'provider_runtime.dart';
import '../notifications/push_inbox_router.dart';

/// Android background/terminated message handler.
///
/// Registered in `main()` with `FirebaseMessaging.onBackgroundMessage`. It runs
/// in a separate isolate where the Supabase session is not available and
/// navigation is impossible, so it deliberately does nothing beyond
/// acknowledging delivery. Cold-start taps arrive through
/// `getInitialMessage()` and background taps through `onMessageOpenedApp`;
/// [HocalistPushService] turns both into lookup signals that the inbox router
/// retains until authentication.
///
/// Explicit limit: this is not terminated-app ringing. See
/// `../calls/call_notifications.dart` for the native contract.
@pragma('vm:entry-point')
Future<void> hocalistPushBackgroundHandler(RemoteMessage message) async {}

final RegExp _notificationIdPattern = RegExp(r'^[0-9a-fA-F-]{36}$');

/// Registers the Android background handler. Call once from `main()` before
/// `runApp`. Safe to call before `Firebase.initializeApp`.
void registerHocalistPushBackgroundHandler() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(hocalistPushBackgroundHandler);
  }
}

/// Android transport bridge. Call start once, enable only from a consent action,
/// and disableBeforeLogout before changing the Auth identity. Apple is deferred.
class HocalistPushService {
  HocalistPushService(this.client);
  final SupabaseClient client;
  final _updates = StreamController<String>.broadcast();
  final _signals = StreamController<PushInboxSignal>.broadcast();
  Stream<PushInboxSignal> get signals => _signals.stream;
  final _errors = StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _queue = Future.value();
  bool _started = false;
  Future<void>? _starting;
  bool _closed = false;
  int _generation = 0;
  Stream<String> get notificationIds => _updates.stream;
  Stream<String> get failures => _errors.stream;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _serial(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object _) {});
    return next;
  }

  void _background(Future<void> operation) {
    unawaited(
      operation.catchError((Object _) {
        if (!_closed) _errors.add('push_unavailable');
      }),
    );
  }

  Future<void> start() {
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (!supported || _started || _closed) return;
    await Firebase.initializeApp();
    if (_closed) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    if (_closed) return;
    _started = true;
    _subscriptions.add(
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => _background(sync()),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((m) => _message(m, opened: false)),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _message(m, opened: true),
      ),
    );
    _subscriptions.add(
      client.auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedOut) {
          _generation++;
          _background(_serial(() => FirebaseMessaging.instance.deleteToken()));
        } else if (event.event == AuthChangeEvent.signedIn) {
          _background(sync());
        }
      }),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _message(initial, opened: true);
    await sync();
  }

  void _message(RemoteMessage message, {required bool opened}) {
    final id = message.data['notification_id'];
    if (_closed || id is! String || !_notificationIdPattern.hasMatch(id)) {
      return;
    }
    // The consumer must call fetchNotification; payloads never authorize
    // routes. Emitting while signed out is deliberate: the inbox router retains
    // the tap and replays it after authentication.
    _signals.add(PushInboxSignal(id, opened: opened));
    if (client.auth.currentSession != null) _updates.add(id);
  }

  Future<Map<String, dynamic>> _installation() async {
    const key = 'hocalist.push.installation.v1';
    final saved = await providerStorage.read(key: key);
    if (saved != null) {
      final decoded = jsonDecode(saved);
      if (decoded is Map<String, dynamic> &&
          decoded['id'] is String &&
          decoded['secret'] is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(decoded['secret'])) {
        return decoded;
      }
      throw const ProviderOperationException('invalid_installation');
    }
    final value = {'id': providerRequestId(), 'secret': secureHex(32)};
    await providerStorage.write(key: key, value: jsonEncode(value));
    return value;
  }

  /// Prompt only after the person explicitly chooses notifications.
  Future<bool> isEnabled() async {
    if (!supported) return false;
    await start();
    final fence = ProviderSessionFence(client);
    final consent = await providerStorage.read(
      key: 'hocalist.push.consent.${fence.userId}',
    );
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    fence.check();
    return consent == 'true' &&
        settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Prompt only after the person explicitly chooses notifications.
  Future<void> enable() async {
    if (!_started) throw const ProviderOperationException('push_not_started');
    final fence = ProviderSessionFence(client);
    final settings = await FirebaseMessaging.instance.requestPermission();
    fence.check();
    final enabled =
        settings.authorizationStatus == AuthorizationStatus.authorized;
    await providerStorage.write(
      key: 'hocalist.push.consent.${fence.userId}',
      value: enabled.toString(),
    );
    if (!enabled) {
      await disableBeforeLogout();
      throw const ProviderOperationException('notification_permission_denied');
    }
    await sync();
  }

  /// Call on app resume too: permissions may have changed in Android settings.
  Future<void> sync() {
    final generation = _generation;
    final session = client.auth.currentSession;
    if (!_started || _closed || session == null) return Future.value();
    final fence = ProviderSessionFence(client);
    return _serial(() async {
      if (_closed || generation != _generation) return;
      fence.check();
      final consent = await providerStorage.read(
        key: 'hocalist.push.consent.${fence.userId}',
      );
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      fence.check();
      if (consent != 'true' ||
          settings.authorizationStatus != AuthorizationStatus.authorized) {
        await _disable(fence);
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      final installation = await _installation();
      fence.check();
      if (token == null || generation != _generation || _closed) return;
      await client
          .schema('hocalist')
          .rpc(
            'push_device_register',
            params: {
              'p_id': installation['id'],
              'p_secret': installation['secret'],
              'p_token': token,
              'p_enabled': true,
            },
          )
          .setHeader('Authorization', 'Bearer ${await fence.freshToken()}');
      fence.check();
    });
  }

  Future<void> _disable(ProviderSessionFence fence) async {
    final saved = await providerStorage.read(
      key: 'hocalist.push.installation.v1',
    );
    try {
      fence.check();
      if (saved != null) {
        final installation = jsonDecode(saved) as Map<String, dynamic>;
        await client
            .schema('hocalist')
            .rpc(
              'push_device_disable',
              params: {
                'p_id': installation['id'],
                'p_secret': installation['secret'],
              },
            )
            .setHeader('Authorization', 'Bearer ${await fence.freshToken()}');
      }
    } finally {
      // Best effort local invalidation even if the network/old session has failed.
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  Future<void> disableBeforeLogout() {
    _generation++;
    if (!_started || client.auth.currentSession == null) return Future.value();
    final fence = ProviderSessionFence(client);
    return _serial(() => _disable(fence));
  }

  Future<void> disableConsent() async {
    final fence = ProviderSessionFence(client);
    await providerStorage.write(
      key: 'hocalist.push.consent.${fence.userId}',
      value: 'false',
    );
    await disableBeforeLogout();
  }

  Future<Map<String, dynamic>?> fetchNotification(String id) async {
    final fence = ProviderSessionFence(client);
    try {
      final rows = await client
          .schema('hocalist')
          .from('notifications')
          .select(
            'id,user_id,kind,source_id,created_at,read_at,title,body,deep_link,payload',
          )
          .eq('id', id)
          .eq('user_id', fence.userId)
          .limit(1)
          .setHeader('Authorization', 'Bearer ${await fence.freshToken()}');
      fence.check();
      if (rows.isEmpty) return null;
      if (rows.single['user_id'] != fence.userId) {
        throw const ProviderOperationException('invalid_notification');
      }
      return Map<String, dynamic>.unmodifiable(rows.single);
    } on ProviderOperationException {
      rethrow;
    } catch (_) {
      throw const ProviderOperationException('notification_unavailable');
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _generation++;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _queue;
    await _updates.close();
    await _signals.close();
    await _errors.close();
  }
}
