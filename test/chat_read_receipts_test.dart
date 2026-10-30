import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_codecs.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';

void main() {
  test('receipts are false until confirmed by the authorised message response', () {
    final json = <String,Object?>{
      'id':'message', 'conversation_id':'pair', 'sender_user_id':'seller',
      'kind':'text', 'text':'Hello', 'sent_at':'2026-10-26T10:00:00Z',
      'attachment_media_ids':<Object?>[],
    };
    expect(decodeMessageJson(json).readByCounterpart, isFalse);
    expect(decodeMessageJson({...json,'read_by_counterpart':true}).readByCounterpart,isTrue);
  });
  testWidgets('outgoing tick changes only when the receipt is confirmed', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(bool read) => MaterialApp(home: Scaffold(body: ApprovedConversationBody(
      onBack:(){},onPrimary:(){},onCall:(){},onMore:(){},onRequestChange:(){},
      onChangeLocation:(){},onAttach:(){},onSend:(_){},onLearnMore:(){},
      realEntries:[ApprovedConversationEntry(isOutgoing:true,time:'10:00',text:'Hello',isRead:read)],
    )));
    await tester.pumpWidget(page(false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.done),findsOneWidget);
    expect(find.byIcon(Icons.done_all),findsNothing);
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.done_all),findsOneWidget);
    expect(find.byIcon(Icons.done),findsNothing);
  });
}
