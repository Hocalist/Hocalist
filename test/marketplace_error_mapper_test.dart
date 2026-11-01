import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_error_mapper.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/meetings/meeting_adapter.dart';
import 'package:hocalist/data/phase2/meetings/phase2_meetings_backend.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'phase2/marketplace/support/marketplace_fakes.dart';

void main() {
  for (final code in ['meeting_seller_payment_required', 'meeting_seller_account_pending']) {
    test('meeting screen receives the specific message: $code', () async {
      final transport = FakeMarketplaceTransport()
        ..handler = (_) => MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server, code: 'P0001', message: code,
        );
      final backend = Phase2MarketplaceMeetingsBackend(adapter: MeetingDataAdapter(
        transport: transport, session: FakeMarketplaceSession('user-a'),
      ));
      await expectLater(backend.respondToMeeting(
        meetingId: '80000000-0000-4000-8000-000000000001', accept: true,
        expectedRevision: 1, operationKey: 'payment-gate',
      ), throwsA(isA<StoreBackendException>().having((e) => e.message, 'message',
        contains(code == 'meeting_seller_payment_required' ? 'Manage payment' : 'account issue'))));
    });
  }
  test('meeting payment errors guide sellers and protect buyer privacy', () {
    const mapper = MarketplaceErrorMapper();
    final seller = mapper.map(const MarketplaceTransportError(
      kind: MarketplaceTransportErrorKind.server,
      code: 'P0001', message: 'meeting_seller_payment_required',
    ), operation: 'meeting.propose');
    final buyer = mapper.map(const MarketplaceTransportError(
      kind: MarketplaceTransportErrorKind.server,
      code: 'P0001', message: 'meeting_seller_account_pending',
    ), operation: 'meeting.respond');
    expect(seller.debugMessage, contains('Manage payment'));
    expect(buyer.debugMessage, contains('seller to resolve an account issue'));
    expect(buyer.debugMessage, isNot(contains('payment')));
    expect(buyer.debugMessage, contains('view or cancel'));
  });
}
