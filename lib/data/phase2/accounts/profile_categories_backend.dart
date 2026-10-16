/// Seller profile category backend over the reviewed `account_completion/131`
/// commands.
///
/// Same session fence as the other configured backends: the identity is
/// captured once, re-checked after every dispatch, and no request is sent for
/// a signed-out session. The selected list preserves retired choices; a new
/// selection must be an active catalogue category.
///
/// Deployment gate: [createConfiguredProfileCategoriesBackend] returns null
/// unless `enabled` is true, so category editing keeps its honest unavailable
/// state until the migration is deployed. Tests inject an [rpc] fake.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/phase2/account_completion.dart';
import '../../../domain/phase2/catalogue.dart';

class ProfileCategoriesRpcException implements Exception {
  const ProfileCategoriesRpcException(
    this.message, {
    this.code,
    this.statusCode,
  });

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'ProfileCategoriesRpcException($code: $message)';
}

/// The write hit a stale profile revision; reload before retrying.
class ProfileCategoriesConflictException implements Exception {
  const ProfileCategoriesConflictException();
}

class ProfileCategoriesUnavailableException implements Exception {
  const ProfileCategoriesUnavailableException(
    this.message, {
    this.outcomeUncertain = false,
  });

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => 'ProfileCategoriesUnavailableException($message)';
}

typedef ProfileCategoriesRpc =
    Future<Map<String, Object?>> Function(
      String function,
      Map<String, Object?> params,
    );

abstract interface class ProfileCategoriesBackend {
  Future<SellerCategorySelection> loadSellerCategories();

  Future<SellerCategoryUpdateResult> updateSellerCategories({
    required int expectedRevision,
    required List<String> categoryIds,
    required String operationKey,
  });
}

class Phase2ProfileCategoriesBackend implements ProfileCategoriesBackend {
  Phase2ProfileCategoriesBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String readFunction = 'seller_profile_categories';
  static const String updateFunction = 'profile_categories_update';
  static const Set<String> allowedFunctions = {readFunction, updateFunction};

  final ProfileCategoriesRpc rpc;
  final String? Function() identity;

  @override
  Future<SellerCategorySelection> loadSellerCategories() async {
    final data = await _call(readFunction, const {});
    return _decodeSelection(data);
  }

  @override
  Future<SellerCategoryUpdateResult> updateSellerCategories({
    required int expectedRevision,
    required List<String> categoryIds,
    required String operationKey,
  }) async {
    final data = await _call(updateFunction, {
      'p_key': operationKey,
      'p_expected_revision': expectedRevision,
      'p_category_ids': List<String>.from(categoryIds),
    });
    return _decodeUpdate(data);
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const ProfileCategoriesUnavailableException(
        'Category changes are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const ProfileCategoriesUnavailableException(
        'Sign in to change your categories.',
      );
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const ProfileCategoriesUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on ProfileCategoriesRpcException catch (error) {
      if (error.code == 'P0001' &&
          error.message.contains('revision_conflict')) {
        throw const ProfileCategoriesConflictException();
      }
      if (error.code == 'P0001' &&
          error.message.contains('idempotency_conflict')) {
        throw const ProfileCategoriesUnavailableException(
          'This change conflicts with an earlier attempt. Reload and try again.',
        );
      }
      throw ProfileCategoriesUnavailableException(
        error.message,
        outcomeUncertain: error.statusCode == null || error.statusCode! >= 500,
      );
    } on ProfileCategoriesUnavailableException {
      rethrow;
    } catch (_) {
      throw const ProfileCategoriesUnavailableException(
        'Your category change could not be confirmed. Retry to check it safely.',
        outcomeUncertain: true,
      );
    }
  }

  SellerCategorySelection _decodeSelection(Map<String, Object?> row) {
    final membershipId = row['membership_id'];
    final revision = row['revision'];
    final selected = row['selected'];
    final available = row['available'];
    if (membershipId is! String ||
        revision is! int ||
        revision < 1 ||
        selected is! List ||
        available is! List) {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
    try {
      return SellerCategorySelection(
        membershipId: membershipId,
        revision: revision,
        selected: [
          for (final item in selected)
            _decodeOption(item, defaultSelectable: null),
        ],
        available: [
          for (final item in available)
            _decodeOption(item, defaultSelectable: true),
        ],
      );
    } on ArgumentError {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
  }

  SellerCategoryOption _decodeOption(Object? raw, {bool? defaultSelectable}) {
    if (raw is! Map) {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final id = row['id'];
    final label = row['label'];
    final scope = row['scope'];
    final status = row['status'];
    if (id is! String ||
        label is! String ||
        scope is! String ||
        status is! String) {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
    return SellerCategoryOption(
      id: id,
      label: label,
      slug: row['slug'] is String ? row['slug']! as String : null,
      scope: CatalogueScope.values.byName(scope),
      status: CatalogueEntryStatus.values.byName(status),
      selectable: row['selectable'] is bool
          ? row['selectable']! as bool
          : (defaultSelectable ?? status == 'active'),
      sortOrder: row['sort_order'] is int ? row['sort_order']! as int : 0,
    );
  }

  SellerCategoryUpdateResult _decodeUpdate(Map<String, Object?> row) {
    final membershipId = row['membership_id'];
    final revision = row['revision'];
    final ids = row['category_ids'];
    if (membershipId is! String ||
        revision is! int ||
        revision < 1 ||
        ids is! List) {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
    try {
      return SellerCategoryUpdateResult(
        membershipId: membershipId,
        revision: revision,
        categoryIds: ids.whereType<String>().toList(growable: false),
      );
    } on ArgumentError {
      throw const ProfileCategoriesUnavailableException(
        'The category response was invalid.',
      );
    }
  }
}

/// Set true only after the reviewed `131_profile_categories` migration is
/// deployed.
const bool kSellerCategoryEditingEnabled = bool.fromEnvironment('HOCALIST_SELLER_CATEGORIES');

ProfileCategoriesBackend? createConfiguredProfileCategoriesBackend({
  bool enabled = kSellerCategoryEditingEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2ProfileCategoriesBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2ProfileCategoriesBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const ProfileCategoriesUnavailableException(
              'The category response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw ProfileCategoriesRpcException(
            error.message,
            code: error.code,
            statusCode: error.code == null ? null : 400,
          );
        }
      },
    );
  } catch (_) {
    return null;
  }
}
