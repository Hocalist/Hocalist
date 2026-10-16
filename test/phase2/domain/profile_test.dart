import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 4,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
  );

  group('BuyerProfile', () {
    final profile = BuyerProfile(
      id: 'buyer-1',
      userId: 'auth-1',
      displayName: 'Maya Chen',
      profilePhotoMediaId: 'media-avatar',
      homeAreaLabel: 'Yonkers, NY',
      preferredMeetupType: 'Public safe-meet location',
      profileNote: 'Weekday evenings',
      contact: const PrivateContactDetails(
        email: 'maya.chen@example.com',
        phone: '(914) 555-0182',
        address: PostalAddress(
          line1: '123 Main Street',
          city: 'Yonkers',
          state: 'NY',
          postalCode: '10701',
          country: 'United States',
        ),
      ),
      stamp: stamp,
    );

    test('immutable copyWith preserves every untouched field', () {
      final updated = profile.copyWith(displayName: 'Maya R. Chen');

      expect(updated.displayName, 'Maya R. Chen');
      expect(updated.id, profile.id);
      expect(updated.userId, profile.userId);
      expect(updated.profilePhotoMediaId, profile.profilePhotoMediaId);
      expect(updated.homeAreaLabel, profile.homeAreaLabel);
      expect(updated.preferredMeetupType, profile.preferredMeetupType);
      expect(updated.profileNote, profile.profileNote);
      expect(updated.contact, profile.contact);
      expect(updated.stamp, profile.stamp);
      expect(profile.displayName, 'Maya Chen');
    });

    test('public projection carries no private contact values', () {
      final projection = profile.toPublicProjection();

      expect(projection.profileId, 'buyer-1');
      expect(projection.displayName, 'Maya Chen');
      expect(projection.areaLabel, 'Yonkers, NY');
      expect(projection.role, HocalistRole.buyer);

      final rendered = projection.toString();
      expect(rendered.contains('maya.chen@example.com'), isFalse);
      expect(rendered.contains('555-0182'), isFalse);
      expect(rendered.contains('123 Main Street'), isFalse);
    });

    test('rejects blank identity fields', () {
      expect(
        () => BuyerProfile(
          id: ' ',
          userId: 'auth-1',
          displayName: 'Maya Chen',
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => BuyerProfile(
          id: 'buyer-1',
          userId: 'auth-1',
          displayName: '',
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('clearing the profile photo drops only that value', () {
      final cleared = profile.copyWith(clearProfilePhoto: true);

      expect(cleared.profilePhotoMediaId, isNull);
      expect(cleared.contact, profile.contact);
      expect(cleared.stamp, profile.stamp);
    });

    test('rejects a blank profile photo id', () {
      expect(
        () => BuyerProfile(
          id: 'buyer-1',
          userId: 'auth-1',
          displayName: 'Maya Chen',
          profilePhotoMediaId: ' ',
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('rejects contradictory photo set and clear inputs', () {
      expect(
        () => profile.copyWith(
          profilePhotoMediaId: 'media-new',
          clearProfilePhoto: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SellerProfile', () {
    final profile = SellerProfile(
      id: 'seller-1',
      userId: 'auth-2',
      displayName: 'Northside Tech',
      categoryLabels: const ['Electronics', 'Tablets'],
      serviceAreaLabel: 'Chicago north side',
      serviceRadiusMiles: 15,
      pickupAvailability: 'Weekdays and Saturday afternoon',
      profileNote: 'Public pickup preferred.',
      stamp: stamp,
    );

    test('public projection includes public seller details only', () {
      final projection = profile.toPublicProjection();

      expect(projection.role, HocalistRole.seller);
      expect(projection.areaLabel, 'Chicago north side');
      expect(projection.categoryLabels, ['Electronics', 'Tablets']);
      expect(projection.serviceRadiusMiles, 15);
      expect(projection.pickupAvailability, 'Weekdays and Saturday afternoon');
      expect(projection.bio, 'Public pickup preferred.');
    });

    test('rejects a negative service radius', () {
      expect(
        () => SellerProfile(
          id: 'seller-1',
          userId: 'auth-2',
          displayName: 'Northside Tech',
          serviceRadiusMiles: -1,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a blank profile photo id and contradictory clear', () {
      expect(
        () => SellerProfile(
          id: 'seller-1',
          userId: 'auth-2',
          displayName: 'Northside Tech',
          profilePhotoMediaId: '',
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => profile.copyWith(
          profilePhotoMediaId: 'media-new',
          clearProfilePhoto: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Membership and privileges', () {
    test('membership links an auth identity to one Hocalist role', () {
      final membership = MembershipRecord(
        membershipId: 'member-1',
        userId: 'auth-1',
        role: HocalistRole.buyer,
        status: MembershipStatus.active,
        stamp: stamp,
      );

      expect(membership.membershipId, 'member-1');
      expect(membership.userId, 'auth-1');
      expect(membership.role, HocalistRole.buyer);
      expect(membership.stamp.revision, stamp.revision);
      expect(
        () => MembershipRecord(
          membershipId: 'member-1',
          userId: '',
          role: HocalistRole.buyer,
          status: MembershipStatus.active,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => MembershipRecord(
          membershipId: '',
          userId: 'auth-1',
          role: HocalistRole.buyer,
          status: MembershipStatus.active,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('one identity can hold buyer and seller memberships separately', () {
      final buyer = MembershipRecord(
        membershipId: 'member-buyer',
        userId: 'auth-1',
        role: HocalistRole.buyer,
        status: MembershipStatus.active,
        stamp: stamp,
      );
      final seller = MembershipRecord(
        membershipId: 'member-seller',
        userId: 'auth-1',
        role: HocalistRole.seller,
        status: MembershipStatus.restricted,
        stamp: stamp,
      );

      expect(buyer.userId, seller.userId);
      expect(buyer.membershipId, isNot(seller.membershipId));
      expect(buyer.role, HocalistRole.buyer);
      expect(seller.role, HocalistRole.seller);
      expect(seller.status, MembershipStatus.restricted);
    });

    test('privileges are scoped to one membership, not the account', () {
      final buyerPrivileges = MembershipPrivileges(
        membershipId: 'member-buyer',
        role: HocalistRole.buyer,
        isPlatformAdmin: false,
        identityVerification: VerificationState.notStarted,
        businessVerification: VerificationState.notStarted,
      );
      final sellerPrivileges = MembershipPrivileges(
        membershipId: 'member-seller',
        role: HocalistRole.seller,
        isPlatformAdmin: false,
        identityVerification: VerificationState.verified,
        businessVerification: VerificationState.submitted,
        planCode: 'pro-monthly',
        planLabel: 'Pro Seller',
      );

      final command = UpdateSellerProfileCommand(
        profileId: 'member-seller',
        expectedRevision: 4,
        displayName: 'Northside Tech',
        categoryLabels: const ['Electronics'],
        idempotencyKey: 'key-1',
      );

      expect(
        buyerPrivileges.identityVerification,
        VerificationState.notStarted,
      );
      expect(sellerPrivileges.membershipId, 'member-seller');
      expect(sellerPrivileges.role, HocalistRole.seller);
      expect(
        sellerPrivileges.businessVerification,
        VerificationState.submitted,
      );
      expect(sellerPrivileges.planCode, 'pro-monthly');
      expect(command.displayName, 'Northside Tech');
      expect(command.expectedRevision, 4);
      expect(
        () => MembershipPrivileges(
          membershipId: ' ',
          role: HocalistRole.seller,
          isPlatformAdmin: false,
          identityVerification: VerificationState.notStarted,
          businessVerification: VerificationState.notStarted,
        ),
        throwsArgumentError,
      );
    });

    test('profile commands require an idempotency key and revision', () {
      expect(
        () => UpdateBuyerProfileCommand(
          profileId: 'buyer-1',
          expectedRevision: 4,
          displayName: 'Maya Chen',
          idempotencyKey: '  ',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateBuyerProfileCommand(
          profileId: 'buyer-1',
          expectedRevision: 0,
          displayName: 'Maya Chen',
          idempotencyKey: 'key-1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('NotificationPreferences', () {
    test('copyWith preserves the other switches', () {
      const preferences = NotificationPreferences();
      final muted = preferences.copyWith(offers: false);

      expect(muted.offers, isFalse);
      expect(muted.messages, preferences.messages);
      expect(muted.deals, preferences.deals);
      expect(muted.safety, preferences.safety);
      expect(preferences.offers, isTrue);
    });

    test('update command carries complete preferences', () {
      final command = UpdateNotificationPreferencesCommand(
        userId: 'auth-1',
        preferences: const NotificationPreferences(
          offers: false,
          messages: true,
          deals: false,
          safety: true,
        ),
        idempotencyKey: 'prefs-1',
      );

      expect(command.preferences.offers, isFalse);
      expect(command.preferences.deals, isFalse);
      expect(command.preferences.safety, isTrue);
    });
  });

  group('Private data redaction', () {
    const sentinelAddress = PostalAddress(
      line1: 'SENTINEL-STREET-9000',
      line2: 'SENTINEL-APT-4B',
      city: 'SENTINEL-CITY',
      state: 'ZZ',
      postalCode: 'SENTINEL-99999',
      country: 'SENTINEL-LAND',
    );
    const contact = PrivateContactDetails(
      email: 'sentinel-person@example.com',
      phone: 'SENTINEL-PHONE-555',
      address: sentinelAddress,
    );

    test('PostalAddress keeps values but redacts debug output', () {
      expect(sentinelAddress.line1, 'SENTINEL-STREET-9000');
      expect(sentinelAddress.populatedFieldCount, 6);

      final rendered = sentinelAddress.toString();
      expect(rendered.contains('SENTINEL'), isFalse);
      expect(rendered.contains('9000'), isFalse);
      expect(rendered, contains('[redacted]'));
    });

    test('PrivateContactDetails redacts contacts and nested address', () {
      expect(contact.email, 'sentinel-person@example.com');
      expect(contact.phone, 'SENTINEL-PHONE-555');
      expect(contact.address, sentinelAddress);

      final rendered = contact.toString();
      expect(rendered.contains('sentinel-person@example.com'), isFalse);
      expect(rendered.contains('SENTINEL-PHONE-555'), isFalse);
      expect(rendered.contains('SENTINEL-STREET-9000'), isFalse);
      expect(rendered, contains('email: present'));
      expect(rendered, contains('address: present'));
    });

    test('profile debug output never reaches the private contact', () {
      final buyer = BuyerProfile(
        id: 'buyer-1',
        userId: 'auth-1',
        displayName: 'Maya Chen',
        homeAreaLabel: 'Yonkers, NY',
        contact: contact,
        stamp: stamp,
      );
      final seller = SellerProfile(
        id: 'seller-1',
        userId: 'auth-2',
        displayName: 'Northside Tech',
        serviceAreaLabel: 'Chicago north side',
        contact: contact,
        stamp: stamp,
      );

      for (final rendered in [buyer.toString(), seller.toString()]) {
        expect(rendered.contains('SENTINEL'), isFalse);
        expect(rendered.contains('sentinel-person@example.com'), isFalse);
      }
    });

    test('rejecting a sensitive value does not echo it in the error', () {
      try {
        RequestLocation.custom(address: const PostalAddress());
        fail('expected an ArgumentError');
      } on ArgumentError catch (error) {
        final rendered = error.toString();
        expect(rendered.contains('SENTINEL'), isFalse);
      }
    });
  });
}
