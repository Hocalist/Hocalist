import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_adapter.dart';
import 'package:hocalist/data/phase2/accounts/account_transport.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

import 'support/account_fakes.dart';

void main() {
  late FakeAccountTransport transport;
  late FakeAccountSession session;
  late AccountDataAdapter adapter;

  setUp(() {
    transport = FakeAccountTransport();
    session = FakeAccountSession(syntheticUserId);
    adapter = AccountDataAdapter(transport: transport, session: session);
  });

  group('session boundary', () {
    test('a signed-out session fails before any transport call', () async {
      session.currentUserId = null;

      final memberships = await adapter.fetchMemberships();
      final membership = await adapter.fetchMembership(
        role: HocalistRole.buyer,
      );
      final profile = await adapter.fetchRoleProfile(role: HocalistRole.buyer);
      final contact = await adapter.fetchPrivateContact();
      final onboard = await adapter.onboard(
        OnboardCommand(
          role: HocalistRole.buyer,
          displayName: 'Maya Chen',
          idempotencyKey: 'k1',
        ),
      );
      final profileUpdate = await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 1,
          displayName: 'Maya Chen',
          idempotencyKey: 'k2',
        ),
      );
      final contactUpdate = await adapter.updateContact(
        UpdateContactCommand(expectedRevision: 1, idempotencyKey: 'k3'),
      );

      for (final result in [
        memberships,
        membership,
        profile,
        contact,
        onboard,
        profileUpdate,
        contactUpdate,
      ]) {
        expect(result.errorOrNull, isA<PermissionDeniedError>());
        expect(
          (result.errorOrNull! as PermissionDeniedError).action,
          'authenticate',
        );
      }
      expect(transport.selectCallCount, 0);
      expect(transport.commandCallCount, 0);
    });
  });

  group('membership reads', () {
    test('selects by session user id and returns both roles sorted', () async {
      transport.onSelect = (query) => rowsResponse([
        membershipRow(
          id: syntheticSellerMembershipId,
          role: 'seller',
          revision: 2,
        ),
        membershipRow(),
      ]);

      final result = await adapter.fetchMemberships();

      final query = transport.selectQueries.single;
      expect(query.schema, 'hocalist');
      expect(query.table, 'memberships');
      expect(query.columns, AccountDataAdapter.membershipColumns);
      expect(query.filters.single.column, 'user_id');
      expect(query.filters.single.value, syntheticUserId);
      expect(query.orderBy, ['role']);

      final memberships = result.valueOrNull!;
      expect(memberships.length, 2);
      expect(memberships.first.role, HocalistRole.buyer);
      expect(memberships.last.role, HocalistRole.seller);
    });

    test('duplicate membership ids or roles are malformed', () async {
      transport.onSelect = (query) =>
          rowsResponse([membershipRow(), membershipRow(revision: 2)]);
      final duplicateId = await adapter.fetchMemberships();
      expect(
        (duplicateId.errorOrNull! as MalformedResponseError).detail,
        'memberships.duplicate_rows',
      );

      transport.onSelect = (query) => rowsResponse([
        membershipRow(),
        membershipRow(id: syntheticSellerMembershipId),
      ]);
      final duplicateRole = await adapter.fetchMemberships();
      expect(
        (duplicateRole.errorOrNull! as MalformedResponseError).detail,
        'memberships.duplicate_rows',
      );
    });

    test('a session change during the request discards the result', () async {
      transport.onSelect = (query) {
        session.currentUserId = syntheticOtherUserId;
        return rowsResponse([membershipRow()]);
      };

      final result = await adapter.fetchMemberships();

      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
      expect(result.valueOrNull, isNull);
    });

    test('a logout before dispatch is rejected without a request', () async {
      session.currentUserId = null;

      final result = await adapter.fetchMemberships();

      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'authenticate',
      );
      expect(transport.selectCallCount, 0);
    });

    test('an empty membership read is a successful empty list', () async {
      final result = await adapter.fetchMemberships();

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('a cross-identity row fails safely without leaking ids', () async {
      const foreignId = 'SENTINEL-FOREIGN-USER';
      transport.onSelect = (query) =>
          rowsResponse([membershipRow(userId: foreignId)]);

      final result = await adapter.fetchMemberships();

      final error = result.errorOrNull;
      expect(error, isA<MalformedResponseError>());
      expect(
        (error! as MalformedResponseError).detail,
        'memberships.user_id_mismatch',
      );
      expect(error.toString().contains(foreignId), isFalse);
    });

    test('one role read returns not-found when the row is hidden', () async {
      final result = await adapter.fetchMembership(role: HocalistRole.seller);

      expect(result.errorOrNull, isA<NotFoundError>());
      expect((result.errorOrNull! as NotFoundError).entityType, 'membership');
      final query = transport.selectQueries.single;
      expect(query.filters.map((filter) => filter.column), ['user_id', 'role']);
    });

    test('multiple rows for one role are malformed, never first-row', () async {
      transport.onSelect = (query) =>
          rowsResponse([membershipRow(), membershipRow(revision: 2)]);

      final result = await adapter.fetchMembership(role: HocalistRole.buyer);

      expect(result.errorOrNull, isA<MalformedResponseError>());
      expect(
        (result.errorOrNull! as MalformedResponseError).detail,
        'memberships.multiple_rows',
      );
    });

    test('a role mismatch in the response is malformed', () async {
      transport.onSelect = (query) => rowsResponse([membershipRow()]);

      final result = await adapter.fetchMembership(role: HocalistRole.seller);

      expect(
        (result.errorOrNull! as MalformedResponseError).detail,
        'memberships.identity_mismatch',
      );
    });
  });

  group('role-profile read', () {
    test(
      'resolves the membership first and filters by membership id',
      () async {
        transport.onSelect = (query) {
          if (query.table == 'memberships') {
            return rowsResponse([membershipRow()]);
          }
          return rowsResponse([
            roleProfileRow(
              serviceRadiusMiles: 15,
              pickupAvailability: 'Weekdays',
            ),
          ]);
        };

        final result = await adapter.fetchRoleProfile(role: HocalistRole.buyer);

        final profile = result.valueOrNull!;
        expect(profile.membershipId, syntheticMembershipId);
        expect(profile.userId, syntheticUserId);
        expect(profile.displayName, 'Maya Chen');

        final profileQuery = transport.selectQueries.last;
        expect(profileQuery.table, 'role_profiles');
        expect(profileQuery.filters.single.column, 'membership_id');
        expect(profileQuery.filters.single.value, syntheticMembershipId);
      },
    );

    test('a hidden profile is not-found, not fabricated data', () async {
      transport.onSelect = (query) => query.table == 'memberships'
          ? rowsResponse([membershipRow(status: 'pending')])
          : rowsResponse(const []);

      final result = await adapter.fetchRoleProfile(role: HocalistRole.buyer);

      expect(result.errorOrNull, isA<NotFoundError>());
      expect((result.errorOrNull! as NotFoundError).entityType, 'role_profile');
    });

    test('a profile from another membership is malformed', () async {
      transport.onSelect = (query) => query.table == 'memberships'
          ? rowsResponse([membershipRow()])
          : rowsResponse([
              roleProfileRow(membershipId: syntheticSellerMembershipId),
            ]);

      final result = await adapter.fetchRoleProfile(role: HocalistRole.buyer);

      expect(
        (result.errorOrNull! as MalformedResponseError).detail,
        'role_profiles.membership_mismatch',
      );
    });

    test(
      'an unknown membership enum fails as malformed, not an error leak',
      () async {
        transport.onSelect = (query) =>
            rowsResponse([membershipRow(status: 'verified')]);

        final result = await adapter.fetchRoleProfile(role: HocalistRole.buyer);

        expect(result.errorOrNull, isA<MalformedResponseError>());
        expect(
          (result.errorOrNull! as MalformedResponseError).detail,
          'memberships.status',
        );
      },
    );
  });

  group('private contact read', () {
    test('selects the session identity and keeps null components', () async {
      transport.onSelect = (query) => rowsResponse([
        contactRow(
          addressLine2: null,
          city: null,
          countryCode: null,
          revision: 5,
        ),
      ]);

      final result = await adapter.fetchPrivateContact();

      final query = transport.selectQueries.single;
      expect(query.table, 'profile_contacts');
      expect(query.filters.single.column, 'user_id');
      expect(query.filters.single.value, syntheticUserId);

      final record = result.valueOrNull!;
      expect(record.userId, syntheticUserId);
      expect(record.contact.addressLine2, isNull);
      expect(record.contact.countryCode, isNull);
      expect(record.stamp.revision, 5);
    });

    test('an empty contact read is not-found', () async {
      final result = await adapter.fetchPrivateContact();

      expect(result.errorOrNull, isA<NotFoundError>());
      expect(
        (result.errorOrNull! as NotFoundError).entityType,
        'private_contact',
      );
    });

    test('a cross-identity contact fails without leaking values', () async {
      const sentinelPhone = 'SENTINEL-PHONE-999';
      transport.onSelect = (query) => rowsResponse([
        contactRow(userId: 'SENTINEL-FOREIGN-USER', phone: sentinelPhone),
      ]);

      final result = await adapter.fetchPrivateContact();

      final error = result.errorOrNull!;
      expect(error, isA<MalformedResponseError>());
      expect(
        (error as MalformedResponseError).detail,
        'profile_contacts.identity_mismatch',
      );
      expect(error.toString().contains(sentinelPhone), isFalse);
      expect(error.toString().contains('SENTINEL-FOREIGN-USER'), isFalse);
    });
  });

  group('onboard command', () {
    test('sends the reviewed RPC parameter shape', () async {
      transport.onCommand = (command) => resultResponse({
        'profile_id': syntheticMembershipId,
        'role': 'buyer',
        'revision': 1,
      });

      final result = await adapter.onboard(
        OnboardCommand(
          role: HocalistRole.buyer,
          displayName: '  Maya Chen  ',
          idempotencyKey: 'onboard-1',
        ),
      );

      final command = transport.commands.single;
      expect(command.schema, 'hocalist');
      expect(command.function, 'account_command');
      expect(command.operation, 'onboard');
      expect(command.key, 'onboard-1');
      expect(command.input, {'role': 'buyer', 'display_name': 'Maya Chen'});

      final onboard = result.valueOrNull!;
      expect(onboard.membershipId, syntheticMembershipId);
      expect(onboard.role, HocalistRole.buyer);
    });

    test('a mismatched role in the response is malformed', () async {
      transport.onCommand = (command) => resultResponse({
        'profile_id': syntheticMembershipId,
        'role': 'seller',
        'revision': 1,
      });

      final result = await adapter.onboard(
        OnboardCommand(
          role: HocalistRole.buyer,
          displayName: 'Maya Chen',
          idempotencyKey: 'onboard-2',
        ),
      );

      expect(
        (result.errorOrNull! as MalformedResponseError).detail,
        'account_command.onboard.role_mismatch',
      );
    });
  });

  group('profile.update command', () {
    test('encodes keep, set and clear patches independently', () async {
      transport.onCommand = (command) =>
          resultResponse({'profile_id': syntheticMembershipId, 'revision': 3});

      final result = await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 2,
          displayName: 'Maya Chen',
          areaLabel: const PatchSet<String>('Yonkers, NY'),
          profileNote: const PatchClear<String>(),
          idempotencyKey: 'profile-1',
        ),
      );

      final command = transport.commands.single;
      expect(command.operation, 'profile.update');
      expect(command.key, 'profile-1');
      expect(command.input.keys.toSet(), {
        'profile_id',
        'expected_revision',
        'display_name',
        'area_label',
        'profile_note',
      });
      expect(command.input['profile_id'], syntheticMembershipId);
      expect(command.input['expected_revision'], 2);
      expect(command.input['display_name'], 'Maya Chen');
      expect(command.input['area_label'], 'Yonkers, NY');
      expect(command.input['profile_note'], isNull);
      expect(result.valueOrNull?.revision, 3);
    });

    test('a profile id mismatch in the response is malformed', () async {
      transport.onCommand = (command) => resultResponse({
        'profile_id': syntheticSellerMembershipId,
        'revision': 3,
      });

      final result = await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 2,
          displayName: 'Maya Chen',
          idempotencyKey: 'profile-2',
        ),
      );

      expect(
        (result.errorOrNull! as MalformedResponseError).detail,
        'account_command.profile_update.profile_mismatch',
      );
    });

    test('a malformed result is distinguishable from connectivity', () async {
      transport.onCommand = (command) =>
          const AccountTransportData(<String, Object?>{'revision': 3});

      final malformed = await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 2,
          displayName: 'Maya Chen',
          idempotencyKey: 'profile-3',
        ),
      );
      expect(
        malformed.errorOrNull!.kind,
        RepositoryFailureKind.malformedResponse,
      );

      transport.onCommand = (command) => const AccountTransportError(
        kind: AccountTransportErrorKind.connectivity,
        retryable: true,
      );
      final offline = await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 2,
          displayName: 'Maya Chen',
          idempotencyKey: 'profile-4',
        ),
      );
      expect(offline.errorOrNull!.kind, RepositoryFailureKind.network);
    });
  });

  group('contact.update command', () {
    test('sends only patched keys with explicit nulls for clears', () async {
      transport.onCommand = (command) =>
          resultResponse(<String, Object?>{'revision': 4});

      final result = await adapter.updateContact(
        UpdateContactCommand(
          expectedRevision: 3,
          phone: const PatchClear<String>(),
          city: const PatchSet<String>('New Rochelle'),
          idempotencyKey: 'contact-1',
        ),
      );

      final command = transport.commands.single;
      expect(command.operation, 'contact.update');
      expect(command.input, {
        'expected_revision': 3,
        'phone': null,
        'city': 'New Rochelle',
      });
      expect(result.valueOrNull?.revision, 4);
    });
  });

  group('retries', () {
    test('a manual retry reuses the same idempotency key', () async {
      var attempts = 0;
      transport.onCommand = (command) {
        attempts += 1;
        if (attempts == 1) {
          // The mutation may have committed; the response was lost.
          return const AccountTransportError(
            kind: AccountTransportErrorKind.connectivity,
            retryable: true,
          );
        }
        return resultResponse(<String, Object?>{'revision': 4});
      };

      final command = UpdateContactCommand(
        expectedRevision: 3,
        city: const PatchSet<String>('New Rochelle'),
        idempotencyKey: 'retry-key-1',
      );

      final first = await adapter.updateContact(command);
      expect(first.errorOrNull, isA<NetworkError>());

      final second = await adapter.updateContact(command);
      expect(second.valueOrNull?.revision, 4);

      expect(transport.commandCallCount, 2);
      expect(transport.commands[0].key, 'retry-key-1');
      expect(transport.commands[1].key, 'retry-key-1');
      expect(transport.commands[0].input, transport.commands[1].input);
    });

    test('the adapter never retries a mutation by itself', () async {
      transport.onCommand = (command) => const AccountTransportError(
        kind: AccountTransportErrorKind.connectivity,
        retryable: true,
      );

      await adapter.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: syntheticMembershipId,
          expectedRevision: 2,
          displayName: 'Maya Chen',
          idempotencyKey: 'no-auto-retry',
        ),
      );

      expect(transport.commandCallCount, 1);
    });
  });
}
