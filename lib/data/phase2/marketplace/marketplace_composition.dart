/// Composition entry point for the SQL-draft-backed marketplace data layer.
///
/// Pass the app's authenticated official `SupabaseClient`. The adapter is a
/// cheap wrapper; recreate it per session composition rather than caching it
/// across account changes.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../local_marketplace_repository.dart';
import '../chat/chat_adapter.dart';
import '../chat/chat_composition.dart';
import 'marketplace_adapter.dart';
import 'marketplace_buyer_offers_backend.dart';
import 'marketplace_chat_backend.dart';
import 'marketplace_error_mapper.dart';
import 'marketplace_leads_backend.dart';
import 'marketplace_offers_backend.dart';
import 'marketplace_requests_backend.dart';
import 'marketplace_seller_offers_backend.dart';
import 'marketplace_store_backend.dart';
import 'marketplace_saved_backend.dart';
import 'supabase_marketplace_session.dart';
import 'supabase_marketplace_transport.dart';

MarketplaceDataAdapter createMarketplaceDataAdapter({
  required SupabaseClient client,
  MarketplaceErrorMapper errorMapper = const MarketplaceErrorMapper(),
}) {
  return MarketplaceDataAdapter(
    transport: SupabaseMarketplaceTransport(client),
    session: SupabaseMarketplaceSession(client),
    errorMapper: errorMapper,
  );
}

MarketplaceSavedBackend? createConfiguredSavedBackend(String userId) {
  try {
    return MarketplaceSavedBackend(
      createMarketplaceDataAdapter(client: Supabase.instance.client),
      userId,
    );
  } catch (_) {
    return null;
  }
}

/// The marketplace-backed conversation repository: chat reads stay on the chat
/// adapter, while opening a deal or discovery-enquiry conversation goes through
/// the server-side marketplace eligibility commands.
MarketplaceConversationRepository createMarketplaceConversationRepository({
  required SupabaseClient client,
  required ChatDataAdapter chat,
}) {
  return MarketplaceConversationRepository(
    chat: chat,
    opener: MarketplaceConversationOpener(
      transport: SupabaseMarketplaceTransport(client),
      session: SupabaseMarketplaceSession(client),
    ),
    enquiryOpener: MarketplaceDiscoveryEnquiryOpener(
      transport: SupabaseMarketplaceTransport(client),
      session: SupabaseMarketplaceSession(client),
    ),
  );
}

/// Store backend for the approved seller Store screen when a real Supabase
/// session is configured. Returns null in prototype mode or before Supabase
/// initialization so the screens keep their local data.
MarketplaceStoreBackend? createConfiguredMarketplaceStoreBackend({
  required String sellerUserId,
}) {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceStoreBackend(
      adapter: createMarketplaceDataAdapter(client: client),
      sellerUserId: sellerUserId,
    );
  } catch (_) {
    return null;
  }
}

/// Leads backend for the approved seller Leads screen when a real Supabase
/// session is configured. Returns null in prototype mode.
MarketplaceLeadsBackend? createConfiguredMarketplaceLeadsBackend({
  required String sellerUserId,
}) {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceLeadsBackend(
      adapter: createMarketplaceDataAdapter(client: client),
      sellerUserId: sellerUserId,
    );
  } catch (_) {
    return null;
  }
}

/// Offers backend for the approved seller offer form when a real Supabase
/// session is configured. Returns null in prototype mode.
MarketplaceOffersBackend? createConfiguredMarketplaceOffersBackend() {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceOffersBackend(
      adapter: createMarketplaceDataAdapter(client: client),
    );
  } catch (_) {
    return null;
  }
}

/// Requests backend for the approved buyer create/edit forms when a real
/// Supabase session is configured. Returns null in prototype mode.
MarketplaceRequestsBackend? createConfiguredMarketplaceRequestsBackend({
  required String buyerUserId,
}) {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceRequestsBackend(
      adapter: createMarketplaceDataAdapter(client: client),
      buyerUserId: buyerUserId,
    );
  } catch (_) {
    return null;
  }
}

/// Buyer offers backend for the offers list/selection screens when a real
/// Supabase session is configured. Returns null in prototype mode.
MarketplaceBuyerOffersBackend? createConfiguredMarketplaceBuyerOffersBackend() {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceBuyerOffersBackend(
      adapter: createMarketplaceDataAdapter(client: client),
    );
  } catch (_) {
    return null;
  }
}

/// Chat backend for the inbox and thread screens when a real Supabase session
/// is configured. Returns null in prototype mode. [chatAttachmentsEnabled]
/// stays false until the reviewed attachment RPC is deployed; the picker reads
/// the repository capability instead of assuming it.
MarketplaceChatBackend? createConfiguredMarketplaceChatBackend({
  required String userId,
  bool chatAttachmentsEnabled = const bool.fromEnvironment('HOCALIST_CHAT_ATTACHMENTS'),
}) {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceChatBackend(
      identity: () => client.auth.currentUser?.id,
      requestReader: createMarketplaceDataAdapter(
        client: client,
      ).fetchSellerRequest,
      offers: createMarketplaceDataAdapter(client: client),
      conversations: createMarketplaceConversationRepository(
        client: client,
        chat: createChatDataAdapter(client: client),
      ),
      currentUserId: userId,
      attachmentsEnabled: chatAttachmentsEnabled,
    );
  } catch (_) {
    return null;
  }
}

/// Seller offers backend for the offer history/detail screens when a real
/// Supabase session is configured. Returns null in prototype mode.
MarketplaceSellerOffersBackend? createConfiguredMarketplaceSellerOffersBackend({
  required String sellerUserId,
}) {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceSellerOffersBackend(
      adapter: createMarketplaceDataAdapter(client: client),
      sellerUserId: sellerUserId,
    );
  } catch (_) {
    return null;
  }
}
