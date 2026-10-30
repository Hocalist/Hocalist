import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/category_answers.dart';
import 'package:hocalist/domain/phase2/catalogue.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/approved/category_question_editor.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_error_mapper.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/failures.dart';

final stamp = RecordStamp(
  revision: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
CategoryQuestion question({bool multiple = false}) => CategoryQuestion(
  CatalogueOptionGroup(
    id: 'group',
    categoryId: 'category',
    label: 'Colour',
    selectionMode: multiple
        ? CatalogueSelectionMode.multiple
        : CatalogueSelectionMode.single,
    isRequired: true,
    status: CatalogueEntryStatus.active,
    sortOrder: 0,
    stamp: stamp,
  ),
  [
    for (final label in ['Blue', 'Green'])
      CatalogueOption(
        id: label,
        groupId: 'group',
        label: label,
        status: CatalogueEntryStatus.active,
        sortOrder: 0,
        stamp: stamp,
      ),
  ],
);

void main() {
  test('changed server questions return an actionable validation result', () {
    for (final message in [
      'required_category_answers',
      'invalid_field: category_answers',
    ]) {
      final error = const MarketplaceErrorMapper().map(
        MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server,
          code: '22023',
          message: message,
        ),
        operation: 'marketplace_command',
      );
      expect(error, isA<ValidationError>());
      expect((error as ValidationError).issues.single.field, 'categoryAnswers');
      expect(error.issues.single.message, contains('category'));
    }
  });
  testWidgets(
    'category controls remain usable across phone widths and text sizes',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.15, 1.3, 1.6]) {
          tester.view.resetPhysicalSize();
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CategoryQuestionEditor(
                        key: ValueKey('$width-$scale'),
                        categoryId: 'category',
                        answers: const [],
                        onChanged: (_) {},
                        loader: (_) async => [question(multiple: true)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$width at $scale');
          expect(find.text('Blue'), findsOneWidget);
          expect(find.text('Green'), findsOneWidget);
        }
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
  for (final multiple in [false, true]) {
    testWidgets(
      'required ${multiple ? 'multiple' : 'single'} choices save and clear',
      (tester) async {
        final key = GlobalKey<CategoryQuestionEditorState>();
        List<CategoryAnswer> answers = [];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => CategoryQuestionEditor(
                  key: key,
                  categoryId: 'category',
                  answers: answers,
                  loader: (_) async => [question(multiple: multiple)],
                  onChanged: (value) => update(() => answers = value),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(key.currentState!.validationMessage(), contains('colour'));
        await tester.tap(find.text('Blue'));
        await tester.pump();
        expect(key.currentState!.validationMessage(), isNull);
        await tester.tap(find.text('Green'));
        await tester.pump();
        expect(
          answers.single.optionIds,
          multiple ? ['Blue', 'Green'] : ['Green'],
        );
        await tester.tap(find.text('Green'));
        await tester.pump();
        if (multiple) {
          await tester.tap(find.text('Blue'));
          await tester.pump();
        }
        expect(answers, isEmpty);
        expect(key.currentState!.validationMessage(), isNotNull);
      },
    );
  }
  testWidgets('loading and failed questions block submission and allow retry', (
    tester,
  ) async {
    final key = GlobalKey<CategoryQuestionEditorState>();
    final pending = Completer<List<CategoryQuestion>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryQuestionEditor(
            key: key,
            categoryId: 'category',
            answers: const [],
            onChanged: (_) {},
            loader: (_) => ++calls == 1 ? pending.future : Future.value([]),
          ),
        ),
      ),
    );
    expect(key.currentState!.validationMessage(), contains('wait'));
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(key.currentState!.validationMessage(), contains('category'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(key.currentState!.validationMessage(), isNull);
  });
  test('answer snapshots decode but command input contains only IDs', () {
    final answer = CategoryAnswer(
      groupId: 'g',
      label: 'Colour',
      optionIds: ['b'],
      labels: ['Blue'],
    );
    expect(CategoryAnswer.decode([answer.toJson()]).single.labels, ['Blue']);
    expect(categoryAnswerInput([answer]), {
      'g': ['b'],
    });
    expect(
      () => CategoryAnswer.decode([
        {'group_id': 'g'},
      ]),
      throwsFormatException,
    );
  });
}
