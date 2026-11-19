import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePresentationBackend {
  ProfilePresentationBackend(this.client) : owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? owner;
  Future<Map<String, dynamic>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (owner == null || client.auth.currentUser?.id != owner)
      throw StateError('Please sign in again.');
    final value = await client.schema('hocalist').rpc(function, params: params);
    if (client.auth.currentUser?.id != owner)
      throw StateError('Your account changed.');
    return Map<String, dynamic>.from(value as Map);
  }

  Future<Map<String, dynamic>> publicSeller(String profileId) =>
      _call('seller_profile_public', {'p_profile': profileId});
  Future<Map<String, dynamic>> visibility([Map<String, Object?>? input]) =>
      _call('seller_profile_visibility', {'p_input': input});
}
