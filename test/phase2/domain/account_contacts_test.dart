import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 3,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
  );

  group('AccountContact', () {
    test('keeps nullable SQL fields exactly, including empty strings', () {
      final contact = AccountContact(
        phone: '',
        addressLine1: '123 Main Street',
        city: 'Yonkers',
        region: 'NY',
        postalCode: '10701',
        countryCode: 'US',
      );

      expect(contact.phone, '');
      expect(contact.addressLine2, isNull);
      expect(contact.city, 'Yonkers');
      expect(contact.region, 'NY');
      expect(contact.countryCode, 'US');
      expect(contact.isEmpty, isFalse);
      expect(AccountContact().isEmpty, isTrue);
    });

    test('rejects values beyond the SQL column lengths', () {
      expect(() => AccountContact(phone: 'x' * 41), throwsArgumentError);
      expect(
        () => AccountContact(addressLine1: 'x' * 301),
        throwsArgumentError,
      );
      expect(() => AccountContact(city: 'x' * 151), throwsArgumentError);
      expect(() => AccountContact(region: 'x' * 151), throwsArgumentError);
      expect(() => AccountContact(postalCode: 'x' * 41), throwsArgumentError);
      expect(() => AccountContact(addressLine1: 'x' * 300), returnsNormally);
    });

    test('country code must be two uppercase letters when present', () {
      expect(() => AccountContact(countryCode: 'us'), throwsArgumentError);
      expect(() => AccountContact(countryCode: 'USA'), throwsArgumentError);
      expect(() => AccountContact(countryCode: ''), throwsArgumentError);
      expect(AccountContact(countryCode: 'GB').countryCode, 'GB');
    });

    test('debug output redacts contact values', () {
      final contact = AccountContact(
        phone: 'SENTINEL-PHONE',
        addressLine1: 'SENTINEL-STREET',
        city: 'SENTINEL-CITY',
      );

      expect(contact.phone, 'SENTINEL-PHONE');
      final rendered = contact.toString();
      expect(rendered.contains('SENTINEL'), isFalse);
      expect(rendered, contains('present'));
    });
  });

  group('PrivateContactRecord', () {
    test('carries the identity id, contact values and its own revision', () {
      final record = PrivateContactRecord(
        userId: 'auth-1',
        contact: AccountContact(),
        stamp: stamp,
      );

      expect(record.userId, 'auth-1');
      expect(record.stamp.revision, 3);
      expect(record.contact.isEmpty, isTrue);

      final updated = record.copyWith(
        contact: AccountContact(city: 'New Rochelle'),
      );
      expect(updated.contact.city, 'New Rochelle');
      expect(updated.userId, record.userId);
      expect(updated.stamp, record.stamp);
    });

    test('rejects a blank identity id', () {
      expect(
        () => PrivateContactRecord(
          userId: ' ',
          contact: AccountContact(),
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });
  });

  group('UpdateContactCommand patch semantics', () {
    test('defaults every optional field to keep', () {
      final command = UpdateContactCommand(
        expectedRevision: 3,
        idempotencyKey: 'contact-1',
      );

      expect(command.phone.isKeep, isTrue);
      expect(command.addressLine1.isKeep, isTrue);
      expect(command.addressLine2.isKeep, isTrue);
      expect(command.city.isKeep, isTrue);
      expect(command.region.isKeep, isTrue);
      expect(command.postalCode.isKeep, isTrue);
      expect(command.countryCode.isKeep, isTrue);
      expect(command.expectedRevision, 3);
    });

    test('supports independent set and clear patches', () {
      final command = UpdateContactCommand(
        expectedRevision: 3,
        phone: const PatchSet<String>('+1 914 555 0182'),
        city: const PatchClear<String>(),
        countryCode: const PatchSet<String>('US'),
        idempotencyKey: 'contact-2',
      );

      expect(command.phone.isSet, isTrue);
      expect(command.phone.valueOrNull, '+1 914 555 0182');
      expect(command.city.isClear, isTrue);
      expect(command.region.isKeep, isTrue);
      expect(command.countryCode.valueOrNull, 'US');
    });

    test('validates set values against SQL bounds', () {
      expect(
        () => UpdateContactCommand(
          expectedRevision: 1,
          phone: PatchSet<String>('x' * 41),
          idempotencyKey: 'contact-3',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateContactCommand(
          expectedRevision: 1,
          countryCode: const PatchSet<String>('usa'),
          idempotencyKey: 'contact-4',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateContactCommand(
          expectedRevision: 0,
          idempotencyKey: 'contact-5',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateContactCommand(expectedRevision: 1, idempotencyKey: ' '),
        throwsArgumentError,
      );
    });
  });

  group('ContactUpdateResult', () {
    test('requires a positive revision', () {
      expect(ContactUpdateResult(revision: 2).revision, 2);
      expect(() => ContactUpdateResult(revision: 0), throwsArgumentError);
    });
  });
}
