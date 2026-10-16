import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 2,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
  );

  group('AccountRoleProfile', () {
    test('carries only draft role-profile fields', () {
      final profile = AccountRoleProfile(
        membershipId: 'member-1',
        userId: 'auth-1',
        role: HocalistRole.seller,
        displayName: 'Northside Tech',
        areaLabel: 'Chicago north side',
        profileNote: 'Public pickup preferred.',
        preferredMeetupType: null,
        serviceRadiusMiles: 15,
        pickupAvailability: 'Weekdays',
        stamp: stamp,
      );

      expect(profile.membershipId, 'member-1');
      expect(profile.userId, 'auth-1');
      expect(profile.role, HocalistRole.seller);
      expect(profile.areaLabel, 'Chicago north side');
      expect(profile.serviceRadiusMiles, 15);
      expect(profile.stamp.revision, 2);
    });

    test('rejects invalid display names, lengths and radius', () {
      expect(
        () => AccountRoleProfile(
          membershipId: 'member-1',
          userId: 'auth-1',
          role: HocalistRole.buyer,
          displayName: '   ',
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRoleProfile(
          membershipId: 'member-1',
          userId: 'auth-1',
          role: HocalistRole.buyer,
          displayName: 'x' * 201,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRoleProfile(
          membershipId: 'member-1',
          userId: 'auth-1',
          role: HocalistRole.seller,
          displayName: 'Northside Tech',
          areaLabel: 'x' * 201,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRoleProfile(
          membershipId: 'member-1',
          userId: 'auth-1',
          role: HocalistRole.seller,
          displayName: 'Northside Tech',
          serviceRadiusMiles: -1,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => AccountRoleProfile(
          membershipId: 'member-1',
          userId: 'auth-1',
          role: HocalistRole.seller,
          displayName: 'Northside Tech',
          serviceRadiusMiles: 100000000,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });
  });

  group('OnboardCommand and result', () {
    test('trims the display name and requires a key', () {
      final command = OnboardCommand(
        role: HocalistRole.buyer,
        displayName: '  Maya Chen  ',
        idempotencyKey: 'onboard-1',
      );

      expect(command.role, HocalistRole.buyer);
      expect(command.displayName, 'Maya Chen');
      expect(command.idempotencyKey, 'onboard-1');
      expect(
        () => OnboardCommand(
          role: HocalistRole.buyer,
          displayName: '   ',
          idempotencyKey: 'onboard-2',
        ),
        throwsArgumentError,
      );
      expect(
        () => OnboardCommand(
          role: HocalistRole.buyer,
          displayName: 'Maya',
          idempotencyKey: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('result requires a membership id and positive revision', () {
      final result = OnboardResult(
        membershipId: 'member-1',
        role: HocalistRole.seller,
        revision: 1,
      );

      expect(result.membershipId, 'member-1');
      expect(result.role, HocalistRole.seller);
      expect(
        () => OnboardResult(
          membershipId: '',
          role: HocalistRole.seller,
          revision: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => OnboardResult(
          membershipId: 'member-1',
          role: HocalistRole.seller,
          revision: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('UpdateRoleProfileCommand patch semantics', () {
    test('keeps optional fields unless patched', () {
      final command = UpdateRoleProfileCommand(
        profileId: 'member-1',
        expectedRevision: 2,
        displayName: '  Maya Chen  ',
        idempotencyKey: 'profile-1',
      );

      expect(command.displayName, 'Maya Chen');
      expect(command.areaLabel.isKeep, isTrue);
      expect(command.profileNote.isKeep, isTrue);
      expect(command.preferredMeetupType.isKeep, isTrue);
      expect(command.serviceRadiusMiles.isKeep, isTrue);
      expect(command.pickupAvailability.isKeep, isTrue);
    });

    test('supports independent set and clear patches', () {
      final command = UpdateRoleProfileCommand(
        profileId: 'member-1',
        expectedRevision: 2,
        displayName: 'Maya Chen',
        areaLabel: const PatchSet<String>('Yonkers, NY'),
        profileNote: const PatchClear<String>(),
        serviceRadiusMiles: const PatchSet<int>(0),
        idempotencyKey: 'profile-2',
      );

      expect(command.areaLabel.valueOrNull, 'Yonkers, NY');
      expect(command.profileNote.isClear, isTrue);
      expect(command.serviceRadiusMiles.valueOrNull, 0);
      expect(command.preferredMeetupType.isKeep, isTrue);
    });

    test('rejects invalid set values and required fields', () {
      expect(
        () => UpdateRoleProfileCommand(
          profileId: 'member-1',
          expectedRevision: 2,
          displayName: 'Maya Chen',
          areaLabel: PatchSet<String>('x' * 201),
          idempotencyKey: 'profile-3',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateRoleProfileCommand(
          profileId: 'member-1',
          expectedRevision: 2,
          displayName: 'Maya Chen',
          profileNote: PatchSet<String>('x' * 2001),
          idempotencyKey: 'profile-4',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateRoleProfileCommand(
          profileId: 'member-1',
          expectedRevision: 2,
          displayName: 'Maya Chen',
          serviceRadiusMiles: const PatchSet<int>(100000000),
          idempotencyKey: 'profile-5',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateRoleProfileCommand(
          profileId: 'member-1',
          expectedRevision: 0,
          displayName: 'Maya Chen',
          idempotencyKey: 'profile-6',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateRoleProfileCommand(
          profileId: 'member-1',
          expectedRevision: 2,
          displayName: '   ',
          idempotencyKey: 'profile-7',
        ),
        throwsArgumentError,
      );
    });
  });

  group('RoleProfileUpdateResult', () {
    test('requires a profile id and positive revision', () {
      final result = RoleProfileUpdateResult(
        profileId: 'member-1',
        revision: 3,
      );

      expect(result.profileId, 'member-1');
      expect(result.revision, 3);
      expect(
        () => RoleProfileUpdateResult(profileId: '', revision: 3),
        throwsArgumentError,
      );
      expect(
        () => RoleProfileUpdateResult(profileId: 'member-1', revision: 0),
        throwsArgumentError,
      );
    });
  });
}
