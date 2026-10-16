import '../marketplace/marketplace_transport.dart';
import '../marketplace/marketplace_session.dart';
import '../accounts/timestamptz.dart';

class SaleConfirmationResult {
  const SaleConfirmationResult(this.status, {this.pin, this.expiresAt});
  final String status;
  final String? pin;
  final DateTime? expiresAt;
  @override
  String toString() => 'SaleConfirmationResult($status, redacted)';
}

class SaleConfirmationAdapter {
  SaleConfirmationAdapter({required this.transport, required this.session});
  final MarketplaceTransport transport;
  final MarketplaceSession session;
  Future<SaleConfirmationResult> call(
    String meeting,
    String action, {
    String? pin,
  }) async {
    final user = session.currentUserId;
    if (user == null) throw StateError('signed_out');
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: 'hocalist',
        function: 'sale_pin',
        params: {'p_meeting': meeting, 'p_action': action, 'p_pin': pin},
      ),
    );
    if (session.currentUserId != user) throw StateError('session_changed');
    if (response is! MarketplaceTransportData || response.data is! Map) {
      throw StateError('sale_unavailable');
    }
    final data = response.data as Map;
    final status = data['status'];
    if (!const {
      'ready',
      'confirmed',
      'unconfirmed',
      'completed_elsewhere',
      'meeting_not_accepted',
      'expired',
      'buyer_must_open_pin',
      'purchase_seller_required',
      'support_required',
      'locked',
      'invalid_format',
      'incorrect',
    }.contains(status)) {
      throw StateError('invalid_response');
    }
    if (status == 'confirmed' &&
        (data['outcome_id'] is! String ||
            !RegExp(
              r'^[a-f0-9-]{36}$',
            ).hasMatch(data['outcome_id'] as String) ||
            DateTime.tryParse(data['confirmed_at']?.toString() ?? '') ==
                null)) {
      throw StateError('invalid_response');
    }
    if (status == 'ready') {
      final value = data['pin'];
      final expiry = parsePostgresTimestamptz(
        data['expires_at']?.toString() ?? '',
        context: 'sale.expires_at',
      );
      if (action != 'display' ||
          value is! String ||
          !RegExp(r'^\d{5}$').hasMatch(value)) {
        throw StateError('invalid_response');
      }
      return SaleConfirmationResult(
        status as String,
        pin: value,
        expiresAt: expiry.toUtc(),
      );
    }
    return SaleConfirmationResult(status as String);
  }
}
