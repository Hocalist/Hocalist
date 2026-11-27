import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/phase2/commercial/commercial.dart';

/// Receives only an encrypted, expiring one-use ticket; never puts the access
/// token or refresh credentials in a browser URL.
Future<Uri> nativeBillingDestination(
  String accessToken, {
  http.Client? client,
  PlanCode? plan,
}) async {
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('https://www.hocalist.com/api/session/native'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw StateError('billing_admission_unavailable');
    final data = jsonDecode(response.body);
    final ticket = data is Map ? data['ticket'] : null;
    if (ticket is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{50,8192}$').hasMatch(ticket)) {
      throw StateError('billing_admission_unavailable');
    }
    return Uri.parse('https://www.hocalist.com/billing/app').replace(
      queryParameters: plan == null ? null : {'plan': plan.name},
      fragment: 'ticket=$ticket',
    );
  } finally {
    if (client == null) transport.close();
  }
}
