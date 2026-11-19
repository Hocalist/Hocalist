import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ContactVerificationFailure implements Exception {
  const ContactVerificationFailure(this.message);
  final String message;
}

/// Contact verification responses never replace the app session.
abstract interface class ContactVerificationGateway {
  Future<User> load();
  Future<bool> sendPhone(String phone);
  Future<bool> confirmPhone(String phone, String code);
  Future<void> resendEmail();
}

class ContactVerificationService implements ContactVerificationGateway {
  ContactVerificationService(this.client);
  final SupabaseClient client;
  String? _pendingPhone, _pendingUser;
  Session _session() {
    final s = client.auth.currentSession;
    if (s == null) {
      throw const ContactVerificationFailure('Please sign in again.');
    }
    return s;
  }

  void _same(String id) {
    if (client.auth.currentUser?.id != id) {
      throw const ContactVerificationFailure(
        'Your account changed. Please reopen verification.',
      );
    }
  }

  @override
  Future<User> load() async {
    final s = _session();
    final u = (await client.auth.getUser(s.accessToken)).user;
    _same(s.user.id);
    if (u == null || u.id != s.user.id) {
      throw const ContactVerificationFailure(
        'Could not check your verification. Please try again.',
      );
    }
    return u;
  }

  Future<void> _request(
    Session s,
    String path,
    Map<String, Object?> body, {
    bool update = false,
  }) async {
    _same(s.user.id);
    final base = client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    final url = Uri.parse('$base/auth/v1/$path');
    final headers = {
      ...client.auth.headers,
      'Authorization': 'Bearer ${s.accessToken}',
      'Content-Type': 'application/json',
    };
    final transport = client.rest.httpClient ?? http.Client();
    try {
      final r =
          await (update
                  ? transport.put(url, headers: headers, body: jsonEncode(body))
                  : transport.post(
                      url,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 30));
      _same(s.user.id);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        var code = '';
        try {
          final v = jsonDecode(r.body);
          if (v is Map) code = '${v['code'] ?? v['error_code'] ?? ''}';
        } catch (_) {}
        throw ContactVerificationFailure(switch (code) {
          'otp_expired' || 'invalid_otp' || 'invalid_token' =>
            'That code is incorrect or expired. Request a new code.',
          'phone_exists' => 'This number is already linked to another account.',
          'over_sms_send_rate_limit' ||
          'over_email_send_rate_limit' ||
          'too_many_requests' => 'Please wait before requesting another code.',
          _ => 'Verification is unavailable right now. Please try again later.',
        });
      }
    } on ContactVerificationFailure {
      rethrow;
    } catch (_) {
      throw const ContactVerificationFailure(
        'Could not confirm the result. Check your verification status before trying again.',
      );
    } finally {
      if (client.rest.httpClient == null) transport.close();
    }
  }

  @override
  Future<bool> sendPhone(String phone) async {
    phone = phone.trim();
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
      throw const ContactVerificationFailure(
        'Enter your number with country code, for example +1 followed by the number.',
      );
    }
    final s = _session();
    final u = await load();
    _same(s.user.id);
    if (u.phone?.replaceAll('+', '') == phone.substring(1) &&
        u.phoneConfirmedAt != null) {
      return true;
    }
    await _request(s, 'user', {'phone': phone}, update: true);
    _pendingPhone = phone;
    _pendingUser = s.user.id;
    return false;
  }

  @override
  Future<bool> confirmPhone(String phone, String code) async {
    final s = _session();
    if (_pendingUser != s.user.id || _pendingPhone != phone.trim()) {
      throw const ContactVerificationFailure(
        'Request a code for this number first.',
      );
    }
    if (!RegExp(r'^[0-9]{4,10}$').hasMatch(code.trim())) {
      throw const ContactVerificationFailure(
        'Enter the code from your text message.',
      );
    }
    await _request(s, 'verify', {
      'phone': phone.trim(),
      'token': code.trim(),
      'type': 'phone_change',
    });
    final u = await load();
    _same(s.user.id);
    final verified =
        u.phone?.replaceAll('+', '') == phone.trim().substring(1) &&
        u.phoneConfirmedAt != null;
    if (verified) {
      _pendingPhone = null;
      _pendingUser = null;
    }
    return verified;
  }

  @override
  Future<void> resendEmail() async {
    final s = _session();
    final u = await load();
    _same(s.user.id);
    if (u.emailConfirmedAt != null) return;
    if (u.email?.isNotEmpty != true) {
      throw const ContactVerificationFailure(
        'Add an email in Account Settings first.',
      );
    }
    await _request(s, 'resend', {'type': 'signup', 'email': u.email});
  }
}
