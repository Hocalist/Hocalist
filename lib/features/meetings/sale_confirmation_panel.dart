import 'package:hocalist/theme/adaptive_palette.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/phase2/outcomes/sale_confirmation.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/seller_ui_foundation.dart';

/// Purchase-confirmation surface for accepted meetings.
///
/// The buyer sees a transient server-issued PIN; the seller verifies it. The
/// panel renders role-appropriate visuals: Buyer surfaces inside the approved
/// Buyer meeting flow and Seller surfaces when the Seller app mounts it.
class SaleConfirmationPanel extends StatefulWidget {
  const SaleConfirmationPanel({
    required this.adapter,
    required this.meetingId,
    required this.isBuyer,
    this.purchaseSelected,
    this.meetingAccepted = true,
    this.onPurchaseConfirmed,
    this.onRefreshMeeting,
    super.key,
  });
  final SaleConfirmationAdapter adapter;
  final String meetingId;
  final bool isBuyer;

  /// True when this meeting's seller is the buyer's designated final purchase;
  /// false when the server says otherwise; null when the caller has no
  /// designation data and the legacy behavior is kept.
  final bool? purchaseSelected;
  final bool meetingAccepted;
  final VoidCallback? onPurchaseConfirmed;
  final Future<void> Function()? onRefreshMeeting;
  @override
  State<SaleConfirmationPanel> createState() => _SaleConfirmationPanelState();
}

class _SaleConfirmationPanelState extends State<SaleConfirmationPanel>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  SaleConfirmationResult? result;
  bool busy = false;
  String? error;
  int generation = 0;
  Timer? expiry;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    run('status');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      generation++;
      expiry?.cancel();
      input.clear();
      if (mounted) {
        setState(() {
          result = null;
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    expiry?.cancel();
    input.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> run(String action, {bool refreshMeeting = false}) async {
    if (busy) return;
    if (action != 'status' && !widget.meetingAccepted) return;
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      if (refreshMeeting) {
        await widget.onRefreshMeeting?.call();
        if (!mounted || token != generation) return;
      }
      final value = await widget.adapter.call(
        widget.meetingId,
        action,
        pin: action == 'verify' ? input.text : null,
      );
      if (!mounted || token != generation) return;
      setState(() {
        result = value;
        if (value.status == 'confirmed') input.clear();
      });
      if (value.status == 'confirmed' ||
          value.status == 'completed_elsewhere') {
        widget.onPurchaseConfirmed?.call();
      }
      expiry?.cancel();
      if (value.expiresAt != null) {
        final wait = value.expiresAt!.difference(DateTime.now().toUtc());
        expiry = Timer(wait.isNegative ? Duration.zero : wait, () {
          if (mounted) {
            setState(() => result = const SaleConfirmationResult('expired'));
          }
        });
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(
          () => error =
              'Could not confirm the result. Retry or refresh the status.',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = result?.status;
    final done = status == 'confirmed' || status == 'completed_elsewhere';
    final awaitingChoice =
        widget.isBuyer && widget.purchaseSelected == false && !done;
    final message = switch (status) {
      'confirmed' =>
        'Purchase confirmed. Item payment remains between buyer and seller.',
      'completed_elsewhere' => 'This request already has a confirmed purchase.',
      'meeting_not_accepted' =>
        'Accept a meeting schedule before confirming a purchase.',
      'expired' =>
        'The accepted meeting day has ended. Reschedule before trying again.',
      'buyer_must_open_pin' =>
        'Ask the buyer to open their purchase PIN first.',
      'purchase_seller_required' =>
        'The buyer has not chosen you for the final purchase. Only the seller they purchased from can complete the PIN.',
      'support_required' => 'Too many attempts. Contact support for help.',
      'locked' => 'Too many attempts. Wait 15 minutes before trying again.',
      'incorrect' => 'That PIN is incorrect. Check it with the buyer.',
      'invalid_format' => 'Enter the five-digit PIN.',
      _ when !widget.meetingAccepted && !done =>
        'Both sides must accept the meeting schedule before using a purchase PIN.',
      _ when awaitingChoice =>
        'Choose the seller you purchased from in your offers before sharing a PIN. Accepted meetings stay valid until their own cutoff.',
      _ =>
        'The PIN confirms a completed purchase, not attendance. Share it only after the sale is complete.',
    };
    final tone = switch (status) {
      'confirmed' => _ConfirmationTone.success,
      'completed_elsewhere' => _ConfirmationTone.success,
      'incorrect' ||
      'invalid_format' ||
      'locked' ||
      'support_required' => _ConfirmationTone.error,
      'expired' ||
      'meeting_not_accepted' ||
      'buyer_must_open_pin' ||
      'purchase_seller_required' => _ConfirmationTone.warning,
      _ => done ? _ConfirmationTone.success : _ConfirmationTone.brand,
    };
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConfirmationNotice(
            isBuyer: widget.isBuyer,
            tone: tone,
            title: done ? 'Purchase confirmed' : 'Confirm purchase',
            message: message,
          ),
          if (result?.pin != null) ...[
            SizedBox(height: metrics.spacing(12)),
            _PinDisplayCard(pin: result!.pin!, isBuyer: widget.isBuyer),
          ],
          if (!widget.isBuyer && !done && widget.meetingAccepted) ...[
            SizedBox(height: metrics.spacing(12)),
            TextField(
              controller: input,
              enabled: !busy,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 5,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: widget.isBuyer
                  ? null
                  : sellerInputText(
                      ApprovedReplicaScope.maybeOf(context) ??
                          ApprovedReplicaMetrics.resolve(
                            brightness: Theme.of(context).brightness,
                            availableWidth: MediaQuery.sizeOf(context).width,
                            textScaler: MediaQuery.textScalerOf(context),
                          ),
                    ),
              decoration: widget.isBuyer
                  ? buyerInputDecoration(
                      context,
                      hintText: '5 digits',
                      prefixIcon: Icon(
                        Icons.password_rounded,
                        color: HocalistPalette.text(
                          context,
                          BuyerUiTokens.action,
                        ),
                      ),
                    ).copyWith(labelText: 'Buyer purchase PIN', counterText: '')
                  : sellerInputDecoration(
                      context,
                      hintText: '5 digits',
                      labelText: 'Buyer purchase PIN',
                      prefixIcon: Icon(
                        Icons.password_rounded,
                        color: HocalistPalette.text(
                          context,
                          SellerUiColors.primary,
                        ),
                      ),
                    ).copyWith(counterText: ''),
            ),
          ],
          if (error != null) ...[
            SizedBox(height: metrics.spacing(10)),
            _ConfirmationNotice(
              isBuyer: widget.isBuyer,
              tone: _ConfirmationTone.error,
              title: 'Confirmation was not completed',
              message: error!,
            ),
          ],
          if (busy) ...[
            SizedBox(height: metrics.spacing(10)),
            if (widget.isBuyer)
              const BuyerProgressStrip(label: 'Checking purchase status…')
            else
              const SellerProgressStrip(label: 'Checking purchase status…'),
          ],
          if (!done && !awaitingChoice && widget.meetingAccepted) ...[
            SizedBox(height: metrics.spacing(12)),
            if (widget.isBuyer)
              BuyerPrimaryButton(
                key: const Key('saleConfirmationAction'),
                onPressed: busy ? null : () => run('display'),
                label: 'Show my purchase PIN',
              )
            else
              SellerPrimaryButton(
                key: const Key('saleConfirmationAction'),
                onPressed: busy ? null : () => run('verify'),
                label: 'Confirm completed purchase',
              ),
          ],
          SizedBox(height: metrics.spacing(8)),
          if (widget.isBuyer)
            BuyerSecondaryButton(
              key: const Key('saleConfirmationRefresh'),
              label: 'Refresh purchase status',
              onPressed: busy
                  ? null
                  : () => run('status', refreshMeeting: true),
            )
          else
            SellerSecondaryButton(
              key: const Key('saleConfirmationRefresh'),
              label: 'Refresh purchase status',
              onPressed: busy
                  ? null
                  : () => run('status', refreshMeeting: true),
            ),
        ],
      ),
    );
  }
}

enum _ConfirmationTone { brand, warning, error, success }

class _ConfirmationNotice extends StatelessWidget {
  const _ConfirmationNotice({
    required this.isBuyer,
    required this.tone,
    required this.title,
    required this.message,
  });

  final bool isBuyer;
  final _ConfirmationTone tone;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final icon = switch (tone) {
      _ConfirmationTone.brand => Icons.verified_outlined,
      _ConfirmationTone.warning => Icons.schedule_rounded,
      _ConfirmationTone.error => Icons.error_outline_rounded,
      _ConfirmationTone.success => Icons.check_circle_rounded,
    };
    if (isBuyer) {
      return BuyerStateNotice(
        icon: icon,
        title: title,
        body: message,
        tone: switch (tone) {
          _ConfirmationTone.brand => BuyerNoticeTone.brand,
          _ConfirmationTone.warning => BuyerNoticeTone.warning,
          _ConfirmationTone.error => BuyerNoticeTone.error,
          _ConfirmationTone.success => BuyerNoticeTone.success,
        },
      );
    }
    return SellerStateNotice(
      icon: icon,
      title: title,
      body: message,
      tone: switch (tone) {
        _ConfirmationTone.brand => SellerNoticeTone.brand,
        _ConfirmationTone.warning => SellerNoticeTone.warning,
        _ConfirmationTone.error => SellerNoticeTone.error,
        _ConfirmationTone.success => SellerNoticeTone.success,
      },
    );
  }
}

class _PinDisplayCard extends StatelessWidget {
  const _PinDisplayCard({required this.pin, required this.isBuyer});

  final String pin;
  final bool isBuyer;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context);
    final media = MediaQuery.of(context);
    final resolved =
        metrics ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final accent = isBuyer ? BuyerUiTokens.action : SellerUiColors.primary;
    final surface = isBuyer
        ? BuyerUiTokens.softSurface
        : SellerUiColors.lavender;
    final border = isBuyer
        ? const Color(0xffd9d5ff)
        : SellerUiColors.lavenderBorder;
    final textColor = isBuyer ? BuyerUiTokens.text : SellerUiColors.ink;
    return Container(
      key: const Key('saleConfirmationPinCard'),
      padding: resolved.geometryInsets(const EdgeInsets.all(18)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, surface),
        borderRadius: BorderRadius.circular(resolved.geometry(18)),
        border: Border.all(color: HocalistPalette.border(context, border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.password_rounded,
                size: resolved.artSize(18),
                color: HocalistPalette.text(context, accent),
              ),
              SizedBox(width: resolved.spacing(6)),
              Text(
                'Your purchase PIN',
                style: TextStyle(
                  fontSize: resolved.fontSize(12.5),
                  fontWeight: FontWeight.w800,
                  color: HocalistPalette.text(context, accent),
                ),
              ),
            ],
          ),
          SizedBox(height: resolved.spacing(10)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              pin,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: resolved.fontSize(38),
                fontWeight: FontWeight.w900,
                letterSpacing: resolved.geometry(10),
                color: HocalistPalette.text(context, textColor),
              ),
            ),
          ),
          SizedBox(height: resolved.spacing(8)),
          Text(
            'Valid through the accepted meeting day in the meeting timezone.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: resolved.fontSize(11.5),
              height: 1.35,
              color: HocalistPalette.text(
                context,
                isBuyer ? BuyerUiTokens.muted : SellerUiColors.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
