import '../../../domain/phase2/failures.dart';
import 'marketplace_adapter.dart';
import 'saved_item_reference.dart';

class SavedContent {
  const SavedContent({
    required this.title,
    required this.description,
    required this.kind,
    this.unavailable = false,
    this.reference,
  });
  final String title;
  final String description;
  final String kind;
  final bool unavailable;
  final SavedItemReference? reference;
}

class MarketplaceSavedBackend {
  MarketplaceSavedBackend(this.adapter, this.userId);
  final MarketplaceDataAdapter adapter;
  final String userId;

  Future<bool> isSaved(SavedItemReference reference) async {
    _checkSession();
    final result = await adapter.fetchSavedItems();
    _checkSession();
    if (result.isFailure) throw StateError('saved_unavailable');
    return result.valueOrNull!.any(
      (row) => row.type == reference.type && row.id == reference.id,
    );
  }

  Future<void> setSaved(
    SavedItemReference reference,
    bool saved,
    String key,
  ) async {
    _checkSession();
    final result = await adapter.setSavedItem(
      type: reference.type,
      id: reference.id,
      saved: saved,
      operationKey: key,
    );
    _checkSession();
    if (result.isFailure) throw StateError('saved_update_unconfirmed');
  }

  void _checkSession() {
    if (adapter.session.currentUserId != userId) {
      throw StateError('session_changed');
    }
  }

  Future<List<SavedContent>> load() async {
    _checkSession();
    final result = await adapter.fetchSavedItems();
    _checkSession();
    if (result.isFailure) throw StateError('saved_unavailable');
    final values = <SavedContent>[];
    for (final reference in result.valueOrNull!) {
      _checkSession();
      RepositoryError? error;
      if (reference.type == 'store_listing') {
        final detail = await adapter.fetchPublicStoreListing(
          listingId: reference.id,
        );
        _checkSession();
        error = detail.errorOrNull;
        final item = detail.valueOrNull;
        if (item != null) {
          if (item.id != reference.id) throw StateError('saved_mismatch');
          values.add(
            SavedContent(
              reference: reference,
              title: item.title,
              description: item.description,
              kind: 'Store listing',
            ),
          );
        }
      } else {
        final detail = await adapter.fetchRequest(requestId: reference.id);
        _checkSession();
        error = detail.errorOrNull;
        final item = detail.valueOrNull;
        if (item != null) {
          if (item.id != reference.id) throw StateError('saved_mismatch');
          values.add(
            SavedContent(
              reference: reference,
              title: item.draft.title,
              description: item.draft.description,
              kind: 'Request',
            ),
          );
        }
      }
      if (error != null) {
        if (error.kind != RepositoryFailureKind.notFound &&
            error.kind != RepositoryFailureKind.permissionDenied) {
          throw StateError('saved_details_unavailable');
        }
        values.add(
          SavedContent(
            reference: reference,
            title: 'Item unavailable',
            description:
                'This saved item is no longer available to your account.',
            kind: 'Saved item',
            unavailable: true,
          ),
        );
      }
    }
    return List.unmodifiable(values);
  }
}
