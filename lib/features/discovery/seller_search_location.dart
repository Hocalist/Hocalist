import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/discovery/discovery_adapter.dart';

/// Search overrides never write the seller's Business / Store address.
class SellerSearchLocation {
  SellerSearchLocation({required this.loadOrigin, required this.readDefault,
    required this.persist, required this.resolve});
  final Future<SellerDiscoveryOrigin> Function() loadOrigin;
  final Future<SellerDiscoveryOriginInput> Function() readDefault;
  final Future<SellerDiscoveryOrigin> Function(SellerDiscoveryOriginInput, String) persist;
  final Future<SellerDiscoveryOriginInput> Function(String) resolve;
  final Map<String, SellerDiscoveryOriginInput> _attempts = {};

  // Opening the filter must not recreate a location the seller cleared.
  Future<SellerDiscoveryOrigin> load() => loadOrigin();

  SellerDiscoveryOriginInput? _selected;
  void remember(SellerDiscoveryOriginInput input) => _selected = input;

  Future<SellerDiscoveryOriginInput> locate(String area) async {
    if (_selected?.areaLabel == area.trim()) return _selected!;
    final saved = await readDefault();
    if (area.trim().isEmpty || area.trim() == saved.areaLabel) return saved;
    return resolve(area.trim());
  }

  Future<SellerDiscoveryOrigin> save(SellerDiscoveryOriginInput input, String key) async {
    var prepared = _attempts[key];
    if (prepared == null) {
      if (input.areaLabel == null && input.latitude == null) {
        // Clear the search only; the saved business address remains unchanged.
        prepared = const SellerDiscoveryOriginInput();
        _selected = null;
      } else if (input.latitude != null && input.longitude != null) {
        prepared = input;
      } else {
        final place = await locate(input.areaLabel ?? '');
        if (place.latitude == null || place.longitude == null) {
          throw const StoreBackendException('Confirm a location before applying a radius.');
        }
        prepared = SellerDiscoveryOriginInput(areaLabel: place.areaLabel,
          latitude: place.latitude, longitude: place.longitude, radiusMiles: input.radiusMiles);
      }
      _attempts[key] = prepared;
    }
    return persist(prepared, key);
  }
}
