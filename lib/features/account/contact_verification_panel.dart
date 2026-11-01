import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import '../../components/hocalist_account_field.dart';
import '../../data/phase2/providers/contact_verification_service.dart';
import '../../theme/seller_ui_foundation.dart';

class ContactVerificationPanel extends StatefulWidget {
  const ContactVerificationPanel({
    required this.service,
    required this.onChanged,
    this.showEmail = true,
    this.showPhone = true,
    super.key,
  });
  final ContactVerificationGateway service;
  final VoidCallback onChanged;
  final bool showEmail, showPhone;
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

  @override
  Widget build(BuildContext context) {
    final emailVerified = user?.emailConfirmedAt != null;
    final phoneVerified = user?.phoneConfirmedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showEmail && widget.showPhone)
          const SellerSectionHeading(title: 'Email and phone'),
        const Text(
          'Already confirmed when you signed up? We use that verification here too.',
        ),
        const SizedBox(height: 12),
        if (widget.showEmail)
          SellerStateNotice(
            icon: Icons.email_outlined,
            title: 'Email',
            body: user == null
                ? 'Checking your email…'
                : user?.email?.isNotEmpty == true
                ? user!.email!
                : 'No email added',
            trailing: SellerStatusChip(
              label: user == null
                  ? 'Checking…'
                  : emailVerified
                  ? 'Verified'
                  : 'Not verified',
            ),
          ),
        if (widget.showEmail &&
            user != null &&
            !emailVerified &&
            user!.email?.isNotEmpty == true)
          SellerSecondaryButton(
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
          SellerStateNotice(
            icon: Icons.phone_outlined,
            title: 'Phone',
            body: phoneVerified
                ? 'Your account phone is confirmed.'
                : 'Confirm a number you can receive text messages on.',
            trailing: SellerStatusChip(
              label: user == null
                  ? 'Checking…'
                  : phoneVerified
                  ? 'Verified'
                  : 'Not verified',
            ),
          ),
        if (widget.showPhone && user != null && (!phoneVerified || sent)) ...[
          HocalistAccountField(
            label: 'Phone number with country code',
            controller: phone,
            seller: true,
            enabled: !busy && !sent,
            keyboardType: TextInputType.phone,
            fieldKey: const Key('verification-phone'),
          ),
          const SizedBox(height: 8),
          if (sent) ...[
            HocalistAccountField(
              label: 'Text message code',
              controller: code,
              seller: true,
              enabled: !busy,
              keyboardType: TextInputType.number,
              fieldKey: const Key('verification-phone-code'),
            ),
            const SizedBox(height: 8),
            SellerPrimaryButton(
              label: 'Verify phone',
              onPressed: busy ? null : () => _run(_confirm),
            ),
            const SizedBox(height: 12),
            SellerSecondaryButton(
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
          SellerSecondaryButton(
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
        SellerSecondaryButton(
          label: busy ? 'Checking…' : 'Refresh verification status',
          onPressed: busy ? null : () => _run(_load),
        ),
      ],
    );
  }
}
