/// Real-mode notification backend for the inbox and preference screens.
library;

import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/notifications.dart';
import '../../../domain/phase2/profiles.dart';
import '../../local_marketplace_repository.dart';
import 'notification_adapter.dart';

class Phase2MarketplaceNotificationsBackend
    implements MarketplaceNotificationsBackend {
  Phase2MarketplaceNotificationsBackend({required this.adapter});

  final NotificationDataAdapter adapter;

  @override
  Future<NotificationInboxPage> loadInbox({
    String? cursor,
    int limit = 50,
  }) async {
    final result = await adapter.fetchInbox(cursor: cursor, limit: limit);
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<void> markRead(String notificationId) async {
    final result = await adapter.markRead(notificationId);
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
  }

  @override
  Future<int> markAllRead() async {
    final result = await adapter.markAllRead();
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<NotificationPreferencesRecord> loadPreferences() async {
    final result = await adapter.fetchPreferences();
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) async {
    final result = await adapter.updatePreferences(
      preferences: preferences,
      expectedRevision: expectedRevision,
      includeLeads: includeLeads,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  bool _isAmbiguous(RepositoryError? error) {
    if (error == null) return false;
    return switch (error.kind) {
      RepositoryFailureKind.network ||
      RepositoryFailureKind.malformedResponse => true,
      RepositoryFailureKind.server =>
        error is ServerError &&
            (error.statusCode == null || error.statusCode! >= 500),
      _ => false,
    };
  }

  String _message(RepositoryError? error) {
    if (error == null) {
      return 'Notifications are unavailable. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.permissionDenied =>
        'You do not have access to these notifications.',
      RepositoryFailureKind.notFound => 'This notification is unavailable.',
      RepositoryFailureKind.conflict =>
        'Preferences changed on another device. Refresh and try again.',
      RepositoryFailureKind.network =>
        'Notifications could not be loaded. Retry to check safely.',
      RepositoryFailureKind.validation =>
        'Check the notification preference values and try again.',
      _ => 'Notifications are unavailable. Try again.',
    };
  }
}
