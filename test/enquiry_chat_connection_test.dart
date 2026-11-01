import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'deal_chat_connection_test.dart' show DealBackend;

class EnquiryBackend extends DealBackend implements MarketplaceEnquiryChatBackend {
  @override
  bool get enquiryThreadsEnabled=>true;
  final enquiryCalls=<({String id,String key,List<String> media})>[];
  final reads=<String>[];
  final enquiryHistory=<String,List<ConversationMessage>>{};
  bool uncertain=false;
  Completer<ConversationMessage>? enquiryPending;
  @override
  Future<List<ChatEnquiry>> loadEnquiries(String id) async=>[
    ChatEnquiry(id:'store',conversationId:id,origin:'store_listing',subjectId:'listing',label:'Store item'),
    ChatEnquiry(id:'trend',conversationId:id,origin:'hocatrends_enquiry',subjectId:'topic',label:'Topic'),
  ];
  @override
  Future<PageSlice<ConversationMessage>> loadEnquiryMessages(String id,String enquiry,String? cursor) async=>PageSlice(items:enquiryHistory[enquiry]??[]);
  @override
  Future<int> markEnquiryRead(String id,String enquiry,String message) async {reads.add(enquiry);return 0;}
  @override
  Future<ConversationMessage> sendEnquiryMessage({required String conversationId,required String enquiryId,required String text,required String clientMessageId,List<String> mediaIds=const []}) async {
    enquiryCalls.add((id:enquiryId,key:clientMessageId,media:mediaIds));
    if(uncertain) {uncertain=false;throw const StoreBackendException('Retry',ambiguous:true);}
    if(enquiryPending!=null) return enquiryPending!.future;
    final message=ConversationMessage(id:clientMessageId,conversationId:conversationId,senderUserId:'buyer',text:text.isEmpty?'Photo':text,sentAt:DateTime.utc(2026),enquiryId:enquiryId);
    enquiryHistory.putIfAbsent(enquiryId,()=>[]).add(message);
    return message;
  }
}
void main() {
  test('explicit enquiry replaces restored deal; each thread keeps its own draft and messages',() async {
    final backend=EnquiryBackend();final repo=LocalMarketplaceRepository(chatBackend:backend);addTearDown(repo.dispose);
    await repo.openChatConversation('pair',offerId:'deal');
    await repo.sendChatMessage('Deal text');
    await repo.openChatConversation('pair',enquiryId:'store');
    expect(repo.activeChatOfferId,isNull);expect(repo.activeChatEnquiryId,'store');expect(repo.chatMessages,isEmpty);
    backend.uncertain=true;
    expect((await repo.sendChatMessage('Retained store draft')).outcomeUncertain,isTrue);
    final key=backend.enquiryCalls.last.key;
    await repo.selectChatEnquiry('trend');expect(repo.unconfirmedChatText,isNull);
    await repo.sendChatMessage('Topic text');
    await repo.selectChatEnquiry('store');expect(repo.unconfirmedChatText,'Retained store draft');
    await repo.sendChatMessage('Retained store draft');expect(backend.enquiryCalls.last.key,key);
    await repo.markChatRead(repo.chatMessages.last.id);
    await repo.selectChatDeal('deal');expect(repo.activeChatEnquiryId,isNull);expect(repo.chatMessages.single.text,'Deal text');
    expect(backend.calls.length,1);expect(backend.reads,contains('store'));
  });
  test('late enquiry acknowledgement cannot appear in another enquiry or deal',() async {
    final backend=EnquiryBackend();final repo=LocalMarketplaceRepository(chatBackend:backend);addTearDown(repo.dispose);
    await repo.openChatConversation('pair',enquiryId:'store');
    final pending=Completer<ConversationMessage>();backend.enquiryPending=pending;
    final sent=repo.sendChatMessage('Slow store reply');
    await repo.selectChatEnquiry('trend');
    pending.complete(ConversationMessage(id:'late',conversationId:'pair',senderUserId:'buyer',text:'Slow store reply',sentAt:DateTime.utc(2026),enquiryId:'store'));
    expect((await sent).isSuccess,isTrue);expect(repo.activeChatEnquiryId,'trend');expect(repo.chatMessages,isEmpty);
  });
  test('delayed uploaded photo stays with original enquiry and retry uses that scope',() async {
    final backend=EnquiryBackend();final repo=LocalMarketplaceRepository(chatBackend:backend);addTearDown(repo.dispose);
    await repo.openChatConversation('pair',enquiryId:'store');
    await repo.selectChatDeal('deal');
    final held=await repo.sendChatAttachment(text:'',mediaIds:['photo'],expectedConversationId:'pair',expectedEnquiryId:'store');
    expect(held.isSuccess,isFalse);expect(backend.enquiryCalls,isEmpty);expect(repo.unconfirmedChatAttachmentIds,isEmpty);
    await repo.selectChatEnquiry('store');expect(repo.unconfirmedChatAttachmentIds,['photo']);
    expect((await repo.retryChatAttachment()).isSuccess,isTrue);
    expect(backend.enquiryCalls.single.id,'store');expect(backend.enquiryCalls.single.media,['photo']);expect(backend.calls,isEmpty);
  });
  test('unsupported or unknown enquiry fails closed instead of sending to a deal',() async {
    final old=LocalMarketplaceRepository(chatBackend:DealBackend());addTearDown(old.dispose);
    await old.openChatConversation('pair',offerId:'deal');
    await expectLater(old.openChatConversation('pair',enquiryId:'store'),throwsA(isA<StoreBackendException>()));
    expect(old.activeChatOfferId,'deal');
    final repo=LocalMarketplaceRepository(chatBackend:EnquiryBackend());addTearDown(repo.dispose);
    await expectLater(repo.openChatConversation('pair',enquiryId:'unknown'),throwsA(isA<StoreBackendException>()));
    expect(repo.chatMessages,isEmpty);expect(repo.chatMessagesError,isNotNull);
  });
}
