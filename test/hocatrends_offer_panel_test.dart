import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/hocatrends_offer_panel.dart';

void main() {
  testWidgets('opt-in retries the same choice after an unknown result', (tester) async {
    final choices = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HocatrendsOfferPanel(
      load: () async => (enabled: false, eligible: true),
      save: (enabled) async {
        choices.add(enabled);
        if (choices.length == 1) throw StateError('Unknown result');
        return (enabled: enabled, eligible: true);
      },
    ))));
    await tester.pumpAndSettle();
    final toggle=find.byKey(const Key('hocatrends-offer-opt-in'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    await tester.tap(find.byKey(const Key('hocatrends-preference-retry')));
    await tester.pumpAndSettle();
    expect(choices, [true,true]);
    expect(tester.widget<SwitchListTile>(toggle).value, true);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(choices, [true,true,false]);
    expect(tester.widget<SwitchListTile>(toggle).value, false);
  });

  testWidgets('ineligible seller can opt out but cannot opt in', (tester) async {
    var current = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HocatrendsOfferPanel(
      load: () async => (enabled: current, eligible: false),
      save: (enabled) async { current=enabled; return (enabled: enabled, eligible: false); },
    ))));
    await tester.pumpAndSettle();
    final toggle=find.byKey(const Key('hocatrends-offer-opt-in'));
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(current,false);
    expect(tester.widget<SwitchListTile>(toggle).onChanged,isNull);
  });
}
