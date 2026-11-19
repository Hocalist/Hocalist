import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../features/approved/place_capture_sheet.dart';
import '../../../domain/phase2/common.dart';

class SavedPlace {
  const SavedPlace({required this.id, required this.name, required this.place});
  final String id;
  final String name;
  final PlaceCaptureResult place;

  static Map<String, Object?> encode(PlaceCaptureResult p) => {
    'label': p.label,
    'address': p.address,
    'place_id': p.placeId,
    'latitude': p.latitude,
    'longitude': p.longitude,
    'timezone_id': p.timezoneId,
    'line1': p.postalAddress?.line1,
    'line2': p.postalAddress?.line2,
    'city': p.postalAddress?.city,
    'region': p.postalAddress?.state,
    'postal_code': p.postalAddress?.postalCode,
    'country': p.postalAddress?.country,
  };
  factory SavedPlace.decode(Map<String, dynamic> row) {
    final p = Map<String, dynamic>.from(row['place'] as Map);
    return SavedPlace(
      id: row['id'] as String,
      name: row['name'] as String,
      place: PlaceCaptureResult(
        label: p['label'] as String,
        address: p['address'] as String,
        placeId: p['place_id'] as String?,
        latitude: (p['latitude'] as num?)?.toDouble(),
        longitude: (p['longitude'] as num?)?.toDouble(),
        timezoneId: p['timezone_id'] as String?,
        postalAddress: PostalAddress(
          line1: p['line1'] as String? ?? p['address'] as String,
          line2: p['line2'] as String?,
          city: p['city'] as String?,
          state: p['region'] as String?,
          postalCode: p['postal_code'] as String?,
          country: p['country'] as String?,
        ),
        source: PlaceCaptureSource.manual,
      ),
    );
  }
}

abstract interface class SavedPlacesRepository {
  Future<List<SavedPlace>> load();
  Future<void> save(PlaceCaptureResult place, String name, {String? id});
  Future<void> remove(String id);
}

class SavedPlacesBackend implements SavedPlacesRepository {
  SavedPlacesBackend(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  Future<dynamic> _call(String action, Map<String, Object?> input) async {
    final user = client.auth.currentUser?.id;
    if (user == null || user != _owner)
      throw StateError('Please sign in again.');
    final result = await client
        .schema('hocalist')
        .rpc('saved_places', params: {'p_action': action, 'p_input': input});
    if (client.auth.currentUser?.id != user)
      throw StateError('Your account changed.');
    return result;
  }

  @override
  Future<List<SavedPlace>> load() async => (await _call('list', {}) as List)
      .map((r) => SavedPlace.decode(Map<String, dynamic>.from(r as Map)))
      .toList();
  @override
  Future<void> save(PlaceCaptureResult place, String name, {String? id}) async {
    await _call('save', {
      'id': id,
      'name': name.trim(),
      'place': SavedPlace.encode(place),
    });
  }

  @override
  Future<void> remove(String id) async {
    await _call('remove', {'id': id});
  }
}
