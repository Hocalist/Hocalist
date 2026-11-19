import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import '../../components/hocalist_account_field.dart';
import '../../components/hocalist_loading_indicator.dart';
import '../../data/phase2/providers/contact_verification_service.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../theme/buyer_ui_foundation.dart';

class ContactVerificationPanel extends StatefulWidget {
  const ContactVerificationPanel({
    required this.service,
    required this.onChanged,
    this.buyer = false,
    this.onVerified,
    this.showEmail = true,
    this.showPhone = true,
    super.key,
  });
  final ContactVerificationGateway service;
  final VoidCallback onChanged;
  final bool showEmail, showPhone, buyer;
  final VoidCallback? onVerified;
  @override
  State<ContactVerificationPanel> createState() =>
      _ContactVerificationPanelState();
}

class _ContactVerificationPanelState extends State<ContactVerificationPanel> {
  late final service = widget.service;
  final phone = TextEditingController(), code = TextEditingController();
  User? user;
  bool busy = false, sent = false;
  String? message;
  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final value = await service.load();
    if (!mounted) return;
    user = value;
    if (!sent && phone.text.isEmpty && value.phone?.isNotEmpty == true) {
      phone.text = '+${value.phone!.replaceAll('+', '')}';
    }
    widget.onChanged();
    if ((!widget.showPhone || value.phoneConfirmedAt != null) &&
        (!widget.showEmail || value.emailConfirmedAt != null)) widget.onVerified?.call();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on ContactVerificationFailure catch (e) {
      if (mounted) message = e.message;
    } catch (_) {
      if (mounted) {
        message = 'Could not check your verification. Please try again.';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() async {
    final verified = await service.sendPhone(phone.text);
    if (!mounted) return;
    sent = !verified;
    code.clear();
    message = verified
        ? 'This phone number is already verified.'
        : 'Code sent. Enter the code from your text message.';
    if (verified) await _load();
  }

  Future<void> _confirm() async {
    final verified = await service.confirmPhone(phone.text, code.text);
    if (!mounted) return;
    if (verified) {
      sent = false;
      code.clear();
      message = 'Phone verified.';
      await _load();
    } else {
      code.clear();
      message =
          'One more confirmation is needed. Enter the next code sent to your phone.';
    }
  }

  Widget _buyerPhoneForm() {
    if (user == null && busy) {
      return const Padding(padding: EdgeInsets.all(20), child: Center(child: HocalistLoadingIndicator()));
    }
    if (user == null) {
      return BuyerStateNotice(icon: Icons.phone_outlined, title: 'Phone verification unavailable',
        body: message ?? 'Please try again.', actionLabel: 'Retry', onAction: () => _run(_load));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(sent ? 'Enter the code sent to ${phone.text}.' : 'We’ll text you a code to confirm this number for withdrawals.'),
      const SizedBox(height: 16),
      HocalistAccountField(
        key: ValueKey(sent), fieldKey: Key(sent ? 'verification-phone-code' : 'verification-phone'),
        label: sent ? 'Text message code' : 'Phone number with country code',
        controller: sent ? code : phone, enabled: !busy,
        keyboardType: sent ? TextInputType.number : TextInputType.phone,
        autofillHints: [sent ? AutofillHints.oneTimeCode : AutofillHints.telephoneNumber],
      ),
      if (message != null && message != 'Code sent. Enter the code from your text message.') ...[
        const SizedBox(height: 8), Text(message!, key: const Key('contact-verification-result')),
      ],
      const SizedBox(height: 18),
      BuyerPrimaryButton(label: busy ? 'Please wait…' : sent ? 'Verify phone' : 'Send code',
        onPressed: busy ? null : () => _run(sent ? _confirm : _send)),
      if (sent) ...[
        const SizedBox(height: 10),
        BuyerSecondaryButton(label: 'Resend code', onPressed: busy ? null : () => _run(_send)),
        const SizedBox(height: 10),
        BuyerSecondaryButton(label: 'Change number', onPressed: busy ? null : () => setState(() {
          sent = false; code.clear(); message = null;
        })),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.buyer && widget.showPhone && !widget.showEmail) {
      return _buyerPhoneForm();
    }
    Widget secondary({required String label, required VoidCallback? onPressed}) => widget.buyer
        ? BuyerSecondaryButton(label: label, onPressed: onPressed)
        : SellerSecondaryButton(label: label, onPressed: onPressed);
    Widget primary({required String label, required VoidCallback? onPressed}) => widget.buyer
        ? BuyerPrimaryButton(label: label, onPressed: onPressed)
        : SellerPrimaryButton(label: label, onPressed: onPressed);
    Widget statusNotice(IconData icon, String title, String body, bool verified) {
      final status = user == null ? 'Checking…' : verified ? 'Verified' : 'Not verified';
      if (widget.buyer) {
        return BuyerStateNotice(icon: icon, title: title, body: body, trailing: BuyerStatusChip(label: status));
      }
      return SellerStateNotice(icon: icon, title: title, body: body, trailing: SellerStatusChip(label: status));
    }
    final emailVerified = user?.emailConfirmedAt != null;
    final phoneVerified = user?.phoneConfirmedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showEmail && widget.showPhone)
          widget.buyer ? const BuyerSectionHeading(title: 'Email and phone') : const SellerSectionHeading(title: 'Email and phone'),
        const Text(
          'Already confirmed when you signed up? We use that verification here too.',
        ),
        const SizedBox(height: 12),
        if (widget.showEmail)
          statusNotice(Icons.email_outlined, 'Email',
              user == null ? 'Checking your email…' : user?.email?.isNotEmpty == true ? user!.email! : 'No email added', emailVerified),
        if (widget.showEmail &&
            user != null &&
            !emailVerified &&
            user!.email?.isNotEmpty == true)
          secondary(
            label: 'Send confirmation email',
            onPressed: busy
                ? null
                : () => _run(() async {
                    await service.resendEmail();
                    if (mounted) {
                      message =
                          'Check your email, then refresh your status below.';
                    }
                  }),
          ),
        const SizedBox(height: 12),
        if (widget.showPhone)
          statusNotice(Icons.phone_outlined, 'Phone', phoneVerified
              ? 'Your account phone is confirmed.'
              : 'Confirm a number you can receive text messages on.', phoneVerified),
        if (widget.showPhone && user != null && (!phoneVerified || sent)) ...[
          HocalistAccountField(
            label: 'Phone number with country code',
            controller: phone,
            seller: !widget.buyer,
            enabled: !busy && !sent,
            keyboardType: TextInputType.phone,
            fieldKey: const Key('verification-phone'),
          ),
          const SizedBox(height: 8),
          if (sent) ...[
            HocalistAccountField(
              label: 'Text message code',
              controller: code,
              seller: !widget.buyer,
              enabled: !busy,
              keyboardType: TextInputType.number,
              fieldKey: const Key('verification-phone-code'),
            ),
            const SizedBox(height: 8),
            primary(
              label: 'Verify phone',
              onPressed: busy ? null : () => _run(_confirm),
            ),
            const SizedBox(height: 12),
            secondary(
              label: 'Use a different number',
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        sent = false;
                        code.clear();
                        message = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
          ],
          secondary(
            label: sent ? 'Send another code' : 'Send code',
            onPressed: busy ? null : () => _run(_send),
          ),
        ],
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              message!,
              key: const Key('contact-verification-result'),
            ),
          ),
        secondary(
          label: busy ? 'Checking…' : 'Refresh verification status',
          onPressed: busy ? null : () => _run(_load),
        ),
      ],
    );
  }
}
