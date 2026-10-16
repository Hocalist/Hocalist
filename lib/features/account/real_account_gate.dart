/// Real-provider bootstrap and account gate.
///
/// Initializes [HocalistProviderConnections] exactly once from an explicit
/// public client configuration, then renders the account gate for the
/// controller phase. Initialization or backend failures are visible states;
/// there is no silent fallback to simulated authentication.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/phase2/providers/provider_connections.dart';
import '../../data/phase2/providers/provider_runtime.dart';
import '../../data/phase2/trust/trust_backend.dart';
import '../../domain/phase2/profiles.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/onboarding_home_pages.dart';
import 'account_auth_gateway.dart';
import 'account_recovery_pages.dart';
import 'push_service_scope.dart';
import 'restricted_account_panel.dart';
import 'hocalist_account_controller.dart';

typedef HocalistConnectionsInitializer =
    Future<HocalistAccountServices> Function(String publishableKey);
typedef HocalistActiveBuilder =
    Widget Function(BuildContext context, HocalistAccountController controller);
typedef HocalistGateShellBuilder = Widget Function(Widget child);

class HocalistRealProviderBootstrap extends StatefulWidget {
  const HocalistRealProviderBootstrap({
    required this.publishableKey,
    required this.activeBuilder,
    this.initialize,
    this.shellBuilder,
    this.trustBackend,
    super.key,
  });

  final String publishableKey;
  final HocalistActiveBuilder activeBuilder;

  /// Test seam for initialization failure paths. Production uses
  /// [HocalistProviderConnections.initialize].
  final HocalistConnectionsInitializer? initialize;

  /// Wraps every pre-access state in the application shell (theme,
  /// accessibility scaling, messenger, directionality). The active subtree
  /// brings its own shell, so MaterialApps are never nested.
  final HocalistGateShellBuilder? shellBuilder;

  /// Manual review status/appeal capability for restricted accounts. Null keeps
  /// the honest refresh/logout-only state.
  final TrustBackend? trustBackend;

  @override
  State<HocalistRealProviderBootstrap> createState() =>
      _HocalistRealProviderBootstrapState();
}

class _HocalistRealProviderBootstrapState
    extends State<HocalistRealProviderBootstrap> {
  late Future<HocalistAccountServices> _future;
  HocalistAccountController? _controller;
  bool _started = false;
  HocalistRole _restoredRole = HocalistRole.buyer;

  @override
  void initState() {
    super.initState();
    _future = _initialize();
  }

  Future<HocalistAccountServices> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _restoredRole =
        preferences.getString('hocalist.auth.selected_role') == 'seller'
        ? HocalistRole.seller
        : HocalistRole.buyer;
    final initializer = widget.initialize;
    if (initializer != null) {
      return initializer(widget.publishableKey);
    }
    return HocalistProviderConnections.initialize(
      publicKey: widget.publishableKey,
    );
  }

  void _retry() {
    setState(() {
      _controller?.dispose();
      _controller = null;
      _started = false;
      _future = _initialize();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _wrap(Widget child) => widget.shellBuilder?.call(child) ?? child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HocalistAccountServices>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _wrap(
            _AccountGatePage(
              key: const ValueKey('real-account-init-failure'),
              title: 'Account connection unavailable',
              body: _initializationMessage(snapshot.error),
              primaryLabel: 'Try again',
              onPrimary: _retry,
            ),
          );
        }
        final services = snapshot.data;
        if (services == null) {
          return _wrap(const _AccountGateLoadingPage());
        }
        final controller = _controller ??= HocalistAccountController(
          auth: services.accountAuth,
          accounts: services.accounts,
          disablePush: services.disablePush,
          initialRole: _restoredRole,
        );
        if (!_started) {
          _started = true;
          controller.start();
        }
        return PushServiceScope(
          service: services is HocalistProviderConnections
              ? services.push
              : null,
          child: HocalistRealAccountGate(
            controller: controller,
            activeBuilder: widget.activeBuilder,
            shellBuilder: widget.shellBuilder,
            trustBackend: widget.trustBackend,
          ),
        );
      },
    );
  }

  static String _initializationMessage(Object? error) {
    if (error is ProviderOperationException) {
      return switch (error.code) {
        'mobile_only' =>
          'Hocalist accounts are available in the Android and iOS app.',
        'public_client_key_required' =>
          'Hocalist could not start on this device. Try again later.',
        _ =>
          'Hocalist could not connect to your account. '
              'Check your connection and try again.',
      };
    }
    return 'Hocalist could not connect to your account. '
        'Check your connection and try again.';
  }
}

/// Phase-driven account gate. Never renders app content for a membership that
/// is missing, pending, restricted or disabled.
class HocalistRealAccountGate extends StatelessWidget {
  const HocalistRealAccountGate({
    required this.controller,
    required this.activeBuilder,
    this.shellBuilder,
    this.trustBackend,
    super.key,
  });

  final HocalistAccountController controller;
  final HocalistActiveBuilder activeBuilder;
  final HocalistGateShellBuilder? shellBuilder;

  /// When provided, the restricted phase renders the manual-review status and
  /// appeal surface without mounting marketplace content.
  final TrustBackend? trustBackend;

  Widget _wrap(Widget child) => shellBuilder?.call(child) ?? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.phase) {
          case AccountAccessPhase.booting:
            return _wrap(const _AccountGateLoadingPage());
          case AccountAccessPhase.signedOut:
            return _wrap(_AccountAuthForm(controller: controller));
          case AccountAccessPhase.emailConfirmationPending:
            return _wrap(
              _AccountGatePage(
                key: const ValueKey('real-account-confirmation-pending'),
                title: 'Confirm your email',
                body:
                    'We sent a confirmation link to your email address. '
                    'Open it before logging in. Signup is not complete until '
                    'the address is confirmed.',
                primaryLabel: 'Back to log in',
                onPrimary: controller.leaveConfirmationPending,
              ),
            );
          case AccountAccessPhase.passwordRecovery:
            return _wrap(_AccountRecoveryPasswordGate(controller: controller));
          case AccountAccessPhase.recoveryEmailSent:
            return _wrap(
              AccountRecoveryEmailSentPage(
                email: controller.recoveryEmail,
                onBack: controller.leaveRecoveryEmailSent,
              ),
            );
          case AccountAccessPhase.recoveryLinkExpired:
            return _wrap(
              AccountRecoveryLinkExpiredPage(
                expired:
                    controller.recoveryLinkFailure?.kind ==
                    AccountRecoverySignalKind.expired,
                onBack: controller.leaveRecoveryLinkExpired,
              ),
            );
          case AccountAccessPhase.onboarding:
            return _wrap(_AccountOnboardingPage(controller: controller));
          case AccountAccessPhase.membershipPending:
            return _wrap(
              _AccountGatePage(
                key: const ValueKey('real-account-membership-pending'),
                title: '${_roleLabel(controller.selectedRole)} account pending',
                body:
                    'Your ${controller.selectedRole.name} account is waiting '
                    'for review. App access starts after it is active.',
                primaryLabel: 'Refresh status',
                onPrimary: controller.refresh,
                secondaryLabel: 'Log out',
                onSecondary: controller.logout,
              ),
            );
          case AccountAccessPhase.membershipRestricted:
            return _wrap(
              RestrictedAccountPanel(
                key: const ValueKey('real-account-membership-restricted'),
                controller: controller,
                backend: trustBackend,
              ),
            );
          case AccountAccessPhase.active:
            return activeBuilder(context, controller);
          case AccountAccessPhase.failed:
            return _wrap(
              _AccountGatePage(
                key: const ValueKey('real-account-failed'),
                title: 'Account unavailable',
                body:
                    controller.errorMessage ??
                    'Hocalist could not load your account. Try again.',
                primaryLabel: 'Try again',
                onPrimary: controller.refresh,
                secondaryLabel: 'Log out',
                onSecondary: controller.logout,
              ),
            );
        }
      },
    );
  }

  static String _roleLabel(HocalistRole role) =>
      role == HocalistRole.seller ? 'Seller' : 'Buyer';
}

class _AccountAuthForm extends StatefulWidget {
  const _AccountAuthForm({required this.controller});

  final HocalistAccountController controller;

  @override
  State<_AccountAuthForm> createState() => _AccountAuthFormState();
}

class _AccountAuthFormState extends State<_AccountAuthForm> {
  bool _showRecoveryRequest = false;
  String? _recoveryError;

  Future<void> _requestReset(String email) async {
    setState(() => _recoveryError = null);
    try {
      await widget.controller.requestPasswordReset(email: email);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _recoveryError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (_showRecoveryRequest) {
      return AccountRecoveryRequestPage(
        onSubmit: _requestReset,
        onBack: () {
          setState(() {
            _showRecoveryRequest = false;
            _recoveryError = null;
            widget.controller.returnToLogin = true;
          });
        },
        busy: controller.formBusy,
        error: _recoveryError,
      );
    }
    final role = controller.selectedRole == HocalistRole.seller
        ? ApprovedAccountRole.seller
        : ApprovedAccountRole.buyer;
    void unsupported(String message) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ApprovedAccountCreationPage(
              key: ValueKey('real-account-${role.name}'),
              role: role,
              initialLoginMode: controller.returnToLogin,
              name: controller.suggestedDisplayName,
              onNameChanged: (_) {},
              onRoleChanged: (next) async {
                final selected = next == ApprovedAccountRole.seller
                    ? HocalistRole.seller
                    : HocalistRole.buyer;
                // This preference retains an explicit choice across a browser
                // callback. Membership authorization still comes from the server.
                final preferences = await SharedPreferences.getInstance();
                await preferences.setString(
                  'hocalist.auth.selected_role',
                  selected.name,
                );
                if (mounted) controller.selectRole(selected);
              },
              onSignup: () {},
              onLogin: () {},
              onUploadProfile: () =>
                  unsupported('Profile photo upload is not available yet.'),
              onRealSubmit: (submission) => submission.loginMode
                  ? controller.logInWithEmail(
                      email: submission.email,
                      password: submission.password,
                    )
                  : controller.signUpWithEmail(
                      name: submission.name,
                      email: submission.email,
                      password: submission.password,
                    ),
              onRealGoogle: controller.signInWithGoogle,
              onRealEmailLink: hocalistLocalWebTest
                  ? (email, name) =>
                        controller.requestEmailLink(email: email, name: name)
                  : null,
              onPhoneRequestCode: (phone, {required signup}) =>
                  controller.requestPhoneCode(phone: phone, signup: signup),
              onPhoneConfirmCode: (phone, code) =>
                  controller.confirmPhoneCode(phone: phone, code: code),
              onApple: null,
              onFacebook: null,
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton(
              key: const ValueKey('real-account-forgot-password'),
              onPressed: controller.formBusy
                  ? null
                  : () => setState(() => _showRecoveryRequest = true),
              child: const Text('Forgot password?'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRecoveryPasswordGate extends StatefulWidget {
  const _AccountRecoveryPasswordGate({required this.controller});

  final HocalistAccountController controller;

  @override
  State<_AccountRecoveryPasswordGate> createState() =>
      _AccountRecoveryPasswordGateState();
}

class _AccountRecoveryPasswordGateState
    extends State<_AccountRecoveryPasswordGate> {
  String? _error;
  String? _logoutError;

  Future<void> _submit(String password) async {
    setState(() => _error = null);
    try {
      await widget.controller.updateRecoveredPassword(password: password);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _cancel() async {
    setState(() => _logoutError = null);
    try {
      await widget.controller.logout();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _logoutError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _logoutError = 'Could not sign out. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Stack(
      children: [
        AccountRecoveryPasswordPage(
          onSubmit: _submit,
          onCancel: _cancel,
          busy: controller.formBusy,
          error: _error ?? _logoutError,
        ),
      ],
    );
  }
}

class _AccountOnboardingPage extends StatefulWidget {
  const _AccountOnboardingPage({required this.controller});

  final HocalistAccountController controller;

  @override
  State<_AccountOnboardingPage> createState() => _AccountOnboardingPageState();
}

class _AccountOnboardingPageState extends State<_AccountOnboardingPage> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.controller.suggestedDisplayName,
  );
  String? _error;
  String? _logoutError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the name shown on your account.');
      return;
    }
    setState(() => _error = null);
    try {
      await widget.controller.onboardSelectedRole(displayName: name);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _logout() async {
    setState(() => _logoutError = null);
    try {
      await widget.controller.logout();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _logoutError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _logoutError = 'Could not sign out. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final role = controller.selectedRole == HocalistRole.seller
        ? 'seller'
        : 'buyer';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 24),
          children: [
            Text(
              'Finish your $role account',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: BuyerUiTokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the name other people will see on Hocalist.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: BuyerUiTokens.muted,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('real-account-onboarding-name'),
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('real-account-onboarding-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xffb3261e),
                ),
              ),
            ],
            const SizedBox(height: 16),
            BuyerPrimaryButton(
              key: const ValueKey('real-account-onboarding-submit'),
              label: controller.formBusy
                  ? 'Creating account...'
                  : 'Create $role account',
              onPressed: controller.formBusy ? null : _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('real-account-onboarding-logout'),
              onPressed: controller.busy ? null : _logout,
              child: const Text('Log out'),
            ),
            if (_logoutError != null) ...[
              const SizedBox(height: 6),
              Text(
                _logoutError!,
                key: const ValueKey('real-account-gate-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xffb3261e),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountGateLoadingPage extends StatelessWidget {
  const _AccountGateLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: ValueKey('real-account-loading'),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _AccountGatePage extends StatefulWidget {
  const _AccountGatePage({
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;

  /// Async secondary action (logout). Failures are shown inline on this page
  /// so no ScaffoldMessenger from outside the app shell is required.
  final Future<void> Function()? onSecondary;

  @override
  State<_AccountGatePage> createState() => _AccountGatePageState();
}

class _AccountGatePageState extends State<_AccountGatePage> {
  String? _actionError;

  Future<void> _runSecondary() async {
    final action = widget.onSecondary;
    if (action == null) return;
    setState(() => _actionError = null);
    try {
      await action();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _actionError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Could not sign out. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BuyerUiTokens.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: BuyerUiTokens.muted,
                  ),
                ),
                if (widget.primaryLabel != null &&
                    widget.onPrimary != null) ...[
                  const SizedBox(height: 22),
                  BuyerPrimaryButton(
                    label: widget.primaryLabel!,
                    onPressed: widget.onPrimary,
                  ),
                ],
                if (widget.secondaryLabel != null &&
                    widget.onSecondary != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _runSecondary,
                    child: Text(widget.secondaryLabel!),
                  ),
                ],
                if (_actionError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _actionError!,
                    key: const ValueKey('real-account-gate-error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xffb3261e),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
