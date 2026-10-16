import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/meeting_directions.dart';

void main() {
  test(
    'confirmed destination refuses generic labels but accepts an address or labelled provider place',
    () {
      expect(hasConfirmedMeetingDestination(label: 'Seller business'), isFalse);
      expect(
        hasConfirmedMeetingDestination(address: '123 Synthetic Ave'),
        isTrue,
      );
      expect(
        hasConfirmedMeetingDestination(
          label: 'Public library',
          placeId: 'synthetic-place',
        ),
        isTrue,
      );
      expect(
        hasConfirmedMeetingDestination(placeId: 'synthetic-place'),
        isFalse,
      );
    },
  );
  test(
    'encodes location as data on fixed HTTPS host without a key or origin',
    () {
      final uri = meetingDirectionsUri(
        address: '123 Test St & x=#?',
        label: 'Unused',
        placeId: 'place/test',
      );
      expect(uri!.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['destination'], '123 Test St & x=#?');
      expect(uri.queryParameters['destination_place_id'], 'place/test');
      expect(uri.queryParameters.containsKey('origin'), isFalse);
      expect(uri.queryParameters.containsKey('key'), isFalse);
    },
  );
  test('missing destination cannot open an empty directions flow', () {
    expect(meetingDirectionsUri(address: ' ', label: ''), isNull);
    expect(
      meetingDirectionsUri(label: 'Library')!.queryParameters['destination'],
      'Library',
    );
  });
}
