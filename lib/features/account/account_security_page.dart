/// Authenticated password and email-change screen.
///
/// Reached from the account settings entry after login. It never fakes a
/// success: provider failures render inline and email changes stay pending
/// until the provider confirms the new address.
library;

import '../../components/hocalist_account_field.dart';
import '../../domain/phase2/profiles.dart';

import 'package:flutter/material.dart';
import '../../components/account_role_components.dart';
import '../../components/hocalist_section_intro.dart';

import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'hocalist_account_controller.dart';

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({
    required this.controller,
    required this.onBack,
    this.embedded = false,
    super.key,
  });

  final bool embedded;
  final HocalistAccountController controller;
  final VoidCallback onBack;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _emailPassword = TextEditingController();
  final _newEmail = TextEditingController();
  String? _passwordError;
  String? _emailError;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _emailPassword.dispose();
    _newEmail.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentPassword.text;
    final next = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (current.isEmpty) {
      setState(() => _passwordError = 'Enter your current password.');
      return;
    }
    if (next.length < 8) {
      setState(() => _passwordError = 'Use at least 8 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _passwordError = 'The two passwords do not match.');
      return;
    }
    setState(() => _passwordError = null);
    try {
      await widget.controller.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _passwordError = error.message);
    }
  }

  Future<void> _startEmailChange() async {
    final email = _newEmail.text.trim();
    final password = _emailPassword.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _emailError = 'Confirm your password to continue.');
      return;
    }
    setState(() => _emailError = null);
    try {
      await widget.controller.requestEmailChange(
        newEmail: email,
        currentPassword: password,
      );
      _newEmail.clear();
      _emailPassword.clear();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _emailError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pendingEmail = controller.pendingEmailChange;
        final seller = controller.selectedRole == HocalistRole.seller;
        return _layout(context, [
          if (!widget.embedded)
            BuyerNestedHeader(
              title: 'Password & security',
              subtitle: 'Update your password and email.',
              backKey: const ValueKey('security-back'),
              onBack: widget.onBack,
            ),
          if (controller.passwordChangeMessage != null)
            _SecurityNote(
              key: const ValueKey('security-message'),
              text: controller.passwordChangeMessage!,
            ),
          if (pendingEmail != null)
            _SecurityNote(
              key: const ValueKey('security-pending-email'),
              text:
                  'Email change to $pendingEmail is pending confirmation. Your current email stays active until then.',
            ),
          _SecuritySection(
            title: 'Change password',
            icon: Icons.lock_outline_rounded,
            children: [
              HocalistAccountField(
                fieldKey: const ValueKey('security-current-password'),
                label: 'Current password',
                controller: _currentPassword,
                autofillHints: const [AutofillHints.password],
                seller: seller,
                enabled: !controller.formBusy,
                obscureText: true,
              ),
              const SizedBox(height: 8),
              HocalistAccountField(
                fieldKey: const ValueKey('security-new-password'),
                label: 'New password',
                controller: _newPassword,
                autofillHints: const [AutofillHints.newPassword],
                seller: seller,
                enabled: !controller.formBusy,
                obscureText: true,
              ),
              const SizedBox(height: 8),
              HocalistAccountField(
                fieldKey: const ValueKey('security-confirm-password'),
                label: 'Confirm new password',
                controller: _confirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!controller.formBusy) _changePassword();
                },
                seller: seller,
                enabled: !controller.formBusy,
                obscureText: true,
              ),
              if (_passwordError != null)
                _SecurityError(
                  key: const ValueKey('security-password-error'),
                  text: _passwordError!,
                ),
              const SizedBox(height: 8),
              AccountActionButton(
                seller: seller,
                key: const ValueKey('security-password-submit'),
                label: controller.formBusy ? 'Updating...' : 'Update password',
                onPressed: controller.formBusy ? null : _changePassword,
              ),
            ],
          ),
          _SecuritySection(
            title: 'Change email',
            icon: Icons.alternate_email_rounded,
            children: [
              Text(
                controller.email == null || controller.email!.trim().isEmpty
                    ? 'No email is on this account.'
                    : 'Current email: ${controller.email}',
                key: const ValueKey('security-current-email'),
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12.5,
                  color: BuyerUiTokens.muted,
                ),
              ),
              const SizedBox(height: 8),
              HocalistAccountField(
                fieldKey: const ValueKey('security-new-email'),
                label: 'New email address',
                controller: _newEmail,
                autofillHints: const [AutofillHints.email],
                seller: seller,
                enabled: !controller.formBusy,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              HocalistAccountField(
                fieldKey: const ValueKey('security-email-password'),
                label: 'Confirm with your password',
                controller: _emailPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!controller.formBusy) _startEmailChange();
                },
                seller: seller,
                enabled: !controller.formBusy,
                obscureText: true,
              ),
              if (_emailError != null)
                _SecurityError(
                  key: const ValueKey('security-email-error'),
                  text: _emailError!,
                ),
              const SizedBox(height: 8),
              BuyerPrimaryButton(
                key: const ValueKey('security-email-submit'),
                label: controller.formBusy
                    ? 'Starting...'
                    : 'Start email change',
                onPressed: controller.formBusy ? null : _startEmailChange,
              ),
              const SizedBox(height: 8),
              const Text(
                'Email changes need confirmation from the new address before they take effect.',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11.5,
                  height: 1.35,
                  color: BuyerUiTokens.muted,
                ),
              ),
            ],
          ),
        ]);
      },
    );
  }

  Widget _layout(BuildContext context, List<Widget> children) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
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
    return Container(
      margin: EdgeInsets.only(bottom: metrics.spacing(16)),
      padding: metrics.geometryInsets(const EdgeInsets.all(16)),
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(metrics.geometry(16)),
        border: Border.all(color: BuyerUiTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HocalistSectionIntro(title: title, icon: icon),
          ...children,
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(10)),
      child: BuyerStateNotice(
        icon: Icons.info_outline_rounded,
        tone: BuyerNoticeTone.brand,
        title: text,
      ),
    );
  }
}

class _SecurityError extends StatelessWidget {
  const _SecurityError({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: BuyerStateNotice(
      icon: Icons.error_outline_rounded,
      tone: BuyerNoticeTone.error,
      title: text,
    ),
  );
}
