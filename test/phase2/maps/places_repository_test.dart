// Places boundary tests: contract validation, session tokens, typed failures
// and response bounds. Fakes only; no provider or network calls.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/places_contract.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';

class FakePlacesTransport implements PlacesTransport {
  Future<PlacesTransportResult> Function(String input, String token)? onSearch;
  Future<PlacesTransportResult> Function(String placeId, String token)?
  onDetails;
  final List<String> queries = <String>[];
  final List<String> sessionTokens = <String>[];

  @override
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  }) {
    queries.add(input);
    sessionTokens.add(sessionToken);
    return onSearch?.call(input, sessionToken) ??
        Future.value(
          const PlacesTransportResult(<String, Object?>{
            'suggestions': [
              <String, Object?>{
                'placeId': 'place-1',
                'label': 'Cross County Mall',
              },
            ],
          }),
        );
  }

  @override
  Future<PlacesTransportResult> details({
    required String placeId,
    required String sessionToken,
  }) {
    sessionTokens.add(sessionToken);
    return onDetails?.call(placeId, sessionToken) ??
        Future.value(
          const PlacesTransportResult(<String, Object?>{
            'placeId': 'place-1',
            'address': '123 Synthetic Ave',
            'latitude': 40.9,
            'longitude': -73.8,
            'attributions': [
              <String, Object?>{
                'provider': 'Google Maps',
                'uri': 'https://maps.google.com',
              },
            ],
          }),
        );
  }
}

void main() {
  group('PlacesSession', () {
    test('generates a UUID v4 token and expires after the max age', () {
      final session = PlacesSession.start(now: DateTime.utc(2026, 5, 1, 12));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(session.token),
        isTrue,
      );
      expect(session.isExpiredAt(DateTime.utc(2026, 5, 1, 12, 14)), isFalse);
      expect(session.isExpiredAt(DateTime.utc(2026, 5, 1, 12, 16)), isTrue);
    });

    test('tokens differ between sessions', () {
      expect(PlacesSession.start().token, isNot(PlacesSession.start().token));
    });
  });

  group('PlacesRepository', () {
    late FakePlacesTransport transport;
    late PlacesRepository repository;

    setUp(() {
      transport = FakePlacesTransport();
      repository = PlacesRepository(transport: transport);
    });

    test('rejects blank and oversized queries before transport', () async {
      final session = PlacesSession.start();
      expect(await repository.search(input: '   ', session: session), isEmpty);
      expect(transport.queries, isEmpty);
      await expectLater(
        repository.search(
          input: 'x' * (placesMaxQueryLength + 1),
          session: session,
        ),
        throwsA(
          isA<PlacesFailure>().having(
            (failure) => failure.code,
            'code',
            PlacesFailureCode.invalidInput,
          ),
        ),
      );
      expect(transport.queries, isEmpty);
    });

    test('maps suggestions and shares the session token', () async {
      final session = PlacesSession.start();
      final suggestions = await repository.search(
        input: 'Cross County',
        session: session,
      );
      expect(suggestions.single.placeId, 'place-1');
      expect(suggestions.single.label, 'Cross County Mall');
      expect(transport.sessionTokens.single, session.token);
    });

    test('rejects oversized suggestion lists', () async {
      transport.onSearch = (_, _) async => PlacesTransportResult({
        'suggestions': List.generate(
          6,
          (index) => {'placeId': 'place-$index', 'label': 'Place $index'},
        ),
      });
      await expectLater(
        repository.search(input: 'mall', session: PlacesSession.start()),
        throwsA(
          isA<PlacesFailure>().having(
            (failure) => failure.code,
            'code',
            PlacesFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test('resolves details with coordinates and attributions', () async {
      final details = await repository.resolve(
        placeId: 'place-1',
        session: PlacesSession.start(),
      );
      expect(details.address, '123 Synthetic Ave');
      expect(details.latitude, 40.9);
      expect(details.longitude, -73.8);
      expect(details.attributions.single.provider, 'Google Maps');
      expect(details.attributions.single.uri, startsWith('https://'));
    });

    test('rejects a mismatched place id', () async {
      transport.onDetails = (_, _) async =>
          const PlacesTransportResult(<String, Object?>{
            'placeId': 'other-place',
            'address': '123 Synthetic Ave',
            'latitude': 40.9,
            'longitude': -73.8,
          });
      await expectLater(
        repository.resolve(placeId: 'place-1', session: PlacesSession.start()),
        throwsA(
          isA<PlacesFailure>().having(
            (failure) => failure.code,
            'code',
            PlacesFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test('rejects out-of-range coordinates', () async {
      transport.onDetails = (_, _) async =>
          const PlacesTransportResult(<String, Object?>{
            'placeId': 'place-1',
            'address': '123 Synthetic Ave',
            'latitude': 120.0,
            'longitude': -73.8,
          });
      await expectLater(
        repository.resolve(placeId: 'place-1', session: PlacesSession.start()),
        throwsA(isA<PlacesFailure>()),
      );
    });

    test('maps every failure code to a safe message', () {
      for (final code in PlacesFailureCode.values) {
        final message = placesFailureMessage(PlacesFailure(code));
        expect(message, isNotEmpty);
        expect(message, isNot(contains('http')));
      }
    });
  });

  group('PlaceDetails', () {
    test('rejects non-https attributions', () {
      expect(
        () => PlaceAttribution(provider: 'Google Maps', uri: 'http://x.test'),
        throwsArgumentError,
      );
    });
  });

  group('placesFailureFromEndpoint', () {
    test('maps the endpoint session codes to a restartable failure', () {
      for (final code in const [
        'session_invalid',
        'session_expired',
        'session_exhausted',
      ]) {
        expect(
          placesFailureFromEndpoint(status: 400, details: {'error': code}).code,
          PlacesFailureCode.sessionExpired,
          reason: code,
        );
      }
      expect(
        placesFailureFromEndpoint(
          status: 400,
          details: {'error': 'suggestion_required'},
        ).code,
        PlacesFailureCode.suggestionRequired,
      );
    });

    test('maps the remaining endpoint codes and falls back by status', () {
      expect(
        placesFailureFromEndpoint(
          status: 400,
          details: {'error': 'invalid_input'},
        ).code,
        PlacesFailureCode.invalidInput,
      );
      expect(
        placesFailureFromEndpoint(
          status: 429,
          details: {'error': 'rate_limited'},
        ).code,
        PlacesFailureCode.rateLimited,
      );
      expect(
        placesFailureFromEndpoint(
          status: 404,
          details: {'error': 'unconfigured'},
        ).code,
        PlacesFailureCode.unconfigured,
      );
      expect(
        placesFailureFromEndpoint(status: 400, details: 'raw text').code,
        PlacesFailureCode.invalidInput,
      );
      expect(
        placesFailureFromEndpoint(status: 500, details: null).code,
        PlacesFailureCode.unavailable,
      );
      expect(
        placesFailureFromEndpoint(
          status: 403,
          details: {'error': 'membership_required'},
        ).code,
        PlacesFailureCode.unavailable,
      );
    });
  });
}
