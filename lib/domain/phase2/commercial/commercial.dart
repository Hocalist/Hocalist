/// Commercial lifecycle view contracts (Phase 2, package 06-commercial).
///
/// Pure Dart. Every type in this file is a strict decode of an authoritative
/// server read; nothing is derived from client-selected plans or local
/// balances. Decoders throw [CommercialContractError] on a shape or invariant
/// violation so a caller can render an honest unavailable state instead of a
/// fabricated amount.
///
/// Money is always integer minor units plus an explicit currency code. Credit
/// ledgers (`HC`) and buyer reward ledgers (`USD`) stay separate types.
library;

class CommercialContractError implements Exception {
  const CommercialContractError(this.reason);

  final String reason;

  @override
  String toString() => 'CommercialContractError($reason)';
}

int _int(Map<String, Object?> json, String key, {int? minimum}) {
  final value = json[key];
  if (value is! int) throw CommercialContractError('bad_int:$key');
  if (minimum != null && value < minimum) {
    throw CommercialContractError('range:$key');
  }
  return value;
}

int? _optInt(Map<String, Object?> json, String key, {int? minimum}) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw CommercialContractError('bad_int:$key');
  if (minimum != null && value < minimum) {
    throw CommercialContractError('range:$key');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw CommercialContractError('bad_string:$key');
  }
  return value;
}

String? _optString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw CommercialContractError('bad_string:$key');
  return value.isEmpty ? null : value;
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw CommercialContractError('bad_bool:$key');
  return value;
}

bool? _optBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw CommercialContractError('bad_bool:$key');
  return value;
}

DateTime _dateTime(Map<String, Object?> json, String key) {
  final raw = _string(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw CommercialContractError('bad_time:$key');
  return parsed.toUtc();
}

DateTime? _optDateTime(Map<String, Object?> json, String key) {
  final raw = _optString(json, key);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw CommercialContractError('bad_time:$key');
  return parsed.toUtc();
}

List<Map<String, Object?>> _rows(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw CommercialContractError('bad_list:$key');
  return value
      .map((row) {
        if (row is! Map) throw CommercialContractError('bad_row:$key');
        return Map<String, Object?>.from(row);
      })
      .toList(growable: false);
}

T _enumValue<T>(String raw, Map<String, T> allowed, String field) {
  final value = allowed[raw];
  if (value == null) throw CommercialContractError('bad_enum:$field');
  return value;
}

// ---------------------------------------------------------------------------
// Seller credit ledger
// ---------------------------------------------------------------------------

enum CreditTargetStatus { reserved, initialCharged, won, released, refunded }

const _creditTargetStatuses = <String, CreditTargetStatus>{
  'reserved': CreditTargetStatus.reserved,
  'initial_charged': CreditTargetStatus.initialCharged,
  'won': CreditTargetStatus.won,
  'released': CreditTargetStatus.released,
  'refunded': CreditTargetStatus.refunded,
};

class WeeklyQuotaView {
  const WeeklyQuotaView({
    required this.weekStart,
    required this.used,
    required this.limit,
  });

  final DateTime weekStart;
  final int used;
  final int limit;

  factory WeeklyQuotaView.fromJson(Map<String, Object?> json) {
    final rawWeek = _string(json, 'week_start');
    final week = DateTime.tryParse(rawWeek);
    if (week == null) {
      throw const CommercialContractError('bad_time:week_start');
    }
    return WeeklyQuotaView(
      weekStart: DateTime.utc(week.year, week.month, week.day),
      used: _int(json, 'used', minimum: 0),
      limit: _int(json, 'limit', minimum: 0),
    );
  }

  int get remaining => limit - used > 0 ? limit - used : 0;
}

class DepositOptionView {
  const DepositOptionView({
    required this.id,
    required this.amountMinor,
    required this.initialFeeMinor,
    required this.winningTotalMinor,
    required this.rateVersion,
    required this.active,
    required this.revision,
    required this.sortOrder,
  });

  final String id;
  final int amountMinor;
  final int initialFeeMinor;
  final int winningTotalMinor;
  final String rateVersion;
  final bool active;
  final int revision;
  final int sortOrder;

  factory DepositOptionView.fromJson(Map<String, Object?> json) {
    final option = DepositOptionView(
      id: _string(json, 'id'),
      amountMinor: _int(json, 'amount_minor', minimum: 1),
      initialFeeMinor: _int(json, 'initial_fee_minor', minimum: 0),
      winningTotalMinor: _int(json, 'winning_total_minor', minimum: 0),
      rateVersion: _string(json, 'rate_version'),
      active: _bool(json, 'active'),
      revision: _int(json, 'revision', minimum: 1),
      sortOrder: _int(json, 'sort_order', minimum: 0),
    );
    if (option.winningTotalMinor < option.initialFeeMinor ||
        option.winningTotalMinor > option.amountMinor) {
      throw const CommercialContractError('option_rate_shape');
    }
    return option;
  }
}

class CreditBatchView {
  const CreditBatchView({
    required this.id,
    required this.originalMinor,
    required this.balanceMinor,
    required this.reservedMinor,
    required this.availableMinor,
    required this.chargedMinor,
    required this.initialFeeMinor,
    required this.winningTotalMinor,
    required this.rateVersion,
    required this.createdAt,
  });

  final String id;
  final int originalMinor;
  final int balanceMinor;
  final int reservedMinor;
  final int availableMinor;
  final int chargedMinor;
  final int initialFeeMinor;
  final int winningTotalMinor;
  final String rateVersion;
  final DateTime createdAt;

  factory CreditBatchView.fromJson(Map<String, Object?> json) {
    final batch = CreditBatchView(
      id: _string(json, 'id'),
      originalMinor: _int(json, 'original_minor', minimum: 1),
      balanceMinor: _int(json, 'balance_minor', minimum: 0),
      reservedMinor: _int(json, 'reserved_minor', minimum: 0),
      availableMinor: _int(json, 'available_minor', minimum: 0),
      chargedMinor: _int(json, 'charged_minor', minimum: 0),
      initialFeeMinor: _int(json, 'initial_fee_minor', minimum: 0),
      winningTotalMinor: _int(json, 'winning_total_minor', minimum: 0),
      rateVersion: _string(json, 'rate_version'),
      createdAt: _dateTime(json, 'created_at'),
    );
    if (batch.reservedMinor > batch.balanceMinor ||
        batch.availableMinor != batch.balanceMinor - batch.reservedMinor ||
        batch.winningTotalMinor > batch.originalMinor) {
      throw const CommercialContractError('batch_shape');
    }
    return batch;
  }
}

class CreditTargetView {
  const CreditTargetView({
    required this.id,
    required this.requestId,
    required this.requestTitle,
    required this.offerId,
    required this.status,
    required this.initialMinor,
    required this.winningMinor,
    required this.chargedMinor,
    required this.reservedMinor,
    required this.weekStart,
    required this.rateVersion,
    required this.qualifiedAt,
    required this.createdAt,
  });

  final String id;
  final String requestId;
  final String? requestTitle;
  final String? offerId;
  final CreditTargetStatus status;
  final int initialMinor;
  final int winningMinor;
  final int chargedMinor;
  final int reservedMinor;
  final DateTime weekStart;
  final String rateVersion;
  final DateTime? qualifiedAt;
  final DateTime createdAt;

  factory CreditTargetView.fromJson(Map<String, Object?> json) {
    final target = CreditTargetView(
      id: _string(json, 'id'),
      requestId: _string(json, 'request_id'),
      requestTitle: _optString(json, 'request_title'),
      offerId: _optString(json, 'offer_id'),
      status: _enumValue(
        _string(json, 'status'),
        _creditTargetStatuses,
        'target_status',
      ),
      initialMinor: _int(json, 'initial_minor', minimum: 0),
      winningMinor: _int(json, 'winning_minor', minimum: 0),
      chargedMinor: _int(json, 'charged_minor', minimum: 0),
      reservedMinor: _int(json, 'reserved_minor', minimum: 0),
      weekStart: () {
        final raw = _string(json, 'week_start');
        final week = DateTime.tryParse(raw);
        if (week == null) {
          throw const CommercialContractError('bad_time:week_start');
        }
        return DateTime.utc(week.year, week.month, week.day);
      }(),
      rateVersion: _string(json, 'rate_version'),
      qualifiedAt: _optDateTime(json, 'qualified_at'),
      createdAt: _dateTime(json, 'created_at'),
    );
    if (target.chargedMinor > target.winningMinor) {
      throw const CommercialContractError('target_shape');
    }
    return target;
  }
}

class CreditWalletView {
  const CreditWalletView({
    required this.currency,
    required this.balanceMinor,
    required this.reservedMinor,
    required this.availableMinor,
    required this.chargedMinor,
    required this.depositedMinor,
    required this.reversalHoldMinor,
    required this.weekly,
    required this.depositOptions,
    required this.batches,
    required this.targets,
    required this.depositOptionsConfigured,
  });

  final String currency;
  final int balanceMinor;
  final int reservedMinor;
  final int availableMinor;
  final int chargedMinor;
  final int depositedMinor;
  final int reversalHoldMinor;
  final WeeklyQuotaView weekly;
  final List<DepositOptionView> depositOptions;
  final List<CreditBatchView> batches;
  final List<CreditTargetView> targets;
  final bool depositOptionsConfigured;

  factory CreditWalletView.fromJson(Map<String, Object?> json) {
    final currency = _string(json, 'currency');
    if (currency != 'HC') throw const CommercialContractError('bad_currency');
    final balance = _int(json, 'balance_minor', minimum: 0);
    final reserved = _int(json, 'reserved_minor', minimum: 0);
    final available = _int(json, 'available_minor', minimum: 0);
    if (reserved > balance || available != balance - reserved) {
      throw const CommercialContractError('wallet_shape');
    }
    final policy = json['policy'];
    if (policy is! Map) throw const CommercialContractError('bad_policy');
    return CreditWalletView(
      currency: currency,
      balanceMinor: balance,
      reservedMinor: reserved,
      availableMinor: available,
      chargedMinor: _int(json, 'charged_minor', minimum: 0),
      depositedMinor: _int(json, 'deposited_minor', minimum: 0),
      reversalHoldMinor: _int(json, 'reversal_hold_minor', minimum: 0),
      weekly: WeeklyQuotaView.fromJson(_map(json, 'weekly')),
      depositOptions: _rows(
        json,
        'deposit_options',
      ).map(DepositOptionView.fromJson).toList(growable: false),
      batches: _rows(
        json,
        'batches',
      ).map(CreditBatchView.fromJson).toList(growable: false),
      targets: _rows(
        json,
        'targets',
      ).map(CreditTargetView.fromJson).toList(growable: false),
      depositOptionsConfigured: _bool(
        Map<String, Object?>.from(policy),
        'deposit_options_configured',
      ),
    );
  }
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw CommercialContractError('bad_map:$key');
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _optMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map) throw CommercialContractError('bad_map:$key');
  return Map<String, Object?>.from(value);
}

// ---------------------------------------------------------------------------
// Buyer reward ledger
// ---------------------------------------------------------------------------

enum RewardItemStatus { earned, held }

const _rewardItemStatuses = <String, RewardItemStatus>{
  'earned': RewardItemStatus.earned,
  'held': RewardItemStatus.held,
};

class RewardItemView {
  const RewardItemView({
    required this.id,
    required this.amountMinor,
    required this.createdAt,
    required this.status,
    required this.holdMinor,
    required this.reversedMinor,
    required this.shortfallMinor,
    required this.itemTitle,
  });

  final String id;
  final int amountMinor;
  final DateTime createdAt;
  final RewardItemStatus status;
  final int holdMinor;
  final int reversedMinor;

  /// Face value of a reversal that could not be recovered from spendable
  /// funds. It is audit history and is never an implicit debt against other
  /// rewards.
  final int shortfallMinor;
  final String? itemTitle;

  factory RewardItemView.fromJson(Map<String, Object?> json) {
    final item = RewardItemView(
      id: _string(json, 'id'),
      amountMinor: _int(json, 'amount_minor', minimum: 1),
      createdAt: _dateTime(json, 'created_at'),
      status: _enumValue(
        _string(json, 'status'),
        _rewardItemStatuses,
        'reward_status',
      ),
      holdMinor: _int(json, 'hold_minor', minimum: 0),
      reversedMinor: _int(json, 'reversed_minor', minimum: 0),
      shortfallMinor: _int(json, 'shortfall_minor', minimum: 0),
      itemTitle: _optString(json, 'item_title'),
    );
    if (item.holdMinor + item.reversedMinor > item.amountMinor ||
        item.shortfallMinor > item.amountMinor) {
      throw const CommercialContractError('reward_shape');
    }
    return item;
  }
}

class WithdrawalTermsView {
  const WithdrawalTermsView({
    required this.configured,
    required this.minimumMinor,
    required this.feeMinor,
    required this.emailVerified,
    required this.phoneVerified,
  });

  final bool configured;
  final int? minimumMinor;
  final int? feeMinor;
  final bool emailVerified;
  final bool phoneVerified;

  bool get contactVerified => emailVerified && phoneVerified;

  factory WithdrawalTermsView.fromJson(Map<String, Object?> json) {
    final configured = _bool(json, 'configured');
    return WithdrawalTermsView(
      configured: configured,
      minimumMinor: configured ? _int(json, 'minimum_minor', minimum: 1) : null,
      feeMinor: configured ? _int(json, 'fee_minor', minimum: 0) : null,
      emailVerified: _bool(json, 'email_verified'),
      phoneVerified: _bool(json, 'phone_verified'),
    );
  }
}

class PayoutPolicyView {
  const PayoutPolicyView({
    required this.providerConfigured,
    required this.executionEnabled,
    required this.providerNeutral,
  });

  final bool providerConfigured;
  final bool executionEnabled;
  final bool providerNeutral;

  factory PayoutPolicyView.fromJson(Map<String, Object?> json) =>
      PayoutPolicyView(
        providerConfigured: _bool(json, 'provider_configured'),
        executionEnabled: _bool(json, 'execution_enabled'),
        providerNeutral: _bool(json, 'provider_neutral'),
      );
}

class ReversalPolicyView {
  const ReversalPolicyView({
    required this.clawbackModeConfigured,
    required this.rewardHoldConfigured,
  });

  final bool clawbackModeConfigured;
  final bool rewardHoldConfigured;

  factory ReversalPolicyView.fromJson(Map<String, Object?> json) =>
      ReversalPolicyView(
        clawbackModeConfigured: _bool(json, 'clawback_mode_configured'),
        rewardHoldConfigured: _bool(json, 'reward_hold_configured'),
      );
}

class RewardWalletView {
  const RewardWalletView({
    required this.currency,
    required this.earnedMinor,
    required this.heldMinor,
    required this.pendingMinor,
    required this.holdMinor,
    required this.withdrawalHoldMinor,
    required this.reversedMinor,
    required this.shortfallMinor,
    required this.processingMinor,
    required this.paidMinor,
    required this.availableMinor,
    required this.rewardPolicyConfigured,
    required this.normalMinor,
    required this.lateMinor,
    required this.lateWindowHours,
    required this.withdrawal,
    required this.payout,
    required this.reversalPolicy,
    required this.items,
  });

  final String currency;
  final int earnedMinor;
  final int heldMinor;
  final int pendingMinor;
  final int holdMinor;
  final int withdrawalHoldMinor;
  final int reversedMinor;

  /// Unrecovered reversal losses: recorded for audit and manual policy, never
  /// deducted from other rewards.
  final int shortfallMinor;
  final int processingMinor;
  final int paidMinor;
  final int availableMinor;
  final bool rewardPolicyConfigured;
  final int? normalMinor;
  final int? lateMinor;
  final int? lateWindowHours;
  final WithdrawalTermsView withdrawal;
  final PayoutPolicyView payout;
  final ReversalPolicyView reversalPolicy;
  final List<RewardItemView> items;

  factory RewardWalletView.fromJson(Map<String, Object?> json) {
    final currency = _string(json, 'currency');
    if (currency != 'USD') throw const CommercialContractError('bad_currency');
    final earned = _int(json, 'earned_minor', minimum: 0);
    final held = _int(json, 'held_minor', minimum: 0);
    final pending = _int(json, 'pending_minor', minimum: 0);
    final hold = _int(json, 'hold_minor', minimum: 0);
    final withdrawalHold = _int(json, 'withdrawal_hold_minor', minimum: 0);
    final reversed = _int(json, 'reversed_minor', minimum: 0);
    final shortfall = _int(json, 'shortfall_minor', minimum: 0);
    final processing = _int(json, 'processing_minor', minimum: 0);
    final paid = _int(json, 'paid_minor', minimum: 0);
    final available = _int(json, 'available_minor', minimum: 0);
    final items = _rows(
      json,
      'items',
    ).map(RewardItemView.fromJson).toList(growable: false);
    // Top-level and per-item values must agree. The item list is capped by the
    // server page, so per-item sums are lower bounds; a per-item value larger
    // than its total is a contract error, never a silently displayed balance.
    var itemHold = 0;
    var itemReversed = 0;
    var itemShortfall = 0;
    for (final item in items) {
      itemHold += item.holdMinor;
      itemReversed += item.reversedMinor;
      itemShortfall += item.shortfallMinor;
    }
    if (pending > held ||
        held != pending + hold + withdrawalHold ||
        itemHold > hold ||
        itemReversed > reversed ||
        itemShortfall > shortfall ||
        reversed > earned ||
        available > earned) {
      throw const CommercialContractError('reward_wallet_shape');
    }
    return RewardWalletView(
      currency: currency,
      earnedMinor: earned,
      heldMinor: held,
      pendingMinor: pending,
      holdMinor: hold,
      withdrawalHoldMinor: withdrawalHold,
      reversedMinor: reversed,
      shortfallMinor: shortfall,
      processingMinor: processing,
      paidMinor: paid,
      availableMinor: available,
      rewardPolicyConfigured: _bool(json, 'reward_policy_configured'),
      normalMinor: _optInt(json, 'normal_minor', minimum: 1),
      lateMinor: _optInt(json, 'late_minor', minimum: 1),
      lateWindowHours: _optInt(json, 'late_window_hours', minimum: 1),
      withdrawal: WithdrawalTermsView.fromJson(_map(json, 'withdrawal')),
      payout: PayoutPolicyView.fromJson(_map(json, 'payout')),
      reversalPolicy: ReversalPolicyView.fromJson(
        _map(json, 'reversal_policy'),
      ),
      items: items,
    );
  }

  /// Dashboard-compatible projection of the authoritative read.
  ///
  /// The approved buyer home card consumes `currency`, `earned_minor` and
  /// `items[].status`. It must never show more than is actually withdrawable:
  /// `earned_minor` is the authoritative available amount, and a reversed or
  /// held item is reported as `held` so the card's held total stays coherent.
  Map<String, Object?> toDashboardMap() => {
    'currency': currency,
    'earned_minor': availableMinor,
    'available_minor': availableMinor,
    'held_minor': heldMinor,
    'reversed_minor': reversedMinor,
    'shortfall_minor': shortfallMinor,
    'processing_minor': processingMinor,
    'paid_minor': paidMinor,
    'withdrawals_enabled': payout.providerConfigured && payout.executionEnabled,
    'items': [
      for (final item in items)
        {
          'id': item.id,
          'amount_minor': item.amountMinor,
          'created_at': item.createdAt.toIso8601String(),
          'status':
              item.status == RewardItemStatus.held || item.reversedMinor > 0
              ? 'held'
              : 'earned',
          'hold_minor': item.holdMinor,
          'reversed_minor': item.reversedMinor,
          'shortfall_minor': item.shortfallMinor,
        },
    ],
  };
}

// ---------------------------------------------------------------------------
// Sale history (role-aware) and drill-down
// ---------------------------------------------------------------------------

enum SaleSide { purchase, sale }

class SaleRewardView {
  const SaleRewardView({
    required this.status,
    required this.amountMinor,
    required this.ruleVersion,
  });

  final String status;
  final int amountMinor;
  final String? ruleVersion;

  factory SaleRewardView.fromJson(Map<String, Object?> json) {
    final status = _string(json, 'status');
    if (!const {'none', 'earned', 'held'}.contains(status)) {
      throw const CommercialContractError('bad_enum:reward_status');
    }
    return SaleRewardView(
      status: status,
      amountMinor: status == 'none' && json['amount_minor'] == null
          ? 0
          : _int(json, 'amount_minor', minimum: 0),
      ruleVersion: _optString(json, 'rule_version'),
    );
  }
}

class SaleFeeView {
  const SaleFeeView({
    required this.status,
    required this.chargedMinor,
    required this.winningMinor,
    required this.initialMinor,
    required this.rateVersion,
  });

  final String status;
  final int chargedMinor;
  final int winningMinor;
  final int initialMinor;
  final String? rateVersion;

  factory SaleFeeView.fromJson(Map<String, Object?> json) => SaleFeeView(
    status: _string(json, 'status'),
    chargedMinor: _int(json, 'charged_minor', minimum: 0),
    winningMinor: _int(json, 'winning_minor', minimum: 0),
    initialMinor: _int(json, 'initial_minor', minimum: 0),
    rateVersion: _optString(json, 'rate_version'),
  );
}

class SaleHistoryEntryView {
  const SaleHistoryEntryView({
    required this.id,
    required this.side,
    required this.confirmedAt,
    required this.title,
    required this.priceMinor,
    required this.currency,
    required this.reward,
    required this.fee,
  });

  final String id;
  final SaleSide side;
  final DateTime confirmedAt;
  final String title;
  final int priceMinor;
  final String currency;
  final SaleRewardView? reward;
  final SaleFeeView? fee;

  factory SaleHistoryEntryView.fromJson(Map<String, Object?> json) {
    final side = _string(json, 'side');
    if (side == 'purchase') {
      return SaleHistoryEntryView(
        id: _string(json, 'id'),
        side: SaleSide.purchase,
        confirmedAt: _dateTime(json, 'confirmed_at'),
        title: _string(json, 'title'),
        priceMinor: _int(json, 'price_minor', minimum: 1),
        currency: _string(json, 'currency'),
        reward: switch (_optMap(json, 'reward')) {
          final Map<String, Object?> value => SaleRewardView.fromJson(value),
          null => null,
        },
        fee: null,
      );
    }
    if (side == 'sale') {
      return SaleHistoryEntryView(
        id: _string(json, 'id'),
        side: SaleSide.sale,
        confirmedAt: _dateTime(json, 'confirmed_at'),
        title: _string(json, 'title'),
        priceMinor: _int(json, 'price_minor', minimum: 1),
        currency: _string(json, 'currency'),
        reward: null,
        fee: switch (_optMap(json, 'fee')) {
          final Map<String, Object?> value => SaleFeeView.fromJson(value),
          null => null,
        },
      );
    }
    throw const CommercialContractError('bad_enum:sale_side');
  }
}

class DealSummaryView {
  const DealSummaryView({
    required this.completed,
    required this.active,
    required this.attention,
  });
  final int completed, active, attention;
  factory DealSummaryView.fromJson(Map<String, Object?> json) =>
      DealSummaryView(
        completed: _int(json, 'completed', minimum: 0),
        active: _int(json, 'active', minimum: 0),
        attention: _int(json, 'attention', minimum: 0),
      );
}

class SaleScheduleView {
  const SaleScheduleView({
    required this.date,
    required this.time,
    required this.timezone,
    required this.placeChoice,
    required this.placeLabel,
    required this.meetingExpiresAt,
  });

  final DateTime date;
  final String time;
  final String timezone;
  final String placeChoice;
  final String? placeLabel;
  final DateTime? meetingExpiresAt;

  factory SaleScheduleView.fromJson(Map<String, Object?> json) {
    final date = DateTime.tryParse(_string(json, 'date'));
    if (date == null) throw const CommercialContractError('bad_time:date');
    final time = _string(json, 'time');
    if (!RegExp(r'^\d{2}:\d{2}(:\d{2})?$').hasMatch(time)) {
      throw const CommercialContractError('bad_time:time');
    }
    return SaleScheduleView(
      date: DateTime.utc(date.year, date.month, date.day),
      time: time,
      timezone: _string(json, 'timezone'),
      placeChoice: _string(json, 'place_choice'),
      placeLabel: _optString(json, 'place_label'),
      meetingExpiresAt: _optDateTime(json, 'meeting_expires_at'),
    );
  }
}

class SaleDetailView {
  const SaleDetailView({
    required this.id,
    required this.side,
    required this.confirmedAt,
    required this.requestId,
    required this.offerId,
    required this.meetingId,
    required this.title,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.schedule,
    required this.reward,
    required this.fee,
    required this.itemPayment,
  });

  final String id;
  final SaleSide side;
  final DateTime confirmedAt;
  final String requestId;
  final String offerId;
  final String meetingId;
  final String title;
  final String description;
  final int priceMinor;
  final String currency;
  final SaleScheduleView schedule;
  final SaleRewardView? reward;
  final SaleFeeView? fee;
  final String itemPayment;

  factory SaleDetailView.fromJson(Map<String, Object?> json) {
    final side = _string(json, 'side');
    if (side != 'purchase' && side != 'sale') {
      throw const CommercialContractError('bad_enum:sale_side');
    }
    final itemPayment = _string(json, 'item_payment');
    if (itemPayment != 'offline') {
      throw const CommercialContractError('bad_item_payment');
    }
    return SaleDetailView(
      id: _string(json, 'id'),
      side: side == 'purchase' ? SaleSide.purchase : SaleSide.sale,
      confirmedAt: _dateTime(json, 'confirmed_at'),
      requestId: _string(json, 'request_id'),
      offerId: _string(json, 'offer_id'),
      meetingId: _string(json, 'meeting_id'),
      title: _string(json, 'title'),
      description: json['description'] is String
          ? json['description']! as String
          : '',
      priceMinor: _int(json, 'price_minor', minimum: 1),
      currency: _string(json, 'currency'),
      schedule: SaleScheduleView.fromJson(_map(json, 'schedule')),
      reward: switch (_optMap(json, 'reward')) {
        final Map<String, Object?> value => SaleRewardView.fromJson(value),
        null => null,
      },
      fee: switch (_optMap(json, 'fee')) {
        final Map<String, Object?> value => SaleFeeView.fromJson(value),
        null => null,
      },
      itemPayment: itemPayment,
    );
  }
}

// ---------------------------------------------------------------------------
// Entitlements
// ---------------------------------------------------------------------------

enum PlanCode { free, pro, elite }

const _planCodes = <String, PlanCode>{
  'free': PlanCode.free,
  'pro': PlanCode.pro,
  'elite': PlanCode.elite,
};

enum EntitlementSource { free, billing, admin, earned }

const _entitlementSources = <String, EntitlementSource>{
  'free': EntitlementSource.free,
  'billing': EntitlementSource.billing,
  'admin': EntitlementSource.admin,
  'earned': EntitlementSource.earned,
};

class PlanLimitView {
  const PlanLimitView({
    required this.planCode,
    required this.storeListingLimit,
    required this.weeklyTargetLimit,
  });

  final PlanCode planCode;
  final int storeListingLimit;
  final int weeklyTargetLimit;

  factory PlanLimitView.fromJson(Map<String, Object?> json) => PlanLimitView(
    planCode: _enumValue(_string(json, 'plan_code'), _planCodes, 'plan_code'),
    storeListingLimit: _int(json, 'store_listing_limit', minimum: 0),
    weeklyTargetLimit: _int(json, 'weekly_target_limit', minimum: 0),
  );
}

class EntitlementPolicyView {
  const EntitlementPolicyView({
    required this.revision,
    required this.version,
    required this.earnedProThreshold,
    required this.calendarConfigured,
    required this.calendarTimezone,
    required this.paidOverlapConfigured,
    required this.paidOverlap,
    required this.downgradeVisibilityConfigured,
    required this.downgradeVisibility,
    required this.annualEnabled,
    required this.trialDays,
  });

  final int revision;
  final String version;
  final int earnedProThreshold;
  final bool calendarConfigured;
  final String? calendarTimezone;
  final bool paidOverlapConfigured;
  final String? paidOverlap;
  final bool downgradeVisibilityConfigured;
  final String? downgradeVisibility;
  final bool annualEnabled;
  final int? trialDays;

  factory EntitlementPolicyView.fromJson(Map<String, Object?> json) =>
      EntitlementPolicyView(
        revision: _int(json, 'revision', minimum: 1),
        version: _string(json, 'version'),
        earnedProThreshold: _int(json, 'earned_pro_threshold', minimum: 1),
        calendarConfigured: _bool(json, 'calendar_configured'),
        calendarTimezone: _optString(json, 'calendar_timezone'),
        paidOverlapConfigured: _bool(json, 'paid_overlap_configured'),
        paidOverlap: _optString(json, 'paid_overlap'),
        downgradeVisibilityConfigured: _bool(
          json,
          'downgrade_visibility_configured',
        ),
        downgradeVisibility: _optString(json, 'downgrade_visibility'),
        annualEnabled: _bool(json, 'annual_enabled'),
        trialDays: _optInt(json, 'trial_days', minimum: 1),
      );
}

class BillingEntitlementView {
  const BillingEntitlementView({
    required this.available,
    required this.plan,
    required this.providerStatus,
    required this.paidUntil,
    required this.reviewRequired,
  });

  final bool available;
  final PlanCode? plan;
  final String? providerStatus;
  final DateTime? paidUntil;
  final bool reviewRequired;

  factory BillingEntitlementView.fromJson(Map<String, Object?> json) {
    final available = _bool(json, 'available');
    final rawPlan = _optString(json, 'plan');
    return BillingEntitlementView(
      available: available,
      plan: rawPlan == null
          ? null
          : _enumValue(rawPlan, _planCodes, 'billing_plan'),
      providerStatus: _optString(json, 'provider_status'),
      paidUntil: _optDateTime(json, 'paid_until'),
      reviewRequired: _bool(json, 'review_required'),
    );
  }
}

class AdminGrantView {
  const AdminGrantView({required this.available, required this.plan});

  final bool available;
  final PlanCode? plan;

  factory AdminGrantView.fromJson(Map<String, Object?> json) {
    final rawPlan = _optString(json, 'plan');
    return AdminGrantView(
      available: _bool(json, 'available'),
      plan: rawPlan == null
          ? null
          : _enumValue(rawPlan, _planCodes, 'admin_plan'),
    );
  }
}

class EarnedProWindowView {
  const EarnedProWindowView({required this.start, required this.sales});

  final DateTime start;
  final int sales;

  factory EarnedProWindowView.fromJson(Map<String, Object?> json) {
    final raw = _string(json, 'start');
    final start = DateTime.tryParse(raw);
    if (start == null) throw const CommercialContractError('bad_time:window');
    return EarnedProWindowView(
      start: DateTime.utc(start.year, start.month, start.day),
      sales: _int(json, 'sales', minimum: 0),
    );
  }
}

class EarnedProView {
  const EarnedProView({
    required this.configured,
    required this.unavailableReason,
    required this.threshold,
    required this.timezone,
    required this.currentWindow,
    required this.qualifyingWindow,
    required this.plan,
    required this.applied,
    required this.overlapUnconfigured,
  });

  final bool configured;
  final String? unavailableReason;
  final int threshold;
  final String? timezone;
  final EarnedProWindowView? currentWindow;
  final EarnedProWindowView? qualifyingWindow;
  final PlanCode? plan;
  final bool applied;
  final bool overlapUnconfigured;

  factory EarnedProView.fromJson(Map<String, Object?> json) {
    final configured = _bool(json, 'configured');
    final reason = _optString(json, 'unavailable_reason');
    if (configured && reason == null && json['current_window'] == null) {
      throw const CommercialContractError('earned_window_missing');
    }
    final rawPlan = _optString(json, 'plan');
    return EarnedProView(
      configured: configured,
      unavailableReason: reason,
      threshold: _int(json, 'threshold', minimum: 1),
      timezone: _optString(json, 'timezone'),
      currentWindow: json['current_window'] == null
          ? null
          : EarnedProWindowView.fromJson(_map(json, 'current_window')),
      qualifyingWindow: json['qualifying_window'] == null
          ? null
          : EarnedProWindowView.fromJson(_map(json, 'qualifying_window')),
      plan: rawPlan == null
          ? null
          : _enumValue(rawPlan, _planCodes, 'earned_plan'),
      applied: _bool(json, 'applied'),
      overlapUnconfigured: _bool(json, 'overlap_unconfigured'),
    );
  }
}

class StoreListingUsageView {
  const StoreListingUsageView({required this.limit, required this.active});

  final int limit;
  final int active;

  factory StoreListingUsageView.fromJson(Map<String, Object?> json) =>
      StoreListingUsageView(
        limit: _int(json, 'limit', minimum: 0),
        active: _int(json, 'active', minimum: 0),
      );
}

class SellerEntitlementView {
  const SellerEntitlementView({
    required this.effectivePlan,
    required this.effectiveSource,
    required this.policy,
    required this.billing,
    required this.admin,
    required this.earned,
    required this.annualAvailable,
    required this.trialAvailable,
    required this.trialDays,
    required this.storeListing,
    required this.plans,
  });

  final PlanCode effectivePlan;
  final EntitlementSource effectiveSource;
  final EntitlementPolicyView policy;
  final BillingEntitlementView billing;
  final AdminGrantView admin;
  final EarnedProView earned;
  final bool annualAvailable;
  final bool trialAvailable;
  final int? trialDays;
  final StoreListingUsageView storeListing;
  final List<PlanLimitView> plans;

  factory SellerEntitlementView.fromJson(Map<String, Object?> json) {
    if (_string(json, 'role') != 'seller') {
      throw const CommercialContractError('bad_role');
    }
    final annual = _map(json, 'annual');
    final trial = _map(json, 'trial');
    final view = SellerEntitlementView(
      effectivePlan: _enumValue(
        _string(json, 'effective_plan'),
        _planCodes,
        'effective_plan',
      ),
      effectiveSource: _enumValue(
        _string(json, 'effective_source'),
        _entitlementSources,
        'effective_source',
      ),
      policy: EntitlementPolicyView.fromJson(_map(json, 'policy')),
      billing: BillingEntitlementView.fromJson(
        _map(_map(json, 'verified'), 'billing'),
      ),
      admin: AdminGrantView.fromJson(_map(_map(json, 'verified'), 'admin')),
      earned: EarnedProView.fromJson(_map(_map(json, 'verified'), 'earned')),
      annualAvailable: _bool(annual, 'available'),
      trialAvailable: _bool(trial, 'available'),
      trialDays: _optInt(trial, 'days', minimum: 1),
      storeListing: StoreListingUsageView.fromJson(_map(json, 'store_listing')),
      plans: _rows(
        json,
        'plans',
      ).map(PlanLimitView.fromJson).toList(growable: false),
    );
    if (view.effectivePlan == PlanCode.free &&
        view.effectiveSource != EntitlementSource.free) {
      throw const CommercialContractError('entitlement_shape');
    }
    if (view.trialAvailable && view.trialDays == null) {
      throw const CommercialContractError('trial_shape');
    }
    return view;
  }
}

class DowngradePreviewView {
  const DowngradePreviewView({
    required this.policyConfigured,
    required this.policy,
    required this.unavailableReason,
    required this.wouldHideExisting,
    required this.wouldBlockNewPublishes,
  });

  final bool policyConfigured;
  final String? policy;
  final String? unavailableReason;
  final bool? wouldHideExisting;
  final bool? wouldBlockNewPublishes;

  factory DowngradePreviewView.fromJson(Map<String, Object?> json) =>
      DowngradePreviewView(
        policyConfigured: _bool(json, 'policy_configured'),
        policy: _optString(json, 'policy'),
        unavailableReason: _optString(json, 'unavailable_reason'),
        wouldHideExisting: _optBool(json, 'would_hide_existing'),
        wouldBlockNewPublishes: _optBool(json, 'would_block_new_publishes'),
      );
}

class PlanPreviewView {
  const PlanPreviewView({
    required this.planCode,
    required this.storeListingLimit,
    required this.weeklyTargetLimit,
    required this.activeListings,
    required this.overLimit,
    required this.downgrade,
    required this.annualAvailable,
    required this.annualAmountMinor,
    required this.trialAvailable,
    required this.trialDays,
  });

  final PlanCode planCode;
  final int storeListingLimit;
  final int weeklyTargetLimit;
  final int activeListings;
  final bool overLimit;
  final DowngradePreviewView downgrade;
  final bool annualAvailable;
  final int? annualAmountMinor;
  final bool trialAvailable;
  final int? trialDays;

  factory PlanPreviewView.fromJson(Map<String, Object?> json) =>
      PlanPreviewView(
        planCode: _enumValue(
          _string(json, 'plan_code'),
          _planCodes,
          'plan_code',
        ),
        storeListingLimit: _int(json, 'store_listing_limit', minimum: 0),
        weeklyTargetLimit: _int(json, 'weekly_target_limit', minimum: 0),
        activeListings: _int(json, 'active_listings', minimum: 0),
        overLimit: _bool(json, 'over_limit'),
        downgrade: DowngradePreviewView.fromJson(_map(json, 'downgrade')),
        annualAvailable: _bool(_map(json, 'annual'), 'available'),
        annualAmountMinor: _optInt(
          _map(json, 'annual'),
          'amount_minor',
          minimum: 1,
        ),
        trialAvailable: _bool(_map(json, 'trial'), 'available'),
        trialDays: _optInt(_map(json, 'trial'), 'days', minimum: 1),
      );
}
