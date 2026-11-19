import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/buyer_ui_foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/phase2/commercial/withdrawal_backend.dart';
import '../../components/hocalist_loading_indicator.dart';
import 'withdrawal_panel.dart';
import '../account/contact_verification_panel.dart';
import '../../data/phase2/providers/contact_verification_service.dart';
import 'payout_return_stub.dart'
    if (dart.library.js_interop) 'payout_return_web.dart' as payout_return;

class BuyerPayoutSetup extends StatefulWidget {
  const BuyerPayoutSetup({super.key, this.backend, this.loadWithdrawals, this.request, this.open});
  final WithdrawalBackend? backend;
  final Future<WithdrawalStatusView> Function()? loadWithdrawals;
  final Future<Map<String, dynamic>> Function(String action)? request;
  final Future<bool> Function(Uri url)? open;
  @override
  State<BuyerPayoutSetup> createState() => _BuyerPayoutSetupState();
}

class _BuyerPayoutSetupState extends State<BuyerPayoutSetup>
    with WidgetsBindingObserver {
  bool busy = true;
  bool ready = false;
  bool saved = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run('status');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) _run('status');
  }

  Future<void> _run(String action) async {
    final client = widget.request == null ? Supabase.instance.client : null;
    final owner = client?.auth.currentUser?.id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = widget.request != null
          ? await widget.request!(action)
          : Map<String, dynamic>.from(
              (await client!.functions.invoke(
                    'hocalist-reward-recipient',
                    body: {'action': action},
                  )).data
                  as Map,
            );
      if (!mounted ||
          (client != null &&
              (owner == null || client.auth.currentUser?.id != owner)))
        return;
      if (action == 'status') {
        setState(() {
          ready = data['ready'] == true;
          saved = data['saved'] == true;
        });
      } else {
        final url = Uri.parse(data['url'] as String);
        if (url.scheme != 'https' || !url.host.endsWith('.stripe.com')) {
          throw StateError('open');
        }
        if (kIsWeb && owner != null) payout_return.rememberPayoutReturn(owner);
        if (!await (widget.open?.call(url) ??
                launchUrl(
                  url,
                  mode: kIsWeb
                      ? LaunchMode.platformDefault
                      : LaunchMode.externalApplication,
                  webOnlyWindowName: '_self',
                )))
          throw StateError('open');
      }
    } catch (_) {
      if (action == 'manage' && kIsWeb) payout_return.clearPayoutReturn();
      if (mounted)
        setState(
          () => error =
              'Payout details are unavailable right now. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.backend == null && widget.loadWithdrawals == null) return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: HocalistLoadingIndicator()),
        ),
      if (error != null) Text(error!),
      BuyerPrimaryButton(
        onPressed: busy ? null : () => _run('manage'),
        label: saved ? 'Edit payout details' : 'Manage payout',
      ),
    ],
    );
    return WithdrawalPanel(
          destination: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Theme.of(context).dividerColor)),
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Payout account'),
            subtitle: Text(error ?? (busy ? 'Checking…' : ready ? 'Ready for withdrawals' :
                saved ? 'Finish setting up your bank account' : 'Add your bank account')),
            trailing: busy ? const SizedBox.square(dimension: 22, child: HocalistLoadingIndicator()) : const Icon(Icons.chevron_right),
            onTap: busy ? null : () => _run(error == null ? 'manage' : 'status'),
          ),
          destinationReady: ready && !busy,
          requestsEnabled: widget.backend != null,
          verificationForm: (phone, verified) => ContactVerificationPanel(
            key: ValueKey(phone), buyer: true, showPhone: phone, showEmail: !phone,
            service: ContactVerificationService(Supabase.instance.client),
            onChanged: () {}, onVerified: verified,
          ),
          load: widget.loadWithdrawals ?? widget.backend!.loadStatus,
          submit: (amount, key) => widget.backend!.requestWithdrawal(
            amountMinor: amount,
            operationKey: key,
          ),
    );
  }
}
