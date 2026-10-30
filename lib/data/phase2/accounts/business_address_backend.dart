import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/phase2/account_contacts.dart';
import '../../../domain/phase2/patch.dart';
import 'account_codecs.dart';

class BusinessAddressBackend {
  BusinessAddressBackend(this.client);
  final SupabaseClient client;
  Future<PrivateContactRecord> load() => _call(null, null);
  Future<PrivateContactRecord> save(UpdateContactCommand command) {
    final input=<String,Object?>{'expected_revision':command.expectedRevision};
    void field(String key,Patch<String> patch) {
      if (!patch.isKeep) input[key]=patch.valueOrNull;
    }
    field('address_line1',command.addressLine1); field('address_line2',command.addressLine2);
    field('city',command.city); field('region',command.region);
    field('postal_code',command.postalCode); field('country_code',command.countryCode);
    return _call(input,command.idempotencyKey);
  }
  Future<PrivateContactRecord> _call(Map<String,Object?>? input,String? key) async {
    final user=client.auth.currentUser?.id;
    if(user==null) throw StateError('Please sign in to manage your address.');
    final value=await client.schema('hocalist').rpc('business_address',params:{'p_input':input,'p_key':key});
    if(client.auth.currentUser?.id!=user) throw StateError('Your account changed.');
    final record=decodePrivateContactRow(Map<String,Object?>.from(value as Map));
    if(record.userId!=user) throw StateError('This address could not be verified.');
    return record;
  }
}
