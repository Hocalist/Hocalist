export type WebsiteRoute =
  | 'home'
  | 'how-it-works'
  | 'pricing'
  | 'download'
  | 'support'
  | 'safety'
  | 'terms'
  | 'privacy'
  | 'refund-cancellation'
  | 'billing'
  | 'billing-return'
  | 'billing-cancel';

export type AppProposalSurface =
  | 'location-map'
  | 'account-health'
  | 'account-security-recovery'
  | 'rewards-ledger'
  | 'credit-wallet'
  | 'withdrawals'
  | 'sale-history'
  | 'support-reporting'
  | 'media-picker'
  | 'store-catalog';

export type ViewportMode = 'desktop' | 'tablet' | 'mobile-430' | 'mobile-390' | 'mobile-360' | 'mobile-320';

export type TextScale = '1.0' | '1.15' | '1.3' | '1.6';

export type SurfaceState = 'default' | 'loading' | 'empty' | 'unavailable' | 'error';

export interface RouteMeta {
  id: WebsiteRoute;
  label: string;
  path: string;
  category: 'public' | 'legal' | 'billing';
  description: string;
}

export const WEBSITE_ROUTES: RouteMeta[] = [
  { id: 'home', label: 'Homepage', path: '/', category: 'public', description: 'Composed hero, marketplace proof, interactive demo, categories, seller value, FAQ' },
  { id: 'how-it-works', label: 'How It Works', path: '/how-it-works', category: 'public', description: 'Step-by-step buyer and seller reverse marketplace walkthrough and 5-digit PIN mechanics' },
  { id: 'pricing', label: 'Seller Plans & Credits', path: '/pricing', category: 'public', description: 'Free, Pro ($15), Elite ($30), FIFO deposit batches ($20/$40), billing boundaries' },
  { id: 'download', label: 'Download & Waitlist', path: '/download', category: 'public', description: 'App preview, interactive consented waitlist form, QR code for testing' },
  { id: 'support', label: 'Support & Inquiries', path: '/support', category: 'public', description: 'Direct contact channels, interactive support intake form, FAQ' },
  { id: 'safety', label: 'Safety & Offline Meetups', path: '/safety', category: 'public', description: 'In-person meeting rules, safe exchange zones, item inspection, PIN verification' },
  { id: 'terms', label: 'Terms of Service', path: '/terms', category: 'legal', description: 'Reverse marketplace obligations, user-arranged offline payments, seller fees' },
  { id: 'privacy', label: 'Privacy Policy', path: '/privacy', category: 'legal', description: 'Location privacy, Stripe billing scope, data retention & deletion' },
  { id: 'refund-cancellation', label: 'Refund & Cancellation', path: '/refund-cancellation', category: 'legal', description: 'Stripe subscription cancellations, credit deposits, offline sale boundaries' },
  { id: 'billing', label: 'Billing Portal (Catalogue & Sign-In)', path: '/billing', category: 'billing', description: 'Seller sign-in, recovery modal, active subscription, credit batches, Stripe portal' },
  { id: 'billing-return', label: 'Checkout Return (Authoritative Status)', path: '/billing/return', category: 'billing', description: 'Post-checkout return verification, pending re-check, entitlement refresh' },
  { id: 'billing-cancel', label: 'Checkout Cancelled', path: '/billing/cancel', category: 'billing', description: 'Reassuring departure notice, no charges made, return to catalogue' }
];

export interface AppProposalMeta {
  id: AppProposalSurface;
  title: string;
  category: string;
  description: string;
}

export const APP_PROPOSALS: AppProposalMeta[] = [
  { id: 'location-map', title: 'Location, Map & Directions Sheet', category: 'Buyer/Seller', description: 'US-first place search, private coordinates, manual fallback, safe meetup spot suggestions' },
  { id: 'account-health', title: 'Seller Account Health & Policy', category: 'Seller', description: 'Replaces fixed 17-bar prototype with factual evaluation window, health states, and appeal route' },
  { id: 'account-security-recovery', title: 'Account Security, Recovery & Auth Gate', category: 'Buyer/Seller', description: 'Role toggle, OTP recovery, linked identities, password reset, account deletion flow' },
  { id: 'rewards-ledger', title: 'Buyer Rewards Ledger & History', category: 'Buyer', description: 'Earned vs pending vs withdrawn ledger, $0.15 regular / $0.30 late window rules' },
  { id: 'credit-wallet', title: 'Seller Credit Wallet & FIFO Batches', category: 'Seller', description: 'Deposit batches ($20/$40), rate snapshots, reservations, weekly customer target counter' },
  { id: 'withdrawals', title: 'Buyer Cash Withdrawals Flow', category: 'Buyer', description: '$20 minimum, $2.50 processing deduction, verified recipient check, failure reconciliation' },
  { id: 'sale-history', title: 'Verified Sale History & Purchase Outcomes', category: 'Buyer/Seller', description: 'PIN-confirmed transactions, agreed offline prices, receipt, review eligibility' },
  { id: 'support-reporting', title: 'Support Case Filing & Issue Reporting', category: 'Buyer/Seller', description: 'Contextual reporting from chat/deal, subject tagging, evidence upload, case tracking' },
  { id: 'media-picker', title: 'Upload, Camera & Media Manager', category: 'Buyer/Seller', description: 'Image selection, crop/preview, upload progress, removal, participant-only privacy' },
  { id: 'store-catalog', title: 'Store Catalog Category & Listing Sheet', category: 'Seller', description: 'Admin-managed categories, product/service variant, published vs draft vs pause status' }
];
