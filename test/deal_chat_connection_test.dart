import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/offers.dart';

class DealBackend
    implements
        MarketplaceChatBackend,
        MarketplacePagedChatBackend,
        MarketplaceDealChatBackend,
        MarketplaceChatAttachmentBackend {
  final calls = <({String offer, String key})>[];
  final history = <String, List<ConversationMessage>>{};
  bool failOnce = false;
  String? paymentBlockedOffer;
  Completer<ConversationMessage>? pending;
  @override
  bool get dealThreadsEnabled => true;
  @override
  Future<int> markDealRead(String id, String offer, String message) async => 0;
  @override
  bool get chatAttachmentsEnabled => true;
  @override
  Future<List<ConversationSummary>> loadInbox() async => [];
  @override
  Future<Offer?> loadMeetingOffer(String id) async => null;
  @override
  Future<List<ConversationMessage>> loadMessages(String id) async => [];
  @override
  Future<PageSlice<ConversationMessage>> loadMessagePage(
    String id,
    String? cursor,
  ) async => PageSlice(items: []);
  @override
  Future<PageSlice<ConversationMessage>> loadDealMessagePage(
    String id,
    String offer,
    String? cursor,
  ) async => PageSlice(items: history[offer] ?? []);
  @override
  Future<ConversationMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
  }) async => throw StateError('Unscoped send');
  @override
  Future<ConversationMessage> sendAttachment({
    required String conversationId,
    required String text,
    required List<String> mediaIds,
    required String clientMessageId,
  }) async => throw StateError('Unscoped attachment');
  @override
  Future<ConversationMessage> sendDealMessage({
    required String conversationId,
    required String offerId,
    required String text,
    required String clientMessageId,
    List<String> mediaIds = const [],
  }) async {
    calls.add((offer: offerId, key: clientMessageId));
    if (offerId == paymentBlockedOffer) {
      throw const StoreBackendException('This deal needs a payment update.',code:'deal_payment_required');
    }
    if (failOnce) {
      failOnce = false;
      throw const StoreBackendException('Try again', ambiguous: true);
    }
    if (pending != null) return pending!.future;
    final m = ConversationMessage(
      id: clientMessageId,
      conversationId: conversationId,
      senderUserId: 'buyer',
      text: text.isEmpty ? 'Synthetic photo' : text,
      sentAt: DateTime.utc(2026),
      offerId: offerId,
    );
    history.putIfAbsent(offerId, () => []).add(m);
    return m;
  }

  @override
  Future<ConversationMember> markRead({
    required String conversationId,
    required String messageId,
  }) async => throw UnimplementedError();
  @override
  Future<ConversationMember> setMuted({
    required String conversationId,
    required bool muted,
  }) async => throw UnimplementedError();
}

void main() {
  test('reopening the same participant chat retains its selected deal scope', () async {
    final backend = DealBackend();
    final repo = LocalMarketplaceRepository(chatBackend: backend);
    addTearDown(repo.dispose);
    await repo.openChatConversation('pair', offerId: 'first');
    await repo.sendChatMessage('First deal only');
    await repo.openChatConversation('pair');
    expect(repo.activeChatOfferId, 'first');
    expect(repo.chatMessages.single.text, 'First deal only');
    await repo.openChatConversation('different-pair');
    expect(repo.activeChatOfferId, isNull);
  });
  test('payment recovery preserves only the affected deal draft and permits other deals', () async {
    final backend=DealBackend()..paymentBlockedOffer='first';
    final repo=LocalMarketplaceRepository(chatBackend:backend);
    addTearDown(repo.dispose);
    await repo.openChatConversation('pair',offerId:'first');
    final failed=await repo.sendChatMessage('Draft awaiting payment');
    expect(failed.code,'deal_payment_required');
    expect(failed.outcomeUncertain,isFalse);
    expect(repo.chatPaymentRequired,isTrue);
    expect(repo.unconfirmedChatText,'Draft awaiting payment');
    await repo.selectChatDeal('second');
    expect(repo.chatPaymentRequired,isFalse);
    expect(repo.unconfirmedChatText,isNull);
    expect((await repo.sendChatMessage('Other deal continues')).isSuccess,isTrue);
    await repo.selectChatDeal('first');
    expect(repo.chatPaymentRequired,isTrue);
    expect(repo.unconfirmedChatText,'Draft awaiting payment');
    backend.paymentBlockedOffer=null;
    expect((await repo.sendChatMessage('Edited draft after payment')).isSuccess,isTrue);
    expect(repo.chatPaymentRequired,isFalse);
    expect(repo.unconfirmedChatText,isNull);
    expect(repo.chatMessages.single.text,'Edited draft after payment');
  });
  test(
    'deal switching isolates history and retry keys inside one participant chat',
    () async {
      final backend = DealBackend()..failOnce = true;
      final repo = LocalMarketplaceRepository(chatBackend: backend);
      addTearDown(repo.dispose);
      await repo.openChatConversation('pair', offerId: 'first');
      await repo.sendChatMessage('First deal draft');
      final firstKey = backend.calls.single.key;
      expect(repo.unconfirmedChatText, 'First deal draft');
      await repo.selectChatDeal('second');
      expect(repo.chatMessages, isEmpty);
      expect(repo.unconfirmedChatText, isNull);
      await repo.sendChatMessage('Second deal draft');
      expect(repo.chatMessages.single.offerId, 'second');
      expect(backend.calls.last.key, isNot(firstKey));
      await repo.selectChatDeal('first');
      expect(repo.unconfirmedChatText, 'First deal draft');
      expect(repo.chatMessages, isEmpty);
      await repo.sendChatMessage('First deal draft');
      expect(backend.calls.last.key, firstKey);
      expect(repo.chatMessages.every((m) => m.offerId == 'first'), isTrue);
    },
  );
  test(
    'a delayed send and photo selection cannot spill into a different deal',
    () async {
      final backend = DealBackend()..pending = Completer<ConversationMessage>();
      final repo = LocalMarketplaceRepository(chatBackend: backend);
      addTearDown(repo.dispose);
      await repo.openChatConversation('pair', offerId: 'first');
      final sending = repo.sendChatMessage('First');
      await repo.selectChatDeal('second');
      backend.pending!.complete(
        ConversationMessage(
          id: 'delayed',
          conversationId: 'pair',
          senderUserId: 'buyer',
          text: 'First',
          sentAt: DateTime.utc(2026),
          offerId: 'first',
        ),
      );
      await sending;
      expect(repo.chatMessages, isEmpty);
      final photo = await repo.sendChatAttachment(
        text: '',
        mediaIds: ['synthetic'],
        expectedConversationId: 'pair',
        expectedOfferId: 'first',
      );
      expect(photo.isSuccess, isFalse);
      expect(repo.hasUnconfirmedChatAttachment, isFalse);
      await repo.selectChatDeal('first');
      expect(repo.hasUnconfirmedChatAttachment, isTrue);
    },
  );
}
