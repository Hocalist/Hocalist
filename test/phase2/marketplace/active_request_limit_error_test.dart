import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_error_mapper.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/failures.dart';
void main() {
  test('posting capacity failure gives a clear configurable limit', () {
    final failure = const MarketplaceErrorMapper().map(
      const MarketplaceTransportError(kind: MarketplaceTransportErrorKind.server, message: 'active_request_limit_reached:4', code: 'P0001'),
      operation: 'request.create',
    );
    expect(failure, isA<ValidationError>());
    final issue = (failure as ValidationError).issues.single;
    expect(issue.code, 'active_request_limit_reached');
    expect(issue.message, contains('4 active requests'));
    expect(issue.message, contains('Close a request'));
  });
}
