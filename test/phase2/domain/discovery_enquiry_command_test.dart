// Shared-contract proof for the Hocatrends enquiry seller target.
//
// Package 02 needs `sellerProfileId` on `OpenDiscoveryEnquiryCommand`. This
// test belongs with the integration patch that adds the field, and proves the
// compatible validation: required for a Hocatrends enquiry, optional for a
// store listing, and always non-blank when supplied.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/conversations.dart';

void main() {
  const topic = '40000000-0000-4000-8000-000000000001';
  const listing = '30000000-0000-4000-8000-000000000001';
  const sellerProfile = '10000000-0000-4000-8000-00000000000b';

  test('a Hocatrends enquiry carries the targeted seller', () {
    final command = OpenDiscoveryEnquiryCommand(
      origin: ConversationOrigin.hocatrendsEnquiry,
      subjectId: topic,
      initiatedByUserId: '00000000-0000-4000-8000-00000000000a',
      sellerProfileId: sellerProfile,
      idempotencyKey: 'key-1',
    );
    expect(command.sellerProfileId, sellerProfile);
  });

  test('a Hocatrends enquiry without a seller stays source-compatible', () {
    final command = OpenDiscoveryEnquiryCommand(
      origin: ConversationOrigin.hocatrendsEnquiry,
      subjectId: topic,
      initiatedByUserId: '00000000-0000-4000-8000-00000000000a',
      idempotencyKey: 'key-1',
    );
    expect(command.sellerProfileId, isNull);
  });

  test('a blank seller is rejected whenever supplied', () {
    expect(
      () => OpenDiscoveryEnquiryCommand(
        origin: ConversationOrigin.hocatrendsEnquiry,
        subjectId: topic,
        initiatedByUserId: '00000000-0000-4000-8000-00000000000a',
        sellerProfileId: '   ',
        idempotencyKey: 'key-1',
      ),
      throwsArgumentError,
    );
  });

  test('a store-listing enquiry stays valid without the extra field', () {
    final command = OpenDiscoveryEnquiryCommand(
      origin: ConversationOrigin.storeListing,
      subjectId: listing,
      initiatedByUserId: '00000000-0000-4000-8000-00000000000a',
      idempotencyKey: 'key-1',
    );
    expect(command.sellerProfileId, isNull);
    expect(command.subjectId, listing);
  });

  test('a targeted-request origin is still rejected', () {
    expect(
      () => OpenDiscoveryEnquiryCommand(
        origin: ConversationOrigin.targetedRequest,
        subjectId: topic,
        initiatedByUserId: '00000000-0000-4000-8000-00000000000a',
        sellerProfileId: sellerProfile,
        idempotencyKey: 'key-1',
      ),
      throwsArgumentError,
    );
  });
}
