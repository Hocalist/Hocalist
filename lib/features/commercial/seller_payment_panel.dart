import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/seller_ui_foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/providers/provider_runtime.dart';
import 'billing_session_navigation.dart';
import 'native_billing_navigation.dart';

// Checkout returns to this hosted origin. Starting there as well preserves its
// own authenticated website session, including from a localhost app preview.
Uri sellerBillingWebsite() => Uri.parse('https://hocalist.com/billing');

/// Opens the existing authenticated website; never handles card data locally.
class SellerPaymentPanel extends StatefulWidget {
  const SellerPaymentPanel({
    this.open,
    this.creditPurchase = false,
    this.label,
    this.compact = false,
    super.key,
  });
  final bool compact;
  final String? label;
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
          !kIsWeb &&
          const bool.fromEnvironment('HOCALIST_BILLING_APP_SESSION')) {
        final client = Supabase.instance.client;
        final fence = ProviderSessionFence(client);
        final token = await fence.freshToken(
          minimumValidity: const Duration(minutes: 30),
        );
        fence.check();
        final destination = await nativeBillingDestination(token);
        fence.check();
        // A token refresh can rebuild the account/plan surface. The explicit
        // native launch intent belongs to this authenticated user, not that
        // transient panel. The fence still cancels sign-out/identity changes;
        // only updating panel state requires it to remain mounted.
        final opened = await launchUrl(
          destination,
          mode: LaunchMode.externalApplication,
        );
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = !opened;
          });
        }
        return;
      }
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
      if (!widget.compact)
        SellerStateNotice(
          icon: Icons.credit_card_outlined,
          title: widget.label != null
              ? 'Your seller subscription'
              : widget.creditPurchase
              ? 'Buy HocaCredits on the website'
              : 'Manage payment methods securely',
          body: widget.label != null
              ? 'Compare monthly and annual plans, or manage your existing subscription on the Hocalist billing website.'
              : widget.creditPurchase
              ? 'Choose a credit pack on the Hocalist billing website. Credits are added after payment is confirmed.'
              : 'Open your seller billing account to manage payment methods. Your card details stay securely with the payment provider.',
        ),
      if (!widget.compact) const SizedBox(height: 12),
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
            : widget.label ??
                  (widget.creditPurchase
                      ? 'Open credit checkout'
                      : 'Manage payment method'),
        onPressed: _busy ? null : _open,
      ),
    ],
  );
}
