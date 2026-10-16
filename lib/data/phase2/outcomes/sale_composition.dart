import 'package:supabase_flutter/supabase_flutter.dart';
import '../marketplace/marketplace_composition.dart';
import 'sale_confirmation.dart';

SaleConfirmationAdapter createSaleConfirmationAdapter() {
  final marketplace = createMarketplaceDataAdapter(
    client: Supabase.instance.client,
  );
  return SaleConfirmationAdapter(
    transport: marketplace.transport,
    session: marketplace.session,
  );
}
