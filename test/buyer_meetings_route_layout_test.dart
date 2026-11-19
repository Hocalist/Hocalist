import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show AppFrame;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_session.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/support/support_adapter.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 390.0]) {
    testWidgets('buyer reports an expired agreed meeting from Past at $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = _SupportTransport();
      final support = SupportAdapter(transport: transport, session: _Buyer());
      final schedule = MeetingScheduleView(
        sequence: 1, date: LocalDate(year: 2020, month: 3, day: 1),
        startTime: LocalTime(hour: 12, minute: 0), timezoneId: 'UTC',
        offsetMinutes: 0, instant: DateTime.utc(2020, 3, 1, 12),
        placeChoice: 'custom', proposedByUserId: 'seller', status: 'accepted',
        createdAt: DateTime.utc(2020),
      );
      MeetingView row(String id, String status, DateTime cutoff) => MeetingView(
        meetingId: id, conversationId: 'conversation', requestId: 'request-$id',
        offerId: 'offer-$id', buyerUserId: 'buyer', sellerUserId: 'seller',
        status: status, revision: 1, meetingExpiresAt: cutoff,
        acceptedSchedule: status == 'proposed' ? null : schedule, revisions: [],
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ApprovedBuyerMeetingsPage(
        meetings: [
          row('past', 'accepted', DateTime.utc(2020, 3, 2)),
          row('future', 'accepted', DateTime.utc(2099)),
          row('canceled', 'cancelled', DateTime.utc(2020)),
          row('unaccepted', 'proposed', DateTime.utc(2020)),
        ],
        onBack: () {}, loading: false, error: null,
        onReportPurchase: support.reportUnconfirmedPurchase,
      ))));
      await tester.pumpAndSettle();
      expect(find.text('Report unconfirmed purchase'), findsNothing);
      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      final report = find.text('Report unconfirmed purchase');
      expect(report, findsOneWidget);
      await tester.tap(report);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('buyer-modal-sheet-close')));
      await tester.pumpAndSettle();
      expect(transport.calls, isEmpty);
      await tester.tap(report);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.text('Report sent to support'), findsOneWidget);
      expect(transport.calls.single.function, 'support_command');
      expect(transport.calls.single.params['p_key'], 'unconfirmed-purchase-past');
      final input = transport.calls.single.params['p_input'] as Map;
      expect(input['body'], contains('Meeting: past'));
      expect(input['body'], contains('Offer: offer-past'));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('full meetings empty state stays visible at $width/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: AppFrame(
                  childOwnsScroll: true,
                  header: const Text('Buyer mode'),
                  child: ApprovedBuyerMeetingsPage(
                    onBack: () {},
                    meetings: const [],
                    loading: false,
                    error: null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('No upcoming meetings yet').hitTestable(),
          findsOneWidget,
        );
      });
    }
  }
}

class _Buyer implements MarketplaceSession {
  @override
  String get currentUserId => 'buyer';
}

class _SupportTransport implements MarketplaceTransport {
  final calls = <MarketplaceRpcCall>[];
  @override
  Future<MarketplaceTransportResponse> callMarketplaceRpc(MarketplaceRpcCall call) async {
    calls.add(call);
    return const MarketplaceTransportData({
      'id': '00000000-0000-4000-8000-000000000001', 'status': 'open', 'revision': 1,
    });
  }
}
