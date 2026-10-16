import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/main.dart' show BuyerProfileEditPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/patch.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/profile_details_editor.dart';
import 'account_test_fakes.dart';
import '../../test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('buyer has one save for display name and nested profile note', (
    tester,
  ) async {
    var name = 'Original buyer';
    UpdateRoleProfileCommand? saved;
    final base = roleProfile(role: HocalistRole.buyer, revision: 9);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuyerProfileEditPage(
              name: name,
              onNameChanged: (value) => name = value,
              onDone: () => throw StateError('Duplicate name-only save'),
              profileDetailsEditor: ProfileDetailsEditor(
                readCurrent: () => base,
                readDisplayName: () => name,
                onSave: (command) async => saved = command,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save profile'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Updated buyer');
    final note = find.byKey(const Key('profileDetailsField1'));
    await tester.ensureVisible(note);
    await tester.enterText(note, 'Meet in a public place');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('profileDetailsSave'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.displayName, 'Updated buyer');
    expect(saved!.expectedRevision, 9);
    expect(
      (saved!.profileNote as PatchSet<String>).value,
      'Meet in a public place',
    );
  });
  testWidgets('Seller info has one save for name and profile details', (
    tester,
  ) async {
    var name = 'Original seller';
    var saves = 0;
    UpdateRoleProfileCommand? saved;
    final base = roleProfile(
      role: HocalistRole.seller,
      revision: 7,
      areaLabel: 'Old area',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerEditProfilePage(
              name: name,
              email: 'seller@example.com',
              onNameChanged: (v) => name = v,
              onBack: () {},
              onDone: () => throw StateError('Duplicate save'),
              profileDetailsEditor: ProfileDetailsEditor(
                readCurrent: () => base,
                readDisplayName: () => name,
                onSave: (command) async {
                  saved = command;
                  saves++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Save profile details'), findsNothing);
    expect(find.byKey(const Key('sellerSaveProfile')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Updated seller');
    await tester.ensureVisible(
      find
          .descendant(
            of: find.byType(ProfileDetailsEditor),
            matching: find.byKey(const Key('profileDetailsField0')),
          )
          .first,
    );
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ProfileDetailsEditor),
            matching: find.byKey(const Key('profileDetailsField0')),
          )
          .first,
      'New area',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const Key('profileDetailsSave'));
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(saved!.displayName, 'Updated seller');
    expect(saved!.expectedRevision, 7);
    expect((saved!.areaLabel as PatchSet<String>).value, 'New area');
  });
  testWidgets('seller details preserve revision and retry exact command', (
    tester,
  ) async {
    final commands = <UpdateRoleProfileCommand>[];
    final base = roleProfile(
      role: HocalistRole.seller,
      revision: 7,
      areaLabel: 'Old area',
      profileNote: 'Old note',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileDetailsEditor(
              readCurrent: () => base,
              onSave: (command) async {
                commands.add(command);
                if (commands.length == 1) throw StateError('lost response');
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('profileDetailsField0')),
      'New area',
    );
    await tester.enterText(find.byKey(const Key('profileDetailsField1')), '');
    await tester.enterText(find.byKey(const Key('profileDetailsField3')), '25');
    await tester.ensureVisible(find.text('Save profile details'));
    await tester.tap(find.text('Save profile details'));
    await tester.pumpAndSettle();
    expect(find.text('Profile details saved.'), findsNothing);
    await tester.ensureVisible(find.text('Retry profile save'));
    await tester.tap(find.text('Retry profile save'));
    await tester.pumpAndSettle();
    expect(commands, hasLength(2));
    expect(identical(commands[0], commands[1]), isTrue);
    expect(commands[0].expectedRevision, 7);
    expect((commands[0].areaLabel as PatchSet<String>).value, 'New area');
    expect(commands[0].profileNote, isA<PatchClear<String>>());
    expect((commands[0].serviceRadiusMiles as PatchSet<int>).value, 25);
    expect(find.text('Profile details saved.'), findsOneWidget);
  });
  testWidgets('buyer cannot submit seller-only fields', (tester) async {
    UpdateRoleProfileCommand? command;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileDetailsEditor(
              readCurrent: () => roleProfile(),
              onSave: (value) async {
                command = value;
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('Service radius (miles)'), findsNothing);
    await tester.ensureVisible(find.text('Save profile details'));
    await tester.tap(find.text('Save profile details'));
    await tester.pumpAndSettle();
    expect(command!.serviceRadiusMiles, isA<PatchKeep<int>>());
    expect(command!.pickupAvailability, isA<PatchKeep<String>>());
  });
  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('profile details fit $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ProfileDetailsEditor(
                    readCurrent: () => roleProfile(role: HocalistRole.seller),
                    onSave: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
