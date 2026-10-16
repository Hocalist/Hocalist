/// Password-recovery screens for the real account gate.
///
/// These are minimal pre-access surfaces, not part of the approved screenshot
/// set. They intentionally render no marketplace content: the gate shows them
/// before any membership or profile data loads.
library;

import 'package:flutter/material.dart';

import '../../theme/buyer_ui_foundation.dart';
import '../../components/hocalist_account_field.dart';
import '../approved/approved_replica_metrics.dart';

/// Shared pre-access page frame used by the recovery states.
class AccountRecoveryScaffold extends StatelessWidget {
  const AccountRecoveryScaffold({
    required this.title,
    required this.body,
    required this.children,
    super.key,
  });

  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
              children: [
                Center(
                  child: SizedBox(
                    width: metrics.artSize(116),
                    height: metrics.artSize(46),
                    child: Image.asset(
                      'assets/brand/hocalist-wordmark.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                SizedBox(height: metrics.spacing(12)),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.displayTitle,
                    weight: FontWeight.w900,
                  ).copyWith(fontSize: metrics.fontSize(21)),
                ),
                SizedBox(height: metrics.spacing(10)),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.primaryBody,
                    color: BuyerUiTokens.muted,
                  ),
                ),
                SizedBox(height: metrics.spacing(22)),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Forgot password" request form. Sending the email is not a login.
class AccountRecoveryRequestPage extends StatefulWidget {
  const AccountRecoveryRequestPage({
    required this.onSubmit,
    required this.onBack,
    this.busy = false,
    this.error,
    super.key,
  });

  final Future<void> Function(String email) onSubmit;
  final VoidCallback onBack;
  final bool busy;
  final String? error;

  @override
  State<AccountRecoveryRequestPage> createState() =>
      _AccountRecoveryRequestPageState();
}

class _AccountRecoveryRequestPageState
    extends State<AccountRecoveryRequestPage> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AccountRecoveryScaffold(
      key: const ValueKey('account-recovery-request'),
      title: 'Reset your password',
      body:
          'Enter the email on your account. We send a reset link that opens '
          'a password screen in the app.',
      children: [
        HocalistAccountField(
          fieldKey: const ValueKey('account-recovery-email'),
          label: 'Email address',
          controller: _email,
          enabled: !widget.busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 10),
          _RecoveryError(
            key: const ValueKey('account-recovery-request-error'),
            message: widget.error!,
          ),
        ],
        const SizedBox(height: 16),
        BuyerPrimaryButton(
          key: const ValueKey('account-recovery-submit'),
          label: widget.busy ? 'Sending...' : 'Send reset link',
          onPressed: widget.busy ? null : _submit,
        ),
        const SizedBox(height: 6),
        BuyerSecondaryButton(
          key: const ValueKey('account-recovery-back'),
          label: 'Back to log in',
          onPressed: widget.busy ? null : widget.onBack,
        ),
      ],
    );
  }

  void _submit() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    widget.onSubmit(email);
  }
}

/// "Check your email" state after a reset request.
class AccountRecoveryEmailSentPage extends StatelessWidget {
  const AccountRecoveryEmailSentPage({
    required this.email,
    required this.onBack,
    super.key,
  });

  final String? email;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AccountRecoveryScaffold(
      key: const ValueKey('account-recovery-email-sent'),
      title: 'Check your email',
      body: email == null || email!.trim().isEmpty
          ? 'Open the reset link in your email to choose a new password. '
                'Nothing changes until then.'
          : 'We sent a reset link to ${email!.trim()}. Open it to choose a '
                'new password. Nothing changes until then.',
      children: [
        BuyerPrimaryButton(
          key: const ValueKey('account-recovery-sent-back'),
          label: 'Back to log in',
          onPressed: onBack,
        ),
      ],
    );
  }
}

/// Expired or invalid recovery-link state. The link failure is never treated
/// as a successful reset or a successful login.
class AccountRecoveryLinkExpiredPage extends StatelessWidget {
  const AccountRecoveryLinkExpiredPage({
    required this.expired,
    required this.onBack,
    super.key,
  });

  final bool expired;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AccountRecoveryScaffold(
      key: const ValueKey('account-recovery-link-failed'),
      title: expired ? 'Reset link expired' : 'Reset link did not work',
      body: expired
          ? 'That link is past its validity window. Request a new one from '
                'the log-in screen and enter your email again.'
          : 'That link was already used or is not valid. Request a new one '
                'from the log-in screen and enter your email again.',
      children: [
        BuyerPrimaryButton(
          key: const ValueKey('account-recovery-failed-back'),
          label: 'Back to log in',
          onPressed: onBack,
        ),
      ],
    );
  }
}

/// New password form for a recovery session.
class AccountRecoveryPasswordPage extends StatefulWidget {
  const AccountRecoveryPasswordPage({
    required this.onSubmit,
    required this.onCancel,
    this.busy = false,
    this.error,
    super.key,
  });

  final Future<void> Function(String password) onSubmit;
  final Future<void> Function() onCancel;
  final bool busy;
  final String? error;

  @override
  State<AccountRecoveryPasswordPage> createState() =>
      _AccountRecoveryPasswordPageState();
}

class _AccountRecoveryPasswordPageState
    extends State<AccountRecoveryPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AccountRecoveryScaffold(
      key: const ValueKey('account-recovery-password'),
      title: 'Choose a new password',
      body:
          'Your reset link worked. Set a new password to continue to your '
          'account.',
      children: [
        HocalistAccountField(
          fieldKey: const ValueKey('account-recovery-new-password'),
          label: 'New password',
          controller: _password,
          enabled: !widget.busy,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 8),
        HocalistAccountField(
          fieldKey: const ValueKey('account-recovery-confirm-password'),
          label: 'Confirm new password',
          controller: _confirm,
          enabled: !widget.busy,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (_localError != null) ...[
          const SizedBox(height: 10),
          _RecoveryError(
            key: const ValueKey('account-recovery-password-error'),
            message: _localError!,
          ),
        ] else if (widget.error != null) ...[
          const SizedBox(height: 10),
          _RecoveryError(
            key: const ValueKey('account-recovery-password-error'),
            message: widget.error!,
          ),
        ],
        const SizedBox(height: 16),
        BuyerPrimaryButton(
          key: const ValueKey('account-recovery-password-submit'),
          label: widget.busy ? 'Saving...' : 'Save new password',
          onPressed: widget.busy ? null : _submit,
        ),
        const SizedBox(height: 6),
        BuyerSecondaryButton(
          key: const ValueKey('account-recovery-password-cancel'),
          label: 'Cancel and sign out',
          onPressed: widget.busy ? null : widget.onCancel,
        ),
      ],
    );
  }

  void _submit() {
    final password = _password.text;
    final confirm = _confirm.text;
    if (password.length < 8) {
      setState(() => _localError = 'Use at least 8 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _localError = 'The two passwords do not match.');
      return;
    }
    setState(() => _localError = null);
    widget.onSubmit(password);
  }
}

class _RecoveryError extends StatelessWidget {
  const _RecoveryError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xffb3261e),
      ),
    );
  }
}
