import type { FinanceReport } from './finance-report';

export const financePreview: FinanceReport = {
  processingGross: 6400,
  months: [
    [6, 118, 270, 132, 42, 35, 96, 132, 340, 54, 3, 19, 28, 11, 13],
    [7, 156, 310, 165, 49, 42, 116, 132, 385, 68, 4, 24, 31, 14, 16],
    [8, 182, 390, 180, 58, 37, 149, 132, 418, 82, 5, 28, 36, 16, 18],
    [9, 210, 410, 225, 63, 53, 178, 138, 507, 97, 5, 33, 45, 20, 22],
    [10, 248, 475, 270, 74, 66, 209, 138, 590, 119, 6, 40, 54, 26, 26],
    [11, 279, 505, 292, 82, 103, 229, 146, 603, 143, 7, 47, 60, 32, 30],
  ].map(([month, subscriptions, targeting, confirmation, stripeFees, refunds, rewardsEarned,
    overhead, deposits, paidNet, paidBuyers, confirmedPurchases, buyersWithOffers,
    buyersRewarded, sellersClosingDeals]) => ({
    month: `2026-${String(month).padStart(2, '0')}`,
    deposits: deposits * 100,
    paidNet: paidNet * 100,
    paidBuyers,
    payoutCount: paidBuyers + 1,
    payoutDeductions: (paidBuyers + 1) * 250,
    revision: 0,
    totals: {
      subscriptions: subscriptions * 100, targeting: targeting * 100, confirmation: confirmation * 100,
      stripeFees: stripeFees * 100, refunds: refunds * 100, rewardsEarned: rewardsEarned * 100,
      overhead: overhead * 100,
    },
    note: 'Example totals for the preview.',
    planContributions: {
      Free: (targeting - refunds - 80) * 41,
      Pro: (subscriptions + confirmation + targeting - stripeFees - rewardsEarned) * 34,
      Elite: (subscriptions + confirmation - refunds) * 38,
    },
    impact: {
      confirmedPurchases, buyersWithOffers, buyersRewarded, sellersClosingDeals,
      sellersReachingBuyers: sellersClosingDeals + 8,
      creditsReturned: refunds * 60,
      belowMinimum: buyersRewarded * 350,
      readyToWithdraw: buyersRewarded * 210,
    },
  })),
};
