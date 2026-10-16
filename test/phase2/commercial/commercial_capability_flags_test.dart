import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/commercial_wallet_backend.dart';
import 'package:hocalist/data/phase2/commercial/withdrawal_backend.dart';

void main() {
  test(
    'read capabilities are independent of payout execution and localhost',
    () {
      const preview = bool.fromEnvironment('HOCALIST_LOCAL_WEB_TEST');
      expect(
        kCommercialReadsEnabled,
        const bool.fromEnvironment(
          'HOCALIST_COMMERCIAL_READS',
          defaultValue: preview,
        ),
      );
      expect(
        kWithdrawalReadsEnabled,
        const bool.fromEnvironment(
          'HOCALIST_WITHDRAWAL_READS',
          defaultValue: preview,
        ),
      );
      expect(kWithdrawalsEnabled, isFalse);
      expect(createConfiguredWithdrawalBackend(), isNull);
    },
  );
}
