import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_codecs.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

import 'support/account_fakes.dart';

void main() {
  group('decodeMembershipRow', () {
    test('decodes the draft memberships wire shape', () {
      final membership = decodeMembershipRow(membershipRow());

      expect(membership.membershipId, syntheticMembershipId);
      expect(membership.userId, syntheticUserId);
      expect(membership.role, HocalistRole.buyer);
      expect(membership.status, MembershipStatus.active);
      expect(membership.stamp.revision, 1);
      expect(membership.stamp.createdAt.isUtc, isTrue);
    });

    test('decodes both roles for a dual-role identity', () {
      final buyer = decodeMembershipRow(membershipRow());
      final seller = decodeMembershipRow(
        membershipRow(
          id: syntheticSellerMembershipId,
          role: 'seller',
          status: 'restricted',
          revision: 4,
        ),
      );

      expect(buyer.userId, seller.userId);
      expect(buyer.membershipId, isNot(seller.membershipId));
      expect(seller.role, HocalistRole.seller);
      expect(seller.status, MembershipStatus.restricted);
      expect(seller.stamp.revision, 4);
    });

    test('rejects unknown enum values with a safe detail', () {
      expect(
        () => decodeMembershipRow(membershipRow(role: 'admin')),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.role',
          ),
        ),
      );
      expect(
        () => decodeMembershipRow(membershipRow(status: 'verified')),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.status',
          ),
        ),
      );
    });

    test('rejects malformed revisions and timestamps', () {
      for (final badRevision in <Object?>[0, -1, '1', 1.0, null]) {
        expect(
          () => decodeMembershipRow(membershipRow(revision: badRevision)),
          throwsA(
            isA<AccountDecodeException>().having(
              (error) => error.detail,
              'detail',
              'memberships.revision',
            ),
          ),
        );
      }
      expect(
        () => decodeMembershipRow(membershipRow(createdAt: 'not-a-date')),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.created_at',
          ),
        ),
      );
      expect(
        () => decodeMembershipRow(membershipRow(updatedAt: '2026-05-01')),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.updated_at',
          ),
        ),
      );
      expect(
        () => decodeMembershipRow(
          membershipRow(createdAt: '2026-02-30T00:00:00Z'),
        ),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.created_at',
          ),
        ),
      );
    });

    test('rejects missing required fields', () {
      final row = membershipRow();
      row.remove('user_id');
      expect(
        () => decodeMembershipRow(row),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'memberships.user_id',
          ),
        ),
      );
    });
  });

  group('decodeRoleProfileRow', () {
    test('decodes nullable fields without manufacturing values', () {
      final profile = decodeRoleProfileRow(
        roleProfileRow(profileNote: null, serviceRadiusMiles: null),
        role: HocalistRole.buyer,
        userId: syntheticUserId,
      );

      expect(profile.membershipId, syntheticMembershipId);
      expect(profile.displayName, 'Maya Chen');
      expect(profile.profileNote, isNull);
      expect(profile.serviceRadiusMiles, isNull);
      expect(profile.stamp.revision, 2);
    });

    test('decodes a seller radius and availability', () {
      final profile = decodeRoleProfileRow(
        roleProfileRow(serviceRadiusMiles: 15, pickupAvailability: 'Weekdays'),
        role: HocalistRole.seller,
        userId: syntheticUserId,
      );

      expect(profile.role, HocalistRole.seller);
      expect(profile.serviceRadiusMiles, 15);
      expect(profile.pickupAvailability, 'Weekdays');
    });

    test('rejects invalid values without echoing them', () {
      expect(
        () => decodeRoleProfileRow(
          roleProfileRow(displayName: '   '),
          role: HocalistRole.buyer,
          userId: syntheticUserId,
        ),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'role_profiles.display_name',
          ),
        ),
      );
      expect(
        () => decodeRoleProfileRow(
          roleProfileRow(areaLabel: 'x' * 201),
          role: HocalistRole.buyer,
          userId: syntheticUserId,
        ),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'role_profiles.field_value',
          ),
        ),
      );
      expect(
        () => decodeRoleProfileRow(
          roleProfileRow(serviceRadiusMiles: -1),
          role: HocalistRole.seller,
          userId: syntheticUserId,
        ),
        throwsA(isA<AccountDecodeException>()),
      );
    });
  });

  group('decodePrivateContactRow', () {
    test('keeps null components null and empty strings as values', () {
      final record = decodePrivateContactRow(
        contactRow(
          phone: '',
          addressLine2: null,
          city: null,
          region: null,
          postalCode: null,
          countryCode: null,
        ),
      );

      expect(record.userId, syntheticUserId);
      expect(record.contact.phone, '');
      expect(record.contact.addressLine2, isNull);
      expect(record.contact.city, isNull);
      expect(record.contact.countryCode, isNull);
      expect(record.stamp.revision, 3);
    });

    test('rejects an invalid country code without echoing it', () {
      try {
        decodePrivateContactRow(contactRow(countryCode: 'us'));
        fail('expected an AccountDecodeException');
      } on AccountDecodeException catch (error) {
        expect(error.detail, 'profile_contacts.field_value');
        expect(error.toString().contains('us'), isFalse);
      }
    });

    test('rejects malformed revision and missing user id', () {
      expect(
        () => decodePrivateContactRow(contactRow(revision: 0)),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'profile_contacts.revision',
          ),
        ),
      );
      final row = contactRow();
      row.remove('user_id');
      expect(
        () => decodePrivateContactRow(row),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'profile_contacts.user_id',
          ),
        ),
      );
    });
  });

  group('RPC result decoders', () {
    test('decode the minimal acknowledgement shapes', () {
      final onboard = decodeOnboardResult(<String, Object?>{
        'profile_id': syntheticMembershipId,
        'role': 'seller',
        'revision': 1,
      });
      expect(onboard.membershipId, syntheticMembershipId);
      expect(onboard.role, HocalistRole.seller);

      final profileUpdate = decodeRoleProfileUpdateResult(<String, Object?>{
        'profile_id': syntheticMembershipId,
        'revision': 2,
      });
      expect(profileUpdate.profileId, syntheticMembershipId);
      expect(profileUpdate.revision, 2);

      final contactUpdate = decodeContactUpdateResult(<String, Object?>{
        'revision': 4,
      });
      expect(contactUpdate.revision, 4);
    });

    test('reject malformed result payloads', () {
      expect(
        () => decodeOnboardResult(<String, Object?>{
          'profile_id': syntheticMembershipId,
          'role': 'admin',
          'revision': 1,
        }),
        throwsA(isA<AccountDecodeException>()),
      );
      expect(
        () => decodeContactUpdateResult(<String, Object?>{'revision': '2'}),
        throwsA(
          isA<AccountDecodeException>().having(
            (error) => error.detail,
            'detail',
            'account_command.contact_update.revision',
          ),
        ),
      );
      expect(
        () => decodeResultObject(<Object?>[], 'account_command.onboard'),
        throwsA(isA<AccountDecodeException>()),
      );
    });
  });

  group('decodeRowList', () {
    test('accepts an empty list and rejects non-list payloads', () {
      expect(decodeRowList(const <Object?>[], 'memberships.select'), isEmpty);
      expect(
        () => decodeRowList(<String, Object?>{}, 'memberships.select'),
        throwsA(isA<AccountDecodeException>()),
      );
      expect(
        () => decodeRowList(const <Object?>[42], 'memberships.select'),
        throwsA(isA<AccountDecodeException>()),
      );
    });
  });
}
