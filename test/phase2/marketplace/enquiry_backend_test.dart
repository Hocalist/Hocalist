import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_chat_backend.dart';
import 'chat_backend_test.dart' show FakeConversationRepository;
void main(){
  test('real enquiry backend routes messages, attachments, reads and validates returned scope',() async {
    final calls=<String>[];
    final payload=<String,Object?>{'id':'message','conversation_id':'pair','sender_user_id':'buyer','kind':'text','text':'Hello','sent_at':'2026-10-30T12:00:00Z','enquiry_id':'enquiry'};
    final backend=Phase2MarketplaceChatBackend(conversations:FakeConversationRepository(),currentUserId:'buyer',enquiryThreadsEnabled:true,attachmentsEnabled:true,dealRpc:(name,args) async {
      calls.add(name);expect(args['p_conversation'],'pair');
      if(name=='chat_enquiries') return {'items':[{'id':'enquiry','conversation_id':'pair','origin':'store_listing','subject_id':'listing','label':'Listing'}]};
      expect(args['p_enquiry'],'enquiry');
      if(name=='chat_enquiry_messages') return {'items':[payload],'next_cursor':null};
      if(name=='chat_enquiry_mark_read') return {'unread_count':2};
      return payload;
    });
    expect((await backend.loadEnquiries('pair')).single.label,'Listing');
    expect((await backend.loadEnquiryMessages('pair','enquiry',null)).items.single.enquiryId,'enquiry');
    await backend.sendEnquiryMessage(conversationId:'pair',enquiryId:'enquiry',text:'Hello',clientMessageId:'key',mediaIds:['photo']);
    expect(await backend.markEnquiryRead('pair','enquiry','message'),2);
    expect(calls,['chat_enquiries','chat_enquiry_messages','chat_enquiry_send','chat_enquiry_mark_read']);
    payload['enquiry_id']='other';
    await expectLater(backend.loadEnquiryMessages('pair','enquiry',null),throwsA(isA<StoreBackendException>()));
    await expectLater(backend.sendEnquiryMessage(conversationId:'pair',enquiryId:'enquiry',text:'Hello',clientMessageId:'key'),throwsA(isA<StoreBackendException>()));
  });
  test('disabled or changed-session enquiry cannot call transport',() async {
    var session='buyer';var calls=0;
    final backend=Phase2MarketplaceChatBackend(conversations:FakeConversationRepository(),currentUserId:'buyer',identity:()=>session,enquiryThreadsEnabled:true,dealRpc:(name,args) async {calls++;return {};});
    session='other';
    await expectLater(backend.loadEnquiries('pair'),throwsA(isA<StoreBackendException>()));expect(calls,0);
    final disabled=Phase2MarketplaceChatBackend(conversations:FakeConversationRepository(),currentUserId:'buyer',dealRpc:(name,args) async {calls++;return {};});
    await expectLater(disabled.loadEnquiries('pair'),throwsA(isA<StoreBackendException>()));expect(calls,0);
  });
}
