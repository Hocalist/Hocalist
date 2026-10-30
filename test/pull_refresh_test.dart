import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/pull_refresh.dart';
import 'package:hocalist/components/hocalist_reload_link.dart';

void main() {
  testWidgets('nested page scrolls refresh once', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullRefreshHost(
            onRefresh: () async {
              reads++;
            },
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 400,
                  child: ListView(
                    key: const Key('inner'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [Text('Nested details')],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(const Key('inner')), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(reads, 1);
  });
  testWidgets('pages without a scroll view refresh without resetting inputs', (
    tester,
  ) async {
    var reads = 0;
    final field = TextEditingController(text: 'Unsaved address');
    addTearDown(field.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullRefreshHost(
            onRefresh: () async {
              reads++;
            },
            child: Column(
              children: [
                TextField(controller: field),
                const Expanded(child: SizedBox(key: Key('space'))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(const Key('space')), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(field.text, 'Unsaved address');
  });
  testWidgets('pull replaces reload controls and waits for data', (
    tester,
  ) async {
    var reads = 0;
    final done = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullRefreshHost(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                HocalistReloadLink(
                  onPressed: () async {
                    reads++;
                    await done.future;
                  },
                ),
                const Text('Saved information'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Reload'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Pull to refresh'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Pull to refresh'), findsNothing);
  });
  testWidgets('a cancelled pull leaves no instruction or reload', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullRefreshHost(
            child: PullRefreshAction(
              onRefresh: () => reads++,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [Text('Details')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('Pull to refresh'), findsNothing);
  });
  testWidgets('unmounted reads do not run and discard remains explicit', (
    tester,
  ) async {
    var discarded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullRefreshHost(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                HocalistReloadLink(
                  description: 'Reload and discard edits',
                  onPressed: () => discarded = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(discarded, false);
    await tester.tap(find.text('Discard changes'));
    expect(discarded, true);
  });
}
