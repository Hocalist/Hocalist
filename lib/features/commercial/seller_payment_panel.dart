import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/seller_ui_foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/providers/provider_runtime.dart';
import 'billing_session_navigation.dart';

// Checkout returns to this hosted origin. Starting there as well preserves its
// own authenticated website session, including from a localhost app preview.
Uri sellerBillingWebsite() => Uri.parse('https://hocalist.com/billing');

/// Opens the existing authenticated website; never handles card data locally.
class SellerPaymentPanel extends StatefulWidget {
  const SellerPaymentPanel({this.open, this.creditPurchase = false, super.key});
  final Future<bool> Function(Uri)? open;
  final bool creditPurchase;
  @override
  State<SellerPaymentPanel> createState() => _SellerPaymentPanelState();
}

class _SellerPaymentPanelState extends State<SellerPaymentPanel> {
  bool _busy = false;
  bool _failed = false;
  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (widget.open == null &&
          kIsWeb &&
          const bool.fromEnvironment('HOCALIST_BILLING_APP_SESSION')) {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          final fence = ProviderSessionFence(client);
          final token = await fence.freshToken(
            minimumValidity: const Duration(minutes: 30),
          );
          fence.check();
          if (!mounted) return;
          if (submitBillingSession(sellerBillingWebsite(), token, userId)) {
            return;
          }
        }
      }
      final opened =
          await (widget.open ??
              (uri) => launchUrl(
                uri,
                mode: kIsWeb
                    ? LaunchMode.platformDefault
                    : LaunchMode.externalApplication,
                webOnlyWindowName: kIsWeb ? '_self' : null,
              ))(sellerBillingWebsite());
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = !opened;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SellerStateNotice(
        icon: Icons.credit_card_outlined,
        title: widget.creditPurchase
            ? 'Buy HocaCredits on the website'
            : 'Manage payment methods securely',
        body: widget.creditPurchase
            ? 'Choose a configured credit pack on the Hocalist billing website. Credits are added only after Stripe confirms payment. This testing flow uses Stripe TEST mode.'
            : 'Open your seller billing account to manage payment methods. Card details stay with Stripe. This testing flow uses Stripe TEST mode.',
      ),
      const SizedBox(height: 12),
      if (_failed)
        const SellerStateNotice(
          icon: Icons.error_outline,
          title: 'Could not open billing',
          body: 'Try again to open the Hocalist billing website.',
          tone: SellerNoticeTone.error,
        ),
      SellerPrimaryButton(
        label: _busy
            ? 'Opening billing…'
            : widget.creditPurchase
            ? 'Open credit checkout'
            : 'Manage payment method',
        onPressed: _busy ? null : _open,
      ),
    ],
  );
}
