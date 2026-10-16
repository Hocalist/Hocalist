/// Phase 2 typed marketplace foundations for Hocalist.
///
/// Pure Dart domain models, commands, typed failures and repository contracts
/// for profiles, requests, offers, conversations and meetings. Nothing in
/// this library talks to Supabase, Stripe, storage or any provider, and no
/// screen is wired to it yet.
library;

// Commercial completion (package 06-commercial): authoritative credit/reward
// wallet, sale drill-down and seller entitlement view contracts. The adapters
// live under lib/data/phase2/commercial/ and are imported directly.
export 'commercial/commercial.dart';

export 'account_contacts.dart';
export 'accounts.dart';
export 'catalogue.dart';
export 'common.dart';
export 'conversations.dart';
export 'failures.dart';
export 'media_reference.dart';
export 'meetings.dart';
export 'money.dart';
export 'offers.dart';
export 'patch.dart';
export 'profiles.dart';
export 'repositories.dart';
export 'requests.dart';
export 'schedule.dart';
export 'store_listings.dart';
