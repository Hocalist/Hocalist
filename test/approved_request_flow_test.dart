import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';

import 'test_fonts.dart';

const _proofHeight = 844.0;
const _compactProofHeight = 693.0;
const _captureKey = Key('approved-request-capture');
const _writeRequestFlowProof = bool.fromEnvironment(
  'HOCALIST_WRITE_REQUEST_FLOW_PROOF',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadHocalistTestFonts);

  for (final width in <double>[304, 320, 360, 390, 430, 600, 768, 980]) {
    testWidgets('approved request states fit ${width.toInt()} logical pixels', (
      tester,
    ) async {
      for (final state in _ProofState.values) {
        await _pumpState(
          tester,
          state: state,
          width: width,
          height: width == 320 ? _compactProofHeight : _proofHeight,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${state.name} overflowed at ${width.toInt()}px',
        );
      }
    });
  }

  testWidgets('request progress keeps completed Details blue', (tester) async {
    const active = Color(0xff1917ff);
    const inactive = Color(0xffe7e8ee);

    Future<Color?> dotColor(Key key) async {
      final container = find
          .descendant(of: find.byKey(key), matching: find.byType(Container))
          .first;
      final widget = tester.widget<Container>(container);
      return (widget.decoration as BoxDecoration?)?.color;
    }

    await _pumpState(tester, state: _ProofState.product, width: 390);
    expect(await dotColor(const ValueKey('approved-request-step-1')), active);
    expect(await dotColor(const ValueKey('approved-request-step-2')), inactive);
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('approved-request-step-connector')),
          )
          .color,
      active,
    );

    await _pumpState(tester, state: _ProofState.location, width: 390);
    expect(await dotColor(const ValueKey('approved-request-step-1')), active);
    expect(await dotColor(const ValueKey('approved-request-step-2')), active);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Location transition resets the integrated request scroll', (
    tester,
  ) async {
    await _pumpState(
      tester,
      state: _ProofState.product,
      width: 390,
      height: _compactProofHeight,
    );
    final scrollable = find.byKey(const Key('approved-request-scroll'));
    final continueAction = find.text('Continue');
    await tester.ensureVisible(continueAction);
    await tester.pumpAndSettle();
    final requestList = tester.widget<ListView>(scrollable);
    expect(requestList.controller!.position.pixels, greaterThan(0));

    await tester.tap(continueAction);
    await tester.pumpAndSettle();

    expect(requestList.controller!.position.pixels, 0);
    expect(find.text('Post a new request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Request Details keeps approved paired cards from 320 to 430 at normal scale',
    (tester) async {
      for (final width in <double>[304, 320, 360, 390, 430]) {
        await _pumpState(
          tester,
          state: _ProofState.details,
          width: width,
          height: width == 320 ? _compactProofHeight : _proofHeight,
        );

        _expectPairedSurfaces(tester, 'Condition', 'Budget (optional)');
        _expectPairedSurfaces(
          tester,
          'Quantity',
          'Willing to receive higher offers?',
        );
        _expectPairedSurfaces(
          tester,
          'Edit location',
          'Current estimated rewards',
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'Request Details overflowed at ${width.toInt()}px.',
        );
      }
    },
  );

  testWidgets(
    'phones preserve readable type and larger widths expand fluidly',
    (tester) async {
      await _pumpState(tester, state: _ProofState.product, width: 390);
      expect(find.byType(ApprovedRequestFlowPage), findsOneWidget);
      final referenceTitle = tester.widget<Text>(
        find.text('Post a new request'),
      );
      final referenceKind = _ancestorRect(
        tester,
        find.text('Product'),
        '_ApprovedKindCard',
      )!;
      final referenceContinue = tester.getRect(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );

      for (final width in <double>[304, 320, 360]) {
        await _pumpState(
          tester,
          state: _ProofState.product,
          width: width,
          height: width == 320 ? _compactProofHeight : _proofHeight,
        );
        final title = tester.widget<Text>(find.text('Post a new request'));
        final kind = _ancestorRect(
          tester,
          find.text('Product'),
          '_ApprovedKindCard',
        )!;
        final continueRect = tester.getRect(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          title.style!.fontSize,
          closeTo(referenceTitle.style!.fontSize! * width / 390, 0.01),
        );
        expect(kind.height, closeTo(referenceKind.height * width / 390, 1));
        expect(
          continueRect.height,
          closeTo(referenceContinue.height * width / 390, 1),
        );
        expect(tester.takeException(), isNull);
      }

      for (final width in <double>[430, 600, 768, 980]) {
        await _pumpState(tester, state: _ProofState.product, width: width);
        final kind = _ancestorRect(
          tester,
          find.text('Product'),
          '_ApprovedKindCard',
        )!;
        expect(kind.width, greaterThan(referenceKind.width));
        expect(kind.center.dx, lessThan(width / 2));
        expect(
          tester.getCenter(find.text('Post a new request')).dx,
          closeTo(width / 2, 0.1),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('320px default preserves a readable approved composition', (
    tester,
  ) async {
    await _pumpState(
      tester,
      state: _ProofState.product,
      width: 320,
      height: _compactProofHeight,
    );
    _expectSameRow(tester, 'Back', 'Continue');
    _expectSameRow(tester, 'Product', 'Service');
    _expectPairedSurfaces(tester, 'Condition', 'Budget');
    _expectPairedSurfaces(
      tester,
      'Quantity',
      'Willing to receive higher offers?',
    );
    _expectSingleRenderedLine(tester, 'Post a new request');
    _expectSingleRenderedLine(tester, 'I want to buy a product');
    _expectSingleRenderedLine(tester, 'I need a service');
    _expectSingleRenderedLine(tester, 'Back');
    _expectSingleRenderedLine(tester, 'Continue');
    _expectSingleRenderedLine(tester, 'Yes');
    _expectSingleRenderedLine(tester, 'Willing to receive higher offers?');
    expect(
      tester.widget<Text>(find.text('Continue')).style?.fontSize,
      closeTo(10.5, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('Yes')).style?.fontSize,
      closeTo(9.25 * 320 / 390, 0.01),
    );
    _expectRenderedLineCountAtMost(
      tester,
      'Tell us more about the product you need',
      2,
    );
    final continueButton = find.ancestor(
      of: find.text('Continue'),
      matching: find.byType(FilledButton),
    );
    final continueBottom = tester.getRect(continueButton).bottom;
    expect(
      continueBottom,
      inInclusiveRange(600, 1800),
      reason:
          'The readable 320px layout should keep Continue near the viewport '
          'without compressing the form; actual bottom: $continueBottom.',
    );
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpState(
      tester,
      state: _ProofState.service,
      width: 320,
      height: _compactProofHeight,
    );
    _expectRenderedLineCountAtMost(
      tester,
      'Tell us more about the service you need',
      2,
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpState(
      tester,
      state: _ProofState.location,
      width: 320,
      height: _compactProofHeight,
    );
    _expectSameRow(tester, 'City', 'State');
    _expectSameRow(tester, 'Country', 'ZIP code');
    final postRequest = tester.getRect(
      find.ancestor(
        of: find.text('Post request'),
        matching: find.byType(FilledButton),
      ),
    );
    final locationBack = tester.getRect(
      find.ancestor(of: find.text('Back'), matching: find.byType(TextButton)),
    );
    expect(locationBack.top, greaterThan(postRequest.bottom));
    _expectSingleRenderedLine(tester, 'Post request');
    _expectSingleRenderedLine(tester, 'Back');
    await tester.ensureVisible(find.text('Post request'));
    await tester.pumpAndSettle();
    expect(find.text('Post request').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpState(
      tester,
      state: _ProofState.details,
      width: 320,
      height: _compactProofHeight,
    );
    _expectSingleRenderedLine(tester, 'iPad Air, 5th gen or newer');
    await tester.ensureVisible(find.byKey(const Key('save-request-changes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-request-changes')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('390 and 320 preserve expanded form cards and CTA sizing', (
    tester,
  ) async {
    await _pumpState(tester, state: _ProofState.product, width: 390);
    final description390 = _ancestorRect(
      tester,
      find.text('Describe the product'),
      '_ApprovedSurface',
    )!;
    final quantity390 = _ancestorRect(
      tester,
      find.text('Quantity'),
      '_ApprovedSurface',
    )!;
    final higherOffers390 = _ancestorRect(
      tester,
      find.text('Willing to receive higher offers?'),
      '_ApprovedSurface',
    )!;
    final continue390 = tester.getRect(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );

    expect(description390.height, greaterThanOrEqualTo(100));
    expect(
      <double>[
        quantity390.height,
        higherOffers390.height,
      ].reduce((left, right) => left > right ? left : right),
      greaterThanOrEqualTo(90),
    );
    expect(continue390.height, greaterThanOrEqualTo(40));

    await _pumpState(
      tester,
      state: _ProofState.product,
      width: 320,
      height: _compactProofHeight,
    );
    const scale = 320 / 390;
    final description320 = _ancestorRect(
      tester,
      find.text('Describe the product'),
      '_ApprovedSurface',
    )!;
    final quantity320 = _ancestorRect(
      tester,
      find.text('Quantity'),
      '_ApprovedSurface',
    )!;
    final higherOffers320 = _ancestorRect(
      tester,
      find.text('Willing to receive higher offers?'),
      '_ApprovedSurface',
    )!;
    final continue320 = tester.getRect(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(FilledButton),
      ),
    );

    expect(description320.height, lessThan(description390.height));
    expect(quantity320.height, lessThanOrEqualTo(quantity390.height));
    expect(higherOffers320.height, lessThanOrEqualTo(higherOffers390.height));
    expect(
      <double>[
        quantity320.height,
        higherOffers320.height,
      ].reduce((left, right) => left > right ? left : right),
      lessThanOrEqualTo(
        <double>[
          quantity390.height,
          higherOffers390.height,
        ].reduce((left, right) => left > right ? left : right),
      ),
    );
    expect(continue320.height, closeTo(continue390.height * scale, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px normal scale keeps approved bottom actions reachable', (
    tester,
  ) async {
    for (final state in _ProofState.values) {
      await _pumpState(tester, state: state, width: 390);
      final action = switch (state) {
        _ProofState.product || _ProofState.service => find.text('Continue'),
        _ProofState.location => find.text('Post request'),
        _ProofState.details => find.byKey(const Key('save-request-changes')),
      };
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('request update uses the upgraded decision sheet', (
    tester,
  ) async {
    await _pumpState(tester, state: _ProofState.details, width: 390);
    final save = find.byKey(const Key('save-request-changes'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('approved-update-request-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const ValueKey('approved-request-sheet-primary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('request fields separate hint and entered-value hierarchy', (
    tester,
  ) async {
    await _pumpState(tester, state: _ProofState.product, width: 390);

    final minimum = tester.widget<TextField>(
      find.byKey(const ValueKey('approved-request-budget-min')),
    );
    expect(minimum.decoration?.hintText, 'Min');
    expect(minimum.decoration?.hintStyle?.fontWeight, FontWeight.w500);
    expect(minimum.style?.fontWeight, FontWeight.w800);
    expect(minimum.decoration?.constraints?.minHeight, closeTo(40, 0.01));

    final description = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Describe what you need, preferred brand, model, size, color, condition, features, etc.',
      ),
    );
    final descriptionPadding =
        description.decoration!.contentPadding! as EdgeInsets;
    expect(descriptionPadding.top, greaterThanOrEqualTo(10));
    expect(descriptionPadding.bottom, greaterThanOrEqualTo(10));

    await _pumpState(tester, state: _ProofState.location, width: 390);
    final cityFinder = find.byKey(
      const ValueKey('approved-request-address-city'),
    );
    final countryFinder = find.byKey(
      const ValueKey('approved-request-address-country'),
    );
    final cityDecoration = tester.widget<InputDecorator>(
      find.descendant(of: cityFinder, matching: find.byType(InputDecorator)),
    );
    final cityEditable = tester.widget<EditableText>(
      find.descendant(of: cityFinder, matching: find.byType(EditableText)),
    );
    final countryDecoration = tester.widget<InputDecorator>(
      find.descendant(of: countryFinder, matching: find.byType(InputDecorator)),
    );
    final countryEditable = tester.widget<EditableText>(
      find.descendant(of: countryFinder, matching: find.byType(EditableText)),
    );
    expect(cityDecoration.decoration.hintText, 'Enter city');
    expect(cityDecoration.decoration.hintStyle?.fontWeight, FontWeight.w500);
    final cityPadding = cityDecoration.decoration.contentPadding! as EdgeInsets;
    expect(cityPadding.top, closeTo(12, 0.01));
    expect(cityPadding.bottom, closeTo(12, 0.01));
    expect(tester.getRect(cityFinder).height, closeTo(44, 0.01));
    expect(cityEditable.style.fontWeight, FontWeight.w600);
    expect(countryEditable.controller.text, 'United States');
    expect(
      countryEditable.style.color,
      isNot(countryDecoration.decoration.hintStyle?.color),
    );
    expect(
      countryDecoration.decoration.suffixIconConstraints?.minWidth,
      lessThan(30),
    );
    expect(find.text('United States'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('304px fields and controls retain vertical breathing room', (
    tester,
  ) async {
    await _pumpState(tester, state: _ProofState.product, width: 304);
    for (final label in <String>[
      'Post a new request',
      'I want to buy a product',
      'I need a service',
      'New',
      'Used',
      'Yes',
      'Back',
      'Continue',
    ]) {
      _expectSingleRenderedLine(tester, label);
    }
    _expectSingleRenderedLine(tester, 'No');

    await _pumpState(tester, state: _ProofState.location, width: 304);
    final cityFinder = find.byKey(
      const ValueKey('approved-request-address-city'),
    );
    final cityDecoration = tester.widget<InputDecorator>(
      find.descendant(of: cityFinder, matching: find.byType(InputDecorator)),
    );
    final cityPadding = cityDecoration.decoration.contentPadding! as EdgeInsets;
    expect(cityPadding.top, greaterThanOrEqualTo(10));
    expect(cityPadding.bottom, greaterThanOrEqualTo(10));
    expect(tester.getRect(cityFinder).height, greaterThanOrEqualTo(34));
    _expectSingleRenderedLine(tester, 'Post request');
    _expectSingleRenderedLine(tester, 'Back');

    await _pumpState(tester, state: _ProofState.details, width: 304);
    final yesButton = find.ancestor(
      of: find.text("Yes, I'm open"),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.getRect(yesButton).height, greaterThanOrEqualTo(28));
    final condition = _ancestorRect(
      tester,
      find.text('Condition'),
      '_ApprovedSurface',
    )!;
    final quantity = _ancestorRect(
      tester,
      find.text('Quantity'),
      '_ApprovedSurface',
    )!;
    expect(quantity.top - condition.bottom, greaterThanOrEqualTo(4));
    for (final label in <String>[
      'New',
      'Used',
      "Yes, I'm open",
      r'$350',
      r'$480',
      'Chicago, IL',
      r'$6.40',
      '32 offers',
      'Save changes',
    ]) {
      _expectSingleRenderedLine(tester, label);
    }
    _expectSingleRenderedLine(tester, 'No, stay on budget');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Product choice and budget controls sit on the card baseline', (
    tester,
  ) async {
    await _pumpState(tester, state: _ProofState.product, width: 390);

    final conditionSurface = _ancestorRect(
      tester,
      find.text('Condition'),
      '_ApprovedSurface',
    )!;
    final newButton = tester.getRect(
      find.ancestor(
        of: find.text('New'),
        matching: find.byType(OutlinedButton),
      ),
    );
    final budgetSurface = _ancestorRect(
      tester,
      find.text('Budget'),
      '_ApprovedSurface',
    )!;
    final minimumField = tester.getRect(
      find.byKey(const ValueKey('approved-request-budget-min')),
    );

    expect(conditionSurface.bottom - newButton.bottom, lessThanOrEqualTo(9));
    expect(budgetSurface.bottom - minimumField.bottom, lessThanOrEqualTo(9));
    expect(newButton.height, closeTo(minimumField.height, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Request Details paired controls share approved baselines', (
    tester,
  ) async {
    for (final width in <double>[304, 320, 390, 430]) {
      await _pumpState(tester, state: _ProofState.details, width: width);

      final newButton = tester.getRect(
        find.ancestor(
          of: find.text('New'),
          matching: find.byType(OutlinedButton),
        ),
      );
      final minimumBudget = _ancestorRect(
        tester,
        find.text(r'$350'),
        '_ApprovedValueBox',
      )!;
      final quantityButton = tester.getRect(
        find.byTooltip('Increase quantity'),
      );
      final higherOfferButton = tester.getRect(
        find.ancestor(
          of: find.text("Yes, I'm open"),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(newButton.top, closeTo(minimumBudget.top, 0.5));
      expect(newButton.bottom, closeTo(minimumBudget.bottom, 0.5));
      expect(quantityButton.top, closeTo(higherOfferButton.top, 1));
      expect(quantityButton.bottom, closeTo(higherOfferButton.bottom, 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Large and XL text reflow and remain actionable', (tester) async {
    for (final scale in <double>[1.15, 1.3, 1.6]) {
      for (final state in _ProofState.values) {
        await _pumpState(
          tester,
          state: state,
          width: 320,
          height: _compactProofHeight,
          textScale: scale,
        );
        final action = switch (state) {
          _ProofState.product || _ProofState.service => find.text('Continue'),
          _ProofState.location => find.text('Post request'),
          _ProofState.details => find.byKey(const Key('save-request-changes')),
        };
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: '${state.name} failed at 320px with text scale $scale',
        );
      }
    }
  });

  testWidgets('request callbacks and local controls remain wired', (
    tester,
  ) async {
    var title = '';
    var budget = '';
    var submitted = false;
    var offersOpened = false;

    await _pumpWidget(
      tester,
      width: 390,
      child: ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (value) => title = value,
        onBudgetChanged: (value) => budget = value,
        onBack: () {},
        onNotifications: () {},
        onSubmit: () => submitted = true,
        includeAppChrome: true,
      ),
    );

    final titleField = find.byType(TextFormField).first;
    await tester.enterText(titleField, 'iPad Air');
    expect(title, 'iPad Air');

    final continueAction = find.text('Continue');
    await tester.ensureVisible(continueAction);
    await tester.pumpAndSettle();
    await tester.tap(continueAction);
    await tester.pumpAndSettle();
    final postAction = find.text('Post request');
    await tester.ensureVisible(postAction);
    await tester.pumpAndSettle();
    await tester.tap(postAction);
    expect(submitted, isTrue);
    expect(budget, isEmpty);

    await _pumpWidget(
      tester,
      width: 390,
      child: ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () => offersOpened = true,
        includeAppChrome: true,
      ),
    );
    await tester.ensureVisible(find.text('32 offers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('32 offers'));
    expect(offersOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an active request warns sellers before updating', (
    tester,
  ) async {
    var saved = false;
    await _pumpWidget(
      tester,
      width: 390,
      child: ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        onSaveRequest: () => saved = true,
        includeAppChrome: true,
      ),
    );

    final saveAction = find.text('Save changes').last;
    await tester.ensureVisible(saveAction);
    await tester.pumpAndSettle();
    await tester.tap(saveAction);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Your active sellers will be notified'),
      findsOneWidget,
    );
    final updateLabel = tester.widget<Text>(find.text('Update request'));
    expect(updateLabel.maxLines, 1);
    expect(updateLabel.softWrap, isFalse);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('approved-request-sheet-primary')))
          .height,
      inInclusiveRange(40, 44),
    );
    expect(saved, isFalse);
    await tester.tap(find.text('Update request'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'writes labelled approved request flow comparison sheet',
    (tester) async {
      final comparisons = <_Comparison>[];
      for (final state in _ProofState.values) {
        await _pumpState(tester, state: state, width: 390);
        final actual = await _capture(tester);
        final output = File(
          'assets/approved_request_flow/${state.name}-actual-390.png',
        );
        output.parent.createSync(recursive: true);
        await output.writeAsBytes(await _pngBytes(actual));
        comparisons.add(
          _Comparison(
            label: state.label,
            targetPath: state.targetPath,
            actual: actual,
          ),
        );
      }

      final contactSheet = await _contactSheet(comparisons);
      final output = File(
        'assets/approved_request_flow/request-flow-comparison-contact-sheet.png',
      );
      await output.writeAsBytes(await _pngBytes(contactSheet));

      expect(output.existsSync(), isTrue);
      expect(output.lengthSync(), greaterThan(1000));
    },
    skip: !_writeRequestFlowProof,
  );
}

enum _ProofState {
  product(
    'Product details',
    'approved resign/post-request-approved/4.2-post-new-request-products-approved.png',
  ),
  service(
    'Service details',
    'approved resign/post-request-approved/4.2.1-post-new-request-service-approved.png',
  ),
  location(
    'Service location',
    'approved resign/post-request-approved/4.2.2-post-new-request-location-approved.png',
  ),
  details(
    'Buyer request details',
    'approved resign/buyer-request-navigation-approved/4.3 Edit Request Details For Products-approved.png',
  );

  const _ProofState(this.label, this.targetPath);
  final String label;
  final String targetPath;
}

Future<void> _pumpState(
  WidgetTester tester, {
  required _ProofState state,
  required double width,
  double height = _proofHeight,
  double textScale = 1,
}) async {
  if (state == _ProofState.details) {
    await _pumpWidget(
      tester,
      width: width,
      height: height,
      textScale: textScale,
      child: ApprovedBuyerRequestDetailsPage(
        key: ValueKey('approved-request-${state.name}'),
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        includeAppChrome: true,
      ),
    );
    return;
  }

  await _pumpWidget(
    tester,
    width: width,
    height: height,
    textScale: textScale,
    child: ApprovedRequestFlowPage(
      key: ValueKey('approved-request-${state.name}'),
      accent: const Color(0xff1917ff),
      requestTitle: '',
      budget: '',
      onTitleChanged: (_) {},
      onBudgetChanged: (_) {},
      onBack: () {},
      onNotifications: () {},
      onSubmit: () {},
      initialKind: state == _ProofState.product
          ? ApprovedRequestKind.product
          : ApprovedRequestKind.service,
      includeAppChrome: true,
    ),
  );

  if (state == _ProofState.location) {
    final continueAction = find.text('Continue');
    await tester.ensureVisible(continueAction);
    await tester.pumpAndSettle();
    await tester.tap(continueAction);
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const Key('approved-request-scroll')),
      const Offset(0, 1600),
      2500,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpWidget(
  WidgetTester tester, {
  required double width,
  required Widget child,
  double height = _proofHeight,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: ObjectKey(child),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      builder: (context, appChild) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(
            key: _captureKey,
            child: appChild ?? const SizedBox.shrink(),
          ),
        );
      },
      home: child,
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'Request surface must build before interaction proof begins.',
  );
}

void _expectSameRow(WidgetTester tester, String left, String right) {
  final leftFinder = find.text(left).first;
  final rightFinder = find.text(right).first;
  final leftCenter = tester.getCenter(leftFinder);
  final rightCenter = tester.getCenter(rightFinder);
  final leftText = tester.widget<Text>(leftFinder);
  final rightText = tester.widget<Text>(rightFinder);
  final media = MediaQuery.of(tester.element(leftFinder));
  final leftSurface = _ancestorRect(tester, leftFinder, '_ApprovedSurface');
  final rightSurface = _ancestorRect(tester, rightFinder, '_ApprovedSurface');
  expect(
    (leftCenter.dy - rightCenter.dy).abs(),
    lessThan(3),
    reason:
        'Expected "$left" and "$right" to retain one approved row. '
        'Centers: ${leftCenter.dy}, ${rightCenter.dy}; '
        'font sizes: ${leftText.style?.fontSize}, ${rightText.style?.fontSize}; '
        'surfaces: $leftSurface, $rightSurface; '
        'media: ${media.size}, scale: ${media.textScaler.scale(1)}.',
  );
}

void _expectPairedSurfaces(
  WidgetTester tester,
  String leftLabel,
  String rightLabel,
) {
  final left = _ancestorRect(
    tester,
    find.text(leftLabel).first,
    '_ApprovedSurface',
  )!;
  final right = _ancestorRect(
    tester,
    find.text(rightLabel).first,
    '_ApprovedSurface',
  )!;
  expect(
    (left.top - right.top).abs(),
    lessThan(2),
    reason: '$leftLabel and $rightLabel must start on the same approved row.',
  );
  expect(
    right.left,
    greaterThan(left.right),
    reason: '$leftLabel and $rightLabel must remain side-by-side.',
  );
  expect(left.width, greaterThan(100));
  expect(right.width, greaterThan(100));
}

Rect? _ancestorRect(WidgetTester tester, Finder finder, String typeName) {
  Element? match;
  tester.element(finder).visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType.toString() == typeName) {
      match = ancestor;
      return false;
    }
    return true;
  });
  final renderBox = match?.renderObject as RenderBox?;
  return renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
}

void _expectSingleRenderedLine(WidgetTester tester, String value) {
  _expectRenderedLineCountAtMost(tester, value, 1);
}

void _expectRenderedLineCountAtMost(
  WidgetTester tester,
  String value,
  int maxLines,
) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(value).first,
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: value.length),
  );
  final lineTops = boxes.map((box) => box.top.round()).toSet();
  expect(
    lineTops.length,
    lessThanOrEqualTo(maxLines),
    reason: 'Expected "$value" to use no more than $maxLines lines.',
  );
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return boundary.toImage(pixelRatio: 1);
}

Future<List<int>> _pngBytes(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Comparison {
  const _Comparison({
    required this.label,
    required this.targetPath,
    required this.actual,
  });

  final String label;
  final String targetPath;
  final ui.Image actual;
}

Future<ui.Image> _contactSheet(List<_Comparison> comparisons) async {
  const columnWidth = 390.0;
  const gutter = 24.0;
  const labelHeight = 42.0;
  const rowHeight = _proofHeight + labelHeight + 24;
  const sheetWidth = columnWidth * 2 + gutter * 3;
  final sheetHeight = rowHeight * comparisons.length + gutter;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);

  _drawLabel(canvas, 'APPROVED TARGET', gutter, 8, columnWidth);
  _drawLabel(
    canvas,
    'FLUTTER IMPLEMENTATION',
    gutter * 2 + columnWidth,
    8,
    columnWidth,
  );

  for (var index = 0; index < comparisons.length; index++) {
    final comparison = comparisons[index];
    final rowTop = gutter + index * rowHeight;
    final target = await _decodeImage(File(comparison.targetPath));
    _drawLabel(
      canvas,
      comparison.label,
      gutter,
      rowTop + 16,
      sheetWidth - gutter * 2,
    );
    final imageTop = rowTop + labelHeight;
    _drawContainedImage(
      canvas,
      target,
      Rect.fromLTWH(gutter, imageTop, columnWidth, _proofHeight),
    );
    _drawContainedImage(
      canvas,
      comparison.actual,
      Rect.fromLTWH(
        gutter * 2 + columnWidth,
        imageTop,
        columnWidth,
        _proofHeight,
      ),
    );
  }

  final picture = recorder.endRecording();
  return picture.toImage(sheetWidth.ceil(), sheetHeight.ceil());
}

Future<ui.Image> _decodeImage(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  return frame.image;
}

void _drawContainedImage(Canvas canvas, ui.Image image, Rect bounds) {
  final scale = (bounds.width / image.width)
      .clamp(0, bounds.height / image.height)
      .toDouble();
  final width = image.width * scale;
  final height = image.height * scale;
  final destination = Rect.fromLTWH(
    bounds.left + (bounds.width - width) / 2,
    bounds.top,
    width,
    height,
  );
  canvas.drawRect(bounds, Paint()..color = const Color(0xfff3f4f8));
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    destination,
    Paint()..filterQuality = FilterQuality.high,
  );
}

void _drawLabel(
  Canvas canvas,
  String text,
  double left,
  double top,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xff10145b),
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  painter.paint(canvas, Offset(left, top));
}
