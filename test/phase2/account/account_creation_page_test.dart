// Widget tests for the approved account creation form in real mode.
// Prototype callback behavior must stay unchanged.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('local email link uses typed identity without a password', (
    tester,
  ) async {
    String? sentEmail;
    String? sentName;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async {},
          onRealEmailLink: (email, name) async {
            sentEmail = email;
            sentName = name;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-name-field')),
      'Buyer Test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'buyer@example.invalid',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-email-link')),
    );
    await tester.pumpAndSettle();
    expect(sentEmail, 'buyer@example.invalid');
    expect(sentName, 'Buyer Test');
    expect(find.text('Check your email for a sign-in link.'), findsOneWidget);
  });

  testWidgets('prototype mode keeps callback behavior without validation', (
    tester,
  ) async {
    var signupCalls = 0;
    var loginCalls = 0;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () => signupCalls += 1,
          onLogin: () => loginCalls += 1,
        ),
      ),
    );

    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pump();
    expect(signupCalls, 1);
    expect(find.byKey(const ValueKey('approved-account-error')), findsNothing);

    await tapVisible(tester, find.text('Log in'));
    await tester.pump();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pump();
    expect(loginCalls, 1);
  });

  testWidgets('real submit validates and sends the typed values', (
    tester,
  ) async {
    ApprovedAccountSubmission? captured;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.seller,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (submission) async => captured = submission,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('approved-account-name-field')),
      'Northside Tech',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'seller@example.invalid',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-confirm-password-field')),
      'secret123',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.role, ApprovedAccountRole.seller);
    expect(captured!.loginMode, isFalse);
    expect(captured!.name, 'Northside Tech');
    expect(captured!.email, 'seller@example.invalid');
    expect(captured!.password, 'secret123');
  });

  testWidgets('invalid email is rejected without calling the handler', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async => calls += 1,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('approved-account-name-field')),
      'Buyer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-confirm-password-field')),
      'secret123',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('password mismatch is rejected', (tester) async {
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('approved-account-name-field')),
      'Buyer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'buyer@example.invalid',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-confirm-password-field')),
      'different',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('handler failures show their safe actionable message', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async => throw const AccountActionException(
            'invalid_credentials',
            'Email or password is not correct.',
          ),
        ),
      ),
    );

    await tapVisible(tester, find.text('Log in'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'buyer@example.invalid',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'secret123',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email or password is not correct.'), findsOneWidget);
  });

  testWidgets('duplicate submit is blocked while a request is in flight', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) {
            calls += 1;
            return pending.future;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('approved-account-name-field')),
      'Buyer',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'buyer@example.invalid',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-confirm-password-field')),
      'secret123',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-primary-action')),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('approved-account-primary-action')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, 1);

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('phone signup requests a code, shows cooldown and verifies', (
    tester,
  ) async {
    String? requestedPhone;
    bool? requestedSignup;
    String? confirmedCode;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async {},
          onPhoneRequestCode: (phone, {required signup}) async {
            requestedPhone = phone;
            requestedSignup = signup;
          },
          onPhoneConfirmCode: (phone, code) async => confirmedCode = code,
        ),
      ),
    );

    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-phone-action')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('approved-account-email-field')),
      ),
      findsNothing,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('approved-account-name-field')),
      ),
      'Phone Buyer',
    );

    await tester.enterText(
      find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const ValueKey('approved-account-phone-field'))),
      '+14155550123',
    );
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('approved-account-primary-action')),
      ),
    );
    await tester.pump();

    expect(requestedPhone, '+14155550123');
    expect(requestedSignup, isTrue);
    expect(
      find.byKey(const ValueKey('approved-account-code-field')),
      findsOneWidget,
    );
    expect(find.text('Resend code (30s)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('approved-account-code-field')),
      '123456',
    );
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('approved-account-primary-action')),
      ),
    );
    await tester.pump();
    expect(confirmedCode, '123456');

    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('approved-account-email-field')),
      findsOneWidget,
    );

    // Dispose the tree so the cooldown timer is cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone login requests a code without creating a user', (
    tester,
  ) async {
    bool? requestedSignup;
    await tester.pumpWidget(
      host(
        ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          name: '',
          onNameChanged: (_) {},
          onRoleChanged: (_) {},
          onSignup: () {},
          onLogin: () {},
          onRealSubmit: (_) async {},
          onPhoneRequestCode: (phone, {required signup}) async {
            requestedSignup = signup;
          },
          onPhoneConfirmCode: (phone, code) async {},
        ),
      ),
    );

    await tapVisible(tester, find.text('Log in'));
    await tester.pump();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('approved-account-phone-action')),
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const ValueKey('approved-account-phone-field'))),
      '+14155550123',
    );
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('approved-account-primary-action')),
      ),
    );
    await tester.pump();

    expect(requestedSignup, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
