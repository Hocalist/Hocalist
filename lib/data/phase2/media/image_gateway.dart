import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/fresh_session_token.dart';

typedef ImageUpload = Future<String> Function(Uint8List bytes, String key);

String photoUploadFailureMessage(Object error) {
  if (error is TimeoutException) {
    return 'The photo upload timed out. Try again.';
  }
  if (error is http.ClientException) {
    return 'The photo upload could not reach the server. Try again.';
  }
  final code = error is StateError ? error.message : null;
  return switch (code) {
    'invalid_image' =>
      'This photo format could not be read. Choose a JPEG or PNG photo.',
    'image_too_large' => 'This photo is too large. Choose a smaller photo.',
    'signed_out' || 'session_changed' =>
      'Your session changed. Sign in again before uploading a photo.',
    'invalid_upload_key' =>
      'The photo upload could not start. Refresh the app and try again.',
    'upload_unauthorized' =>
      'Your session could not authorize the upload. Sign in again.',
    'upload_rejected' =>
      'The server rejected this photo. Choose another JPEG or PNG photo.',
    'upload_unavailable' =>
      'The photo server is unavailable. Try again shortly.',
    _ => 'The photo could not be uploaded. Try again.',
  };
}

/// Media receipts use a UUID, independently of text account/marketplace keys.
String newMediaUploadKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _mediaKeyPattern = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
typedef MediaPost =
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
    });

/// Upload purposes the media gateway accepts. `review`/`report` are private
/// evidence; they must never be rendered through a generic profile/chat
/// surface.
const Set<String> hocalistMediaUploadPurposes = {
  'offer',
  'store',
  'profile',
  'chat',
  'review',
  'report',
};

ImageUpload? configuredImageUpload(String purpose) {
  if (!hocalistMediaUploadPurposes.contains(purpose)) return null;
  try {
    final gateway = ImageGateway(Supabase.instance.client);
    return (bytes, key) => gateway.upload(bytes, key, purpose);
  } catch (_) {
    return null;
  }
}

class ImageGateway {
  ImageGateway(this.client, {MediaPost? post}) : _post = post ?? http.post;
  final SupabaseClient client;
  final MediaPost _post;
  Future<Uint8List> read(String id) async {
    final session = client.auth.currentSession;
    if (session == null) throw StateError('signed_out');
    final token = await freshSessionToken(client);
    if (token == null || client.auth.currentUser?.id != session.user.id) {
      throw StateError('session_changed');
    }
    final response = await _post(
      Uri.parse(
        'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-media',
      ).replace(queryParameters: {'action': 'read', 'id': id}),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    if (client.auth.currentSession?.user.id != session.user.id ||
        response.statusCode != 200) {
      throw StateError('image_unavailable');
    }
    return response.bodyBytes;
  }

  Future<String> upload(Uint8List bytes, String key, String purpose) async {
    if (!_mediaKeyPattern.hasMatch(key)) {
      throw StateError('invalid_upload_key');
    }
    final session = client.auth.currentSession;
    if (session == null) throw StateError('signed_out');
    final token = await freshSessionToken(client);
    if (token == null || client.auth.currentUser?.id != session.user.id) {
      throw StateError('session_changed');
    }
    if (bytes.length > 4 * 1024 * 1024) throw StateError('image_too_large');
    final response = await _post(
      Uri.parse(
        'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-media?action=upload',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'image/jpeg',
        'x-upload-key': key,
        'x-media-purpose': purpose,
      },
      body: bytes,
    ).timeout(const Duration(seconds: 35));
    if (client.auth.currentSession?.user.id != session.user.id) {
      throw StateError('session_changed');
    }
    if (response.statusCode != 200) {
      throw StateError(switch (response.statusCode) {
        401 || 403 => 'upload_unauthorized',
        400 || 413 => 'upload_rejected',
        _ => 'upload_unavailable',
      });
    }
    final data = jsonDecode(response.body);
    final id = data is Map ? data['id'] : null;
    if (id is! String ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
        ).hasMatch(id)) {
      throw StateError('invalid_response');
    }
    return id;
  }
}
