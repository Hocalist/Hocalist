import 'package:flutter/foundation.dart';
import '../../domain/phase2/commercial/commercial.dart';

@immutable
class SellerOfferPresentation {
  const SellerOfferPresentation.approvedPrototype()
    : planLabel = 'Your Pro Plan',
      initialBid = r'$1.90',
      winningBid = r'$4.75',
      remainingWinningBid = null,
      rateHint = null,
      higherOffersAllowed = false,
      defaultPrice = '550';

  const SellerOfferPresentation.real({
    this.initialBid = 'Not available',
    this.winningBid = 'Not available',
    this.planLabel = 'HocaCredit deposit batches',
    this.remainingWinningBid,
    this.rateHint,
  }) : higherOffersAllowed = false,
       defaultPrice = '';

  factory SellerOfferPresentation.fromWallet(
    CreditWalletView wallet,
    String? requestId, {
    DateTime? requestExpiresAt,
    DateTime? now,
    PlanCode? plan,
  }) {
    String hc(int minor) => '${(minor / 100).toStringAsFixed(2)} HC';
    final planName = switch (plan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro Seller',
      PlanCode.elite => 'Elite Seller',
      null => null,
    };
    SellerOfferPresentation rates(
      int initial,
      int winning,
      String source,
      String hint,
    ) => SellerOfferPresentation.real(
      planLabel: planName == null ? source : '$planName · $source',
      initialBid: hc(initial),
      winningBid: hc(winning),
      remainingWinningBid: hc(winning - initial),
      rateHint: hint,
    );
    for (final target in wallet.targets) {
      if (target.requestId == requestId &&
          (target.status == CreditTargetStatus.reserved ||
              target.status == CreditTargetStatus.initialCharged)) {
        return rates(
          target.initialMinor,
          target.winningMinor,
          'Saved deal rates',
          'This offer keeps the rates reserved for this deal.',
        );
      }
    }
    final terms = wallet.paygo;
    final remaining = requestExpiresAt?.difference(
      now ?? DateTime.now().toUtc(),
    );
    final late =
        terms != null &&
        remaining != null &&
        remaining > Duration.zero &&
        remaining <= Duration(hours: terms.lateWindowHours);
    final batches =
        wallet.batches.where((batch) => batch.fundingKind != 'paygo').toList()
          ..sort((a, b) {
            final time = a.createdAt.compareTo(b.createdAt);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    for (final batch in batches) {
      final available = batch.fundingKind == 'standard'
          ? batches
                .where(
                  (other) =>
                      other.fundingKind == 'standard' &&
                      other.initialFeeMinor == batch.initialFeeMinor &&
                      other.winningTotalMinor == batch.winningTotalMinor &&
                      other.rateVersion == batch.rateVersion,
                )
                .fold<int>(0, (sum, other) => sum + other.availableMinor)
          : batch.availableMinor;
      if (available >=
          (late ? terms.lateTotalMinor : batch.winningTotalMinor)) {
        return rates(
          late ? terms.lateTotalMinor : batch.initialFeeMinor,
          late ? terms.lateTotalMinor : batch.winningTotalMinor,
          'Wallet rates',
          late
              ? 'The final-hours rate applies to this request.'
              : 'Your deposit keeps the rates saved when it was added.',
        );
      }
    }
    if (terms != null && terms.enabled && terms.authorised) {
      return rates(
        late ? terms.lateTotalMinor : terms.initialMinor,
        late ? terms.lateTotalMinor : terms.winningMinor,
        'Pay as you go',
        late
            ? 'The final-hours rate applies to this request.'
            : 'Your saved card uses your current plan’s standard rates.',
      );
    }
    if (terms != null) {
      return rates(
        late ? terms.lateTotalMinor : terms.initialMinor,
        late ? terms.lateTotalMinor : terms.winningMinor,
        'Standard rates',
        'Add credits before sending. These are your plan’s standard rates.',
      );
    }
    return const SellerOfferPresentation.real(
      initialBid: 'Add credits',
      winningBid: 'Add credits',
    );
  }

  final String planLabel;
  final String initialBid;
  final String winningBid;
  final String? remainingWinningBid;
  final String? rateHint;
  final bool higherOffersAllowed;
  final String defaultPrice;
}
