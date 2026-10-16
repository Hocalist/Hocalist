import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 1,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  );

  ConversationMember buyerMember() => ConversationMember(
    userId: 'auth-buyer',
    profileId: 'buyer-1',
    role: HocalistRole.buyer,
    joinedAt: DateTime.utc(2026, 5, 1),
  );

  ConversationMember sellerMember() => ConversationMember(
    userId: 'auth-seller',
    profileId: 'seller-1',
    role: HocalistRole.seller,
    joinedAt: DateTime.utc(2026, 5, 1),
    isMuted: true,
    lastReadMessageId: 'message-1',
    lastReadAt: DateTime.utc(2026, 5, 2),
  );

  group('Conversation origins', () {
    test('targeted request conversations link a request and offer', () {
      final conversation = Conversation(
        id: 'conversation-1',
        origin: ConversationOrigin.targetedRequest,
        requestId: 'request-1',
        offerId: 'offer-1',
        members: [buyerMember(), sellerMember()],
        status: ConversationStatus.open,
        stamp: stamp,
      );

      expect(conversation.isDealScoped, isTrue);
      expect(conversation.requestId, 'request-1');
      expect(conversation.offerId, 'offer-1');
      expect(conversation.memberFor('auth-seller')?.isMuted, isTrue);
      expect(conversation.memberFor('missing'), isNull);
    });

    test('targeted request conversations require a request id', () {
      expect(
        () => Conversation(
          id: 'conversation-1',
          origin: ConversationOrigin.targetedRequest,
          members: [buyerMember(), sellerMember()],
          status: ConversationStatus.open,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => Conversation(
          id: 'conversation-1',
          origin: ConversationOrigin.targetedRequest,
          requestId: 'request-1',
          listingId: 'listing-1',
          members: [buyerMember(), sellerMember()],
          status: ConversationStatus.open,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('Store conversations link a listing and are not deal-scoped', () {
      final conversation = Conversation(
        id: 'conversation-2',
        origin: ConversationOrigin.storeListing,
        listingId: 'listing-1',
        members: [buyerMember(), sellerMember()],
        status: ConversationStatus.open,
        stamp: stamp,
      );

      expect(conversation.isDealScoped, isFalse);
      expect(
        () => Conversation(
          id: 'conversation-2',
          origin: ConversationOrigin.storeListing,
          requestId: 'request-1',
          listingId: 'listing-1',
          members: [buyerMember(), sellerMember()],
          status: ConversationStatus.open,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('Hocatrends enquiries link a discovery topic only', () {
      final conversation = Conversation(
        id: 'conversation-3',
        origin: ConversationOrigin.hocatrendsEnquiry,
        discoveryTopicId: 'trend-1',
        members: [buyerMember(), sellerMember()],
        status: ConversationStatus.open,
        stamp: stamp,
      );

      expect(conversation.isDealScoped, isFalse);
      expect(
        () => Conversation(
          id: 'conversation-3',
          origin: ConversationOrigin.hocatrendsEnquiry,
          discoveryTopicId: 'trend-1',
          offerId: 'offer-1',
          members: [buyerMember(), sellerMember()],
          status: ConversationStatus.open,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('a conversation needs at least one member', () {
      expect(
        () => Conversation(
          id: 'conversation-1',
          origin: ConversationOrigin.targetedRequest,
          requestId: 'request-1',
          members: const [],
          status: ConversationStatus.open,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ConversationMember', () {
    test('mute and read updates preserve membership identity', () {
      final member = sellerMember();
      final updated = member.copyWith(
        isMuted: false,
        lastReadMessageId: 'message-2',
        lastReadAt: DateTime.utc(2026, 5, 3),
      );

      expect(updated.isMuted, isFalse);
      expect(updated.lastReadMessageId, 'message-2');
      expect(updated.userId, member.userId);
      expect(updated.profileId, member.profileId);
      expect(updated.role, member.role);
      expect(updated.joinedAt, member.joinedAt);
      expect(member.isMuted, isTrue);
    });
  });

  group('ConversationMessage', () {
    test('accepts text or attachment metadata but not an empty message', () {
      final attachment = MediaReference(
        id: 'media-1',
        kind: MediaKind.image,
        fileName: 'ipad-front.jpg',
        contentType: 'image/jpeg',
        byteSize: 204800,
      );

      final message = ConversationMessage(
        id: 'message-2',
        conversationId: 'conversation-1',
        senderUserId: 'auth-seller',
        kind: MessageKind.attachment,
        text: 'Here is the exact item.',
        attachments: [attachment],
        sentAt: DateTime.parse('2026-05-02T09:31:00+02:00'),
        clientMessageId: 'client-2',
      );

      expect(message.attachments.single.fileName, 'ipad-front.jpg');
      expect(message.attachments.single.byteSize, 204800);
      expect(message.sentAt.isUtc, isTrue);
      expect(message.clientMessageId, 'client-2');

      expect(
        () => ConversationMessage(
          id: 'message-3',
          conversationId: 'conversation-1',
          senderUserId: 'auth-seller',
          sentAt: DateTime.utc(2026, 5, 2),
        ),
        throwsArgumentError,
      );
    });

    test('system notices cannot carry attachments', () {
      expect(
        () => ConversationMessage(
          id: 'message-4',
          conversationId: 'conversation-1',
          senderUserId: 'system',
          kind: MessageKind.systemNotice,
          text: 'Offer updated.',
          attachments: [
            MediaReference(
              id: 'media-1',
              kind: MediaKind.image,
              fileName: 'x.png',
            ),
          ],
          sentAt: DateTime.utc(2026, 5, 2),
        ),
        throwsArgumentError,
      );
    });

    test('debug output never includes message text', () {
      final message = ConversationMessage(
        id: 'message-5',
        conversationId: 'conversation-1',
        senderUserId: 'auth-buyer',
        text: 'SENTINEL-MESSAGE-TEXT',
        sentAt: DateTime.utc(2026, 5, 2),
      );

      expect(message.text, 'SENTINEL-MESSAGE-TEXT');
      expect(message.toString().contains('SENTINEL-MESSAGE-TEXT'), isFalse);
    });
  });

  group('ConversationSummary', () {
    Conversation conversation() => Conversation(
      id: 'conversation-1',
      origin: ConversationOrigin.targetedRequest,
      requestId: 'request-1',
      members: [buyerMember(), sellerMember()],
      status: ConversationStatus.open,
      stamp: stamp,
    );

    test('counterpart must be a conversation member', () {
      final summary = ConversationSummary(
        conversation: conversation(),
        counterpartDisplayName: 'Northside Tech',
        counterpartProfileId: 'seller-1',
        unreadCount: 2,
      );

      expect(summary.unreadCount, 2);
      expect(summary.counterpartProfileId, 'seller-1');

      expect(
        () => ConversationSummary(
          conversation: conversation(),
          counterpartDisplayName: 'Unknown',
          counterpartProfileId: 'profile-404',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Conversation commands', () {
    test('targeted and discovery opens stay separate', () {
      final targeted = OpenTargetedRequestConversationCommand(
        requestId: 'request-1',
        offerId: 'offer-1',
        buyerUserId: 'auth-buyer',
        idempotencyKey: 'open-1',
      );
      expect(targeted.offerId, 'offer-1');

      final enquiry = OpenDiscoveryEnquiryCommand(
        origin: ConversationOrigin.hocatrendsEnquiry,
        subjectId: 'trend-1',
        initiatedByUserId: 'auth-buyer',
        idempotencyKey: 'open-2',
      );
      expect(enquiry.origin, ConversationOrigin.hocatrendsEnquiry);

      expect(
        () => OpenDiscoveryEnquiryCommand(
          origin: ConversationOrigin.targetedRequest,
          subjectId: 'request-1',
          initiatedByUserId: 'auth-buyer',
          idempotencyKey: 'open-3',
        ),
        throwsArgumentError,
      );
    });

    test('send requires content and a client message id', () {
      final send = SendMessageCommand(
        conversationId: 'conversation-1',
        senderUserId: 'auth-buyer',
        text: 'Does Saturday still work?',
        clientMessageId: 'client-1',
      );
      expect(send.clientMessageId, 'client-1');

      expect(
        () => SendMessageCommand(
          conversationId: 'conversation-1',
          senderUserId: 'auth-buyer',
          clientMessageId: 'client-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => SendMessageCommand(
          conversationId: 'conversation-1',
          senderUserId: 'auth-buyer',
          text: 'Hi',
          clientMessageId: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => SendMessageCommand(
          conversationId: 'conversation-1',
          senderUserId: 'auth-buyer',
          attachmentMediaIds: const ['media-1', ' '],
          clientMessageId: 'client-1',
        ),
        throwsArgumentError,
      );
    });

    test('read and mute commands carry the acting member', () {
      final read = MarkConversationReadCommand(
        conversationId: 'conversation-1',
        userId: 'auth-buyer',
        lastReadMessageId: 'message-5',
      );
      final mute = SetConversationMutedCommand(
        conversationId: 'conversation-1',
        userId: 'auth-buyer',
        isMuted: true,
        idempotencyKey: 'mute-1',
      );

      expect(read.lastReadMessageId, 'message-5');
      expect(mute.isMuted, isTrue);
    });
  });
}
