import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/offer_funding_sheet.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

void main() {
  for (final cancel in [true, false]) {
    testWidgets(
      'saved card returns to same draft after ${cancel ? "cancel" : "consent"}',
      (tester) async {
        final events = <Map<String, dynamic>>[];
        OfferFundingResult? outcome;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const TextField(key: Key('message')),
                    TextButton(
                      onPressed: () async {
                        outcome =
                            await showModalBottomSheet<OfferFundingResult>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => OfferFundingSheet(
                                planLabel: 'Free',
                                request: (input) async {
                                  events.add(input);
                                  if (input['operation'] == 'inspect')
                                    return {
                                      'card': {
                                        'brand': 'visa',
                                        'last4': '4242',
                                        'id': 'pm_Test',
                                      },
                                      'authorised': false,
                                    };
                                  return {'state': 'authorised'};
                                },
                              ),
                            );
                      },
                      child: const Text('Send offer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('message')),
          'Keep my offer',
        );
        await tester.tap(find.text('Send offer'));
        await tester.pumpAndSettle();
        expect(find.text('VISA •••• 4242'), findsOneWidget);
        expect(find.text('Continue to Stripe'), findsNothing);
        expect(
          tester
              .widget<SellerPrimaryButton>(find.byType(SellerPrimaryButton))
              .onPressed,
          isNull,
        );
        if (!cancel) {
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Authorize fees'));
        } else {
          await tester.tap(find.text('Return to my offer'));
        }
        await tester.pumpAndSettle();
        expect(
          outcome,
          cancel ? OfferFundingResult.canceled : OfferFundingResult.ready,
        );
        expect(find.text('Keep my offer'), findsOneWidget);
        expect(
          events.map((e) => e['operation']),
          cancel ? ['inspect'] : ['inspect', 'authorize'],
        );
        if (!cancel) expect(events.last['method'], 'pm_Test');
      },
    );
  }
}
