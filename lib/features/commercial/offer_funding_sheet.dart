import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../components/hocalist_loading_indicator.dart';
import 'package:uuid/uuid.dart';
import '../../theme/seller_ui_foundation.dart';
import 'offer_funding_window_stub.dart'
    if (dart.library.js_interop) 'offer_funding_window_web.dart';
import 'seller_payment_panel.dart';
import '../approved/approved_replica_metrics.dart';
import '../../theme/adaptive_palette.dart';

enum OfferFundingResult { ready, canceled }

class OfferFundingSheet extends StatefulWidget {
  const OfferFundingSheet({required this.planLabel, this.request, super.key});
  final String planLabel;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? request;
  @override
  State<OfferFundingSheet> createState() => _OfferFundingSheetState();
}

class _OfferFundingSheetState extends State<OfferFundingSheet>
    with WidgetsBindingObserver {
  final window = OfferFundingWindow();
  SupabaseClient get client => Supabase.instance.client;
  late final owner = client.auth.currentUser?.id;
  String key = const Uuid().v4();
  Map? card;
  String? setup;
  Timer? timer;
  String? error;
  bool loading = true,
      consent = false,
      alreadyAuthorized = false,
      checking = false,
      inspected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inspect();
  }

  Future<Map> call(Map<String, dynamic> body) async {
    if (widget.request != null) return widget.request!(body);
    if (owner == null || client.auth.currentUser?.id != owner)
      throw StateError('session');
    final response = await client.functions.invoke(
      'hocalist-offer-funding',
      body: body,
    );
    if (client.auth.currentUser?.id != owner) throw StateError('session');
    return response.data as Map;
  }

  Future<void> inspect() async {
    setState(() {
      loading = true;
      error = null;
      consent = false;
    });
    try {
      final state = await call({'operation': 'inspect'});
      if (!mounted) return;
      setState(() {
        card = state['card'] as Map?;
        alreadyAuthorized = state['authorised'] == true;
        inspected = true;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not check your payment method. Try again.',
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void finish(OfferFundingResult result) {
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> start() async {
    if (!consent || loading) return;
    if (card == null && !window.open()) {
      setState(
        () => error = 'Allow the Stripe window to open, then try again.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await call({
        'operation': card == null ? 'begin' : 'authorize',
        'idempotency_key': key,
        'consent_version': 'paygo-v1',
        if (card != null) 'method': card!['id'],
      });
      if (!mounted) return;
      if (response['state'] == 'authorised') {
        finish(OfferFundingResult.ready);
        return;
      }
      setup = response['setup_id'] as String;
      if (response['state'] == 'needs_confirmation') {
        await verify();
        return;
      }
      final url = Uri.parse(response['url'] as String);
      if (url.origin != 'https://checkout.stripe.com' ||
          !await window.navigate(url))
        throw StateError('checkout');
      if (!mounted) return;
      if (kIsWeb)
        timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (setup == null || checking) return;
          final result = window.returned(setup!);
          if (result != null) {
            timer?.cancel();
            verify();
          }
        });
    } catch (_) {
      window.close();
      if (mounted)
        setState(() {
          setup = null;
          inspected = false;
          consent = false;
          key = const Uuid().v4();
          error =
              'Payment setup could not be opened. Check your card and try again.';
        });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verify() async {
    if (checking || setup == null) return;
    checking = true;
    try {
      final state = await call({'operation': 'confirm', 'setup_id': setup});
      if (!mounted) return;
      finish(
        state['state'] == 'authorised'
            ? OfferFundingResult.ready
            : OfferFundingResult.canceled,
      );
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not confirm setup. Check again or return to your offer.',
        );
    } finally {
      checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed && setup != null)
      verify();
  }

  @override
  void dispose() {
    timer?.cancel();
    window.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final gap = SizedBox(height: metrics.spacing(12));
    final elite = widget.planLabel.startsWith('Elite');
    final freeOrPro =
        widget.planLabel.startsWith('Free') ||
        widget.planLabel.startsWith('Pro');
    final accent = HocalistPalette.text(context, SellerUiColors.primaryBright);
    return SellerModalSheet(
      title: !inspected
          ? 'Payment for offers'
          : alreadyAuthorized
          ? 'Offer funding'
          : card != null
          ? 'Authorize targeting fees'
          : 'Set up a card for offers',
      icon: Icons.credit_card_outlined,
      subtitle: alreadyAuthorized
          ? 'Your card is authorized. Check your wallet balance to continue.'
          : card == null
          ? 'Add a card securely in Stripe. Your draft stays here.'
          : 'Choose whether to use this card for targeting fees.',
      onClose: () => finish(OfferFundingResult.canceled),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            SellerStateNotice(
              icon: Icons.info_outline,
              title: error!,
              tone: SellerNoticeTone.error,
            ),
            gap,
          ],
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: HocalistLoadingIndicator()),
            )
          else if (!inspected)
            SellerPrimaryButton(
              label: 'Check payment method',
              onPressed: inspect,
            )
          else if (alreadyAuthorized)
            const SellerPaymentPanel(preserveDraft: true, creditPurchase: true)
          else if (setup != null)
            SellerPrimaryButton(
              label: 'Check setup and return to offer',
              onPressed: verify,
            )
          else ...[
            if (card != null) ...[
              SellerStateNotice(
                icon: Icons.credit_card_rounded,
                title:
                    "${card!['brand'].toString().toUpperCase()} •••• ${card!['last4']}",
              ),
              gap,
            ],
            SellerStateNotice(
              icon: Icons.receipt_long_outlined,
              title: 'Sending an offer is free',
              body: elite
                  ? 'Targeting fees stay pending until a PIN-confirmed purchase or the seven-day deadline. Eligible no-purchase fees are waived.'
                  : freeOrPro
                  ? 'The initial fee applies when the buyer replies. A confirmed purchase can add the remaining winning fee.'
                  : 'Free and Pro initial fees apply when the buyer replies. Elite fees wait until purchase confirmation or the seven-day deadline.',
            ),
            gap,
            Material(
              color: HocalistPalette.surface(
                context,
                consent ? SellerUiColors.lavender : SellerUiColors.white,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(14)),
                side: BorderSide(
                  color: consent
                      ? accent
                      : HocalistPalette.border(context, SellerUiColors.line),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: metrics.geometry(10),
                  vertical: metrics.geometry(2),
                ),
                checkboxShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                activeColor: SellerUiColors.primaryBright,
                value: consent,
                title: Text(
                  'I authorize future targeting fees for my offers.',
                  style: sellerText(metrics, 13, weight: FontWeight.w700),
                ),
                onChanged: (v) => setState(() => consent = v == true),
              ),
            ),
            gap,
            SellerPrimaryButton(
              label: card == null ? 'Continue to Stripe' : 'Authorize fees',
              onPressed: consent ? start : null,
            ),
          ],
          gap,
          SellerSecondaryButton(
            label: 'Return to my offer',
            onPressed: () => finish(OfferFundingResult.canceled),
          ),
        ],
      ),
    );
  }
}
