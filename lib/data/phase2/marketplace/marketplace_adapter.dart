/// Marketplace adapters backed by the reviewed draft-020 RPCs.
///
/// Implements the catalogue, request, offer and Store repository contracts over
/// the marketplace RPCs. Identity comes from the injected session;
/// caller-supplied user ids are checked against it, never trusted. Meeting,
/// PIN, credits and reward behavior is not part of this foundation and is not
/// simulated here.
library;

import '../../../domain/phase2/catalogue.dart';
import '../../../domain/phase2/category_answers.dart';
import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/conversations.dart';
import '../../../domain/phase2/discovery.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/offers.dart';
import '../../../domain/phase2/repositories.dart';
import '../../../domain/phase2/requests.dart';
import '../../../domain/phase2/store_listings.dart';
import 'marketplace_codecs.dart';
import 'marketplace_error_mapper.dart';
import 'marketplace_session.dart';
import 'marketplace_transport.dart';
import 'saved_item_reference.dart';

class MarketplaceDataAdapter
    implements
        CatalogueRepository,
        RequestRepository,
        OfferRepository,
        StoreListingRepository {
  MarketplaceDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  static const String schema = 'hocalist';

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  String? _captureIdentity() => session.currentUserId;

  Future<RepositoryResult<bool>> setSavedItem({
    required String type,
    required String id,
    required bool saved,
    required String operationKey,
  }) => _read(
    'marketplace_saved_set',
    {'p_type': type, 'p_item': id, 'p_saved': saved, 'p_key': operationKey},
    (row, context) {
      if (row['item_type'] != type ||
          row['item_id'] != id ||
          row['saved'] != saved) {
        throw MarketplaceDecodeException('$context.acknowledgement');
      }
      return saved;
    },
  );

  Future<RepositoryResult<List<SavedItemReference>>> fetchSavedItems() =>
      _read('marketplace_saved_items', const {}, (row, context) {
        final records = decodeObjectList(row['items'], context)
            .map((item) => SavedItemReference.decode(item, context))
            .toList(growable: false);
        final keys = records.map((item) => '${item.type}:${item.id}').toSet();
        if (keys.length != records.length) {
          throw MarketplaceDecodeException('$context.duplicate');
        }
        return List<SavedItemReference>.unmodifiable(records);
      });

  bool _isStillCurrent(String userId) => session.currentUserId == userId;

  RepositoryResult<T> _failure<T>(RepositoryError error) =>
      RepositoryFailureResult(error);

  RepositoryError _identityMismatch(String field) =>
      PermissionDeniedError(action: 'identity_mismatch', entityType: field);

  Future<RepositoryResult<Map<String, Object?>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: schema, function: function, params: params),
    );
    if (!_isStillCurrent(userId)) return _failure(_staleSession);
    return switch (response) {
      MarketplaceTransportData(:final data) => _decode(function, data),
      MarketplaceTransportError() => RepositoryFailureResult(
        errorMapper.map(response, operation: function),
      ),
    };
  }

  RepositoryResult<Map<String, Object?>> _decode(
    String function,
    Object? data,
  ) {
    try {
      return RepositorySuccess(decodeObject(data, function));
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<T>> _read<T>(
    String function,
    Map<String, Object?> params,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, params);
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, function));
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<PageSlice<T>>> _readPage<T>(
    String function,
    Map<String, Object?> params,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, params);
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodePage(result.valueOrNull!, function, decode),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<Map<String, Object?>>> _command(
    String operation,
    String key,
    Map<String, Object?> input,
  ) {
    return _rpc('marketplace_command', {
      'p_operation': operation,
      'p_key': key,
      'p_input': input,
    });
  }

  Future<RepositoryResult<Map<String, Object?>>> _adminCommand(
    String operation,
    String key,
    Map<String, Object?> input,
  ) {
    return _rpc('marketplace_admin_command', {
      'p_operation': operation,
      'p_key': key,
      'p_input': input,
    });
  }

  Future<RepositoryResult<T>> _commandRecord<T>(
    String operation,
    String key,
    Map<String, Object?> input,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _command(operation, key, input);
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, operation));
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: operation, detail: error.detail),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Field mapping
  // -------------------------------------------------------------------------

  Map<String, Object?> _requestFields(RequestDraft draft) {
    final location = draft.location;
    final address = location.address;
    return {
      'kind': requestKindToWire(draft.kind),
      'title': draft.title,
      'description': draft.description,
      if (draft.imageMediaIds.isNotEmpty ||
          const bool.fromEnvironment('HOCALIST_REQUEST_PHOTOS'))
        'image_media_ids': draft.imageMediaIds,
      'condition': draft.condition == null
          ? null
          : productConditionToWire(draft.condition!),
      'service_type': draft.serviceType == null
          ? null
          : serviceTypeToWire(draft.serviceType!),
      'quantity': draft.quantity,
      'budget_minimum_minor': draft.budget.minimum?.minorUnits,
      'budget_maximum_minor': draft.budget.maximum?.minorUnits,
      'currency_code': draft.budget.currencyCode,
      'accepts_higher_offers': draft.acceptsHigherOffers,
      'category_id': draft.categoryId,
      'category_answers': categoryAnswerInput(draft.categoryAnswers),
      'use_home_address': location.useHomeAddress,
      if (location.timezoneId != null) 'location_timezone': location.timezoneId,
      'address_line1': address?.line1,
      'address_line2': address?.line2,
      'city': address?.city,
      'region': address?.state,
      'postal_code': address?.postalCode,
      'country_code': address?.country,
      if (location.coordinates != null) ...{
        'latitude': location.coordinates!.latitude,
        'longitude': location.coordinates!.longitude,
      },
    };
  }

  Map<String, Object?> _offerFields(OfferTerms terms) {
    final occurrence = terms.schedule.occurrence;
    return {
      'price_minor': terms.price.minorUnits,
      'currency_code': terms.price.currencyCode,
      'message': terms.message,
      'image_media_ids': terms.imageMediaIds,
      'schedule_date': terms.schedule.date.toString(),
      'schedule_time': terms.schedule.startTime.toString(),
      'schedule_timezone': terms.schedule.timezoneId,
      if (occurrence != null)
        'schedule_occurrence': repeatedTimeOccurrenceToWire(occurrence),
      'place_choice': placeChoiceToWire(terms.place.choice),
      'place_label': terms.place.label,
      'place_address': terms.place.address,
      'place_id': terms.place.placeId,
      if (terms.place.latitude != null) 'place_latitude': terms.place.latitude,
      if (terms.place.longitude != null)
        'place_longitude': terms.place.longitude,
    };
  }

  Map<String, Object?> _listingFields({
    required ListingKind kind,
    required String title,
    required String description,
    required String categoryId,
    required String priceLabel,
    required String serviceArea,
    required String availability,
    required List<String> imageMediaIds,
    required List<CategoryAnswer> categoryAnswers,
    ListingPublishIntent? publishIntent,
  }) {
    return {
      'kind': kind.name,
      'title': title,
      'description': description,
      'category_id': categoryId,
      'category_answers': categoryAnswerInput(categoryAnswers),
      'price_label': priceLabel,
      'service_area': serviceArea,
      'availability': availability,
      'image_media_ids': imageMediaIds,
      if (publishIntent != null) 'publish_intent': publishIntent.name,
    };
  }

  // -------------------------------------------------------------------------
  // Catalogue
  // -------------------------------------------------------------------------

  Future<RepositoryResult<List<Map<String, Object?>>>> _catalogueRows(
    bool includeRetired,
  ) async {
    final result = await _rpc('marketplace_catalogue', {
      'p_scope': null,
      'p_include_retired': includeRetired,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeObjectList(result.valueOrNull!['categories'], 'catalogue'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'marketplace_catalogue',
          detail: error.detail,
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<PageSlice<CatalogueCategory>>> fetchCategories({
    CatalogueScope? scope,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  }) async {
    final result = await _rpc('marketplace_catalogue', {
      'p_scope': scope?.name,
      'p_include_retired': includeRetired,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      final categories = decodeCatalogueJson(result.valueOrNull!, 'catalogue');
      return RepositorySuccess(
        PageSlice<CatalogueCategory>(items: categories, nextCursor: null),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'marketplace_catalogue',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<List<CategoryQuestion>>> fetchCategoryQuestions(
    String categoryId,
  ) async {
    final rows = await _catalogueRows(false);
    if (rows.isFailure) return _failure(rows.errorOrNull!);
    try {
      for (final row in rows.valueOrNull!) {
        if (row['id'] != categoryId) continue;
        final groups = decodeNestedOptionGroupsJson(row, 'catalogue');
        final rawGroups = decodeObjectList(row['groups'], 'catalogue');
        return RepositorySuccess([
          for (final group in groups.where((g) => g.isActive))
            CategoryQuestion(group, [
              for (final raw in rawGroups.where((r) => r['id'] == group.id))
                for (final option in decodeObjectList(
                  raw['options'],
                  'catalogue',
                ))
                  if (decodeCatalogueOptionJson(option, 'catalogue').isActive)
                    decodeCatalogueOptionJson(option, 'catalogue'),
            ]),
        ]);
      }
      return _failure(
        const NotFoundError(
          entityType: 'catalogue_category',
          entityId: 'requested',
        ),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'marketplace_catalogue',
          detail: error.detail,
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<PageSlice<CatalogueOptionGroup>>> fetchOptionGroups({
    required String categoryId,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  }) async {
    final rows = await _catalogueRows(includeRetired);
    if (rows.isFailure) return _failure(rows.errorOrNull!);
    for (final row in rows.valueOrNull!) {
      if (row['id'] != categoryId) continue;
      try {
        return RepositorySuccess(
          PageSlice<CatalogueOptionGroup>(
            items: decodeNestedOptionGroupsJson(row, 'catalogue'),
            nextCursor: null,
          ),
        );
      } on MarketplaceDecodeException catch (error) {
        return _failure(
          MalformedResponseError(
            operation: 'marketplace_catalogue',
            detail: error.detail,
          ),
        );
      }
    }
    return _failure(
      const NotFoundError(
        entityType: 'catalogue_category',
        entityId: 'requested',
      ),
    );
  }

  @override
  Future<RepositoryResult<PageSlice<CatalogueOption>>> fetchOptions({
    required String groupId,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  }) async {
    final rows = await _catalogueRows(includeRetired);
    if (rows.isFailure) return _failure(rows.errorOrNull!);
    try {
      for (final category in rows.valueOrNull!) {
        final groups = decodeObjectList(category['groups'], 'catalogue');
        for (final group in groups) {
          if (group['id'] != groupId) continue;
          final optionRows = decodeObjectList(group['options'], 'catalogue');
          final options = <CatalogueOption>[];
          for (var index = 0; index < optionRows.length; index++) {
            options.add(
              decodeCatalogueOptionJson(
                optionRows[index],
                'catalogue.options[$index]',
              ),
            );
          }
          return RepositorySuccess(
            PageSlice<CatalogueOption>(items: options, nextCursor: null),
          );
        }
      }
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'marketplace_catalogue',
          detail: error.detail,
        ),
      );
    }
    return _failure(
      const NotFoundError(
        entityType: 'catalogue_option_group',
        entityId: 'requested',
      ),
    );
  }

  Future<RepositoryResult<CatalogueCategory>> _categoryById(
    String categoryId,
  ) async {
    final result = await fetchCategories(includeRetired: true);
    if (result.isFailure) return _failure(result.errorOrNull!);
    for (final category in result.valueOrNull!.items) {
      if (category.id == categoryId) return RepositorySuccess(category);
    }
    return _failure(
      const NotFoundError(
        entityType: 'catalogue_category',
        entityId: 'requested',
      ),
    );
  }

  Future<RepositoryResult<CatalogueOptionGroup>> _groupById(
    String groupId,
  ) async {
    final result = await fetchCategories(includeRetired: true);
    if (result.isFailure) return _failure(result.errorOrNull!);
    for (final category in result.valueOrNull!.items) {
      final groups = await fetchOptionGroups(
        categoryId: category.id,
        includeRetired: true,
      );
      if (groups.isFailure) continue;
      for (final group in groups.valueOrNull!.items) {
        if (group.id == groupId) return RepositorySuccess(group);
      }
    }
    return _failure(
      const NotFoundError(
        entityType: 'catalogue_option_group',
        entityId: 'requested',
      ),
    );
  }

  Future<RepositoryResult<CatalogueOption>> _optionById(String optionId) async {
    final result = await fetchCategories(includeRetired: true);
    if (result.isFailure) return _failure(result.errorOrNull!);
    for (final category in result.valueOrNull!.items) {
      final groups = await fetchOptionGroups(
        categoryId: category.id,
        includeRetired: true,
      );
      if (groups.isFailure) continue;
      for (final group in groups.valueOrNull!.items) {
        final options = await fetchOptions(
          groupId: group.id,
          includeRetired: true,
        );
        if (options.isFailure) continue;
        for (final option in options.valueOrNull!.items) {
          if (option.id == optionId) return RepositorySuccess(option);
        }
      }
    }
    return _failure(
      const NotFoundError(
        entityType: 'catalogue_option',
        entityId: 'requested',
      ),
    );
  }

  @override
  Future<RepositoryResult<PageSlice<LocationEntry>>> fetchLocations({
    String? countryCode,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  }) {
    return _readPage('marketplace_locations', {
      'p_country': countryCode,
      'p_include_retired': includeRetired,
    }, decodeLocationJson);
  }

  /// Valid named IANA zones provided by the server for meeting scheduling.
  /// Abbreviations and fixed-offset names are rejected server-side.
  Future<RepositoryResult<List<String>>> fetchTimezones() async {
    final result = await _rpc(
      'marketplace_timezones',
      const <String, Object?>{},
    );
    if (result.isFailure) return _failure(result.errorOrNull!);
    final items = result.valueOrNull!['items'];
    if (items is! List) {
      return _failure(
        const MalformedResponseError(
          operation: 'marketplace_timezones',
          detail: 'items',
        ),
      );
    }
    final zones = <String>[];
    for (final item in items) {
      if (item is! String || item.trim().isEmpty) {
        return _failure(
          const MalformedResponseError(
            operation: 'marketplace_timezones',
            detail: 'items',
          ),
        );
      }
      zones.add(item);
    }
    return RepositorySuccess(List<String>.unmodifiable(zones));
  }

  @override
  Future<RepositoryResult<CatalogueCategory>> createCategory(
    CreateCatalogueCategoryCommand command,
  ) async {
    final result =
        await _adminCommand('category.create', command.idempotencyKey, {
          'parent_id': command.parentId,
          'label': command.label,
          'slug': command.slug,
          'scope': command.scope.name,
          'sort_order': command.sortOrder,
        });
    if (result.isFailure) return _failure(result.errorOrNull!);
    final id = result.valueOrNull!['id'];
    if (id is! String) {
      return _failure(
        const MalformedResponseError(
          operation: 'category.create',
          detail: 'id',
        ),
      );
    }
    return _categoryById(id);
  }

  @override
  Future<RepositoryResult<CatalogueCategory>> updateCategory(
    UpdateCatalogueCategoryCommand command,
  ) async {
    final result =
        await _adminCommand('category.update', command.idempotencyKey, {
          'category_id': command.categoryId,
          'expected_revision': command.expectedRevision,
          'parent_id': command.clearParent ? null : command.parentId,
          'label': command.label,
          'slug': command.clearSlug ? null : command.slug,
          'scope': command.scope.name,
          'sort_order': command.sortOrder,
        });
    if (result.isFailure) return _failure(result.errorOrNull!);
    return _categoryById(command.categoryId);
  }

  @override
  Future<RepositoryResult<CatalogueOptionGroup>> createOptionGroup(
    CreateCatalogueOptionGroupCommand command,
  ) async {
    final result = await _adminCommand('group.create', command.idempotencyKey, {
      'category_id': command.categoryId,
      'label': command.label,
      'selection_mode': command.selectionMode.name,
      'is_required': command.isRequired,
      'sort_order': command.sortOrder,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    final id = result.valueOrNull!['id'];
    if (id is! String) {
      return _failure(
        const MalformedResponseError(operation: 'group.create', detail: 'id'),
      );
    }
    return _groupById(id);
  }

  @override
  Future<RepositoryResult<CatalogueOptionGroup>> updateOptionGroup(
    UpdateCatalogueOptionGroupCommand command,
  ) async {
    final result = await _adminCommand('group.update', command.idempotencyKey, {
      'group_id': command.groupId,
      'expected_revision': command.expectedRevision,
      'label': command.label,
      'selection_mode': command.selectionMode.name,
      'is_required': command.isRequired,
      'sort_order': command.sortOrder,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    return _groupById(command.groupId);
  }

  @override
  Future<RepositoryResult<CatalogueOption>> createOption(
    CreateCatalogueOptionCommand command,
  ) async {
    final result =
        await _adminCommand('option.create', command.idempotencyKey, {
          'group_id': command.groupId,
          'label': command.label,
          'sort_order': command.sortOrder,
        });
    if (result.isFailure) return _failure(result.errorOrNull!);
    final id = result.valueOrNull!['id'];
    if (id is! String) {
      return _failure(
        const MalformedResponseError(operation: 'option.create', detail: 'id'),
      );
    }
    return _optionById(id);
  }

  @override
  Future<RepositoryResult<CatalogueOption>> updateOption(
    UpdateCatalogueOptionCommand command,
  ) async {
    final result =
        await _adminCommand('option.update', command.idempotencyKey, {
          'option_id': command.optionId,
          'expected_revision': command.expectedRevision,
          'label': command.label,
          'sort_order': command.sortOrder,
        });
    if (result.isFailure) return _failure(result.errorOrNull!);
    return _optionById(command.optionId);
  }

  @override
  Future<RepositoryResult<CatalogueEntryStatusResult>> setEntryStatus(
    SetCatalogueEntryStatusCommand command,
  ) async {
    final result =
        await _adminCommand('entry.set_status', command.idempotencyKey, {
          'entry_type': command.entryType.name,
          'entry_id': command.entryId,
          'expected_revision': command.expectedRevision,
          'status': command.status.name,
        });
    if (result.isFailure) return _failure(result.errorOrNull!);
    final stamp = await _refetchedStamp(command);
    if (stamp == null) {
      return _failure(
        MalformedResponseError(operation: 'entry.set_status', detail: 'stamp'),
      );
    }
    return RepositorySuccess(
      CatalogueEntryStatusResult(
        entryType: command.entryType,
        entryId: command.entryId,
        status: command.status,
        stamp: stamp,
      ),
    );
  }

  Future<RecordStamp?> _refetchedStamp(
    SetCatalogueEntryStatusCommand command,
  ) async {
    switch (command.entryType) {
      case CatalogueEntryType.category:
        final result = await _categoryById(command.entryId);
        return result.valueOrNull?.stamp;
      case CatalogueEntryType.optionGroup:
        final result = await _groupById(command.entryId);
        return result.valueOrNull?.stamp;
      case CatalogueEntryType.option:
        final result = await _optionById(command.entryId);
        return result.valueOrNull?.stamp;
    }
  }

  // -------------------------------------------------------------------------
  // Requests
  // -------------------------------------------------------------------------

  @override
  Future<RepositoryResult<PageSlice<MarketplaceRequest>>> fetchBuyerRequests({
    required String buyerUserId,
    RequestStatus? status,
    PageQuery page = PageQuery.standard,
  }) {
    if (buyerUserId != _captureIdentity()) {
      return Future.value(_failure(_identityMismatch('buyerUserId')));
    }
    return _readPage('marketplace_my_requests', {
      'p_status': status?.name,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodeRequestJson);
  }

  @override
  Future<RepositoryResult<MarketplaceRequest>> fetchRequest({
    required String requestId,
  }) {
    return _read('marketplace_request', {
      'p_request': requestId,
    }, decodeRequestJson);
  }

  @override
  Future<RepositoryResult<PageSlice<SellerLeadProjection>>> fetchSellerLeads({
    required String sellerUserId,
    SellerLeadQuery? query,
  }) {
    if (sellerUserId != _captureIdentity()) {
      return Future.value(_failure(_identityMismatch('sellerUserId')));
    }
    final page = query?.page ?? PageQuery.standard;
    return _readPage('marketplace_seller_leads', {
      'p_kind': query?.kind?.name,
      'p_category': query?.categoryId,
      'p_area': query?.areaLabel,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodeLeadJson);
  }

  /// Reads only the seller-visible projection, never the buyer's address.
  Future<RepositoryResult<SellerLeadProjection>> fetchSellerRequest(
    String requestId,
  ) => _read('marketplace_request', {'p_request': requestId}, decodeLeadJson);

  /// Paged, server-filtered seller discovery from the discovery_completion
  /// RPC. Older servers without that function fail closed with a typed error.
  Future<RepositoryResult<DiscoveryLeadPage>> fetchDiscoveryLeadPage({
    RequestKind? kind,
    String? categoryId,
    String? areaLabel,
    String? query,
    int? budgetMinimumMinor,
    int? budgetMaximumMinor,
    DiscoverySort sort = DiscoverySort.newest,
    int? radiusMiles,
    PageQuery page = PageQuery.standard,
  }) {
    return _read('marketplace_discovery_leads', {
      'p_kind': kind?.name,
      'p_category': categoryId,
      'p_area': areaLabel,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
      'p_sort': sort.wire,
      'p_radius_miles': radiusMiles,
      'p_query': query,
      'p_budget_min_minor': budgetMinimumMinor,
      'p_budget_max_minor': budgetMaximumMinor,
    }, decodeDiscoveryLeadPageJson);
  }

  @override
  Future<RepositoryResult<MarketplaceRequest>> createRequest(
    CreateRequestCommand command,
  ) {
    return _commandRecord(
      'request.create',
      command.idempotencyKey,
      _requestFields(command.draft),
      decodeRequestJson,
    );
  }

  @override
  Future<RepositoryResult<MarketplaceRequest>> updateRequest(
    UpdateRequestCommand command,
  ) {
    return _commandRecord('request.update', command.idempotencyKey, {
      'request_id': command.requestId,
      'expected_revision': command.expectedRevision,
      ..._requestFields(command.draft),
    }, decodeRequestJson);
  }

  @override
  Future<RepositoryResult<MarketplaceRequest>> closeRequest(
    CloseRequestCommand command,
  ) {
    return _commandRecord('request.close', command.idempotencyKey, {
      'request_id': command.requestId,
      'expected_revision': command.expectedRevision,
      if (command.reason != null) 'reason': command.reason,
    }, decodeRequestJson);
  }

  @override
  Future<RepositoryResult<MarketplaceRequest>> reopenRequest(
    ReopenRequestCommand command,
  ) {
    return _commandRecord('request.reopen', command.idempotencyKey, {
      'request_id': command.requestId,
      'expected_revision': command.expectedRevision,
    }, decodeRequestJson);
  }

  // -------------------------------------------------------------------------
  // Offers
  // -------------------------------------------------------------------------

  @override
  Future<RepositoryResult<PageSlice<Offer>>> fetchRequestOffers({
    required String requestId,
    PageQuery page = PageQuery.standard,
  }) {
    return _readPage('marketplace_request_offers', {
      'p_request': requestId,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodeOfferJson);
  }

  @override
  Future<RepositoryResult<PageSlice<Offer>>> fetchSellerOffers({
    required String sellerUserId,
    PageQuery page = PageQuery.standard,
  }) async {
    if (sellerUserId != _captureIdentity()) {
      return _failure(_identityMismatch('sellerUserId'));
    }
    final result = await _readPage('marketplace_my_offers', {
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodeOfferJson);
    if (result.isFailure) return _failure(result.errorOrNull!);
    final own = result.valueOrNull!.items
        .where((offer) => offer.sellerUserId == sellerUserId)
        .toList(growable: false);
    return RepositorySuccess(
      PageSlice<Offer>(items: own, nextCursor: result.valueOrNull!.nextCursor),
    );
  }

  @override
  Future<RepositoryResult<Offer>> fetchOffer({required String offerId}) {
    return _read('marketplace_offer', {'p_offer': offerId}, decodeOfferJson);
  }

  Future<RepositoryResult<PageSlice<Offer>>> fetchConversationDeals(
    String conversationId,
  ) => _readPage('chat_deals', {
    'p_conversation': conversationId,
  }, decodeOfferJson);

  @override
  Future<RepositoryResult<Offer>> submitOffer(SubmitOfferCommand command) {
    return _commandRecord('offer.submit', command.idempotencyKey, {
      'request_id': command.requestId,
      ..._offerFields(command.terms),
    }, decodeOfferJson);
  }

  @override
  Future<RepositoryResult<Offer>> reviseOffer(ReviseOfferCommand command) {
    return _commandRecord('offer.revise', command.idempotencyKey, {
      'offer_id': command.offerId,
      'expected_offer_revision': command.expectedOfferRevision,
      ..._offerFields(command.terms),
    }, decodeOfferJson);
  }

  @override
  Future<RepositoryResult<Offer>> withdrawOffer(WithdrawOfferCommand command) {
    return _commandRecord('offer.withdraw', command.idempotencyKey, {
      'offer_id': command.offerId,
      'expected_offer_revision': command.expectedOfferRevision,
      if (command.reason != null) 'reason': command.reason,
    }, decodeOfferJson);
  }

  @override
  Future<RepositoryResult<Offer>> selectOffer(SelectOfferCommand command) {
    return _commandRecord('offer.select', command.idempotencyKey, {
      'offer_id': command.offerId,
      'revision_id': command.revisionId,
      'expected_offer_revision': command.expectedOfferRevision,
    }, decodeOfferJson);
  }

  @override
  Future<RepositoryResult<Offer>> selectPurchaseOffer(
    SelectPurchaseCommand command,
  ) {
    return _commandRecord('purchase.select', command.idempotencyKey, {
      'offer_id': command.offerId,
      'expected_offer_revision': command.expectedOfferRevision,
    }, decodeOfferJson);
  }

  /// Opens (or returns) the deal conversation for a selected offer. The server
  /// decides eligibility; the client only sends the offer id and its key.
  Future<RepositoryResult<String>> openOfferConversation({
    required String offerId,
    required String idempotencyKey,
  }) {
    return MarketplaceConversationOpener(
      transport: transport,
      session: session,
      errorMapper: errorMapper,
    ).openOfferConversation(
      offerId: offerId,
      idempotencyKey: idempotencyKey,
      actingUserId: session.currentUserId ?? '',
    );
  }

  // -------------------------------------------------------------------------
  // Store listings
  // -------------------------------------------------------------------------

  @override
  Future<RepositoryResult<PageSlice<StoreListing>>> fetchSellerListings({
    required String sellerUserId,
    ListingKind? kind,
    ListingStatus? status,
    String? query,
    PageQuery page = PageQuery.standard,
  }) {
    if (sellerUserId != _captureIdentity()) {
      return Future.value(_failure(_identityMismatch('sellerUserId')));
    }
    return _readPage('marketplace_my_store_listings', {
      'p_kind': kind?.name,
      'p_status': status?.name,
      'p_query': query,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodeStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListing>> fetchStoreListing({
    required String listingId,
  }) {
    return _read('marketplace_store_listing', {
      'p_listing': listingId,
    }, decodeStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListingSummary>> fetchSellerStoreSummary({
    required String sellerUserId,
  }) async {
    if (sellerUserId != _captureIdentity()) {
      return _failure(_identityMismatch('sellerUserId'));
    }
    return _read(
      'marketplace_store_summary',
      const <String, Object?>{},
      decodeStoreSummaryJson,
    );
  }

  /// Server-owned plan and Store allowance for the signed-in seller.
  Future<RepositoryResult<MarketplacePlanStatus>> fetchStorePlanStatus() {
    return _read(
      'marketplace_store_summary',
      const <String, Object?>{},
      decodePlanStatusJson,
    );
  }

  @override
  Future<RepositoryResult<PageSlice<PublicStoreListing>>>
  fetchPublicSellerListings({
    required String sellerProfileId,
    ListingKind? kind,
    PageQuery page = PageQuery.standard,
  }) {
    return _readPage('marketplace_public_store_listings', {
      'p_seller_profile': sellerProfileId,
      'p_kind': kind?.name,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
    }, decodePublicStoreListingJson);
  }

  @override
  Future<RepositoryResult<PublicStoreListing>> fetchPublicStoreListing({
    required String listingId,
  }) {
    return _read('marketplace_store_listing', {
      'p_listing': listingId,
    }, decodePublicStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListing>> createStoreListing(
    CreateStoreListingCommand command,
  ) {
    return _commandRecord(
      'store.create',
      command.idempotencyKey,
      _listingFields(
        kind: command.kind,
        title: command.title,
        description: command.description,
        categoryId: command.categoryId,
        categoryAnswers: command.categoryAnswers,
        priceLabel: command.priceLabel,
        serviceArea: command.serviceArea,
        availability: command.availability,
        imageMediaIds: command.imageMediaIds,
        publishIntent: command.publishIntent,
      ),
      decodeStoreListingJson,
    );
  }

  @override
  Future<RepositoryResult<StoreListing>> updateStoreListing(
    UpdateStoreListingCommand command,
  ) {
    return _commandRecord('store.update', command.idempotencyKey, {
      'listing_id': command.listingId,
      'expected_revision': command.expectedRevision,
      ..._listingFields(
        kind: ListingKind.product,
        title: command.title,
        description: command.description,
        categoryId: command.categoryId,
        categoryAnswers: command.categoryAnswers,
        priceLabel: command.priceLabel,
        serviceArea: command.serviceArea,
        availability: command.availability,
        imageMediaIds: command.imageMediaIds,
      ),
    }, decodeStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListing>> setStoreListingPublication(
    SetStoreListingPublicationCommand command,
  ) {
    return _commandRecord('store.publish', command.idempotencyKey, {
      'listing_id': command.listingId,
      'expected_revision': command.expectedRevision,
      'publish': command.publish,
    }, decodeStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListing>> archiveStoreListing(
    ArchiveStoreListingCommand command,
  ) {
    return _commandRecord('store.archive', command.idempotencyKey, {
      'listing_id': command.listingId,
      'expected_revision': command.expectedRevision,
      if (command.reason != null) 'reason': command.reason,
    }, decodeStoreListingJson);
  }

  @override
  Future<RepositoryResult<StoreListing>> duplicateStoreListing(
    DuplicateStoreListingCommand command,
  ) {
    return _commandRecord('store.duplicate', command.idempotencyKey, {
      'listing_id': command.listingId,
    }, decodeStoreListingJson);
  }
}

/// Opens the deal conversation for a selected offer through the server-side
/// eligibility command. The server decides eligibility; the client only sends
/// the offer id and its idempotency key.
class MarketplaceConversationOpener {
  MarketplaceConversationOpener({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  Future<RepositoryResult<String>> openOfferConversation({
    required String offerId,
    required String idempotencyKey,
    required String actingUserId,
  }) async {
    final userId = session.currentUserId;
    if (userId == null) {
      return const RepositoryFailureResult(
        PermissionDeniedError(
          action: 'authenticate',
          entityType: 'account_session',
        ),
      );
    }
    if (actingUserId != userId) {
      return const RepositoryFailureResult(
        PermissionDeniedError(
          action: 'identity_mismatch',
          entityType: 'actingUserId',
        ),
      );
    }
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: MarketplaceDataAdapter.schema,
        function: 'marketplace_command',
        params: {
          'p_operation': 'conversation.open_offer',
          'p_key': idempotencyKey,
          'p_input': {'offer_id': offerId},
        },
      ),
    );
    if (session.currentUserId != userId) {
      return const RepositoryFailureResult(
        PermissionDeniedError(
          action: 'session_changed',
          entityType: 'account_session',
        ),
      );
    }
    switch (response) {
      case MarketplaceTransportData(:final data):
        try {
          final json = decodeObject(data, 'conversation.open_offer');
          final conversationId = json['conversation_id'];
          if (conversationId is! String || conversationId.trim().isEmpty) {
            return const RepositoryFailureResult(
              MalformedResponseError(
                operation: 'conversation.open_offer',
                detail: 'conversation_id',
              ),
            );
          }
          return RepositorySuccess(conversationId);
        } on MarketplaceDecodeException catch (error) {
          return RepositoryFailureResult(
            MalformedResponseError(
              operation: 'conversation.open_offer',
              detail: error.detail,
            ),
          );
        }
      case MarketplaceTransportError():
        return RepositoryFailureResult(
          errorMapper.map(response, operation: 'conversation.open_offer'),
        );
    }
  }
}

/// Opens one authorized Store/Hocatrends discovery enquiry through the
/// server-side eligibility command. Origin isolation is server-owned: the
/// client sends only the origin and subject, never a participant list.
class MarketplaceDiscoveryEnquiryOpener {
  MarketplaceDiscoveryEnquiryOpener({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  Future<RepositoryResult<String>> openDiscoveryEnquiry({
    required DiscoveryEnquiryOrigin origin,
    required String subjectId,
    String? sellerProfileId,
    required String idempotencyKey,
    required String actingUserId,
  }) async {
    final userId = session.currentUserId;
    if (userId == null) return const RepositoryFailureResult(_sessionError);
    if (actingUserId != userId) {
      return const RepositoryFailureResult(
        PermissionDeniedError(
          action: 'identity_mismatch',
          entityType: 'actingUserId',
        ),
      );
    }
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: MarketplaceDataAdapter.schema,
        function: 'discovery_open_enquiry',
        params: {
          'p_key': idempotencyKey,
          'p_input': {
            'origin': origin.wire,
            if (origin == DiscoveryEnquiryOrigin.storeListing)
              'listing_id': subjectId
            else ...{
              'topic_id': subjectId,
              'seller_profile_id': ?sellerProfileId,
            },
          },
        },
      ),
    );
    if (session.currentUserId != userId) {
      return const RepositoryFailureResult(_staleError);
    }
    switch (response) {
      case MarketplaceTransportData(:final data):
        try {
          final json = decodeObject(data, 'discovery_open_enquiry');
          final conversationId = json['conversation_id'];
          if (conversationId is! String || conversationId.trim().isEmpty) {
            return const RepositoryFailureResult(
              MalformedResponseError(
                operation: 'discovery_open_enquiry',
                detail: 'conversation_id',
              ),
            );
          }
          return RepositorySuccess(conversationId);
        } on MarketplaceDecodeException catch (error) {
          return RepositoryFailureResult(
            MalformedResponseError(
              operation: 'discovery_open_enquiry',
              detail: error.detail,
            ),
          );
        }
      case MarketplaceTransportError():
        return RepositoryFailureResult(
          errorMapper.map(response, operation: 'discovery_open_enquiry'),
        );
    }
  }

  static const RepositoryError _sessionError = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleError = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );
}

/// `ConversationRepository` bridge: chat reads delegate to the chat adapter and
/// the two opening operations use the marketplace eligibility command.
class MarketplaceConversationRepository implements ConversationRepository {
  MarketplaceConversationRepository({
    required this.chat,
    required this.opener,
    this.enquiryOpener,
  });

  final ConversationRepository chat;
  final MarketplaceConversationOpener opener;

  /// Optional discovery-enquiry opener. Absent keeps Store/Hocatrends
  /// enquiries unavailable instead of creating an unauthorized conversation.
  final MarketplaceDiscoveryEnquiryOpener? enquiryOpener;

  static const RepositoryError _discoveryUnavailable = PermissionDeniedError(
    action: 'conversation_open_unavailable',
    entityType: 'conversation',
  );

  @override
  Future<RepositoryResult<PageSlice<ConversationSummary>>> fetchInbox({
    required String userId,
    PageQuery page = PageQuery.standard,
  }) => chat.fetchInbox(userId: userId, page: page);

  @override
  Future<RepositoryResult<Conversation>> fetchConversation({
    required String conversationId,
  }) => chat.fetchConversation(conversationId: conversationId);

  @override
  Future<RepositoryResult<PageSlice<ConversationMessage>>> fetchMessages({
    required String conversationId,
    PageQuery page = PageQuery.standard,
    String? beforeMessageId,
  }) => chat.fetchMessages(
    conversationId: conversationId,
    page: page,
    beforeMessageId: beforeMessageId,
  );

  @override
  Future<RepositoryResult<ConversationMessage>> sendMessage(
    SendMessageCommand command,
  ) => chat.sendMessage(command);

  @override
  Future<RepositoryResult<ConversationMember>> markConversationRead(
    MarkConversationReadCommand command,
  ) => chat.markConversationRead(command);

  @override
  Future<RepositoryResult<ConversationMember>> setConversationMuted(
    SetConversationMutedCommand command,
  ) => chat.setConversationMuted(command);

  @override
  Future<RepositoryResult<Conversation>> openTargetedRequestConversation(
    OpenTargetedRequestConversationCommand command,
  ) async {
    final opened = await opener.openOfferConversation(
      offerId: command.offerId,
      idempotencyKey: command.idempotencyKey,
      actingUserId: command.buyerUserId,
    );
    if (opened.isFailure) {
      return RepositoryFailureResult(opened.errorOrNull!);
    }
    return chat.fetchConversation(conversationId: opened.valueOrNull!);
  }

  @override
  Future<RepositoryResult<Conversation>> openDiscoveryEnquiry(
    OpenDiscoveryEnquiryCommand command,
  ) async {
    final opener = enquiryOpener;
    if (opener == null) {
      return const RepositoryFailureResult(_discoveryUnavailable);
    }
    if (command.origin == ConversationOrigin.hocatrendsEnquiry &&
        command.sellerProfileId == null) {
      return const RepositoryFailureResult(_discoveryUnavailable);
    }
    final opened = await opener.openDiscoveryEnquiry(
      origin: command.origin == ConversationOrigin.storeListing
          ? DiscoveryEnquiryOrigin.storeListing
          : DiscoveryEnquiryOrigin.hocatrendsEnquiry,
      subjectId: command.subjectId,
      sellerProfileId: command.sellerProfileId,
      idempotencyKey: command.idempotencyKey,
      actingUserId: command.initiatedByUserId,
    );
    if (opened.isFailure) {
      return RepositoryFailureResult(opened.errorOrNull!);
    }
    return chat.fetchConversation(conversationId: opened.valueOrNull!);
  }
}
