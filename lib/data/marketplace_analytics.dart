import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional Android analytics. Business operations never wait for tracking.
/// Record IDs are used only for local retry protection, never sent to GA4.
class MarketplaceAnalytics {
  MarketplaceAnalytics([
    this._channel = const MethodChannel('hocalist/marketplace_analytics'),
  ]);

  static final instance = MarketplaceAnalytics();
  final MethodChannel _channel;
  Future<void> _pending = Future<void>.value();

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> consent() async =>
      supported &&
      (await _channel
              .invokeMethod<bool>('getConsent')
              .timeout(const Duration(seconds: 3)) ??
          false);

  Future<void> setConsent(bool enabled) async {
    if (!supported) return;
    final saved = await _channel
        .invokeMethod<bool>('setConsent', enabled)
        .timeout(const Duration(seconds: 3));
    if (saved != true) throw StateError('Analytics preference was not saved.');
  }

  Future<void> buyerRequestSubmitted(String requestId) =>
      _recordOnce('buyer_request_submitted', requestId);

  Future<void> sellerProfileCreated(String membershipId) =>
      _recordOnce('seller_signup_completed', membershipId);

  Future<void> _recordOnce(String event, String recordId) {
    if (!supported || recordId.trim().isEmpty) return Future<void>.value();
    _pending = _pending.then((_) async {
      try {
        if (!await consent()) return;
        final preferences = await SharedPreferences.getInstance();
        final key = 'hocalist.analytics.sent.$event.$recordId';
        if (preferences.getBool(key) == true) return;
        // Prefer a missed measurement to counting the same saved action twice
        // after a crash or lost platform-channel response.
        if (!await preferences.setBool(key, true)) return;
        await _channel
            .invokeMethod<bool>(event)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Analytics must never fail signup, request posting or navigation.
      }
    });
    return _pending;
  }
}
