import 'package:supabase_flutter/supabase_flutter.dart';
import '../marketplace/marketplace_composition.dart';
import 'support_adapter.dart';

SupportAdapter createSupportAdapter() {
  final marketplace = createMarketplaceDataAdapter(
    client: Supabase.instance.client,
  );
  return SupportAdapter(
    transport: marketplace.transport,
    session: marketplace.session,
  );
}
