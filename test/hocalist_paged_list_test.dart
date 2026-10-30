import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_paged_list.dart';

void main() {
  testWidgets('next fetches a server cursor and previous reuses cached rows', (tester) async {
    var items = List.generate(5, (i) => i), calls = 0;
    var more = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return HocalistPagedList<int>(items: items, hasMore: more,
        loadMore: () async { calls++; update(() { items = List.generate(8, (i) => i); more = false; }); },
        itemBuilder: (_, i) => Text('Item $i'));
    }))));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Item 5'), findsOneWidget);
    expect(find.text('Item 0'), findsNothing);
    expect(calls, 1);
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Item 0'), findsOneWidget);
    expect(calls, 1);
  });
  testWidgets('a filtered empty cache loads its first page without skipping rows', (tester) async {
    var items = <int>[];
    var more = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return HocalistPagedList<int>(items: items, hasMore: more,
        loadMore: () async { update(() { items = [1, 2]; more = false; }); },
        itemBuilder: (_, i) => Text('Item $i'));
    }))));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
  });
  testWidgets('failed next page keeps current rows and permits retry', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HocalistPagedList<int>(
      items: [1, 2, 3, 4, 5], hasMore: true,
      loadMore: () async => throw StateError('offline'), itemBuilder: (_, i) => Text('Item $i'),
    ))));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Next')).onPressed, isNotNull);
  });
}
