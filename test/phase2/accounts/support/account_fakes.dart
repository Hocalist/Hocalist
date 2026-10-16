/// Synthetic account transport/session fakes and wire-row builders.
///
/// Deterministic, offline and shared by the account data-layer tests.
library;

import 'package:hocalist/data/phase2/accounts/account_session.dart';
import 'package:hocalist/data/phase2/accounts/account_transport.dart';

class FakeAccountSession implements AccountSession {
  FakeAccountSession(this.currentUserId);

  @override
  String? currentUserId;
}

/// One recorded `account_command` call.
class RecordedAccountCommand {
  const RecordedAccountCommand({
    required this.schema,
    required this.function,
    required this.operation,
    required this.key,
    required this.input,
  });

  final String schema;
  final String function;
  final String operation;
  final String key;
  final Map<String, Object?> input;
}

class FakeAccountTransport implements AccountTransport {
  final List<AccountTableQuery> selectQueries = <AccountTableQuery>[];
  final List<RecordedAccountCommand> commands = <RecordedAccountCommand>[];

  AccountTransportResponse Function(AccountTableQuery query)? onSelect;
  AccountTransportResponse Function(RecordedAccountCommand command)? onCommand;

  int get selectCallCount => selectQueries.length;

  int get commandCallCount => commands.length;

  @override
  Future<AccountTransportResponse> selectRows(AccountTableQuery query) async {
    selectQueries.add(query);
    return onSelect?.call(query) ?? const AccountTransportData(<Object?>[]);
  }

  @override
  Future<AccountTransportResponse> callAccountCommand({
    required String schema,
    required String function,
    required String operation,
    required String key,
    required Map<String, Object?> input,
  }) async {
    final command = RecordedAccountCommand(
      schema: schema,
      function: function,
      operation: operation,
      key: key,
      input: Map<String, Object?>.unmodifiable(input),
    );
    commands.add(command);
    return onCommand?.call(command) ??
        const AccountTransportData(<String, Object?>{});
  }
}

const String syntheticUserId = '22222222-2222-2222-2222-222222222222';
const String syntheticOtherUserId = '44444444-4444-4444-4444-444444444444';
const String syntheticMembershipId = '11111111-1111-1111-1111-111111111111';
const String syntheticSellerMembershipId =
    '33333333-3333-3333-3333-333333333333';

Map<String, Object?> membershipRow({
  String id = syntheticMembershipId,
  String userId = syntheticUserId,
  String role = 'buyer',
  String status = 'active',
  Object? revision = 1,
  String createdAt = '2026-05-01T00:00:00+00:00',
  String updatedAt = '2026-05-01T00:00:00+00:00',
}) {
  return <String, Object?>{
    'id': id,
    'user_id': userId,
    'role': role,
    'status': status,
    'revision': revision,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

Map<String, Object?> roleProfileRow({
  String membershipId = syntheticMembershipId,
  String displayName = 'Maya Chen',
  String? areaLabel = 'Yonkers, NY',
  String? profileNote,
  String? preferredMeetupType = 'Public safe-meet location',
  int? serviceRadiusMiles,
  String? pickupAvailability,
  int revision = 2,
  String createdAt = '2026-05-01T00:00:00+00:00',
  String updatedAt = '2026-05-02T00:00:00+00:00',
}) {
  return <String, Object?>{
    'membership_id': membershipId,
    'display_name': displayName,
    'area_label': areaLabel,
    'profile_note': profileNote,
    'preferred_meetup_type': preferredMeetupType,
    'service_radius_miles': serviceRadiusMiles,
    'pickup_availability': pickupAvailability,
    'revision': revision,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

Map<String, Object?> contactRow({
  String userId = syntheticUserId,
  String? phone = '+1 914 555 0182',
  String? addressLine1 = '123 Main Street',
  String? addressLine2,
  String? city = 'Yonkers',
  String? region = 'NY',
  String? postalCode = '10701',
  String? countryCode = 'US',
  Object? revision = 3,
  String createdAt = '2026-05-01T00:00:00+00:00',
  String updatedAt = '2026-05-02T00:00:00+00:00',
}) {
  return <String, Object?>{
    'user_id': userId,
    'phone': phone,
    'address_line1': addressLine1,
    'address_line2': addressLine2,
    'city': city,
    'region': region,
    'postal_code': postalCode,
    'country_code': countryCode,
    'revision': revision,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

AccountTransportData rowsResponse(List<Map<String, Object?>> rows) =>
    AccountTransportData(rows);

AccountTransportData resultResponse(Map<String, Object?> result) =>
    AccountTransportData(result);
