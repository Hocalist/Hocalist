// Synthetic commercial payload builders for the wallet/entitlement tests.
//
// These mirror the reviewed `commercial_completion` server JSON exactly so the
// domain decoders and panels are exercised without a live database.
Map<String, Object?> creditWalletJson({
  int balance = 5470,
  int reserved = 220,
  int charged = 530,
  int deposited = 6000,
  int reversalHold = 0,
  bool optionsConfigured = false,
  int used = 2,
  int limit = 10,
  List<Map<String, Object?>>? batches,
  List<Map<String, Object?>>? targets,
  List<Map<String, Object?>>? options,
}) => {
  'currency': 'HC',
  'balance_minor': balance,
  'reserved_minor': reserved,
  'available_minor': balance - reserved,
  'charged_minor': charged,
  'deposited_minor': deposited,
  'reversal_hold_minor': reversalHold,
  'weekly': {
    'week_start': '2026-09-21',
    'used': used,
    'limit': limit,
  },
  'deposit_options': options ?? const [],
  'batches': batches ??
      [
        batchJson(),
        batchJson(
          id: 'bt-2',
          original: 2000,
          balance: 1845,
          reserved: 220,
          charged: 155,
          initial: 155,
          winning: 375,
          rateVersion: 'v20',
        ),
      ],
  'targets': targets ??
      [
        targetJson(),
      ],
  'policy': {'deposit_options_configured': optionsConfigured, 'weekly_limit_resolved': limit},
};

Map<String, Object?> batchJson({
  String id = 'bt-1',
  int original = 4000,
  int balance = 3625,
  int reserved = 0,
  int charged = 375,
  int initial = 155,
  int winning = 375,
  String rateVersion = 'v40',
}) => {
  'id': id,
  'original_minor': original,
  'balance_minor': balance,
  'reserved_minor': reserved,
  'available_minor': balance - reserved,
  'charged_minor': charged,
  'initial_fee_minor': initial,
  'winning_total_minor': winning,
  'rate_version': rateVersion,
  'created_at': '2026-09-01T12:00:00Z',
};

Map<String, Object?> targetJson({
  String id = 'tg-1',
  String status = 'initial_charged',
  int charged = 155,
  int reserved = 220,
  String? title = 'Sold camera',
}) => {
  'id': id,
  'request_id': 'req-1',
  'request_title': title,
  'offer_id': 'off-1',
  'status': status,
  'initial_minor': 155,
  'winning_minor': 375,
  'charged_minor': charged,
  'reserved_minor': reserved,
  'week_start': '2026-09-21',
  'rate_version': 'v20',
  'qualified_at': '2026-09-22T12:00:00Z',
  'created_at': '2026-09-21T12:00:00Z',
};

Map<String, Object?> rewardWalletJson({
  int earned = 15,
  int? held,
  int pending = 15,
  int hold = 0,
  int withdrawalHold = 0,
  int reversed = 0,
  int shortfall = 0,
  int processing = 0,
  int paid = 0,
  bool policyConfigured = true,
  bool withdrawalConfigured = true,
  bool providerConfigured = false,
  bool executionEnabled = false,
  bool emailVerified = true,
  bool phoneVerified = true,
  bool rewardHoldConfigured = false,
  bool clawbackConfigured = false,
  List<Map<String, Object?>>? items,
}) {
  final computedHeld = pending + hold + withdrawalHold;
  final computedAvailable =
      earned - processing - paid - hold - withdrawalHold - reversed;
  return {
    'currency': 'USD',
    'earned_minor': earned,
    'held_minor': held ?? computedHeld,
    'pending_minor': pending,
    'hold_minor': hold,
    'withdrawal_hold_minor': withdrawalHold,
    'reversed_minor': reversed,
    'shortfall_minor': shortfall,
    'processing_minor': processing,
    'paid_minor': paid,
    'available_minor': computedAvailable > 0 ? computedAvailable : 0,
    'reward_policy_configured': policyConfigured,
    'normal_minor': policyConfigured ? 15 : null,
    'late_minor': policyConfigured ? 30 : null,
    'late_window_hours': policyConfigured ? 12 : null,
    'withdrawal': {
      'configured': withdrawalConfigured,
      'minimum_minor': withdrawalConfigured ? 2000 : null,
      'fee_minor': withdrawalConfigured ? 250 : null,
      'email_verified': emailVerified,
      'phone_verified': phoneVerified,
    },
    'payout': {
      'provider_configured': providerConfigured,
      'execution_enabled': executionEnabled,
      'provider_neutral': true,
    },
    'reversal_policy': {
      'clawback_mode_configured': clawbackConfigured,
      'reward_hold_configured': rewardHoldConfigured,
    },
    'items': items ??
        [
          {
            'id': 'rw-1',
            'amount_minor': 15,
            'created_at': '2026-09-23T12:00:00Z',
            'status': hold > 0 || reversed > 0 ? 'held' : 'earned',
            'hold_minor': hold,
            'reversed_minor': reversed,
            'shortfall_minor': shortfall,
            'item_title': 'Sold laptop',
          },
          {
            'id': 'rw-2',
            'amount_minor': 15,
            'created_at': '2026-09-24T12:00:00Z',
            'status': 'held',
            'hold_minor': 0,
            'reversed_minor': 0,
            'shortfall_minor': 0,
            'item_title': 'Sold camera',
          },
        ],
  };
}

Map<String, Object?> saleHistoryPurchaseJson({String id = 'so-2'}) => {
  'id': id,
  'side': 'purchase',
  'confirmed_at': '2026-09-25T12:00:00Z',
  'title': 'Sold camera',
  'price_minor': 15000,
  'currency': 'USD',
  'reward': {'status': 'held', 'amount_minor': 15, 'rule_version': 'reward-v1'},
};

Map<String, Object?> saleHistorySaleJson({String id = 'so-1'}) => {
  'id': id,
  'side': 'sale',
  'confirmed_at': '2026-09-24T12:00:00Z',
  'title': 'Sold laptop',
  'price_minor': 42000,
  'currency': 'USD',
  'fee': {
    'status': 'won',
    'charged_minor': 375,
    'winning_minor': 375,
    'initial_minor': 155,
    'rate_version': 'v40',
  },
};

Map<String, Object?> saleDetailJson({String id = 'so-1', String side = 'sale'}) => {
  'id': id,
  'side': side,
  'confirmed_at': '2026-09-24T12:00:00Z',
  'request_id': 'req-1',
  'offer_id': 'off-1',
  'meeting_id': 'meet-1',
  'title': 'Sold laptop',
  'description': 'Good condition',
  'price_minor': 42000,
  'currency': 'USD',
  'schedule': {
    'date': '2026-11-05',
    'time': '18:30:00',
    'timezone': 'America/New_York',
    'place_choice': 'specific_place',
    'place_label': 'Synthetic place',
    'meeting_expires_at': '2026-11-06T04:00:00Z',
  },
  'reward': side == 'purchase'
      ? {'status': 'earned', 'amount_minor': 15, 'rule_version': 'reward-v1'}
      : null,
  'fee': side == 'sale'
      ? {
          'status': 'won',
          'charged_minor': 375,
          'winning_minor': 375,
          'initial_minor': 155,
          'rate_version': 'v40',
        }
      : null,
  'item_payment': 'offline',
};

Map<String, Object?> entitlementJson({
  String effectivePlan = 'free',
  String effectiveSource = 'free',
  bool calendarConfigured = false,
  String calendarTimezone = 'UTC',
  bool overlapConfigured = false,
  String paidOverlap = 'highest_priority',
  bool downgradeConfigured = false,
  String downgradePolicy = 'keep_existing_block_new',
  bool annualEnabled = false,
  int trialDays = 14,
  bool earnedApplied = false,
  bool overlapUnconfigured = false,
  String? billingPlan,
  String? adminPlan,
  int qualifyingSales = 7,
  int currentSales = 0,
  int storeLimit = 3,
  int activeListings = 0,
}) => {
  'role': 'seller',
  'effective_plan': effectivePlan,
  'effective_source': effectiveSource,
  'policy': {
    'revision': 1,
    'version': 'threshold-only-v1',
    'earned_pro_threshold': 7,
    'calendar_configured': calendarConfigured,
    'calendar_timezone': calendarConfigured ? calendarTimezone : null,
    'paid_overlap_configured': overlapConfigured,
    'paid_overlap': overlapConfigured ? paidOverlap : null,
    'downgrade_visibility_configured': downgradeConfigured,
    'downgrade_visibility': downgradeConfigured ? downgradePolicy : null,
    'annual_enabled': annualEnabled,
    'trial_days': trialDays,
  },
  'verified': {
    'billing': {
      'available': billingPlan != null,
      'plan': billingPlan,
      'provider_status': billingPlan == null ? null : 'active',
      'paid_until': billingPlan == null ? null : '2026-10-20T00:00:00Z',
      'review_required': false,
    },
    'admin': {'available': adminPlan != null, 'plan': adminPlan},
    'earned': {
      'configured': calendarConfigured,
      'unavailable_reason': calendarConfigured ? null : 'calendar_unconfigured',
      'threshold': 7,
      'timezone': calendarConfigured ? calendarTimezone : null,
      'current_window': calendarConfigured
          ? {'start': '2026-09-01', 'sales': currentSales}
          : null,
      'qualifying_window': calendarConfigured
          ? {'start': '2026-08-01', 'sales': qualifyingSales}
          : null,
      'plan': qualifyingSales >= 7 && calendarConfigured ? 'pro' : null,
      'applied': earnedApplied,
      'overlap_unconfigured': overlapUnconfigured,
    },
  },
  'annual': {'available': annualEnabled},
  'trial': {'available': true, 'days': trialDays},
  'store_listing': {'limit': storeLimit, 'active': activeListings},
  'plans': [
    {'plan_code': 'free', 'store_listing_limit': 3, 'weekly_target_limit': 10},
    {'plan_code': 'pro', 'store_listing_limit': 15, 'weekly_target_limit': 50},
    {'plan_code': 'elite', 'store_listing_limit': 50, 'weekly_target_limit': 100},
  ],
};

Map<String, Object?> planPreviewJson({
  String plan = 'free',
  bool downgradeConfigured = false,
  bool overLimit = true,
}) => {
  'plan_code': plan,
  'store_listing_limit': plan == 'free' ? 3 : (plan == 'pro' ? 15 : 50),
  'weekly_target_limit': plan == 'free' ? 10 : (plan == 'pro' ? 50 : 100),
  'active_listings': overLimit ? 4 : 1,
  'over_limit': overLimit,
  'downgrade': {
    'policy_configured': downgradeConfigured,
    'policy': downgradeConfigured ? 'keep_existing_block_new' : null,
    'unavailable_reason': downgradeConfigured ? null : 'downgrade_policy_unconfigured',
    'would_hide_existing': null,
    'would_block_new_publishes': downgradeConfigured ? overLimit : null,
  },
  'annual': {'available': false, 'amount_minor': null},
  'trial': {'available': false, 'days': null},
};
