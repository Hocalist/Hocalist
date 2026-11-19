import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/phase2/account_contacts.dart';
import '../../../domain/phase2/patch.dart';
import 'account_codecs.dart';
import '../discovery/discovery_adapter.dart';
import '../maps/places_repository.dart';

class BusinessAddressBackend {
  BusinessAddressBackend(this.client, {this.places});
  final PlacesRepository? places;
  final Map<String, Map<String,Object?>> _attempts = {};
  final SupabaseClient client;
  Future<PrivateContactRecord> load() async {
    final identity=client.auth.currentUser?.id;
    final row = await _raw(null, null);
    if (row.containsKey('latitude') && row['latitude'] == null && places != null) {
      final input = <String,Object?>{'expected_revision':row['revision']};
      try {
        if (await _resolve(input, row)) {
          if(client.auth.currentUser?.id!=identity) throw StateError('Your account changed.');
          return await _call(input, 'business-location-${row['revision']}');
        }
      } catch (_) { /* The saved address remains usable when lookup fails. */ }
    }
    if(client.auth.currentUser?.id!=identity) throw StateError('Your account changed.');
    return decodePrivateContactRow(row);
  }
  Future<SellerDiscoveryOriginInput> searchDefault(int radius) async {
    var row = await _raw(null, null);
    if (row['latitude'] == null && places != null) {
      await load();
      row = await _raw(null, null);
    }
    return SellerDiscoveryOriginInput(
      areaLabel: (row['city'] as String?)?.trim().isNotEmpty == true ? row['city'] as String : (row['region'] as String?),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      radiusMiles: radius.clamp(1, 500),
    );
  }
  Future<bool> _resolve(Map<String,Object?> input, Map<String,Object?> current) async {
    final merged = {...current,...input};
    if ((merged['address_line1'] as String? ?? '').trim().isEmpty &&
        (merged['city'] as String? ?? '').trim().isEmpty) { return false; }
    final resolver=places;
    if (resolver==null) return false;
    final query=['address_line1','address_line2','city','region','postal_code','country_code']
      .map((key)=>merged[key]).whereType<String>().where((v)=>v.trim().isNotEmpty).join(', ');
    final place=await resolver.resolveAddress(query);
    input['latitude']=place.latitude; input['longitude']=place.longitude;
    final postal=place.postalAddress;
    if(postal?.city?.trim().isNotEmpty==true) input['city']=postal!.city;
    if(postal?.state?.trim().isNotEmpty==true) input['region']=postal!.state;
    if(postal?.postalCode?.trim().isNotEmpty==true) input['postal_code']=postal!.postalCode;
    if(postal?.country?.trim().isNotEmpty==true) input['country_code']=postal!.country;
    return true;
  }
  Future<PrivateContactRecord> save(UpdateContactCommand command) async {
    final identity=client.auth.currentUser?.id;
    final attemptKey=(identity ?? '') + ':' + command.idempotencyKey;
    final replay=_attempts[attemptKey];
    if(replay!=null) return _call(replay,command.idempotencyKey);
    final input=<String,Object?>{'expected_revision':command.expectedRevision};
    void field(String key,Patch<String> patch) {
      if (!patch.isKeep) input[key]=patch.valueOrNull;
    }
    field('address_line1',command.addressLine1); field('address_line2',command.addressLine2);
    field('city',command.city); field('region',command.region);
    field('postal_code',command.postalCode); field('country_code',command.countryCode);
    final current=await _raw(null,null);
    if (current['revision'] != command.expectedRevision) throw StateError('The address changed. Reload before saving.');
    await _resolve(input,current);
    if(client.auth.currentUser?.id!=identity) throw StateError('Your account changed.');
    _attempts[attemptKey]=input;
    return _call(input,command.idempotencyKey);
  }
  Future<PrivateContactRecord> _call(Map<String,Object?>? input,String? key) async =>
    decodePrivateContactRow(await _raw(input,key));
  Future<Map<String,Object?>> _raw(Map<String,Object?>? input,String? key) async {
    final user=client.auth.currentUser?.id;
    if(user==null) throw StateError('Please sign in to manage your address.');
    final value=await client.schema('hocalist').rpc('business_address',params:{'p_input':input,'p_key':key});
    if(client.auth.currentUser?.id!=user) throw StateError('Your account changed.');
    final record=decodePrivateContactRow(Map<String,Object?>.from(value as Map));
    if(record.userId!=user) throw StateError('This address could not be verified.');
    return Map<String,Object?>.from(value);
  }
}
