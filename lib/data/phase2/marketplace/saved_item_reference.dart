import 'marketplace_codecs.dart';

class SavedItemReference {
  const SavedItemReference({required this.id, required this.type});
  final String id;
  final String type;

  static SavedItemReference decode(Map<String, Object?> row, String context) {
    final id = row['item_id'];
    final type = row['item_type'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        (type != 'request' && type != 'store_listing')) {
      throw MarketplaceDecodeException('$context.reference');
    }
    return SavedItemReference(id: id, type: type as String);
  }
}
