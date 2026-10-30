import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'phase2/commercial/support/commercial_payloads.dart';

void main() {
  for(final entry in [
    (PlanCode.free,195,475),(PlanCode.free,185,450),
    (PlanCode.pro,175,460),(PlanCode.pro,165,450),
    (PlanCode.elite,155,375),(PlanCode.elite,145,325),
  ]) {
    test('wallet quote keeps ${entry.$1.name} deposit rates ${entry.$2}/${entry.$3}',(){
      final wallet=CreditWalletView.fromJson(creditWalletJson(targets:[],batches:[
        batchJson(initial:entry.$2,winning:entry.$3),
      ]));
      final quote=SellerOfferPresentation.fromWallet(wallet,'new',plan:entry.$1);
      expect(quote.initialBid,'${(entry.$2/100).toStringAsFixed(2)} HC');
      expect(quote.winningBid,'${(entry.$3/100).toStringAsFixed(2)} HC');
      expect(quote.remainingWinningBid,'${((entry.$3-entry.$2)/100).toStringAsFixed(2)} HC');
      expect(quote.planLabel,contains('Wallet rates'));
      expect(quote.rateHint,contains('deposit'));
    });
  }
  test('standard deposits combine only when their immutable rates match', () {
    final wallet = CreditWalletView.fromJson(creditWalletJson(targets: [], batches: [
      {...batchJson(id: 'small-one', balance: 200, initial: 200, winning: 500), 'original_minor': 200, 'funding_kind': 'standard', 'reserved_minor': 0, 'available_minor': 200, 'rate_version': 'standard:free:1'},
      {...batchJson(id: 'small-two', balance: 300, initial: 200, winning: 500), 'original_minor': 300, 'funding_kind': 'standard', 'reserved_minor': 0, 'available_minor': 300, 'rate_version': 'standard:free:1'},
    ]));
    final quote = SellerOfferPresentation.fromWallet(wallet, 'new');
    expect(quote.initialBid, '2.00 HC');
    expect(quote.winningBid, '5.00 HC');
    final changed = CreditWalletView.fromJson(creditWalletJson(targets: [], batches: [
      {...batchJson(id: 'small-one', balance: 200, initial: 200, winning: 500), 'original_minor': 200, 'funding_kind': 'standard', 'reserved_minor': 0, 'available_minor': 200, 'rate_version': 'standard:free:1'},
      {...batchJson(id: 'small-two', balance: 300, initial: 200, winning: 500), 'original_minor': 300, 'funding_kind': 'standard', 'reserved_minor': 0, 'available_minor': 300, 'rate_version': 'standard:free:2'},
    ]));
    expect(SellerOfferPresentation.fromWallet(changed, 'new').initialBid, 'Add credits');
  });
  Map<String, Object?> terms({bool enabled = true}) => {
    'enabled': enabled, 'authorised': true, 'initial_minor': 200,
    'winning_minor': 500, 'late_window_hours': 12, 'late_total_minor': 200,
  };
  test('paygo uses server tier rates when no prepaid batch funds the deal', () {
    final wallet = CreditWalletView.fromJson({...creditWalletJson(targets: [], batches: []), 'paygo': terms()});
    final value = SellerOfferPresentation.fromWallet(wallet, 'new');
    expect(value.planLabel, 'Pay as you go');
    expect(value.initialBid, '2.00 HC');
    expect(value.winningBid, '5.00 HC');
  });
  test('paygo batches allow partial funding and never masquerade as prepaid rates', () {
    final wallet = CreditWalletView.fromJson({...creditWalletJson(targets: [], batches: [
      {...batchJson(original: 200, balance: 200, reserved: 0, charged: 0, initial: 200, winning: 500), 'funding_kind': 'paygo'},
    ]), 'paygo': terms()});
    expect(wallet.batches.single.fundingKind, 'paygo');
    expect(SellerOfferPresentation.fromWallet(wallet, 'new').planLabel, 'Pay as you go');
    expect(()=>CreditWalletView.fromJson(creditWalletJson(targets: [], batches: [batchJson(original: 200, balance: 200, reserved: 0, charged: 0, initial: 200, winning: 500)])), throwsA(isA<CommercialContractError>()));
  });
  test('last twelve-hour preview matches the server two-HC total and restores ordinary rates outside the window', () {
    final now = DateTime.utc(2026,10,25,12);
    final wallet = CreditWalletView.fromJson({...creditWalletJson(targets: [], batches: [batchJson(balance: 200, reserved: 0, initial: 195, winning: 475)]), 'paygo': terms()});
    final late = SellerOfferPresentation.fromWallet(wallet, 'new', now: now, requestExpiresAt: now.add(const Duration(hours: 12)));
    expect(late.initialBid, '2.00 HC');expect(late.winningBid, '2.00 HC');
    expect(late.remainingWinningBid,'0.00 HC');
    final ordinary = SellerOfferPresentation.fromWallet(wallet, 'new', now: now, requestExpiresAt: now.add(const Duration(hours: 12, seconds: 1)));
    expect(ordinary.planLabel, 'Pay as you go');expect(ordinary.winningBid, '5.00 HC');
  });
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
    expect(value.remainingWinningBid,'2.20 HC');
    expect(value.planLabel,'Saved deal rates');
  });
  test('disabled or unauthorised card funding shows standard rates without claiming a saved-card quote',(){
    for(final enabled in [false,true]) {
      final wallet=CreditWalletView.fromJson({...creditWalletJson(targets:[],batches:[]),
        'paygo':{...terms(enabled:enabled),'authorised':false,'initial_minor':190,'winning_minor':475}});
      final quote=SellerOfferPresentation.fromWallet(wallet,'new',plan:PlanCode.pro);
      expect(quote.planLabel,'Pro Seller · Standard rates');
      expect(quote.initialBid,'1.90 HC');
      expect(quote.remainingWinningBid,'2.85 HC');
      expect(quote.rateHint,contains('Add credits'));
    }
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
