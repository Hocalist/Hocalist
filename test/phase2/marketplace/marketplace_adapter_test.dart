// Focused marketplace codec and adapter tests. Fakes only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/catalogue.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/repositories.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/domain/phase2/store_listings.dart';

import 'support/marketplace_fakes.dart';

MarketplaceTransportResponse data(Object? value) =>
    MarketplaceTransportData(value);

MarketplaceTransportResponse serverError(String message, {String? code}) =>
    MarketplaceTransportError(
      kind: MarketplaceTransportErrorKind.server,
      message: message,
      code: code,
    );

void main() {
  late FakeMarketplaceSession session;
  late FakeMarketplaceTransport transport;
  late MarketplaceDataAdapter adapter;

  setUp(() {
    session = FakeMarketplaceSession(buyerId);
    transport = FakeMarketplaceTransport();
    adapter = MarketplaceDataAdapter(transport: transport, session: session);
  });

  test('integrated Hocatrends enquiry forwards the selected seller', () async {
    final chat = _FakeConversationRepository();
    final bridge = MarketplaceConversationRepository(
      chat: chat,
      opener: MarketplaceConversationOpener(
        transport: transport,
        session: session,
      ),
      enquiryOpener: MarketplaceDiscoveryEnquiryOpener(
        transport: transport,
        session: session,
      ),
    );
    transport.handler = (_) =>
        data({'conversation_id': '70000000-0000-4000-8000-000000000001'});
    await bridge.openDiscoveryEnquiry(
      OpenDiscoveryEnquiryCommand(
        origin: ConversationOrigin.hocatrendsEnquiry,
        subjectId: categoryId,
        sellerProfileId: sellerProfileId,
        initiatedByUserId: buyerId,
        idempotencyKey: 'topic-enquiry',
      ),
    );
    expect(transport.calls.single.function, 'discovery_open_enquiry');
    expect(transport.calls.single.params['p_input'], {
      'origin': 'hocatrends_enquiry',
      'topic_id': categoryId,
      'seller_profile_id': sellerProfileId,
    });
    expect(chat.lastConversationId, '70000000-0000-4000-8000-000000000001');
  });

  group('marketplace codecs', () {
    test('request coordinates decode privately and reject malformed pairs', () {
      final raw = requestJson();
      raw['location'] = {
        'use_home_address': false,
        'address_line1': 'Private place',
        'latitude': 40.9,
        'longitude': -73.8,
      };
      final decoded = decodeRequestJson(raw, 'request');
      expect(decoded.draft.location.coordinates?.longitude, -73.8);
      expect(decoded.draft.location.toString(), isNot(contains('40.9')));
      for (final bad in [double.nan, double.infinity, 91, '40.9', null]) {
        raw['location'] = {
          'use_home_address': false,
          'address_line1': 'Private place',
          'latitude': bad,
          'longitude': -73.8,
        };
        expect(
          () => decodeRequestJson(raw, 'request'),
          throwsA(isA<MarketplaceDecodeException>()),
        );
      }
    });
    test('decode a request, lead, offer, listing and catalogue', () {
      final request = decodeRequestJson(requestJson(), 'request');
      expect(request.id, requestId);
      expect(request.status, RequestStatus.active);
      expect(request.draft.kind, RequestKind.product);
      expect(request.draft.condition, ProductCondition.used);
      expect(request.draft.budget.minimum?.minorUnits, 35000);
      expect(request.draft.location.useHomeAddress, isTrue);

      final lead = decodeLeadJson(leadJson(), 'lead');
      expect(lead.buyerDisplayName, 'Buyer A');
      expect(lead.areaLabel, 'Yonkers, NY');
      expect(lead.requestRevision, 1);

      final offer = decodeOfferJson(offerJson(), 'offer');
      expect(offer.status, OfferStatus.submitted);
      expect(offer.revisions.single.sequence, 1);
      expect(offer.revisions.single.terms.price.minorUnits, 42000);
      expect(
        offer.revisions.single.terms.schedule.date,
        LocalDate(year: 2026, month: 10, day: 1),
      );
      expect(
        offer.revisions.single.terms.place.choice,
        MeetupPlaceChoice.specificPlace,
      );

      final listing = decodeStoreListingJson(listingJson(), 'listing');
      expect(listing.status, ListingStatus.draft);
      expect(listing.moderationStatus, ListingModerationStatus.pendingReview);

      final categories = decodeCatalogueJson(catalogueJson(), 'catalogue');
      expect(categories.single.label, 'Electronics');
      expect(categories.single.scope, CatalogueScope.product);
      final groups = decodeNestedOptionGroupsJson(
        (catalogueJson()['categories']! as List).single as Map<String, Object?>,
        'catalogue',
      );
      expect(groups.single.label, 'Condition');
    });

    test('reject malformed payloads with safe details', () {
      expect(
        () => decodeRequestJson(requestJson()..['revision'] = 0, 'request'),
        throwsA(
          isA<MarketplaceDecodeException>().having(
            (e) => e.detail,
            'detail',
            'request.revision',
          ),
        ),
      );
      expect(
        () => decodeOfferJson(offerJson()..['status'] = 'unknown', 'offer'),
        throwsA(
          isA<MarketplaceDecodeException>().having(
            (e) => e.detail,
            'detail',
            'offer.status',
          ),
        ),
      );
      expect(
        () => decodeStoreListingJson(
          listingJson()..['moderation_status'] = 'weird',
          'listing',
        ),
        throwsA(
          isA<MarketplaceDecodeException>().having(
            (e) => e.detail,
            'detail',
            'listing.moderation_status',
          ),
        ),
      );
      expect(
        () => decodePage<MarketplaceRequest>(
          <String, Object?>{'items': 'nope', 'next_cursor': null},
          'page',
          decodeRequestJson,
        ),
        throwsA(isA<MarketplaceDecodeException>()),
      );
    });
  });

  group('marketplace adapter', () {
    test('request create posts the reviewed wire fields', () async {
      transport.handler = (call) => data(requestJson());
      final result = await adapter.createRequest(
        CreateRequestCommand(
          idempotencyKey: 'key-1',
          draft: RequestDraft(
            kind: RequestKind.product,
            title: 'iPad Air, 5th gen or newer',
            description: 'Needs to be in good condition.',
            condition: ProductCondition.used,
            quantity: 1,
            budget: MoneyRange(
              minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
              maximum: Money(minorUnits: 48000, currencyCode: 'USD'),
            ),
            categoryId: categoryId,
          ),
        ),
      );
      expect(result.isSuccess, isTrue);
      final call = transport.calls.single;
      expect(call.function, 'marketplace_command');
      expect(call.params['p_operation'], 'request.create');
      expect(call.params['p_key'], 'key-1');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['kind'], 'product');
      expect(input['condition'], 'used');
      expect(input['budget_minimum_minor'], 35000);
      expect(input['category_id'], categoryId);
      expect(input['use_home_address'], isTrue);
    });

    test('identity mismatch and stale session are rejected', () async {
      final mismatch = await adapter.fetchBuyerRequests(
        buyerUserId: 'someone-else',
      );
      expect(mismatch.isFailure, isTrue);
      expect(
        (mismatch.errorOrNull! as PermissionDeniedError).action,
        'identity_mismatch',
      );
      expect(transport.calls, isEmpty);

      final gate = Completer<void>();
      transport.gate = gate.future;
      transport.handler = (call) =>
          data(pageJson([requestJson()], cursor: null));
      final pending = adapter.fetchBuyerRequests(buyerUserId: buyerId);
      await Future<void>.delayed(Duration.zero);
      session.replaceWith('user-c');
      gate.complete();
      final stale = await pending;
      expect(stale.isFailure, isTrue);
      expect(
        (stale.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
    });

    test('revision and limit failures map to typed errors', () async {
      transport.handler = (call) =>
          serverError('revision_conflict', code: 'P0001');
      final conflict = await adapter.updateRequest(
        UpdateRequestCommand(
          requestId: requestId,
          expectedRevision: 1,
          idempotencyKey: 'key-2',
          draft: RequestDraft(
            kind: RequestKind.product,
            title: 'Updated',
            condition: ProductCondition.used,
          ),
        ),
      );
      expect(
        (conflict.errorOrNull! as ConflictError).conflictCode,
        'revision_conflict',
      );

      transport.handler = (call) =>
          serverError('store_limit_exceeded', code: 'P0001');
      final limited = await adapter.createStoreListing(
        CreateStoreListingCommand(
          kind: ListingKind.product,
          title: 'New listing',
          categoryId: categoryId,
          priceLabel: r'$10',
          idempotencyKey: 'key-3',
        ),
      );
      expect(
        (limited.errorOrNull! as LimitExceededError).limitCode,
        'store_listing',
      );

      transport.handler = (call) => serverError('request_access_denied');
      final denied = await adapter.fetchRequest(requestId: 'x');
      expect(
        (denied.errorOrNull! as PermissionDeniedError).action,
        'request_access_denied',
      );
    });

    test('credit targeting failures map to typed, explicit errors', () async {
      final terms = OfferTerms(
        price: Money(minorUnits: 42000, currencyCode: 'USD'),
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 11, day: 5),
          startTime: LocalTime(hour: 18, minute: 30),
          timezoneId: 'America/New_York',
        ),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: 'Synthetic Mall',
        ),
      );
      SubmitOfferCommand submit() => SubmitOfferCommand(
        requestId: requestId,
        terms: terms,
        idempotencyKey: 'credit-key',
      );

      transport.handler = (call) =>
          serverError('targeting_fee_unconfigured', code: 'P0001');
      var result = await adapter.submitOffer(submit());
      expect(
        (result.errorOrNull! as ConflictError).conflictCode,
        'targeting_fee_unconfigured',
      );

      transport.handler = (call) =>
          serverError('insufficient_single_batch', code: 'P0001');
      result = await adapter.submitOffer(submit());
      expect(
        (result.errorOrNull! as ConflictError).conflictCode,
        'insufficient_single_batch',
      );

      transport.handler = (call) =>
          serverError('weekly_target_limit', code: 'P0001');
      result = await adapter.submitOffer(submit());
      expect(
        (result.errorOrNull! as LimitExceededError).limitCode,
        'weekly_targets',
      );
    });

    test(
      'offer select sends the accepted revision and expected revision',
      () async {
        transport.handler = (call) => data(
          offerJson(
            status: 'selected',
            revision: 2,
            acceptedRevisionId: revisionId,
          ),
        );
        final result = await adapter.selectOffer(
          SelectOfferCommand(
            offerId: offerId,
            revisionId: revisionId,
            expectedOfferRevision: 1,
            idempotencyKey: 'key-4',
          ),
        );
        expect(result.isSuccess, isTrue);
        final input =
            transport.calls.single.params['p_input']! as Map<String, Object?>;
        expect(input['offer_id'], offerId);
        expect(input['revision_id'], revisionId);
        expect(input['expected_offer_revision'], 1);
        expect(result.valueOrNull!.status, OfferStatus.selected);
      },
    );

    test('seller offers are filtered to the signed-in seller', () async {
      session.replaceWith(sellerId);
      transport.handler = (call) => data(pageJson([offerJson()]));
      final result = await adapter.fetchSellerOffers(sellerUserId: sellerId);
      expect(result.valueOrNull!.items, hasLength(1));

      transport.handler = (call) => data(
        pageJson([
          <String, Object?>{
            ...offerJson(),
            'id': '40000000-0000-4000-8000-000000000002',
            'seller_user_id': 'user-c',
            'revisions': [
              <String, Object?>{
                ...revisionJson(),
                'offer_id': '40000000-0000-4000-8000-000000000002',
              },
            ],
          },
        ]),
      );
      final filtered = await adapter.fetchSellerOffers(sellerUserId: sellerId);
      expect(filtered.valueOrNull!.items, isEmpty);
    });

    test('catalogue admin commands require the server admin check', () async {
      transport.handler = (call) =>
          serverError('admin_required', code: '42501');
      final denied = await adapter.createCategory(
        CreateCatalogueCategoryCommand(
          label: 'Electronics',
          scope: CatalogueScope.product,
          idempotencyKey: 'cat-1',
        ),
      );
      expect(
        (denied.errorOrNull! as PermissionDeniedError).action,
        'admin_required',
      );

      transport.handler = (call) => call.function == 'marketplace_catalogue'
          ? data(catalogueJson())
          : data(<String, Object?>{'id': categoryId});
      final created = await adapter.createCategory(
        CreateCatalogueCategoryCommand(
          label: 'Electronics',
          scope: CatalogueScope.product,
          idempotencyKey: 'cat-1',
        ),
      );
      expect(created.isSuccess, isTrue);
      final calls = transport.calls;
      expect(calls.first.function, 'marketplace_admin_command');
      expect(calls.last.function, 'marketplace_catalogue');
    });

    test('locations and store summary decode server configuration', () async {
      transport.handler = (call) => data(
        pageJson([
          <String, Object?>{
            'id': '60000000-0000-4000-8000-000000000001',
            'country_code': 'US',
            'region': 'NY',
            'city': 'Yonkers',
            'label': 'Yonkers, NY',
            'status': 'active',
            'sort_order': 1,
            'revision': 1,
            'created_at': '2026-05-01T00:00:00+00:00',
            'updated_at': '2026-05-01T00:00:00+00:00',
          },
        ]),
      );
      final locations = await adapter.fetchLocations();
      expect(locations.valueOrNull!.items.single.label, 'Yonkers, NY');

      transport.handler = (call) => data(<String, Object?>{
        'draft_count': 1,
        'active_count': 2,
        'paused_count': 0,
        'archived_count': 3,
        'plan_code': 'free',
        'store_listing_limit': 3,
      });
      final summary = await adapter.fetchSellerStoreSummary(
        sellerUserId: buyerId,
      );
      expect(summary.valueOrNull!.totalCount, 6);
      final plan = await adapter.fetchStorePlanStatus();
      expect(plan.valueOrNull!.planCode, 'free');
      expect(plan.valueOrNull!.storeListingLimit, 3);
    });
  });

  group('conversation opener and bridge', () {
    test('opening requires a selected offer result from the server', () async {
      final opener = MarketplaceConversationOpener(
        transport: transport,
        session: session,
      );
      transport.handler = (call) =>
          serverError('conversation_not_eligible', code: 'P0001');
      final ineligible = await opener.openOfferConversation(
        offerId: offerId,
        idempotencyKey: 'open-1',
        actingUserId: buyerId,
      );
      expect(
        (ineligible.errorOrNull! as ConflictError).conflictCode,
        'conversation_not_eligible',
      );

      transport.handler = (call) => data(<String, Object?>{
        'conversation_id': '70000000-0000-4000-8000-000000000001',
      });
      final opened = await opener.openOfferConversation(
        offerId: offerId,
        idempotencyKey: 'open-2',
        actingUserId: buyerId,
      );
      expect(opened.valueOrNull, '70000000-0000-4000-8000-000000000001');
      final input =
          transport.calls.last.params['p_input']! as Map<String, Object?>;
      expect(input['offer_id'], offerId);
    });

    test(
      'bridge delegates reads and marks discovery opening unavailable',
      () async {
        final chat = _FakeConversationRepository();
        final bridge = MarketplaceConversationRepository(
          chat: chat,
          opener: MarketplaceConversationOpener(
            transport: transport,
            session: session,
          ),
        );
        final inbox = await bridge.fetchInbox(userId: buyerId);
        expect(inbox.isSuccess, isTrue);
        expect(chat.inboxCalls, 1);

        final discovery = await bridge.openDiscoveryEnquiry(
          OpenDiscoveryEnquiryCommand(
            origin: ConversationOrigin.storeListing,
            subjectId: listingId,
            initiatedByUserId: buyerId,
            idempotencyKey: 'discovery-1',
          ),
        );
        expect(
          (discovery.errorOrNull! as PermissionDeniedError).action,
          'conversation_open_unavailable',
        );
        expect(transport.calls, isEmpty);
      },
    );
  });
}

class _FakeConversationRepository implements ConversationRepository {
  int inboxCalls = 0;
  String? lastConversationId;

  @override
  Future<RepositoryResult<PageSlice<ConversationSummary>>> fetchInbox({
    required String userId,
    PageQuery page = PageQuery.standard,
  }) async {
    inboxCalls += 1;
    return RepositorySuccess(PageSlice<ConversationSummary>(items: const []));
  }

  @override
  Future<RepositoryResult<Conversation>> fetchConversation({
    required String conversationId,
  }) async {
    lastConversationId = conversationId;
    return const RepositoryFailureResult(
      NotFoundError(entityType: 'conversation', entityId: 'requested'),
    );
  }

  @override
  Future<RepositoryResult<PageSlice<ConversationMessage>>> fetchMessages({
    required String conversationId,
    PageQuery page = PageQuery.standard,
    String? beforeMessageId,
  }) async =>
      RepositorySuccess(PageSlice<ConversationMessage>(items: const []));

  @override
  Future<RepositoryResult<ConversationMessage>> sendMessage(
    SendMessageCommand command,
  ) async =>
      const RepositoryFailureResult(ServerError(operation: 'sendMessage'));

  @override
  Future<RepositoryResult<ConversationMember>> markConversationRead(
    MarkConversationReadCommand command,
  ) async => const RepositoryFailureResult(
    ServerError(operation: 'markConversationRead'),
  );

  @override
  Future<RepositoryResult<ConversationMember>> setConversationMuted(
    SetConversationMutedCommand command,
  ) async => const RepositoryFailureResult(
    ServerError(operation: 'setConversationMuted'),
  );

  @override
  Future<RepositoryResult<Conversation>> openTargetedRequestConversation(
    OpenTargetedRequestConversationCommand command,
  ) async => const RepositoryFailureResult(
    ServerError(operation: 'openTargetedRequestConversation'),
  );

  @override
  Future<RepositoryResult<Conversation>> openDiscoveryEnquiry(
    OpenDiscoveryEnquiryCommand command,
  ) async => const RepositoryFailureResult(
    ServerError(operation: 'openDiscoveryEnquiry'),
  );
}
