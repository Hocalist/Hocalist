import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'phase2/commercial/support/commercial_payloads.dart';

void main() {
  test(
    'rates use the oldest single eligible batch, not subscription or combined balances',
    () {
      final wallet = CreditWalletView.fromJson(
        creditWalletJson(
          targets: [],
          batches: [
            {
              ...batchJson(id: 'new', initial: 145, winning: 325),
              'created_at': '2026-10-01T00:00:00Z',
            },
            batchJson(id: 'old', balance: 100, initial: 155, winning: 375),
            batchJson(id: 'eligible', initial: 165, winning: 400),
          ],
        ),
      );
      final value = SellerOfferPresentation.fromWallet(wallet, 'new-request');
      expect(value.initialBid, '1.65 HC');
      expect(value.winningBid, '4.00 HC');
    },
  );
  test('existing reservation retains its own immutable rates', () {
    final wallet = CreditWalletView.fromJson(creditWalletJson(batches: []));
    final value = SellerOfferPresentation.fromWallet(wallet, 'req-1');
    expect(value.initialBid, '1.55 HC');
    expect(value.winningBid, '3.75 HC');
  });
  test(
    'insufficient individual batches request credits rather than inventing rates',
    () {
      final wallet = CreditWalletView.fromJson(
        creditWalletJson(
          targets: [],
          batches: [
            batchJson(id: 'a', balance: 200),
            batchJson(id: 'b', balance: 200),
          ],
        ),
      );
      expect(
        SellerOfferPresentation.fromWallet(wallet, 'new').initialBid,
        'Add credits',
      );
    },
  );
}
