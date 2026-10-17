import 'package:hocalist/theme/adaptive_palette.dart';
import 'dart:async';
import '../../components/notification_indicator.dart';

import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/commercial/withdrawal_backend.dart';
import '../../data/phase2/meetings/meeting_codecs.dart';
import '../../data/phase2/maps/meeting_directions.dart';
import '../../data/phase2/reviews/review_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/notifications.dart';
import '../../domain/phase2/requests.dart';
import '../../domain/phase2/reviews.dart';
import '../../theme/accessibility_visuals.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../account/hocalist_account_controller.dart';
import 'approved_replica_metrics.dart';
import 'buyer_bottom_navigation.dart';

const _approvedAssetRoot = 'assets/approved_onboarding_home';
const _navy = BuyerUiTokens.text;
const _blue = BuyerUiTokens.action;
const _muted = BuyerUiTokens.muted;
const _green = Color(0xff078b2d);
const _line = BuyerUiTokens.border;
const _lavender = BuyerUiTokens.softSurface;

enum ApprovedAccountRole { buyer, seller }

/// One submitted account form with the values the user actually typed.
class ApprovedAccountSubmission {
  const ApprovedAccountSubmission({
    required this.role,
    required this.loginMode,
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
  });

  final ApprovedAccountRole role;
  final bool loginMode;
  final String name;
  final String email;
  final String password;
  final String phone;
}

typedef ApprovedAccountSubmit =
    Future<void> Function(ApprovedAccountSubmission submission);
typedef ApprovedPhoneRequest =
    Future<void> Function(String phone, {required bool signup});
typedef ApprovedPhoneConfirm = Future<void> Function(String phone, String code);

/// Ephemeral signup intent shared across role changes; never persisted to disk.
class ApprovedAccountDraft {
  String name = '', email = '', phone = '', password = '', confirmation = '';
  bool? loginMode;
  void clear() {
    name = email = phone = password = confirmation = '';
    loginMode = null;
  }
}

class ApprovedAccountCreationPage extends StatefulWidget {
  const ApprovedAccountCreationPage({
    required this.role,
    required this.name,
    required this.onNameChanged,
    required this.onRoleChanged,
    this.onClose,
    required this.onSignup,
    required this.onLogin,
    this.onGoogle,
    this.onApple,
    this.onFacebook,
    this.onUploadProfile,
    this.onRealSubmit,
    this.onRealGoogle,
    this.onRealEmailLink,
    this.onPhoneRequestCode,
    this.onPhoneConfirmCode,
    this.initialLoginMode = false,
    this.phoneSheet = false,
    this.draft,
    this.onForgotPassword,
    super.key,
  });

  final ApprovedAccountRole role;
  final String name;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<ApprovedAccountRole> onRoleChanged;

  /// Hidden when null; the real account gate has no previous screen to close.
  final VoidCallback? onClose;

  /// Prototype callbacks, used only when no real submit handler is supplied.
  final VoidCallback onSignup;
  final VoidCallback onLogin;
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final VoidCallback? onFacebook;
  final VoidCallback? onUploadProfile;

  /// Real-provider handlers. When [onRealSubmit] is set, the form values are
  /// validated and submitted through it instead of the prototype callbacks.
  final ApprovedAccountSubmit? onRealSubmit;
  final Future<void> Function()? onRealGoogle;
  final Future<void> Function(String email, String name)? onRealEmailLink;
  final ApprovedPhoneRequest? onPhoneRequestCode;
  final ApprovedPhoneConfirm? onPhoneConfirmCode;
  final bool initialLoginMode;
  final bool phoneSheet;
  final ApprovedAccountDraft? draft;
  final VoidCallback? onForgotPassword;

  @override
  State<ApprovedAccountCreationPage> createState() =>
      _ApprovedAccountCreationPageState();
}

class _ApprovedAccountCreationPageState
    extends State<ApprovedAccountCreationPage> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _phonePattern = RegExp(r'^\+[1-9][0-9]{7,14}$');

  bool _loginMode = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _submitting = false;
  String? _formError;
  String? _providerNotice;
  String _email = '';
  String _phone = '';
  String _password = '';
  String _confirmPassword = '';
  String _name = '';

  bool _phoneMode = false;
  bool _codeSent = false;
  String _code = '';
  int _cooldown = 0;
  Timer? _cooldownTimer;

  bool get _phoneAvailable =>
      widget.onPhoneRequestCode != null && widget.onPhoneConfirmCode != null;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _name = draft?.name.isNotEmpty == true ? draft!.name : widget.name;
    _email = draft?.email ?? '';
    _phone = draft?.phone ?? '';
    _password = draft?.password ?? '';
    _confirmPassword = draft?.confirmation ?? '';
    _loginMode = draft?.loginMode ?? widget.initialLoginMode;
    _phoneMode = widget.phoneSheet;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String fallback,
  }) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _formError = null;
      _providerNotice = null;
    });
    try {
      await action();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } catch (_) {
      if (mounted) setState(() => _formError = fallback);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validateEmailForm() {
    if (!_loginMode && _name.trim().isEmpty) return 'Enter your name.';
    final email = _email.trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    if (_password.isEmpty) return 'Enter your password.';
    if (_password.length < 6) {
      return 'Passwords must be at least 6 characters.';
    }
    if (!_loginMode && _password != _confirmPassword) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submitEmail() async {
    final handler = widget.onRealSubmit;
    if (handler == null) {
      // Explicit prototype mode keeps its original callback behavior.
      if (_loginMode) {
        widget.onLogin();
        widget.draft?.clear();
      } else {
        widget.onSignup();
        widget.draft?.clear();
      }
      return;
    }
    final problem = _validateEmailForm();
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }
    await _run(() async {
      await handler(
        ApprovedAccountSubmission(
          role: widget.role,
          loginMode: _loginMode,
          name: _name.trim(),
          email: _email.trim(),
          password: _password,
          phone: _phone.trim(),
        ),
      );
      widget.draft?.clear();
    }, fallback: 'Sign-in failed. Try again.');
  }

  Future<void> _submitGoogle() async {
    if (_submitting) return;
    final handler = widget.onRealGoogle;
    if (handler == null) {
      if (widget.onGoogle != null) {
        widget.onGoogle!();
      } else {
        _providerUnavailable('Google');
      }
      return;
    }
    await _run(() async {
      await handler();
      if (mounted) {
        setState(
          () => _providerNotice =
              'Finish signing in with Google in your browser.',
        );
      }
    }, fallback: 'Google sign-in could not start. Try again.');
  }

  Future<void> _requestEmailLink() async {
    final handler = widget.onRealEmailLink;
    if (handler == null || _submitting) return;
    final email = _email.trim();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      setState(() => _formError = 'Enter a valid email address.');
      return;
    }
    if (!_loginMode && _name.trim().isEmpty) {
      setState(() => _formError = 'Enter your name.');
      return;
    }
    await _run(() async {
      await handler(email, _name.trim());
      if (mounted) {
        setState(
          () => _providerNotice = 'Check your email for a sign-in link.',
        );
      }
    }, fallback: 'The sign-in link could not be sent. Try again.');
  }

  void _providerUnavailable(String provider) {
    setState(
      () => _providerNotice =
          '$provider sign-in is unavailable. Use email or phone instead.',
    );
  }

  Future<void> _requestCode() async {
    if (!_loginMode && _name.trim().isEmpty) {
      setState(() => _formError = 'Enter your name.');
      return;
    }
    final phone = _phone.trim();
    if (phone.isEmpty) {
      setState(() => _formError = 'Enter your phone number.');
      return;
    }
    if (!_phonePattern.hasMatch(phone)) {
      setState(
        () => _formError = 'Use a country code, for example +14155550123.',
      );
      return;
    }
    await _run(() async {
      await widget.onPhoneRequestCode!(phone, signup: !_loginMode);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _code = '';
      });
      _startCooldown();
    }, fallback: 'The code could not be sent. Try again.');
  }

  Future<void> _confirmCode() async {
    final code = _code.trim();
    if (code.isEmpty) {
      setState(() => _formError = 'Enter the code from the SMS message.');
      return;
    }
    await _run(() async {
      await widget.onPhoneConfirmCode!(_phone.trim(), code);
      widget.draft?.clear();
      if (mounted && widget.phoneSheet) Navigator.of(context).pop();
    }, fallback: 'The code could not be verified. Try again.');
  }

  Future<void> _openPhoneSheet() async {
    final draft = widget.draft ?? ApprovedAccountDraft();
    draft.name = _name;
    draft.phone = _phone;
    draft.loginMode = _loginMode;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HocalistPalette.surface(context, Colors.white),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .9,
          ),
          child: ApprovedAccountCreationPage(
            role: widget.role,
            name: _name,
            draft: draft,
            phoneSheet: true,
            initialLoginMode: _loginMode,
            onNameChanged: widget.onNameChanged,
            onRoleChanged: widget.onRoleChanged,
            onSignup: widget.onSignup,
            onLogin: widget.onLogin,
            onClose: () => Navigator.of(sheetContext).pop(),
            onPhoneRequestCode: widget.onPhoneRequestCode,
            onPhoneConfirmCode: widget.onPhoneConfirmCode,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _name = draft.name;
      _phone = draft.phone;
    });
  }

  void _cancelPhone() {
    if (widget.phoneSheet) {
      Navigator.of(context).pop();
      return;
    }
    _cooldownTimer?.cancel();
    setState(() {
      _phoneMode = false;
      _codeSent = false;
      _code = '';
      _cooldown = 0;
      _formError = null;
      _providerNotice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final accessibilityReflow = metrics.accessibilityReflow;
    final loginMode = _loginMode;
    final phoneMode = _phoneMode;
    final title = phoneMode
        ? (_codeSent ? 'Enter your code' : 'Continue with phone')
        : (loginMode ? 'Log in to your account' : 'Create your account');
    final subtitle = phoneMode
        ? (_codeSent
              ? 'Enter the code we texted to your phone.'
              : 'We will text a verification code. Standard message rates may apply.')
        : (loginMode
              ? 'Welcome back to Hocalist.'
              : 'Join Hocalist to get started.');

    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: metrics.geometryInsets(
            const EdgeInsets.fromLTRB(22, 6, 22, 16),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.innerContentMaxWidth(
                  referenceHorizontalInset: 22,
                ),
              ),
              child: Column(
                children: [
                  SizedBox(
                    key: const ValueKey('approved-account-modal-header'),
                    height: metrics.geometry(widget.phoneSheet ? 40 : 103),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: metrics.geometry(38),
                            height: metrics.geometry(4),
                            decoration: BoxDecoration(
                              color: HocalistPalette.surface(
                                context,
                                const Color(0xffc8c9d9),
                              ),
                              borderRadius: BorderRadius.circular(
                                metrics.geometry(99),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onClose != null)
                          Positioned(
                            top: metrics.geometry(4),
                            right: 0,
                            child: _ApprovedAssetButton(
                              tooltip: 'Close',
                              asset: 'account-close.png',
                              size: 36,
                              onTap: widget.onClose!,
                            ),
                          ),
                        if (!widget.phoneSheet)
                          Positioned(
                            top: metrics.geometry(29),
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Semantics(
                                button: true,
                                label: 'Upload profile image',
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onUploadProfile,
                                  child: Image.asset(
                                    '$_approvedAssetRoot/account-profile-add.png',
                                    width: metrics.geometry(74),
                                    height: metrics.geometry(74),
                                    filterQuality: FilterQuality.high,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: metrics.geometry(8)),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: _text(
                      context,
                      size: 22,
                      weight: FontWeight.w800,
                      color: _navy,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: metrics.geometry(5)),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: _text(context, size: 12.5, color: _muted),
                  ),
                  SizedBox(height: metrics.geometry(23)),
                  if (!widget.phoneSheet)
                    _ApprovedRoleSelector(
                      role: widget.role,
                      stacked: accessibilityReflow,
                      onChanged: widget.onRoleChanged,
                    ),
                  SizedBox(height: metrics.geometry(23)),
                  if (!phoneMode) ...[
                    if (!loginMode) ...[
                      _ApprovedField(
                        key: const ValueKey('approved-account-name-field'),
                        iconAsset: 'account-person.png',
                        hint: widget.role == ApprovedAccountRole.buyer
                            ? 'Full name'
                            : 'Store or seller name',
                        initialValue: _name,
                        onChanged: (value) {
                          _name = value;
                          widget.draft?.name = value;
                          widget.draft?.name = value;
                          widget.onNameChanged(value);
                        },
                      ),
                      SizedBox(height: metrics.geometry(9)),
                    ],
                    _ApprovedField(
                      key: const ValueKey('approved-account-email-field'),
                      iconAsset: 'account-mail.png',
                      hint: 'Email address',
                      keyboardType: TextInputType.emailAddress,
                      initialValue: _email,
                      onChanged: (value) {
                        _email = value;
                        widget.draft?.email = value;
                      },
                    ),
                    SizedBox(height: metrics.geometry(9)),
                    if (!loginMode) ...[
                      _ApprovedField(
                        key: const ValueKey('approved-account-phone-field'),
                        iconAsset: 'account-phone.png',
                        hint: 'Phone number (optional)',
                        keyboardType: TextInputType.phone,
                        initialValue: _phone,
                        onChanged: (value) {
                          _phone = value;
                          widget.draft?.phone = value;
                        },
                      ),
                      SizedBox(height: metrics.geometry(9)),
                    ],
                    _ApprovedField(
                      key: const ValueKey('approved-account-password-field'),
                      iconAsset: 'account-lock.png',
                      hint: 'Password',
                      obscureText: !_passwordVisible,
                      initialValue: _password,
                      onChanged: (value) {
                        _password = value;
                        widget.draft?.password = value;
                      },
                      suffix: _ApprovedFieldAssetButton(
                        key: const ValueKey('approved-account-password-eye'),
                        tooltip: _passwordVisible
                            ? 'Hide password'
                            : 'Show password',
                        asset: 'account-eye.png',
                        onTap: () => setState(
                          () => _passwordVisible = !_passwordVisible,
                        ),
                      ),
                    ),
                    if (!loginMode) ...[
                      SizedBox(height: metrics.geometry(9)),
                      _ApprovedField(
                        key: const ValueKey(
                          'approved-account-confirm-password-field',
                        ),
                        iconAsset: 'account-lock.png',
                        hint: 'Confirm password',
                        obscureText: !_confirmPasswordVisible,
                        initialValue: _confirmPassword,
                        onChanged: (value) {
                          _confirmPassword = value;
                          widget.draft?.confirmation = value;
                        },
                        suffix: _ApprovedFieldAssetButton(
                          key: const ValueKey(
                            'approved-account-confirm-password-eye',
                          ),
                          tooltip: _confirmPasswordVisible
                              ? 'Hide confirm password'
                              : 'Show confirm password',
                          asset: 'account-eye.png',
                          onTap: () => setState(
                            () => _confirmPasswordVisible =
                                !_confirmPasswordVisible,
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    if (!loginMode) ...[
                      _ApprovedField(
                        key: const ValueKey('approved-account-name-field'),
                        iconAsset: 'account-person.png',
                        hint: widget.role == ApprovedAccountRole.buyer
                            ? 'Full name'
                            : 'Store or seller name',
                        initialValue: _name,
                        readOnly: _codeSent,
                        onChanged: (value) {
                          _name = value;
                          widget.draft?.name = value;
                          widget.onNameChanged(value);
                        },
                      ),
                      SizedBox(height: metrics.geometry(9)),
                    ],
                    _ApprovedField(
                      key: const ValueKey('approved-account-phone-field'),
                      iconAsset: 'account-phone.png',
                      hint: 'Phone number (+country code)',
                      keyboardType: TextInputType.phone,
                      readOnly: _codeSent,
                      initialValue: _phone,
                      onChanged: (value) {
                        _phone = value;
                        widget.draft?.phone = value;
                      },
                    ),
                    if (_codeSent) ...[
                      SizedBox(height: metrics.geometry(9)),
                      _ApprovedField(
                        key: const ValueKey('approved-account-code-field'),
                        iconAsset: 'account-lock.png',
                        hint: 'Verification code',
                        keyboardType: TextInputType.number,
                        onChanged: (value) => _code = value,
                      ),
                    ],
                  ],
                  if (loginMode && !phoneMode)
                    TextButton(
                      key: const ValueKey('approved-account-forgot-password'),
                      onPressed: _submitting
                          ? null
                          : widget.onForgotPassword ??
                                () => setState(
                                  () => _providerNotice =
                                      'Password recovery requires the connected account service.',
                                ),
                      child: const Text('Forgot password?'),
                    ),
                  if (_formError != null) ...[
                    SizedBox(height: metrics.geometry(10)),
                    Text(
                      _formError!,
                      key: const ValueKey('approved-account-error'),
                      textAlign: TextAlign.center,
                      style: _text(
                        context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: const Color(0xffb3261e),
                      ),
                    ),
                  ],
                  if (_providerNotice != null) ...[
                    SizedBox(height: metrics.geometry(10)),
                    Text(
                      _providerNotice!,
                      key: const ValueKey('approved-account-provider-notice'),
                      textAlign: TextAlign.center,
                      style: _text(
                        context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: _blue,
                      ),
                    ),
                  ],
                  SizedBox(height: metrics.geometry(15)),
                  _ApprovedPrimaryButton(
                    key: const ValueKey('approved-account-primary-action'),
                    label: phoneMode
                        ? (_codeSent ? 'Verify code' : 'Send code')
                        : (loginMode ? 'Log in' : 'Create account'),
                    busy: _submitting,
                    onTap: phoneMode
                        ? (_codeSent ? _confirmCode : _requestCode)
                        : _submitEmail,
                  ),
                  if (!phoneMode && widget.onRealEmailLink != null) ...[
                    SizedBox(height: metrics.geometry(4)),
                    TextButton(
                      key: const ValueKey('approved-account-email-link'),
                      onPressed: _submitting ? null : _requestEmailLink,
                      child: Text(
                        'Email me a test sign-in link',
                        style: _text(
                          context,
                          size: 11.5,
                          weight: FontWeight.w800,
                          color: _blue,
                        ),
                      ),
                    ),
                  ],
                  if (phoneMode) ...[
                    SizedBox(height: metrics.geometry(4)),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_codeSent)
                          TextButton(
                            key: const ValueKey('approved-account-resend-code'),
                            onPressed: (_submitting || _cooldown > 0)
                                ? null
                                : _requestCode,
                            child: Text(
                              _cooldown > 0
                                  ? 'Resend code (${_cooldown}s)'
                                  : 'Resend code',
                              style: _text(
                                context,
                                size: 11.5,
                                weight: FontWeight.w800,
                                color: _blue,
                              ),
                            ),
                          ),
                        TextButton(
                          key: const ValueKey('approved-account-phone-cancel'),
                          onPressed: _submitting ? null : _cancelPhone,
                          child: Text(
                            _codeSent ? 'Cancel' : 'Use email instead',
                            style: _text(
                              context,
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: _blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    SizedBox(height: metrics.geometry(14)),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: _line)),
                        Padding(
                          padding: metrics.geometryInsets(
                            const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          child: Text(
                            'or continue with',
                            style: _text(context, size: 11, color: _muted),
                          ),
                        ),
                        const Expanded(child: Divider(color: _line)),
                      ],
                    ),
                    SizedBox(height: metrics.geometry(11)),
                    _ApprovedSocialButton(
                      key: const ValueKey('approved-account-google-action'),
                      label: 'Continue with Google',
                      asset: 'social-google.png',
                      onTap: _submitGoogle,
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    _ApprovedSocialButton(
                      key: const ValueKey('approved-account-apple-action'),
                      label: 'Continue with Apple',
                      asset: 'social-apple.png',
                      onTap:
                          widget.onApple ?? () => _providerUnavailable('Apple'),
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    _ApprovedSocialButton(
                      key: const ValueKey('approved-account-facebook-action'),
                      label: 'Continue with Facebook',
                      asset: 'social-facebook.png',
                      onTap:
                          widget.onFacebook ??
                          () => _providerUnavailable('Facebook'),
                    ),
                    if (_phoneAvailable) ...[
                      SizedBox(height: metrics.geometry(8)),
                      TextButton(
                        key: const ValueKey('approved-account-phone-action'),
                        onPressed: _submitting ? null : _openPhoneSheet,
                        child: Text(
                          'Continue with phone',
                          style: _text(
                            context,
                            size: 11.5,
                            weight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: metrics.geometry(8)),
                    Wrap(
                      key: const ValueKey('approved-account-login-row'),
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          loginMode
                              ? 'Don\'t have an account? '
                              : 'Already have an account? ',
                          style: _text(context, size: 11.5, color: _muted),
                        ),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => setState(() {
                                  _loginMode = !loginMode;
                                  widget.draft?.loginMode = _loginMode;
                                  widget.draft?.loginMode = _loginMode;
                                  _formError = null;
                                  _providerNotice = null;
                                }),
                          style: TextButton.styleFrom(
                            minimumSize: metrics.geometrySize(
                              const Size(44, 36),
                            ),
                            padding: metrics.geometryInsets(
                              const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            loginMode ? 'Sign up' : 'Log in',
                            style: _text(
                              context,
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: _blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedRoleSelector extends StatelessWidget {
  const _ApprovedRoleSelector({
    required this.role,
    required this.stacked,
    required this.onChanged,
  });

  final ApprovedAccountRole role;
  final bool stacked;
  final ValueChanged<ApprovedAccountRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final buyer = _ApprovedRoleButton(
      label: 'I am buying',
      iconAsset: 'account-role-buyer.png',
      selected: role == ApprovedAccountRole.buyer,
      onTap: () => onChanged(ApprovedAccountRole.buyer),
    );
    final seller = _ApprovedRoleButton(
      label: 'I am selling',
      iconAsset: 'account-role-seller.png',
      selected: role == ApprovedAccountRole.seller,
      onTap: () => onChanged(ApprovedAccountRole.seller),
    );
    if (stacked) {
      return Column(
        children: [
          buyer,
          SizedBox(height: metrics.geometry(10)),
          seller,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: buyer),
        SizedBox(width: metrics.geometry(8)),
        Expanded(child: seller),
      ],
    );
  }
}

class _ApprovedRoleButton extends StatelessWidget {
  const _ApprovedRoleButton({
    required this.label,
    required this.iconAsset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: HocalistPalette.surface(
          context,
          selected ? const Color(0xfff7f6ff) : Colors.white,
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
          child: Container(
            key: ValueKey('approved-account-role-$label'),
            constraints: BoxConstraints(minHeight: metrics.geometry(42)),
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(metrics.geometry(10)),
              border: Border.all(
                color: HocalistPalette.border(
                  context,
                  selected ? const Color(0xffaaa6ff) : const Color(0xffdfe3ee),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BuyerAssetIcon(
                  asset: '$_approvedAssetRoot/$iconAsset',
                  slotSize: metrics.geometry(22),
                ),
                SizedBox(width: metrics.geometry(8)),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: _text(
                      context,
                      size: 12.5,
                      weight: FontWeight.w800,
                      color: selected ? _blue : _navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedField extends StatelessWidget {
  const _ApprovedField({
    required this.iconAsset,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.readOnly = false,
    super.key,
  });

  final String iconAsset;
  final String hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: _text(context, size: 12, color: _navy),
      decoration: InputDecoration(
        isDense: true,
        constraints: BoxConstraints(minHeight: metrics.geometry(44)),
        hintText: hint,
        hintStyle: _text(context, size: 12, color: _muted),
        prefixIcon: Padding(
          padding: EdgeInsets.all(metrics.geometry(10)),
          child: BuyerAssetIcon(
            asset: '$_approvedAssetRoot/$iconAsset',
            slotSize: metrics.geometry(20),
          ),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: metrics.geometry(42),
          minHeight: metrics.geometry(42),
        ),
        suffixIconConstraints: BoxConstraints(
          minWidth: metrics.geometry(42),
          minHeight: metrics.geometry(42),
        ),
        suffixIcon: suffix,
        contentPadding: metrics.geometryInsets(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        filled: true,
        fillColor: HocalistPalette.surface(context, Colors.white),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
          borderSide: BorderSide(
            color: HocalistPalette.border(context, const Color(0xffdfe3ee)),
            width: metrics.geometry(1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
          borderSide: BorderSide(
            color: HocalistPalette.border(context, _blue),
            width: metrics.geometry(1.5),
          ),
        ),
      ),
    );
  }
}

class _ApprovedFieldAssetButton extends StatelessWidget {
  const _ApprovedFieldAssetButton({
    required this.tooltip,
    required this.asset,
    required this.onTap,
    super.key,
  });

  final String tooltip;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: SizedBox(
          width: metrics.geometry(36),
          height: metrics.geometry(36),
          child: Material(
            color: HocalistPalette.surface(context, Colors.transparent),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(metrics.geometry(4)),
                child: BuyerAssetIcon(
                  asset: '$_approvedAssetRoot/$asset',
                  slotSize: metrics.geometry(28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedSocialButton extends StatelessWidget {
  const _ApprovedSocialButton({
    required this.label,
    required this.asset,
    required this.onTap,
    super.key,
  });

  final String label;
  final String asset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: HocalistPalette.text(context, _navy),
          minimumSize: Size.fromHeight(metrics.geometry(42)),
          side: BorderSide(
            color: HocalistPalette.border(context, const Color(0xffdfe3ee)),
            width: metrics.geometry(1),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(99)),
          ),
        ),
        icon: Image.asset(
          '$_approvedAssetRoot/$asset',
          width: metrics.geometry(18),
          height: metrics.geometry(18),
        ),
        label: Text(
          label,
          style: _text(
            context,
            size: 11.5,
            weight: FontWeight.w700,
            color: onTap == null ? _muted : _navy,
          ),
        ),
      ),
    );
  }
}

class ApprovedBuyerBenefitsPage extends StatefulWidget {
  const ApprovedBuyerBenefitsPage({
    required this.name,
    required this.onClose,
    required this.onFinish,
    this.initialStep = 0,
    super.key,
  });

  final String name;
  final VoidCallback onClose;
  final VoidCallback onFinish;
  final int initialStep;

  @override
  State<ApprovedBuyerBenefitsPage> createState() =>
      _ApprovedBuyerBenefitsPageState();
}

class _ApprovedBuyerBenefitsPageState extends State<ApprovedBuyerBenefitsPage> {
  static const _videoPreviewDuration = Duration(seconds: 8);

  final _benefitsScrollController = ScrollController();
  Timer? _videoPreviewTimer;
  int _videoIndex = 0;
  bool _showScrollCue = true;

  static const _firstBenefits = [
    _ApprovedBenefit(
      'benefit-reward.png',
      'Earn rewards on every purchase',
      'Sellers pay you to have the chance to earn your business. Choose one to buy from and keep your earnings.',
    ),
    _ApprovedBenefit(
      'benefit-tag.png',
      'Receive the best offers',
      'Sellers compete for your business so you get better deals.',
    ),
    _ApprovedBenefit(
      'benefit-shield.png',
      'Post safely and privately',
      'Sellers only see a name, but can\'t contact you until you choose to talk to them.',
    ),
    _ApprovedBenefit(
      'benefit-chat.png',
      'Chat and compare easily',
      'Chat with sellers, compare offers, and choose what\'s best for you.',
    ),
  ];

  static const _secondBenefits = [
    _ApprovedBenefit(
      'benefit-location.png',
      'Mileage logic for less driving',
      'Only sellers within the mileage distance you choose will be able to target you.',
    ),
    _ApprovedBenefit(
      'benefit-medal.png',
      'Build your reputation for better offers',
      'Buying more means you\'re a prime customer, sellers get a notification when you post to offer you special deals.',
    ),
    _ApprovedBenefit(
      'benefit-payment-shield.png',
      'We protect your choices & reward you for it',
      'Choose who to talk to, meet safely, and complete item payment on your terms outside the app.',
    ),
    _ApprovedBenefit(
      'benefit-review-dollar.png',
      'Reviewing Your Seller Pays Off',
      'Get extra commissions when reviewing a seller; honesty pays off every time.',
    ),
  ];

  static const _videoPreviews = [
    'buyer-video-welcome.png',
    'buyer-video-payment.png',
  ];

  @override
  void initState() {
    super.initState();
    _benefitsScrollController.addListener(_updateScrollCue);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollCue());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !HocalistMotion.reduced(context)) {
        _videoPreviewTimer = Timer(_videoPreviewDuration, _showSecondVideo);
      }
    });
  }

  void _showSecondVideo() {
    if (!mounted ||
        HocalistMotion.reduced(context) ||
        _videoIndex == _videoPreviews.length - 1) {
      return;
    }
    setState(() => _videoIndex = 1);
  }

  void _updateScrollCue() {
    if (!mounted || !_benefitsScrollController.hasClients) return;
    final position = _benefitsScrollController.position;
    final shouldShow =
        position.maxScrollExtent > 8 &&
        position.pixels < position.maxScrollExtent - 8;
    if (_showScrollCue != shouldShow) {
      setState(() => _showScrollCue = shouldShow);
    }
  }

  @override
  void dispose() {
    _videoPreviewTimer?.cancel();
    _benefitsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final firstName = widget.name.trim().isEmpty
        ? ''
        : widget.name.trim().split(RegExp(r'\s+')).first;
    final videoPreview = _videoPreviews[_videoIndex];
    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      child: SafeArea(
        child: Padding(
          padding: metrics.geometryInsets(
            const EdgeInsets.fromLTRB(26, 18, 26, 14),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.innerContentMaxWidth(
                  referenceHorizontalInset: 26,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _ApprovedAssetButton(
                      tooltip: 'Close',
                      asset: 'account-close.png',
                      size: 36,
                      onTap: widget.onClose,
                    ),
                  ),
                  SizedBox(height: metrics.geometry(5)),
                  _ApprovedBuyerWelcome(name: firstName),
                  SizedBox(height: metrics.geometry(14)),
                  Center(
                    child: SizedBox(
                      key: const ValueKey('approved-benefits-video'),
                      width: metrics.geometry(272),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          metrics.geometry(10),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: metrics.geometry(12),
                              color: HocalistPalette.surface(
                                context,
                                Colors.black,
                              ),
                              padding: EdgeInsets.only(
                                left: metrics.geometry(7),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: List.generate(
                                  3,
                                  (index) => Container(
                                    width: metrics.geometry(6),
                                    height: metrics.geometry(6),
                                    margin: EdgeInsets.only(
                                      right: metrics.geometry(4),
                                    ),
                                    decoration: BoxDecoration(
                                      color: HocalistPalette.surface(
                                        context,
                                        Color(0xffa9a9a9),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: HocalistMotion.duration(context, 240),
                              child: Semantics(
                                key: ValueKey(videoPreview),
                                image: true,
                                label:
                                    'Buyer welcome video ${_videoIndex + 1} of ${_videoPreviews.length} preview',
                                child: Image.asset(
                                  '$_approvedAssetRoot/$videoPreview',
                                  fit: BoxFit.fitWidth,
                                  filterQuality: FilterQuality.high,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: metrics.geometry(14)),
                  Expanded(
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          key: const ValueKey('approved-benefits-scroll'),
                          controller: _benefitsScrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(
                            bottom: metrics.geometry(42),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'As a buyer, you will:',
                                style: _text(
                                  context,
                                  size: 16,
                                  weight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              SizedBox(height: metrics.geometry(7)),
                              for (final benefit in _firstBenefits) ...[
                                _ApprovedBenefitCard(benefit: benefit),
                                SizedBox(height: metrics.geometry(6)),
                              ],
                              for (final benefit in _secondBenefits) ...[
                                _ApprovedBenefitCard(benefit: benefit),
                                SizedBox(height: metrics.geometry(6)),
                              ],
                              const _ApprovedFairnessBanner(),
                              SizedBox(height: metrics.geometry(20)),
                              _ApprovedPrimaryButton(
                                key: const ValueKey(
                                  'approved-benefits-primary',
                                ),
                                label: 'Jump to dashboard',
                                referenceHeight: 54,
                                onTap: widget.onFinish,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showScrollCue ? 1 : 0,
                              duration: HocalistMotion.duration(context, 180),
                              child: const _ApprovedBenefitsScrollCue(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedBenefitsScrollCue extends StatelessWidget {
  const _ApprovedBenefitsScrollCue();

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      height: metrics.geometry(42),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00ffffff),
            HocalistPalette.surface(context, Colors.white),
          ],
        ),
      ),
      child: BuyerGlyphIcon(
        icon: Icons.keyboard_arrow_down_rounded,
        slotSize: metrics.geometry(24),
        glyphSize: metrics.geometry(24),
        color: HocalistPalette.text(context, _blue),
        semanticLabel: 'More Buyer benefits below',
      ),
    );
  }
}

class _ApprovedBuyerWelcome extends StatelessWidget {
  const _ApprovedBuyerWelcome({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = _replicaMetrics(context).accessibilityReflow;
        final avatar = Image.asset(
          '$_approvedAssetRoot/buyer-avatar.png',
          key: const ValueKey('approved-benefits-avatar'),
          width: metrics.geometry(70),
          height: metrics.geometry(70),
        );
        final copy = Column(
          crossAxisAlignment: stack
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Welcome to Hocalist  🎉' : 'Welcome, $name  🎉',
              textAlign: stack ? TextAlign.center : TextAlign.left,
              style: _text(
                context,
                size: 18,
                weight: FontWeight.w800,
                color: _navy,
                height: 1.15,
              ),
            ),
            SizedBox(height: metrics.geometry(3)),
            Text(
              'With your Hocalist buyer account, you get paid to buy and enjoy the best offers.',
              textAlign: stack ? TextAlign.center : TextAlign.left,
              style: _text(context, size: 11.5, color: _muted, height: 1.28),
            ),
          ],
        );
        if (stack) {
          return Column(
            children: [
              avatar,
              SizedBox(height: metrics.geometry(10)),
              copy,
            ],
          );
        }
        return Row(
          children: [
            avatar,
            SizedBox(width: metrics.geometry(12)),
            Expanded(child: copy),
          ],
        );
      },
    );
  }
}

class _ApprovedBenefitCard extends StatelessWidget {
  const _ApprovedBenefitCard({required this.benefit});

  final _ApprovedBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: ValueKey('approved-benefit-${benefit.asset}'),
      constraints: BoxConstraints(minHeight: metrics.geometry(64)),
      padding: metrics.geometryInsets(const EdgeInsets.fromLTRB(9, 7, 9, 7)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        border: Border.all(
          color: HocalistPalette.border(context, _line),
          width: metrics.geometry(1),
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BuyerAssetIcon(
            asset: '$_approvedAssetRoot/${benefit.asset}',
            slotSize: metrics.geometry(44),
          ),
          SizedBox(width: metrics.geometry(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: _text(
                    context,
                    size: 11,
                    weight: FontWeight.w700,
                    color: _navy,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: metrics.geometry(1)),
                Text(
                  benefit.body,
                  style: _text(context, size: 9.5, color: _muted, height: 1.22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedFairnessBanner extends StatelessWidget {
  const _ApprovedFairnessBanner();

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const ValueKey('approved-benefits-fairness-banner'),
      padding: metrics.geometryInsets(
        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xffeef7f1)),
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Row(
        children: [
          BuyerAssetIcon(
            asset: '$_approvedAssetRoot/benefit-green-shield.png',
            slotSize: metrics.geometry(34),
          ),
          SizedBox(width: metrics.geometry(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fair, transparent, and built for you.',
                  style: _text(
                    context,
                    size: 11,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.geometry(1)),
                Text(
                  'We\'re here to give you more value every time you buy.',
                  style: _text(context, size: 9.5, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedBenefit {
  const _ApprovedBenefit(this.asset, this.title, this.body);

  final String asset;
  final String title;
  final String body;
}

class _ApprovedPrimaryButton extends StatelessWidget {
  const _ApprovedPrimaryButton({
    required this.label,
    required this.onTap,
    this.referenceHeight = 50,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double referenceHeight;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return BuyerPrimaryButton(
      label: label,
      onPressed: busy ? null : onTap,
      compact: referenceHeight <= 44,
      minimumHeight: referenceHeight,
      trailing: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

class _ApprovedAssetButton extends StatelessWidget {
  const _ApprovedAssetButton({
    required this.tooltip,
    required this.asset,
    required this.size,
    required this.onTap,
  });

  final String tooltip;
  final String asset;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: BoxConstraints.tightFor(
        width: metrics.geometry(size),
        height: metrics.geometry(size),
      ),
      padding: EdgeInsets.zero,
      icon: asset == 'notification.png'
          ? NotificationArtwork(
              child: BuyerAssetIcon(
                asset: '$_approvedAssetRoot/$asset',
                slotSize: metrics.geometry(size - 8),
              ),
            )
          : BuyerAssetIcon(
              asset: '$_approvedAssetRoot/$asset',
              slotSize: metrics.geometry(size - 8),
            ),
    );
  }
}

class ApprovedNoAccountHomePage extends StatefulWidget {
  const ApprovedNoAccountHomePage({
    required this.onStart,
    required this.onBuyer,
    required this.onSeller,
    this.onNotifications,
    this.onHome,
    this.onTrends,
    this.onWinners,
    this.onSignup,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onBuyer;
  final VoidCallback onSeller;
  final VoidCallback? onNotifications;
  final VoidCallback? onHome;
  final VoidCallback? onTrends;
  final VoidCallback? onWinners;
  final VoidCallback? onSignup;

  @override
  State<ApprovedNoAccountHomePage> createState() =>
      _ApprovedNoAccountHomePageState();
}

class _ApprovedNoAccountHomePageState extends State<ApprovedNoAccountHomePage> {
  int _openFaq = 0;

  static const _benefits = [
    _ApprovedHomeBenefit(
      'home-benefit-reward.png',
      'Buyers Earn Commissions From Sellers Targeting',
      'You get rewards every time you buy through the app.',
    ),
    _ApprovedHomeBenefit(
      'home-benefit-target.png',
      'Businesses Don\'t Waste Money On Ads Just To Reach People',
      'Sellers target real buyers who are actively looking.',
    ),
    _ApprovedHomeBenefit(
      'home-benefit-handshake.png',
      'A System designed to give both sides & Better Outcome',
      'Fair, transparent, and built to create more value for everyone.',
    ),
    _ApprovedHomeBenefit(
      'home-benefit-shield.png',
      'Safe, private, and in your control',
      'You decide who to talk to and complete the deal on your terms.',
    ),
  ];

  static const _faqs = [
    _ApprovedFaq(
      'faq-question.png',
      'What is Hocalist?',
      'Hocalist is a reverse marketplace where buyers post what they need and sellers compete for the opportunity to earn your business.',
    ),
    _ApprovedFaq(
      'faq-gift.png',
      'Does Hocalist sell the items I buy?',
      'No. Buyers choose sellers and arrange the item handoff directly after selection.',
    ),
    _ApprovedFaq(
      'faq-store.png',
      'Why pay through Hocalist?',
      'Seller payments are for seller tools, credits, and access. Item payment stays outside Hocalist.',
    ),
    _ApprovedFaq(
      'faq-buyer.png',
      'What Incentive do I get as a buyer?',
      'Buyers can earn rewards when sellers target and win their business through the app.',
    ),
    _ApprovedFaq(
      'faq-target.png',
      'What Incentive do I get as a seller?',
      'Sellers can target real buyers who are actively looking instead of spending broadly on ads.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Material(
      color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: metrics.geometryInsets(
                  const EdgeInsets.fromLTRB(16, 10, 16, 24),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: metrics.innerContentMaxWidth(
                        referenceHorizontalInset: 16,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ApprovedHeader(
                          onNotifications: widget.onNotifications ?? () {},
                        ),
                        SizedBox(height: metrics.geometry(16)),
                        _ApprovedImageAction(
                          semanticLabel:
                              'I am buying. Get paid to buy and get the best offers. Post a request.',
                          asset: 'home-buyer-card.png',
                          aspectRatio: 786 / 460,
                          onTap: widget.onBuyer,
                        ),
                        SizedBox(height: metrics.geometry(14)),
                        _ApprovedImageAction(
                          semanticLabel:
                              'I am selling. Target real customers and beat the competition. Browse requests.',
                          asset: 'home-seller-card.png',
                          aspectRatio: 786 / 303,
                          onTap: widget.onSeller,
                        ),
                        SizedBox(height: metrics.geometry(20)),
                        Text(
                          'We Are The Better Option',
                          style: _text(
                            context,
                            size: 14,
                            weight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(4)),
                        Text(
                          'Our reverse marketplace works, plain and simple',
                          style: _text(context, size: 10, color: _navy),
                        ),
                        SizedBox(height: metrics.geometry(14)),
                        _ApprovedHomeBenefits(benefits: _benefits),
                        SizedBox(height: metrics.geometry(22)),
                        Text(
                          'See How Hocalist Works',
                          style: _text(
                            context,
                            size: 20,
                            weight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(4)),
                        Text(
                          'Watch a quick 60-second overview',
                          style: _text(context, size: 13.5, color: _navy),
                        ),
                        SizedBox(height: metrics.geometry(10)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(8),
                          ),
                          child: Image.asset(
                            '$_approvedAssetRoot/home-video.png',
                            bundle: DefaultAssetBundle.of(context),
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(20)),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Frequently Asked Questions',
                                style: _text(
                                  context,
                                  size: 19,
                                  weight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _openFaq = -2),
                              child: Text(
                                'View all',
                                style: _text(
                                  context,
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: _blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: metrics.geometry(6)),
                        _ApprovedFaqPanel(
                          faqs: _faqs,
                          openFaq: _openFaq,
                          onTap: (index) => setState(
                            () => _openFaq = _openFaq == index ? -1 : index,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(28)),
                        _ApprovedStartBanner(onTap: widget.onStart),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ApprovedNoAccountBottomNavigation(
              selectedIndex: 0,
              onHome: widget.onHome ?? () {},
              onHocatrends: widget.onTrends ?? () {},
              onWinners: widget.onWinners ?? () {},
              onSignup: widget.onSignup ?? widget.onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedHeader extends StatelessWidget {
  const _ApprovedHeader({
    required this.onNotifications,
    this.buyerMode = false,
  });

  final VoidCallback onNotifications;
  final bool buyerMode;

  @override
  Widget build(BuildContext context) {
    if (buyerMode) {
      return BuyerTopLevelHeader(onNotifications: onNotifications);
    }

    final metrics = _replicaMetrics(context);
    final logo = Image.asset(
      'assets/brand/hocalist-wordmark.png',
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xfff3f3ff)
          : null,
      width: metrics.geometry(buyerMode ? 88 : 104),
      height: metrics.geometry(buyerMode ? 54 : 62),
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.high,
    );
    final notification = _ApprovedAssetButton(
      tooltip: 'Notifications',
      asset: 'notification.png',
      size: buyerMode ? 44 : 40,
      onTap: onNotifications,
    );
    final modePill = Container(
      constraints: BoxConstraints(minHeight: metrics.geometry(38)),
      padding: metrics.geometryInsets(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(99)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuyerAssetIcon(
            asset: '$_approvedAssetRoot/buyer-mode-check.png',
            slotSize: metrics.geometry(22),
          ),
          SizedBox(width: metrics.geometry(6)),
          Text(
            'Buyer mode',
            style: _text(
              context,
              size: 12,
              weight: FontWeight.w800,
              color: _blue,
              height: 1.05,
            ),
          ),
        ],
      ),
    );

    if (buyerMode && metrics.accessibilityReflow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [logo, const Spacer(), notification]),
          Align(alignment: Alignment.centerRight, child: modePill),
        ],
      );
    }

    return Row(
      children: [
        logo,
        const Spacer(),
        if (buyerMode) ...[modePill, SizedBox(width: metrics.geometry(8))],
        notification,
      ],
    );
  }
}

class _ApprovedImageAction extends StatelessWidget {
  const _ApprovedImageAction({
    required this.semanticLabel,
    required this.asset,
    required this.aspectRatio,
    required this.onTap,
  });

  final String semanticLabel;
  final String asset;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        key: ValueKey('approved-home-$asset'),
        color: HocalistPalette.surface(context, Colors.transparent),
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Image.asset(
              '$_approvedAssetRoot/$asset',
              bundle: DefaultAssetBundle.of(context),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedHomeBenefits extends StatelessWidget {
  const _ApprovedHomeBenefits({required this.benefits});

  final List<_ApprovedHomeBenefit> benefits;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      children: [
        for (var index = 0; index < benefits.length; index++) ...[
          Container(
            key: ValueKey('approved-home-benefit-${benefits[index].asset}'),
            constraints: BoxConstraints(minHeight: metrics.geometry(51)),
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Colors.white),
              borderRadius: BorderRadius.circular(metrics.geometry(12)),
              border: Border.all(
                color: HocalistPalette.border(context, const Color(0xffe8ebf5)),
                width: metrics.geometry(1),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x1000036c),
                  blurRadius: metrics.geometry(14),
                  offset: Offset(0, metrics.geometry(5)),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BuyerAssetIcon(
                  asset: '$_approvedAssetRoot/${benefits[index].asset}',
                  slotSize: metrics.geometry(34),
                ),
                SizedBox(width: metrics.geometry(11)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        benefits[index].title,
                        style: _text(
                          context,
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: _navy,
                          height: 1.12,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(2)),
                      Text(
                        benefits[index].body,
                        style: _text(
                          context,
                          size: 8.5,
                          color: _muted,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (index != benefits.length - 1)
            SizedBox(height: metrics.geometry(7)),
        ],
      ],
    );
  }
}

class _ApprovedFaqPanel extends StatelessWidget {
  const _ApprovedFaqPanel({
    required this.faqs,
    required this.openFaq,
    required this.onTap,
  });

  final List<_ApprovedFaq> faqs;
  final int openFaq;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (var index = 0; index < faqs.length; index++) ...[
            InkWell(
              onTap: () => onTap(index),
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BuyerAssetIcon(
                      asset: '$_approvedAssetRoot/${faqs[index].asset}',
                      slotSize: metrics.geometry(28),
                    ),
                    SizedBox(width: metrics.geometry(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            faqs[index].question,
                            style: _text(
                              context,
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          if (openFaq == index || openFaq == -2) ...[
                            SizedBox(height: metrics.geometry(6)),
                            Text(
                              faqs[index].answer,
                              style: _text(
                                context,
                                size: 11.5,
                                color: _muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    BuyerGlyphIcon(
                      icon: openFaq == index || openFaq == -2
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      slotSize: metrics.geometry(24),
                      glyphSize: metrics.geometry(24),
                      color: HocalistPalette.text(context, _navy),
                    ),
                  ],
                ),
              ),
            ),
            if (index != faqs.length - 1)
              Divider(
                height: metrics.geometry(1),
                indent: metrics.geometry(48),
                color: const Color(0xffedf0f8),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedStartBanner extends StatelessWidget {
  const _ApprovedStartBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = _replicaMetrics(context).accessibilityReflow;
        final copy = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ready to start earning?',
                style: _text(
                  context,
                  size: 15,
                  weight: FontWeight.w800,
                  color: _blue,
                ),
              ),
              SizedBox(height: metrics.geometry(4)),
              Text(
                'Join thousands of buyers earning rewards every day on Hocalist.',
                style: _text(context, size: 12, color: _navy),
              ),
            ],
          ),
        );
        final action = FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: HocalistPalette.surface(
              context,
              accessibility.backgroundOr(_blue),
            ),
            foregroundColor: HocalistPalette.text(
              context,
              accessibility.foregroundOr(Colors.white),
            ),
            minimumSize: Size(0, metrics.geometry(48)),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.geometry(12),
              vertical: metrics.geometry(10),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                accessibility.radiusOr(metrics.geometry(99)),
              ),
            ),
          ),
          child: Text(
            'Create Free Account',
            textAlign: TextAlign.center,
            style: _text(
              context,
              size: 12,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
        return Container(
          padding: EdgeInsets.all(metrics.geometry(14)),
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, _lavender),
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          '$_approvedAssetRoot/ready-gift.png',
                          bundle: DefaultAssetBundle.of(context),
                          width: metrics.geometry(74),
                          height: metrics.geometry(74),
                        ),
                        SizedBox(width: metrics.geometry(10)),
                        copy,
                      ],
                    ),
                    SizedBox(height: metrics.geometry(10)),
                    action,
                  ],
                )
              : Row(
                  children: [
                    Image.asset(
                      '$_approvedAssetRoot/ready-gift.png',
                      bundle: DefaultAssetBundle.of(context),
                      width: metrics.geometry(70),
                      height: metrics.geometry(70),
                    ),
                    SizedBox(width: metrics.geometry(10)),
                    copy,
                    SizedBox(width: metrics.geometry(10)),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

class _ApprovedBottomNav extends StatelessWidget {
  const _ApprovedBottomNav({required this.items, required this.selectedIndex});

  final List<_ApprovedNavItem> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Center(
      child: SizedBox(
        width: metrics.contentMaxWidth,
        child: Container(
          key: const ValueKey('approved-bottom-navigation'),
          constraints: BoxConstraints(minHeight: metrics.geometry(78)),
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, Colors.white),
            border: Border(
              top: BorderSide(
                color: HocalistPalette.border(context, const Color(0xffedf0f8)),
                width: metrics.geometry(1),
              ),
            ),
          ),
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: index == selectedIndex,
                    label: items[index].label,
                    child: InkWell(
                      key: ValueKey(
                        'approved-public-nav-${items[index].label.toLowerCase().replaceAll(' ', '-')}',
                      ),
                      onTap: items[index].onTap,
                      child: Container(
                        margin: metrics.geometryInsets(
                          const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: metrics.geometry(6),
                        ),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            index == selectedIndex ? _lavender : Colors.white,
                          ),
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(8),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BuyerAssetIcon(
                              asset:
                                  '$_approvedAssetRoot/${items[index].asset}',
                              slotSize: metrics.geometry(28),
                            ),
                            SizedBox(height: metrics.geometry(3)),
                            Text(
                              items[index].label,
                              maxLines: metrics.accessibilityReflow ? 2 : 1,
                              textAlign: TextAlign.center,
                              style: _text(
                                context,
                                size: 11,
                                weight: index == selectedIndex
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: index == selectedIndex ? _blue : _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screenshot-approved navigation shared by every logged-out surface.
/// Keeping this public prevents public Hocatrends from falling back to the
/// older generic navigation component.
class ApprovedNoAccountBottomNavigation extends StatelessWidget {
  const ApprovedNoAccountBottomNavigation({
    required this.onHome,
    required this.onHocatrends,
    required this.onWinners,
    required this.onSignup,
    this.selectedIndex = 0,
    super.key,
  });

  final VoidCallback onHome;
  final VoidCallback onHocatrends;
  final VoidCallback onWinners;
  final VoidCallback onSignup;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return _ApprovedBottomNav(
      selectedIndex: selectedIndex,
      items: [
        _ApprovedNavItem('Home', 'nav-home.png', onHome),
        _ApprovedNavItem('Hocatrends', 'nav-hocatrends.png', onHocatrends),
        _ApprovedNavItem('Winners', 'nav-winners.png', onWinners),
        _ApprovedNavItem('Sign Up', 'nav-signup.png', onSignup),
      ],
    );
  }
}

class _ApprovedHomeBenefit {
  const _ApprovedHomeBenefit(this.asset, this.title, this.body);
  final String asset;
  final String title;
  final String body;
}

class _ApprovedFaq {
  const _ApprovedFaq(this.asset, this.question, this.answer);
  final String asset;
  final String question;
  final String answer;
}

class _ApprovedNavItem {
  const _ApprovedNavItem(this.label, this.asset, this.onTap);
  final String label;
  final String asset;
  final VoidCallback onTap;
}

ApprovedReplicaMetrics _replicaMetrics(BuildContext context) {
  return ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        brightness: Theme.of(context).brightness,
        availableWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
      );
}

BoxDecoration _panelDecoration(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return BoxDecoration(
    color: HocalistPalette.surface(context, Colors.white),
    borderRadius: BorderRadius.circular(metrics.geometry(8)),
    border: Border.all(
      color: HocalistPalette.border(context, const Color(0xffe8ebf5)),
      width: metrics.geometry(1),
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0x1000036c),
        blurRadius: metrics.geometry(14),
        offset: Offset(0, metrics.geometry(5)),
      ),
    ],
  );
}

/// Buyer-facing dashboard projection of one authoritative request.
@immutable
class BuyerRequestView {
  const BuyerRequestView({
    required this.requestId,
    required this.revision,
    required this.title,
    required this.budgetLabel,
    required this.statusLabel,
    this.acceptanceExpiresAt,
  });

  factory BuyerRequestView.fromRequest(MarketplaceRequest request) {
    final draft = request.draft;
    return BuyerRequestView(
      requestId: request.id,
      revision: request.stamp.revision,
      title: draft.title,
      budgetLabel: _formatBudget(draft.budget),
      statusLabel: switch (request.status) {
        RequestStatus.active => 'Active request',
        RequestStatus.draft => 'Draft request',
        RequestStatus.closed => 'Closed request',
        RequestStatus.expired => 'Expired request',
        RequestStatus.cancelled => 'Cancelled request',
      },
      acceptanceExpiresAt: request.acceptanceExpiresAt,
    );
  }

  final String requestId;
  final int revision;
  final String title;
  final String budgetLabel;
  final String statusLabel;

  /// Exclusive end of the request acceptance window, when the server supplied
  /// it. Shown as the authoritative countdown on the request card.
  final DateTime? acceptanceExpiresAt;

  /// Device-local "Offers close …" label, or null before the first acceptance.
  String? get windowLabel {
    final expires = acceptanceExpiresAt;
    if (expires == null) return null;
    final local = expires.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Offers close ${months[local.month - 1]} ${local.day}, '
        '$displayHour:$minute $period';
  }

  static String _formatBudget(MoneyRange range) {
    String amount(Money money) {
      final units = money.minorUnits / 100;
      return units.truncateToDouble() == units
          ? units.toStringAsFixed(0)
          : units.toStringAsFixed(2);
    }

    if (range.isEmpty) return 'No budget set';
    final minimum = range.minimum;
    final maximum = range.maximum;
    if (minimum != null && maximum != null) {
      return '\$${amount(minimum)} - \$${amount(maximum)}';
    }
    if (minimum != null) return 'From \$${amount(minimum)}';
    return 'Up to \$${amount(maximum!)}';
  }
}

/// One safe inbox summary shown in the home Recent activity section. Only
/// server-authored title, kind, time and read state are projected; amounts and
/// review claims never enter this view.
@immutable
class ApprovedActivityView {
  const ApprovedActivityView({
    required this.id,
    required this.kind,
    required this.title,
    required this.timeLabel,
    this.unread = false,
  });

  factory ApprovedActivityView.fromNotification(
    NotificationInboxItem item, {
    DateTime? now,
  }) {
    return ApprovedActivityView(
      id: item.id,
      kind: item.kind,
      title: item.title,
      timeLabel: _relativeTime(item.createdAt, now ?? DateTime.now()),
      unread: item.isUnread,
    );
  }

  final String id;
  final String kind;
  final String title;
  final String timeLabel;
  final bool unread;

  String get asset => switch (kind) {
    'new_offer' || 'new_message' => 'activity-chat.png',
    'meeting_update' => 'activity-check.png',
    'billing_update' => 'activity-reward.png',
    _ => 'activity-star.png',
  };

  static String _relativeTime(DateTime createdAt, DateTime now) {
    final local = createdAt.toLocal();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}

/// Buyer meeting-list route used when no single meeting detail is selected.
/// It keeps the approved Buyer meeting-card grammar instead of rendering the
/// Seller Meets page inside the Buyer flow.
class ApprovedBuyerMeetingsPage extends StatelessWidget {
  const ApprovedBuyerMeetingsPage({
    required this.onBack,
    required this.meetings,
    required this.loading,
    required this.error,
    this.onRefresh,
    this.onOpenMeeting,
    super.key,
  });

  final VoidCallback onBack;
  final List<MeetingView> meetings;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;
  final ValueChanged<MeetingView>? onOpenMeeting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('approvedBuyerMeetingsBack'),
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back,
                      color: HocalistPalette.text(context, _navy),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      'Your meetings',
                      style: _text(
                        context,
                        size: 18,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const Key('approvedBuyerMeetingsList'),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                children: [
                  if (loading && meetings.isEmpty)
                    const _ApprovedDashboardNotice(
                      key: Key('buyerMeetingsListLoading'),
                      message: 'Loading your meetings…',
                    )
                  else if (error != null && meetings.isEmpty)
                    _ApprovedDashboardNotice(
                      key: const Key('buyerMeetingsListError'),
                      message: error!,
                      onRetry: onRefresh,
                    )
                  else
                    _ApprovedRealMeetingsPanel(
                      meetings: meetings,
                      loading: loading,
                      error: error,
                      onRetry: onRefresh,
                      onOpen: onOpenMeeting,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApprovedBuyerHomePage extends StatelessWidget {
  const ApprovedBuyerHomePage({
    required this.name,
    required this.requestTitle,
    required this.requestPosted,
    required this.onCreate,
    required this.onRequestDetails,
    required this.onOffers,
    required this.onRecentActivity,
    required this.onWallet,
    this.onOpenOffers,
    this.meetingConfirmed = false,
    this.onMeetingDetails,
    this.onNotifications,
    this.onHome,
    this.onTrends,
    this.onOffersTab,
    this.onChats,
    this.onMore,
    this.realRequests,
    this.requestsLoading = false,
    this.requestsError,
    this.onRefreshRequests,
    this.onOpenRequest,
    this.loadRealRewards,
    this.realMeetings,
    this.meetingsLoading = false,
    this.meetingsError,
    this.onRefreshMeetings,
    this.onOpenMeeting,
    this.realActivity,
    this.activityLoading = false,
    this.activityError,
    this.onRefreshActivity,
    super.key,
  });

  final String name;
  final String requestTitle;
  final bool requestPosted;
  final VoidCallback onCreate;
  final VoidCallback onRequestDetails;
  final VoidCallback onOffers;
  final VoidCallback onRecentActivity;
  final VoidCallback onWallet;

  /// Opens the offers route scoped to the tapped real request. Prototype mode
  /// keeps the shared [onOffers] navigation.
  final ValueChanged<BuyerRequestView>? onOpenOffers;
  final bool meetingConfirmed;
  final VoidCallback? onMeetingDetails;
  final VoidCallback? onNotifications;
  final VoidCallback? onHome;
  final VoidCallback? onTrends;
  final VoidCallback? onOffersTab;
  final VoidCallback? onChats;
  final VoidCallback? onMore;

  /// Real buyer requests for the "My requests" section. Null keeps the
  /// approved prototype card.
  final List<BuyerRequestView>? realRequests;
  final bool requestsLoading;
  final String? requestsError;
  final VoidCallback? onRefreshRequests;
  final ValueChanged<BuyerRequestView>? onOpenRequest;

  /// When set, dashboard reward cards use the authenticated ledger instead of
  /// the approved prototype figures.
  final Future<Map<String, dynamic>> Function()? loadRealRewards;
  final List<MeetingView>? realMeetings;
  final bool meetingsLoading;
  final String? meetingsError;
  final VoidCallback? onRefreshMeetings;
  final ValueChanged<MeetingView>? onOpenMeeting;

  /// Real inbox summaries for the home Recent activity section. Null keeps the
  /// approved prototype activity card.
  final List<ApprovedActivityView>? realActivity;
  final bool activityLoading;
  final String? activityError;
  final VoidCallback? onRefreshActivity;

  bool get usesRealRequests => realRequests != null;

  bool get usesRealData =>
      realRequests != null ||
      realMeetings != null ||
      realActivity != null ||
      loadRealRewards != null;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().isEmpty
        ? ''
        : name.trim().split(RegExp(r'\s+')).first;
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: viewport.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        // Earliest request acceptance window first; requests without an
        // accepted offer keep their server order after those.
        final requests = realRequests == null
            ? null
            : (List<BuyerRequestView>.of(realRequests!)..sort((a, b) {
                final aExpiry = a.acceptanceExpiresAt;
                final bExpiry = b.acceptanceExpiresAt;
                if (aExpiry == null && bExpiry == null) return 0;
                if (aExpiry == null) return 1;
                if (bExpiry == null) return -1;
                return aExpiry.compareTo(bExpiry);
              }));
        return ApprovedReplicaScope(
          metrics: metrics,
          child: Material(
            color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
            child: SafeArea(
              child: _ApprovedBuyerHomeLayout(
                metrics: metrics,
                welcome: Padding(
                  key: const ValueKey('approved-buyer-fixed-welcome'),
                  padding: metrics.geometryInsets(
                    const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: metrics.innerContentMaxWidth(
                          referenceHorizontalInset: 18,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ApprovedHeader(
                            buyerMode: true,
                            onNotifications: onNotifications ?? () {},
                          ),
                          SizedBox(height: metrics.geometry(6)),
                          _ApprovedDashboardHero(name: firstName),
                          SizedBox(height: metrics.geometry(10)),
                        ],
                      ),
                    ),
                  ),
                ),
                content: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: metrics.innerContentMaxWidth(
                        referenceHorizontalInset: 18,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (loadRealRewards != null)
                          _ApprovedRealRewardCards(
                            load: loadRealRewards!,
                            onTap: onWallet,
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = metrics.accessibilityReflow;
                              final cards = [
                                _ApprovedRewardCard(
                                  onTap: onWallet,
                                  alignActionToBottom: !stacked,
                                ),
                                const _ApprovedPendingCard(),
                              ];
                              if (stacked) {
                                return Column(
                                  children: [
                                    cards[0],
                                    SizedBox(height: metrics.geometry(10)),
                                    cards[1],
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: cards[0]),
                                  SizedBox(width: metrics.geometry(8)),
                                  Expanded(child: cards[1]),
                                ],
                              );
                            },
                          ),
                        SizedBox(height: metrics.geometry(10)),
                        _ApprovedPostRequest(onTap: onCreate),
                        if (requestPosted || usesRealRequests) ...[
                          SizedBox(height: metrics.geometry(10)),
                          Text(
                            'My requests',
                            style: _text(
                              context,
                              size: 14,
                              weight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: metrics.geometry(6)),
                          if (usesRealRequests) ...[
                            if (requestsLoading)
                              const _ApprovedDashboardNotice(
                                key: Key('buyerRequestsLoading'),
                                message: 'Loading your requests…',
                              )
                            else if (requestsError != null)
                              _ApprovedDashboardNotice(
                                key: const Key('buyerRequestsError'),
                                message: requestsError!,
                                onRetry: onRefreshRequests,
                              )
                            else if (requests!.isEmpty)
                              _ApprovedEmptySectionCard(
                                key: const Key('buyerRequestsEmpty'),
                                asset: 'dashboard-clipboard.png',
                                title: 'No active requests yet',
                                body:
                                    'Post a request to receive seller offers. '
                                    'Your requests appear here with their status '
                                    'and budget.',
                                actionLabel: 'Post a request',
                                onAction: onCreate,
                              )
                            else
                              for (final request in requests.take(4)) ...[
                                _ApprovedActiveRequest(
                                  title: request.title,
                                  showPin: false,
                                  metaLabel: [
                                    request.statusLabel,
                                    request.budgetLabel,
                                    if (request.windowLabel != null)
                                      request.windowLabel!,
                                  ].join(' · '),
                                  onDetails: () => onOpenRequest?.call(request),
                                  onOffers: () {
                                    final open = onOpenOffers;
                                    if (open != null) {
                                      open(request);
                                    } else {
                                      onOffers();
                                    }
                                  },
                                ),
                                SizedBox(height: metrics.geometry(8)),
                              ],
                          ] else
                            _ApprovedActiveRequest(
                              title: requestTitle,
                              onDetails: onRequestDetails,
                              onOffers: onOffers,
                            ),
                        ],
                        SizedBox(height: metrics.geometry(8)),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Upcoming meetings',
                                style: _text(
                                  context,
                                  size: 14,
                                  weight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: onMeetingDetails,
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: metrics.geometryInsets(
                                  const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'View all',
                                style: _text(
                                  context,
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: _blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (realMeetings != null)
                          _ApprovedRealMeetingsPanel(
                            meetings: realMeetings!,
                            loading: meetingsLoading,
                            error: meetingsError,
                            onRetry: onRefreshMeetings,
                            onOpen: onOpenMeeting,
                          )
                        else
                          _ApprovedUpcomingMeetingsPanel(
                            onTap: onMeetingDetails ?? onRecentActivity,
                            meetingConfirmed: meetingConfirmed,
                          ),
                        SizedBox(height: metrics.geometry(12)),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Recent activity',
                                style: _text(
                                  context,
                                  size: 14,
                                  weight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: onRecentActivity,
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: metrics.geometryInsets(
                                  const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'View all',
                                style: _text(
                                  context,
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: _blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: metrics.geometry(6)),
                        if (realActivity != null)
                          _ApprovedRealActivityPanel(
                            items: realActivity!,
                            loading: activityLoading,
                            error: activityError,
                            onRetry: onRefreshActivity,
                            onOpen: onRecentActivity,
                          )
                        else if (usesRealData)
                          const _ApprovedEmptySectionCard(
                            key: Key('buyerActivityUnavailable'),
                            asset: 'activity-star.png',
                            title: 'Activity unavailable',
                            body:
                                'Recent offer, meeting and account updates '
                                'could not be loaded. Open the inbox to retry.',
                          )
                        else
                          _ApprovedActivityPanel(onTap: onRecentActivity),
                        SizedBox(height: metrics.geometry(12)),
                        _ApprovedKeepEarningBanner(realMode: usesRealData),
                      ],
                    ),
                  ),
                ),
                navigation: BuyerBottomNavigation(
                  selected: ApprovedBuyerNavSelection.home,
                  accentColor: _blue,
                  callbacks: ApprovedBuyerNavigation(
                    onHome: onHome ?? () {},
                    onHocatrends: onTrends ?? () {},
                    onOffers: onOffersTab ?? onOffers,
                    onChats: onChats ?? () {},
                    onMore: onMore ?? () {},
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ApprovedBuyerHomeLayout extends StatelessWidget {
  const _ApprovedBuyerHomeLayout({
    required this.metrics,
    required this.welcome,
    required this.content,
    required this.navigation,
  });

  final ApprovedReplicaMetrics metrics;
  final Widget welcome;
  final Widget content;
  final Widget navigation;

  @override
  Widget build(BuildContext context) {
    if (metrics.accessibilityReflow) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('approved-buyer-home-accessibility-scroll'),
              child: Column(
                children: [
                  welcome,
                  Padding(
                    padding: metrics.geometryInsets(
                      const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    ),
                    child: content,
                  ),
                ],
              ),
            ),
          ),
          navigation,
        ],
      );
    }

    return Column(
      children: [
        welcome,
        Expanded(
          child: SingleChildScrollView(
            padding: metrics.geometryInsets(
              const EdgeInsets.fromLTRB(18, 0, 18, 24),
            ),
            child: content,
          ),
        ),
        navigation,
      ],
    );
  }
}

/// Upgraded rewards destination reached from the approved buyer dashboard.
/// It deliberately avoids the legacy ScreenBlock/MetricRow surface family.
class ApprovedBuyerRewardsDetailPage extends StatelessWidget {
  const ApprovedBuyerRewardsDetailPage({
    required this.onBack,
    required this.onDealHistory,
    this.onWithdraw,
    this.realContent,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onDealHistory;
  final VoidCallback? onWithdraw;
  final Widget? realContent;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    if (realContent != null) {
      return ApprovedReplicaScope(
        metrics: metrics,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedDetailHeading(
              title: 'Rewards',
              subtitle: 'Your earned buyer rewards.',
              onBack: onBack,
            ),
            SizedBox(height: metrics.spacing(16)),
            realContent!,
          ],
        ),
      );
    }
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Column(
        key: const ValueKey('approved-rewards-detail-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Rewards',
            subtitle: 'Track earned rewards and your next payout.',
            onBack: onBack,
          ),
          SizedBox(height: metrics.spacing(16)),
          Container(
            padding: metrics.geometryInsets(const EdgeInsets.all(18)),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, _lavender),
              borderRadius: BorderRadius.circular(metrics.geometry(18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total rewards earned',
                        style: _text(
                          context,
                          size: 13,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(6)),
                      Text(
                        '\$128.45',
                        style: _text(
                          context,
                          size: 31,
                          weight: FontWeight.w800,
                          color: _blue,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(5)),
                      Text(
                        'From 42 completed purchases',
                        style: _text(context, size: 11.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                BuyerAssetIconSurface(
                  asset: '$_approvedAssetRoot/dashboard-trophy-glyph.png',
                  surfaceSize: metrics.artSize(74),
                  iconSize: metrics.artSize(42),
                  backgroundColor: HocalistPalette.surface(
                    context,
                    const Color(0xffe9e4ff),
                  ),
                  shape: BuyerIconSurfaceShape.circle,
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(12)),
          Row(
            children: [
              Expanded(
                child: _ApprovedRewardMetric(
                  asset: 'dashboard-calendar.png',
                  label: 'Pending',
                  value: '\$24.80',
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              const Expanded(
                child: _ApprovedRewardMetric(
                  asset: 'ready-gift.png',
                  label: 'Until payout',
                  value: '\$0.20',
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.spacing(12)),
          _ApprovedDetailSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Next payout',
                        style: _text(
                          context,
                          size: 14,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ),
                    Text(
                      'May 20, 2025',
                      style: _text(
                        context,
                        size: 11,
                        weight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: metrics.geometry(12)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: .992,
                    minHeight: 9,
                    backgroundColor: HocalistPalette.surface(
                      context,
                      _lavender,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(_blue),
                  ),
                ),
                SizedBox(height: metrics.geometry(8)),
                Text(
                  '\$24.80 of \$25.00 ready',
                  style: _text(
                    context,
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(16)),
          Text(
            'Reward activity',
            style: _text(
              context,
              size: 16,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(8)),
          _ApprovedDetailSurface(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                _ApprovedRewardActivityRow(
                  asset: 'dashboard-clipboard.png',
                  title: 'iPad Air purchase',
                  subtitle: 'Pending review',
                  value: '+\$0.40',
                ),
                Divider(height: 1, color: _line),
                _ApprovedRewardActivityRow(
                  asset: 'dashboard-trophy.png',
                  title: 'Samsung TV purchase',
                  subtitle: 'Reward earned',
                  value: '+\$3.20',
                ),
                Divider(height: 1, color: _line),
                _ApprovedRewardActivityRow(
                  asset: 'dashboard-clipboard.png',
                  title: 'MacBook Air purchase',
                  subtitle: 'Reward earned',
                  value: '+\$6.40',
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(16)),
          Text(
            'Payout destination',
            style: _text(
              context,
              size: 16,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(8)),
          _ApprovedDetailSurface(
            child: InkWell(
              key: const Key('approved-rewards-payout-destination'),
              onTap: onWithdraw,
              borderRadius: BorderRadius.circular(metrics.geometry(12)),
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(vertical: 4),
                ),
                child: Row(
                  children: [
                    Container(
                      width: metrics.artSize(38),
                      height: metrics.artSize(38),
                      decoration: BoxDecoration(
                        color: HocalistPalette.surface(context, _lavender),
                        shape: BoxShape.circle,
                      ),
                      child: BuyerGlyphIcon(
                        icon: Icons.account_balance_outlined,
                        slotSize: metrics.artSize(38),
                        glyphSize: metrics.artSize(20),
                        color: HocalistPalette.text(context, _blue),
                      ),
                    ),
                    SizedBox(width: metrics.geometry(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add or manage payout method',
                            style: _text(
                              context,
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: metrics.geometry(2)),
                          Text(
                            'Choose where eligible rewards will be sent.',
                            style: _text(context, size: 10.5, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    BuyerGlyphIcon(
                      icon: Icons.chevron_right,
                      slotSize: metrics.artSize(24),
                      glyphSize: metrics.artSize(20),
                      color: HocalistPalette.text(context, _muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: metrics.spacing(16)),
          Text(
            'Payout history',
            style: _text(
              context,
              size: 16,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(8)),
          _ApprovedDetailSurface(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                _ApprovedRewardActivityRow(
                  asset: 'dashboard-calendar.png',
                  title: 'Next reward payout',
                  subtitle: 'May 20, 2025 • Pending',
                  value: '\$24.80',
                  valueColor: _blue,
                ),
                Divider(height: 1, color: _line),
                _ApprovedRewardActivityRow(
                  asset: 'ready-gift.png',
                  title: 'Reward payout',
                  subtitle: 'Apr 20, 2025 • Sent',
                  value: '\$42.15',
                  valueColor: _navy,
                ),
                Divider(height: 1, color: _line),
                _ApprovedRewardActivityRow(
                  asset: 'ready-gift.png',
                  title: 'Reward payout',
                  subtitle: 'Mar 20, 2025 • Sent',
                  value: '\$31.20',
                  valueColor: _navy,
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(12)),
          _ApprovedDetailSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BuyerGlyphIcon(
                  icon: Icons.info_outline_rounded,
                  slotSize: 24,
                  glyphSize: 20,
                  color: HocalistPalette.text(context, _blue),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reward payouts are separate from item payment. Buyers and sellers still complete item payment offline.',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.secondaryBody,
                      color: _muted,
                      height: 1.4,
                    ).copyWith(fontSize: metrics.fontSize(11)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(16)),
          BuyerPrimaryButton(
            key: const ValueKey('approved-rewards-withdraw-button'),
            label: 'Manage payout & withdraw',
            onPressed: onWithdraw,
          ),
          SizedBox(height: metrics.spacing(10)),
          BuyerSecondaryButton(
            key: const ValueKey('approved-rewards-history-button'),
            label: 'View buyer deal history',
            onPressed: onDealHistory,
          ),
        ],
      ),
    );
  }
}

/// Real-mode binding for the approved Buyer rewards sections.
///
/// The approved hero, pending/until-payout metrics, next-payout progress,
/// reward activity, payout destination and payout history sections are
/// preserved. Every amount comes from `commercial_reward_wallet` and
/// `withdrawal_status`; a missing ledger or policy renders a designed
/// loading/unavailable state instead of a fabricated value.
class ApprovedBuyerRewardsRealSections extends StatefulWidget {
  const ApprovedBuyerRewardsRealSections({
    this.load,
    this.loadWithdrawals,
    this.onWithdraw,
    this.onDealHistory,
    super.key,
  });

  final Future<RewardWalletView> Function()? load;
  final Future<WithdrawalStatusView> Function()? loadWithdrawals;
  final VoidCallback? onWithdraw;
  final VoidCallback? onDealHistory;

  @override
  State<ApprovedBuyerRewardsRealSections> createState() =>
      _ApprovedBuyerRewardsRealSectionsState();
}

class _ApprovedBuyerRewardsRealSectionsState
    extends State<ApprovedBuyerRewardsRealSections> {
  RewardWalletView? _wallet;
  WithdrawalStatusView? _withdrawals;
  bool _busy = true;
  bool _withdrawalsBusy = false;
  String? _error;
  String? _withdrawalsError;
  int _generation = 0;

  static String _usd(int cents) =>
      '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  static String _date(DateTime value) {
    final date = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'} ${date.timeZoneName}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final run = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _withdrawalsError = null;
    });
    final load = widget.load;
    if (load == null) {
      if (mounted && run == _generation) setState(() => _busy = false);
      // The withdrawal read is independent of the rewards wallet, so payout
      // history can still load while the wallet is unavailable.
      await _loadWithdrawals(run);
      return;
    }
    try {
      final value = await load();
      if (!mounted || run != _generation) return;
      setState(() => _wallet = value);
    } catch (_) {
      if (mounted && run == _generation) {
        setState(() => _error = 'Rewards could not be loaded. Please retry.');
      }
    } finally {
      if (mounted && run == _generation) setState(() => _busy = false);
    }
    await _loadWithdrawals(run);
  }

  Future<void> _loadWithdrawals(int run) async {
    final load = widget.loadWithdrawals;
    if (load == null) return;
    if (mounted && run == _generation) {
      setState(() {
        _withdrawalsBusy = true;
        _withdrawalsError = null;
      });
    }
    try {
      final value = await load();
      if (!mounted || run != _generation) return;
      setState(() => _withdrawals = value);
    } catch (_) {
      if (mounted && run == _generation) {
        setState(
          () => _withdrawalsError = 'Payout history could not be loaded.',
        );
      }
    } finally {
      if (mounted && run == _generation) {
        setState(() => _withdrawalsBusy = false);
      }
    }
  }

  bool get _walletFailed => _wallet == null && !_busy && _error != null;

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    final metrics = _replicaMetrics(context);
    return Column(
      key: const ValueKey('approved-rewards-real-sections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(wallet, metrics),
        SizedBox(height: metrics.spacing(12)),
        _metricsRow(wallet, metrics),
        SizedBox(height: metrics.spacing(12)),
        _nextPayoutSection(wallet, metrics),
        SizedBox(height: metrics.spacing(16)),
        _sectionHeading('Reward activity'),
        SizedBox(height: metrics.geometry(8)),
        _activitySection(wallet, metrics),
        SizedBox(height: metrics.spacing(16)),
        _sectionHeading('Payout destination'),
        SizedBox(height: metrics.geometry(8)),
        _payoutDestinationSection(wallet, metrics),
        SizedBox(height: metrics.spacing(16)),
        _sectionHeading('Payout history'),
        SizedBox(height: metrics.geometry(8)),
        _ApprovedDetailSurface(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _payoutHistory(wallet, metrics),
        ),
        SizedBox(height: metrics.spacing(12)),
        _rewardPaymentNotice(metrics),
        SizedBox(height: metrics.spacing(16)),
        BuyerPrimaryButton(
          key: const ValueKey('approved-rewards-withdraw-button'),
          label: 'Manage payout & withdraw',
          onPressed: widget.onWithdraw,
        ),
        SizedBox(height: metrics.spacing(10)),
        BuyerSecondaryButton(
          key: const ValueKey('approved-rewards-history-button'),
          label: 'View buyer deal history',
          onPressed: widget.onDealHistory,
        ),
      ],
    );
  }

  Widget _sectionHeading(String title) => Text(
    title,
    style: _text(context, size: 16, weight: FontWeight.w800, color: _navy),
  );

  Widget _heroLabel() => Text(
    'Total rewards earned',
    style: _text(context, size: 13, weight: FontWeight.w800, color: _navy),
  );

  /// Approved hero. Non-ready states show the designed placeholder ('—') and
  /// never a fabricated or prototype amount; the trophy artwork is preserved.
  Widget _hero(RewardWalletView? wallet, ApprovedReplicaMetrics metrics) {
    final Widget body;
    if (wallet != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroLabel(),
          SizedBox(height: metrics.geometry(6)),
          Text(
            _usd(wallet.earnedMinor),
            key: const ValueKey('approved-rewards-earned'),
            style: _text(
              context,
              size: 31,
              weight: FontWeight.w800,
              color: _blue,
            ),
          ),
          SizedBox(height: metrics.geometry(5)),
          Text(
            'Available to withdraw: ${_usd(wallet.availableMinor)}',
            key: const ValueKey('approved-rewards-available-caption'),
            style: _text(context, size: 11.5, color: _muted),
          ),
        ],
      );
    } else if (_busy) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroLabel(),
          SizedBox(height: metrics.geometry(6)),
          Text(
            '—',
            style: _text(
              context,
              size: 31,
              weight: FontWeight.w800,
              color: _blue,
            ),
          ),
          SizedBox(height: metrics.geometry(5)),
          Text(
            'Updating your rewards…',
            style: _text(context, size: 11.5, color: _muted),
          ),
          SizedBox(height: metrics.geometry(8)),
          const BuyerProgressStrip(),
        ],
      );
    } else if (_walletFailed) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroLabel(),
          SizedBox(height: metrics.geometry(6)),
          Text(
            '—',
            style: _text(
              context,
              size: 31,
              weight: FontWeight.w800,
              color: _blue,
            ),
          ),
          SizedBox(height: metrics.geometry(5)),
          Text(_error!, style: _text(context, size: 11.5, color: _muted)),
          SizedBox(height: metrics.geometry(8)),
          BuyerSecondaryButton(
            key: const ValueKey('approved-rewards-retry'),
            compact: true,
            label: 'Retry',
            onPressed: _load,
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroLabel(),
          SizedBox(height: metrics.geometry(6)),
          Text(
            '—',
            style: _text(
              context,
              size: 31,
              weight: FontWeight.w800,
              color: _blue,
            ),
          ),
          SizedBox(height: metrics.geometry(5)),
          Text(
            'Rewards are not available yet.',
            style: _text(context, size: 11.5, color: _muted),
          ),
        ],
      );
    }
    final hero = HocalistEntrance(
      key: ValueKey((
        'rewards-hero',
        _busy,
        _walletFailed,
        wallet?.earnedMinor,
      )),
      child: Container(
        key: const ValueKey('approved-rewards-hero'),
        padding: metrics.geometryInsets(const EdgeInsets.all(18)),
        decoration: BoxDecoration(
          color: _lavender,
          borderRadius: BorderRadius.circular(metrics.geometry(18)),
        ),
        child: Row(
          children: [
            Expanded(child: body),
            BuyerAssetIconSurface(
              asset: '$_approvedAssetRoot/dashboard-trophy-glyph.png',
              surfaceSize: metrics.artSize(74),
              iconSize: metrics.artSize(42),
              backgroundColor: const Color(0xffe9e4ff),
              shape: BuyerIconSurfaceShape.circle,
            ),
          ],
        ),
      ),
    );
    if (wallet != null) return hero;
    final phaseKey = _busy
        ? 'approved-rewards-loading'
        : _walletFailed
        ? 'approved-rewards-error'
        : 'approved-rewards-unavailable';
    return KeyedSubtree(key: ValueKey(phaseKey), child: hero);
  }

  Widget _metricsRow(RewardWalletView? wallet, ApprovedReplicaMetrics metrics) {
    final configured =
        wallet != null &&
        wallet.withdrawal.configured &&
        wallet.withdrawal.minimumMinor != null;
    final minimum = configured ? wallet.withdrawal.minimumMinor : null;
    final untilPayout = minimum == null || wallet == null
        ? null
        : (minimum - wallet.availableMinor).clamp(0, minimum);
    final pending = wallet == null ? '—' : _usd(wallet.pendingMinor);
    final placeholderNote = _busy ? 'Loading…' : 'Not available';
    final untilNote = wallet == null
        ? placeholderNote
        : untilPayout == null
        ? 'Policy not configured'
        : null;
    return Row(
      children: [
        Expanded(
          child: _ApprovedRewardMetric(
            asset: 'dashboard-calendar.png',
            label: 'Pending',
            value: pending,
            note: wallet == null ? placeholderNote : null,
            valueKey: const ValueKey('approved-rewards-pending'),
          ),
        ),
        SizedBox(width: metrics.spacing(10)),
        Expanded(
          child: _ApprovedRewardMetric(
            asset: 'ready-gift.png',
            label: 'Until payout',
            value: untilPayout == null ? '—' : _usd(untilPayout),
            note: untilNote,
            valueKey: const ValueKey('approved-rewards-until-payout'),
          ),
        ),
      ],
    );
  }

  Widget _nextPayoutSection(
    RewardWalletView? wallet,
    ApprovedReplicaMetrics metrics,
  ) {
    if (wallet != null) {
      final minimum = wallet.withdrawal.minimumMinor;
      if (wallet.withdrawal.configured && minimum != null) {
        return _nextPayoutSurface(wallet, minimum, metrics);
      }
      return const _ApprovedDetailSurface(
        child: BuyerStateNotice(
          key: ValueKey('approved-rewards-next-payout-unavailable'),
          icon: Icons.account_balance_outlined,
          tone: BuyerNoticeTone.warning,
          title: 'Withdrawal terms are not configured yet',
          body:
              'The next payout cannot be calculated until the withdrawal '
              'policy is published.',
        ),
      );
    }
    if (_busy) {
      return _ApprovedDetailSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next payout',
                    style: _text(
                      context,
                      size: 14,
                      weight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ),
                Text(
                  'Loading…',
                  style: _text(context, size: 11, color: _muted),
                ),
              ],
            ),
            SizedBox(height: metrics.geometry(12)),
            const BuyerProgressStrip(
              key: ValueKey('approved-rewards-next-payout-loading'),
            ),
            SizedBox(height: metrics.geometry(8)),
            Text(
              'Payout progress will appear here.',
              style: _text(context, size: 11.5, color: _muted),
            ),
          ],
        ),
      );
    }
    return _nextPayoutUnavailable(
      title: 'Payout progress is unavailable',
      body: _walletFailed
          ? 'The rewards ledger could not be read, so payout progress cannot '
                'be calculated yet.'
          : 'Payout progress will appear once the rewards ledger is enabled '
                'for this build.',
    );
  }

  Widget _nextPayoutUnavailable({required String title, required String body}) {
    return _ApprovedDetailSurface(
      child: BuyerStateNotice(
        key: const ValueKey('approved-rewards-next-payout-unavailable'),
        icon: Icons.hourglass_empty_rounded,
        tone: BuyerNoticeTone.warning,
        title: title,
        body: body,
      ),
    );
  }

  Widget _activitySection(
    RewardWalletView? wallet,
    ApprovedReplicaMetrics metrics,
  ) {
    if (wallet != null) {
      return _ApprovedDetailSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: wallet.items.isEmpty
            ? _emptyState(
                metrics,
                icon: Icons.savings_outlined,
                title: 'No earned rewards yet.',
                body:
                    'Rewards from eligible confirmed purchases will appear here.',
                key: const ValueKey('approved-rewards-activity-empty'),
              )
            : Column(
                children: [
                  for (var index = 0; index < wallet.items.length; index++) ...[
                    _activityRow(wallet.items[index], metrics),
                    if (index != wallet.items.length - 1)
                      Divider(height: 1, color: _line),
                  ],
                ],
              ),
      );
    }
    if (_busy) {
      return const _ApprovedDetailSurface(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: BuyerProgressStrip(
          key: ValueKey('approved-rewards-activity-loading'),
          label: 'Loading reward activity…',
        ),
      );
    }
    return _ApprovedDetailSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: _emptyState(
        metrics,
        icon: Icons.cloud_off_rounded,
        title: 'Reward activity is unavailable',
        body: _walletFailed
            ? 'Reward activity could not be loaded. Nothing is estimated locally.'
            : 'Reward activity will appear once the rewards ledger is enabled for this build.',
        key: const ValueKey('approved-rewards-activity-unavailable'),
      ),
    );
  }

  Widget _payoutDestinationSection(
    RewardWalletView? wallet,
    ApprovedReplicaMetrics metrics,
  ) {
    if (wallet == null) {
      return _payoutDestination(
        metrics,
        payoutEnabled: false,
        subtitle: _busy
            ? 'Loading payout details…'
            : _walletFailed
            ? 'Unavailable while the rewards ledger cannot be read.'
            : 'Payout details will appear once the rewards ledger is enabled.',
      );
    }
    final payoutEnabled =
        wallet.payout.providerConfigured && wallet.payout.executionEnabled;
    return _payoutDestination(
      metrics,
      payoutEnabled: payoutEnabled,
      subtitle: payoutEnabled
          ? 'Choose where eligible rewards will be sent.'
          : 'Payout execution is not enabled yet. Provider setup is still pending.',
    );
  }

  Widget _rewardPaymentNotice(ApprovedReplicaMetrics metrics) {
    return _ApprovedDetailSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BuyerGlyphIcon(
            icon: Icons.info_outline_rounded,
            slotSize: 24,
            glyphSize: 20,
            color: _blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reward payouts are separate from item payment. Buyers and sellers still complete item payment offline.',
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.secondaryBody,
                color: _muted,
                height: 1.4,
              ).copyWith(fontSize: metrics.fontSize(11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextPayoutSurface(
    RewardWalletView wallet,
    int minimum,
    ApprovedReplicaMetrics metrics,
  ) {
    final ready = wallet.availableMinor >= minimum;
    final progress = minimum <= 0
        ? 1.0
        : (wallet.availableMinor / minimum).clamp(0.0, 1.0);
    return _ApprovedDetailSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Next payout',
                  style: _text(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                ready ? 'Ready to withdraw' : 'Minimum ${_usd(minimum)}',
                key: const ValueKey('approved-rewards-next-payout-state'),
                style: _text(
                  context,
                  size: 11,
                  weight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.geometry(12)),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Semantics(
              container: true,
              child: LinearProgressIndicator(
                key: const ValueKey('approved-rewards-next-payout-progress'),
                semanticsLabel: 'Next payout progress',
                value: progress,
                minHeight: 9,
                backgroundColor: _lavender,
                valueColor: const AlwaysStoppedAnimation<Color>(_blue),
              ),
            ),
          ),
          SizedBox(height: metrics.geometry(8)),
          Text(
            '${_usd(wallet.availableMinor)} of ${_usd(minimum)} ready',
            key: const ValueKey('approved-rewards-next-payout-caption'),
            style: _text(
              context,
              size: 11.5,
              weight: FontWeight.w700,
              color: _navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(RewardItemView item, ApprovedReplicaMetrics metrics) {
    final earned = item.status == RewardItemStatus.earned;
    return _ApprovedRewardActivityRow(
      asset: earned ? 'dashboard-trophy.png' : 'dashboard-clipboard.png',
      title: item.itemTitle ?? 'Confirmed purchase',
      subtitle:
          '${earned ? (item.holdMinor > 0 ? 'Earned — on hold' : 'Reward earned') : 'On hold until the sale is confirmed'}'
          ' • ${_date(item.createdAt)}',
      value: '${earned ? '+' : ''}${_usd(item.amountMinor)}',
      valueColor: earned ? _green : const Color(0xffb35b00),
    );
  }

  Widget _payoutDestination(
    ApprovedReplicaMetrics metrics, {
    required bool payoutEnabled,
    required String subtitle,
  }) {
    return _ApprovedDetailSurface(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('approved-rewards-payout-destination'),
          onTap: payoutEnabled ? widget.onWithdraw : null,
          borderRadius: BorderRadius.circular(metrics.geometry(12)),
          child: Padding(
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(vertical: 4),
            ),
            child: Row(
              children: [
                Container(
                  width: metrics.artSize(38),
                  height: metrics.artSize(38),
                  decoration: const BoxDecoration(
                    color: _lavender,
                    shape: BoxShape.circle,
                  ),
                  child: BuyerGlyphIcon(
                    icon: payoutEnabled
                        ? Icons.account_balance_outlined
                        : Icons.hourglass_empty_rounded,
                    slotSize: metrics.artSize(38),
                    glyphSize: metrics.artSize(20),
                    color: _blue,
                  ),
                ),
                SizedBox(width: metrics.geometry(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payoutEnabled
                            ? 'Add or manage payout method'
                            : 'Payout destination',
                        style: _text(
                          context,
                          size: 12.5,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(2)),
                      Text(
                        subtitle,
                        key: const ValueKey('approved-rewards-payout-state'),
                        style: _text(context, size: 10.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                if (payoutEnabled)
                  const BuyerGlyphIcon(
                    icon: Icons.chevron_right,
                    slotSize: 24,
                    glyphSize: 20,
                    color: _muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Approved payout-history section. The authoritative withdrawal read is
  /// independent of the rewards wallet, so loaded requests render even while
  /// the wallet is missing; otherwise a designed state is shown.
  Widget _payoutHistory(
    RewardWalletView? wallet,
    ApprovedReplicaMetrics metrics,
  ) {
    final requests = _withdrawals?.requests ?? const <WithdrawalRequestView>[];
    if (requests.isNotEmpty) {
      return Column(
        children: [
          for (var index = 0; index < requests.length; index++) ...[
            _payoutRow(requests[index]),
            if (index != requests.length - 1) Divider(height: 1, color: _line),
          ],
        ],
      );
    }
    if (_withdrawals != null) {
      return _emptyState(
        metrics,
        icon: Icons.receipt_long_outlined,
        title: 'No payout requests yet.',
        body: 'Requested payouts and their provider status will appear here.',
        key: const ValueKey('approved-rewards-history-empty'),
      );
    }
    if (widget.loadWithdrawals == null) {
      return _emptyState(
        metrics,
        icon: Icons.receipt_long_outlined,
        title: 'Payout history is not available yet',
        body: wallet == null
            ? 'The payout history read is not connected in this build. '
                  'Nothing is estimated locally.'
            : !wallet.withdrawal.configured
            ? 'Withdrawal terms are not published, so payout requests cannot '
                  'be recorded.'
            : 'The payout history read is not connected in this build. '
                  'Nothing is estimated locally.',
        key: const ValueKey('approved-rewards-history-unavailable'),
      );
    }
    if (_withdrawalsBusy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: BuyerProgressStrip(
          key: ValueKey('approved-rewards-history-loading'),
          label: 'Loading payout history…',
        ),
      );
    }
    if (_withdrawalsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: BuyerStateNotice(
          key: const ValueKey('approved-rewards-history-error'),
          icon: Icons.cloud_off_rounded,
          tone: BuyerNoticeTone.error,
          title: 'Payout history could not be loaded',
          body: _withdrawalsError,
          actionLabel: 'Retry history',
          onAction: () => _loadWithdrawals(_generation),
        ),
      );
    }
    return _emptyState(
      metrics,
      icon: Icons.receipt_long_outlined,
      title: 'No payout requests yet.',
      body: 'Requested payouts and their provider status will appear here.',
      key: const ValueKey('approved-rewards-history-empty'),
    );
  }

  Widget _payoutRow(WithdrawalRequestView row) {
    final label = switch (row.status) {
      'processing' => 'Processing • funds reserved',
      'failed' => 'Failed • funds restored',
      'paid' => 'Paid',
      _ => 'Unknown',
    };
    final color = switch (row.status) {
      'paid' => _green,
      'failed' => const Color(0xffc62828),
      _ => _blue,
    };
    return _ApprovedRewardActivityRow(
      asset: row.isPaid ? 'ready-gift.png' : 'dashboard-calendar.png',
      title: 'Withdrawal',
      subtitle: '$label • ${_date(row.createdAt)}',
      value: _usd(row.netMinor),
      valueColor: color,
    );
  }

  Widget _emptyState(
    ApprovedReplicaMetrics metrics, {
    required IconData icon,
    required String title,
    required String body,
    required Key key,
  }) {
    return Padding(
      key: key,
      padding: EdgeInsets.symmetric(vertical: metrics.geometry(16)),
      child: Column(
        children: [
          BuyerGlyphIcon(
            icon: icon,
            slotSize: BuyerIconTokens.feature,
            color: _blue,
          ),
          SizedBox(height: metrics.geometry(8)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: _text(
              context,
              size: 12.5,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(4)),
          Text(
            body,
            textAlign: TextAlign.center,
            style: _text(context, size: 10.5, color: _muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class ApprovedBuyerWithdrawalPage extends StatefulWidget {
  const ApprovedBuyerWithdrawalPage({
    required this.onBack,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onComplete;

  @override
  State<ApprovedBuyerWithdrawalPage> createState() =>
      _ApprovedBuyerWithdrawalPageState();
}

class _ApprovedBuyerWithdrawalPageState
    extends State<ApprovedBuyerWithdrawalPage> {
  final _amountController = TextEditingController(text: '128.45');
  String? _payoutDestination;
  bool _submitted = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _addDestination() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedPayoutDestinationSheet(
        onClose: () => Navigator.pop(sheetContext, false),
        onSave: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (added == true && mounted) {
      setState(() => _payoutDestination = 'Payout account •••• 8421');
    }
  }

  Future<void> _reviewWithdrawal() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || amount > 128.45) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(r'Enter an amount up to $128.45.')),
      );
      return;
    }
    if (_payoutDestination == null) {
      await _addDestination();
      if (!mounted || _payoutDestination == null) return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedWithdrawalReviewSheet(
        amount: amount,
        destination: _payoutDestination!,
        onClose: () => Navigator.pop(sheetContext, false),
        onConfirm: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _submitted = true);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    if (_submitted) {
      return ApprovedReplicaScope(
        metrics: metrics,
        child: Column(
          key: const ValueKey('approved-withdrawal-success-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedDetailHeading(
              title: 'Withdrawal requested',
              subtitle: 'Your request is ready for payout processing.',
              onBack: widget.onBack,
            ),
            SizedBox(height: metrics.spacing(18)),
            _ApprovedDetailSurface(
              child: Column(
                children: [
                  BuyerAssetIconSurface(
                    asset: '$_approvedAssetRoot/dashboard-calendar.png',
                    surfaceSize: metrics.artSize(72),
                    iconSize: metrics.artSize(38),
                    backgroundColor: HocalistPalette.surface(
                      context,
                      const Color(0xffe7f7ef),
                    ),
                    shape: BuyerIconSurfaceShape.circle,
                  ),
                  SizedBox(height: metrics.spacing(12)),
                  Text(
                    '\$${_amountController.text.trim()}',
                    style: _text(
                      context,
                      size: 30,
                      weight: FontWeight.w900,
                      color: _blue,
                    ),
                  ),
                  SizedBox(height: metrics.spacing(5)),
                  Text(
                    'Pending payout connection',
                    style: _text(
                      context,
                      size: 13,
                      weight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  SizedBox(height: metrics.spacing(6)),
                  Text(
                    'The UI request is saved locally. Transfer timing and final status will come from the payout backend.',
                    textAlign: TextAlign.center,
                    style: _text(
                      context,
                      size: 11.5,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.spacing(14)),
            BuyerPrimaryButton(
              key: const Key('approved-withdrawal-done'),
              label: 'Back to rewards',
              onPressed: widget.onBack,
            ),
          ],
        ),
      );
    }

    return ApprovedReplicaScope(
      metrics: metrics,
      child: Column(
        key: const ValueKey('approved-withdrawal-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Withdraw rewards',
            subtitle: 'Choose an amount and where you want to receive it.',
            onBack: widget.onBack,
          ),
          SizedBox(height: metrics.spacing(16)),
          _ApprovedDetailSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available to withdraw',
                  style: _text(context, size: 12, color: _muted),
                ),
                SizedBox(height: metrics.spacing(4)),
                Text(
                  '\$128.45',
                  style: _text(
                    context,
                    size: 28,
                    weight: FontWeight.w900,
                    color: _blue,
                  ),
                ),
                SizedBox(height: metrics.spacing(14)),
                const BuyerFieldLabel('Withdrawal amount', uppercase: true),
                SizedBox(height: metrics.spacing(5)),
                TextField(
                  key: const Key('approved-withdrawal-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: buyerInputDecoration(
                    context,
                    hintText: '0.00',
                    prefixText: '\$ ',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(12)),
          _ApprovedDetailSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payout destination',
                  style: _text(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.spacing(10)),
                Material(
                  color: HocalistPalette.surface(context, Colors.transparent),
                  child: ListTile(
                    key: const Key('approved-withdrawal-destination'),
                    contentPadding: EdgeInsets.zero,
                    leading: BuyerGlyphIcon(
                      icon: Icons.account_balance_outlined,
                      slotSize: metrics.artSize(30),
                      glyphSize: metrics.artSize(24),
                      color: HocalistPalette.text(context, _blue),
                    ),
                    title: Text(
                      _payoutDestination ?? 'Add a payout account',
                      style: _text(
                        context,
                        size: 12.5,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    subtitle: Text(
                      _payoutDestination == null
                          ? 'Secure provider connection will be added with the backend.'
                          : 'Selected for this withdrawal',
                      style: _text(context, size: 10.5, color: _muted),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: HocalistPalette.text(context, _blue),
                    ),
                    onTap: _addDestination,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(
            'Pending rewards are not included. Fees, eligibility, and timing will be supplied by the rewards backend.',
            style: _text(context, size: 10.5, color: _muted, height: 1.4),
          ),
          SizedBox(height: metrics.spacing(16)),
          BuyerPrimaryButton(
            key: const Key('approved-withdrawal-review'),
            label: 'Review withdrawal',
            onPressed: _reviewWithdrawal,
          ),
        ],
      ),
    );
  }
}

class _ApprovedPayoutDestinationSheet extends StatelessWidget {
  const _ApprovedPayoutDestinationSheet({
    required this.onClose,
    required this.onSave,
  });

  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _ApprovedBuyerFlowSheet(
      key: const Key('approved-payout-destination-sheet'),
      icon: Icons.account_balance_outlined,
      title: 'Add payout destination',
      subtitle:
          'Enter preview details now. Secure account collection will be handled by the payout provider later.',
      onClose: onClose,
      children: [
        const _ApprovedBuyerSheetField(
          fieldKey: Key('approved-payout-account-name'),
          label: 'Account holder name',
          hintText: 'Maya Chen',
        ),
        const SizedBox(height: 10),
        const _ApprovedBuyerSheetField(
          fieldKey: Key('approved-payout-account-ending'),
          label: 'Account last four digits',
          hintText: '8421',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        BuyerPrimaryButton(
          key: const Key('approved-payout-save'),
          label: 'Save payout destination',
          onPressed: onSave,
        ),
      ],
    );
  }
}

class _ApprovedWithdrawalReviewSheet extends StatelessWidget {
  const _ApprovedWithdrawalReviewSheet({
    required this.amount,
    required this.destination,
    required this.onClose,
    required this.onConfirm,
  });

  final double amount;
  final String destination;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return _ApprovedBuyerFlowSheet(
      key: const Key('approved-withdrawal-review-sheet'),
      icon: Icons.payments_outlined,
      title: 'Review withdrawal',
      subtitle: 'Confirm the amount and destination before continuing.',
      onClose: onClose,
      children: [
        _ApprovedDetailSurface(
          child: Column(
            children: [
              _ApprovedSummaryLine(
                label: 'Amount',
                value: '\$${amount.toStringAsFixed(2)}',
              ),
              const Divider(color: _line),
              _ApprovedSummaryLine(label: 'To', value: destination),
              const Divider(color: _line),
              const _ApprovedSummaryLine(
                label: 'Status',
                value: 'Pending provider connection',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        BuyerPrimaryButton(
          key: const Key('approved-withdrawal-confirm'),
          label: 'Confirm withdrawal',
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

class _ApprovedBuyerFlowSheet extends StatelessWidget {
  const _ApprovedBuyerFlowSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.children,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BuyerModalSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      titleKey: const Key('approvedBuyerSheetTitle'),
      onClose: onClose,
      child: Column(
        key: const Key('approvedBuyerSheetContent'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ApprovedBuyerSheetField extends StatelessWidget {
  const _ApprovedBuyerSheetField({
    required this.fieldKey,
    required this.label,
    required this.hintText,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final String hintText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuyerFieldLabel(label),
        const SizedBox(height: 5),
        TextField(
          key: fieldKey,
          keyboardType: keyboardType,
          style: _text(context, size: 12, color: _navy),
          decoration: buyerInputDecoration(context, hintText: hintText),
        ),
      ],
    );
  }
}

class _ApprovedSummaryLine extends StatelessWidget {
  const _ApprovedSummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: _text(context, size: 11, color: _muted)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: _text(
                context,
                size: 11.5,
                weight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ApprovedSellerPublicProfilePage extends StatelessWidget {
  const ApprovedSellerPublicProfilePage({
    required this.onBack,
    this.onSelect,
    this.realSellerName,
    this.realMode = false,
    this.subtitle = 'Seller details from the selected offer.',
    this.selectionBusy = false,
    this.selectionError,
    this.publishedListings,
    this.reputation,
    this.reputationLoading = false,
    this.reputationError,
    this.verificationLabel,
    super.key,
  });

  final VoidCallback onBack;

  /// Selection action for the offer flow. Null when the profile is opened from
  /// a conversation and there is no offer to select.
  final VoidCallback? onSelect;
  final String? realSellerName;
  final bool realMode;
  final String subtitle;
  final bool selectionBusy;
  final String? selectionError;
  final Widget? publishedListings;

  /// Authoritative public reputation from published reviews. Null keeps the
  /// honest "not available yet" state.
  final PublicSellerReputation? reputation;
  final bool reputationLoading;
  final String? reputationError;

  /// Reviewed verification state supplied by the trust projection.
  final String? verificationLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    if (realMode) {
      final reputation = this.reputation;
      return ApprovedReplicaScope(
        metrics: metrics,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedDetailHeading(
              title: 'Seller profile',
              subtitle: subtitle,
              onBack: onBack,
            ),
            SizedBox(height: metrics.spacing(14)),
            _ApprovedDetailSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: metrics.geometry(56),
                        height: metrics.geometry(56),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            BuyerUiTokens.activeSurface,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          realSellerName?.trim().isNotEmpty == true
                              ? realSellerName!
                                    .trim()
                                    .substring(0, 1)
                                    .toUpperCase()
                              : '—',
                          style: _text(
                            context,
                            size: 23,
                            weight: FontWeight.w900,
                            color: BuyerUiTokens.action,
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.spacing(12)),
                      Expanded(
                        child: Text(
                          realSellerName ?? 'Seller details unavailable',
                          style: _text(
                            context,
                            size: 19,
                            weight: FontWeight.w900,
                            color: _navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (verificationLabel != null) ...[
                    SizedBox(height: metrics.spacing(4)),
                    Text(
                      verificationLabel!,
                      style: _text(context, size: 11.5, color: _green),
                    ),
                  ],
                  SizedBox(height: metrics.spacing(12)),
                  if (reputationLoading && reputation == null)
                    Text(
                      'Loading public seller reputation…',
                      style: _text(context, size: 12, color: _muted),
                    )
                  else if (reputation == null || !reputation.available)
                    BuyerStateNotice(
                      icon: Icons.rate_review_outlined,
                      title: 'Public reputation',
                      body:
                          reputationError ??
                          'Public ratings and verified history are not available for this seller yet.',
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _ApprovedProfileMetric(
                            value: reputation.averageRating == null
                                ? '—'
                                : reputation.averageRating!.toStringAsFixed(1),
                            label: 'Rating',
                          ),
                        ),
                        Expanded(
                          child: _ApprovedProfileMetric(
                            value: '${reputation.completedDeals}',
                            label: 'Confirmed deals',
                          ),
                        ),
                        Expanded(
                          child: _ApprovedProfileMetric(
                            value: '${reputation.ratingCount}',
                            label: 'Reviews',
                          ),
                        ),
                      ],
                    ),
                    if (reputation.reviews.isNotEmpty) ...[
                      SizedBox(height: metrics.spacing(12)),
                      for (final review in reputation.reviews) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: HocalistPalette.surface(
                              context,
                              Colors.white,
                            ),
                            border: Border.all(
                              color: HocalistPalette.border(context, _line),
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${review.rating} / 5 · '
                                '${review.reviewerLabel}',
                                style: _text(
                                  context,
                                  size: 11.5,
                                  weight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              if (review.body.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  review.body,
                                  style: _text(
                                    context,
                                    size: 11.5,
                                    color: _navy,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'No published reviews yet.',
                          style: _text(context, size: 11.5, color: _muted),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            SizedBox(height: metrics.spacing(12)),
            _ApprovedDetailSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ApprovedProfileInfoRow(
                    icon: Icons.verified_user_outlined,
                    title: 'Trust details',
                    body:
                        verificationLabel ??
                        'Public verification details are not available for this seller.',
                  ),
                  const Divider(color: _line),
                  const _ApprovedProfileInfoRow(
                    icon: Icons.inventory_2_outlined,
                    title: 'What this seller offers',
                    body:
                        'Published listings appear below when available. Other service details are unavailable.',
                  ),
                  const Divider(color: _line),
                  const _ApprovedProfileInfoRow(
                    icon: Icons.handshake_outlined,
                    title: 'Meetup preferences',
                    body:
                        'Meetup preferences are unavailable. Agree on the place and time in your conversation.',
                  ),
                ],
              ),
            ),
            if (selectionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  selectionError!,
                  style: TextStyle(
                    color: HocalistPalette.text(
                      context,
                      Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (onSelect != null) ...[
              SizedBox(height: metrics.spacing(16)),
              BuyerPrimaryButton(
                key: const Key('approved-public-profile-select-seller'),
                label: selectionBusy
                    ? 'Selecting seller…'
                    : 'Select seller and open chat',
                onPressed: selectionBusy || realSellerName == null
                    ? null
                    : onSelect,
              ),
            ],
            if (publishedListings != null) ...[
              SizedBox(height: metrics.spacing(18)),
              publishedListings!,
            ],
          ],
        ),
      );
    }
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Column(
        key: const ValueKey('approved-seller-public-profile-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Seller profile',
            subtitle: 'Review trust and service details before selecting.',
            onBack: onBack,
          ),
          SizedBox(height: metrics.spacing(14)),
          _ApprovedDetailSurface(
            child: Column(
              children: [
                Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/approved_offers_chat/john-avatar.png',
                        width: metrics.artSize(66),
                        height: metrics.artSize(66),
                        fit: BoxFit.cover,
                      ),
                    ),
                    SizedBox(width: metrics.spacing(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'John D.',
                            style: _text(
                              context,
                              size: 19,
                              weight: FontWeight.w900,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: metrics.spacing(4)),
                          Text(
                            'Verified seller • Active now',
                            style: _text(
                              context,
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: _green,
                            ),
                          ),
                          SizedBox(height: metrics.spacing(4)),
                          Text(
                            'Yonkers, NY • 2.1 mi',
                            style: _text(context, size: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: metrics.spacing(14)),
                const Row(
                  children: [
                    Expanded(
                      child: _ApprovedProfileMetric(
                        value: '4.9',
                        label: 'Rating',
                      ),
                    ),
                    Expanded(
                      child: _ApprovedProfileMetric(
                        value: '126',
                        label: 'Deals',
                      ),
                    ),
                    Expanded(
                      child: _ApprovedProfileMetric(
                        value: '98%',
                        label: 'Response',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(12)),
          const _ApprovedDetailSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ApprovedProfileInfoRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Trust details',
                  body:
                      'Identity verified and marketplace safety checks complete.',
                ),
                Divider(color: _line),
                _ApprovedProfileInfoRow(
                  icon: Icons.inventory_2_outlined,
                  title: 'What this seller offers',
                  body: 'Electronics, tablets, televisions, and accessories.',
                ),
                Divider(color: _line),
                _ApprovedProfileInfoRow(
                  icon: Icons.handshake_outlined,
                  title: 'Meetup preferences',
                  body: 'Public pickup locations and in-store handoffs.',
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(16)),
          BuyerPrimaryButton(
            key: const Key('approved-public-profile-select-seller'),
            label: 'Select seller and open chat',
            onPressed: onSelect,
          ),
        ],
      ),
    );
  }
}

class _ApprovedProfileMetric extends StatelessWidget {
  const _ApprovedProfileMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: _text(
            context,
            size: 16,
            weight: FontWeight.w900,
            color: _navy,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: _text(context, size: 10.5, color: _muted)),
      ],
    );
  }
}

class _ApprovedProfileInfoRow extends StatelessWidget {
  const _ApprovedProfileInfoRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerGlyphIcon(
            icon: icon,
            slotSize: 26,
            glyphSize: 23,
            color: HocalistPalette.text(context, _blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _text(
                    context,
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: _text(
                    context,
                    size: 10.5,
                    color: _muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ApprovedMeetingDetailsPage extends StatefulWidget {
  const ApprovedMeetingDetailsPage({
    required this.onBack,
    required this.onConfirm,
    this.meeting,
    this.busy = false,
    this.error,
    this.onDecline,
    this.onCancel,
    this.onReschedule,
    this.viewerUserId,
    this.onDirections,
    this.saleConfirmation,
    this.purchaseConfirmed = false,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onConfirm;

  /// Authoritative meeting detail. When null the approved prototype rows stay
  /// unchanged; when present only server facts are rendered.
  final MeetingView? meeting;
  final bool busy;
  final String? error;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;
  final String? viewerUserId;
  final VoidCallback? onDirections;
  final Widget? saleConfirmation;
  final bool purchaseConfirmed;

  @override
  State<ApprovedMeetingDetailsPage> createState() =>
      _ApprovedMeetingDetailsPageState();
}

class _ApprovedMeetingDetailsPageState
    extends State<ApprovedMeetingDetailsPage> {
  MeetingView? get _meeting => widget.meeting;

  MeetingScheduleView? get _schedule =>
      _meeting?.pendingSchedule ?? _meeting?.acceptedSchedule;

  String get _title =>
      _meeting?.offerSummary?.title ?? 'Offer details unavailable';

  String get _price => _meeting?.offerSummary?.priceLabel ?? '';

  String get _statusLabel => switch (_meeting?.status) {
    'accepted' => 'Meeting confirmed',
    'proposed' => 'Meeting proposed',
    'reschedule_proposed' => 'Reschedule requested',
    'cancelled' => 'Meeting cancelled',
    _ => 'Offer accepted',
  };

  String get _placeLabel {
    final schedule = _schedule;
    for (final value in [schedule?.placeLabel, schedule?.placeAddress]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return switch (schedule?.placeChoice) {
      'buyer_location' => 'Buyer location — confirm the address in chat',
      'seller_business' => 'Seller business — confirm the address in chat',
      _ => 'Address not confirmed',
    };
  }

  bool get _hasDirections => hasConfirmedMeetingDestination(
    address: _meeting?.acceptedSchedule?.placeAddress,
    label: _meeting?.acceptedSchedule?.placeLabel,
    placeId: _meeting?.acceptedSchedule?.placeId,
  );

  String get _timeLabel {
    final schedule = _schedule;
    if (schedule == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = schedule.startTime.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minute = schedule.startTime.minute.toString().padLeft(2, '0');
    return '${months[schedule.date.month - 1]} ${schedule.date.day} • '
        '$displayHour:$minute $period · ${schedule.timezoneId}';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final viewport = MediaQuery.sizeOf(context);
    final compactViewport = viewport.width <= 340 || viewport.height <= 700;
    final realMode = _meeting != null;
    final canDecline =
        realMode &&
        !widget.purchaseConfirmed &&
        _meeting!.hasPendingSchedule &&
        !_meeting!.isCancelled &&
        _meeting!.pendingSchedule!.proposedByUserId != widget.viewerUserId;
    final canCancel =
        realMode &&
        !widget.purchaseConfirmed &&
        !_meeting!.isCancelled &&
        !_meeting!.hasPendingSchedule &&
        _meeting!.hasAcceptedSchedule;
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Column(
        key: const ValueKey('approved-meeting-details-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Meeting details',
            subtitle: 'Confirm the place and time both sides will see.',
            onBack: widget.onBack,
          ),
          SizedBox(height: metrics.spacing(compactViewport ? 8 : 16)),
          _ApprovedDetailSurface(
            padding: EdgeInsets.all(compactViewport ? 10 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: metrics.artSize(compactViewport ? 56 : 68),
                  height: metrics.artSize(compactViewport ? 62 : 76),
                  padding: metrics.geometryInsets(const EdgeInsets.all(5)),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      const Color(0xfff8f8ff),
                    ),
                    borderRadius: BorderRadius.circular(metrics.geometry(12)),
                  ),
                  child: realMode
                      ? const BuyerAssetIcon(
                          asset: 'assets/approved_offers_chat/chat-time.png',
                          slotSize: 24,
                        )
                      : Image.asset(
                          'assets/approved_offers_chat/chat-ipad.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                ),
                SizedBox(width: metrics.geometry(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        realMode ? _title : 'iPad Air 5th Gen 64GB',
                        style: _text(
                          context,
                          size: 15,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      if (!realMode || _price.isNotEmpty) ...[
                        SizedBox(height: metrics.geometry(4)),
                        Text(
                          realMode ? _price : '\$650',
                          style: _text(
                            context,
                            size: 20,
                            weight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                      ],
                      SizedBox(height: metrics.geometry(6)),
                      Container(
                        padding: metrics.geometryInsets(
                          const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            const Color(0xffe9f8ee),
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          realMode ? _statusLabel : 'Offer accepted',
                          style: _text(
                            context,
                            size: 10,
                            weight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(compactViewport ? 8 : 12)),
          _ApprovedDetailSurface(
            padding: EdgeInsets.all(compactViewport ? 10 : 14),
            child: Column(
              children: [
                _ApprovedMeetingField(
                  key: const ValueKey('approved-meeting-location-field'),
                  asset: 'chat-location.png',
                  label: 'Pickup location',
                  initialValue: realMode ? _placeLabel : 'Yonkers, NY',
                  readOnly: realMode,
                ),
                SizedBox(height: metrics.geometry(compactViewport ? 8 : 12)),
                _ApprovedMeetingField(
                  key: const ValueKey('approved-meeting-time-field'),
                  asset: 'chat-time.png',
                  label: 'Date and time',
                  initialValue: realMode ? _timeLabel : 'Today • 5:00 PM',
                  readOnly: realMode,
                ),
                SizedBox(height: metrics.geometry(compactViewport ? 8 : 12)),
                _ApprovedMeetingField(
                  asset: 'chat-safety.png',
                  label: 'Meeting note',
                  initialValue: 'Inspect the item before paying offline',
                  readOnly: realMode,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.spacing(compactViewport ? 8 : 12)),
          Container(
            padding: metrics.geometryInsets(
              EdgeInsets.all(compactViewport ? 10 : 13),
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xffeef9f2)),
              borderRadius: BorderRadius.circular(metrics.geometry(14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BuyerAssetIcon(
                  asset: 'assets/approved_offers_chat/chat-deal-shield.png',
                  slotSize: metrics.artSize(34),
                ),
                SizedBox(width: metrics.geometry(10)),
                Expanded(
                  child: Text(
                    'Meet in a public place, inspect the item, and pay the seller offline only when you are satisfied.',
                    style: _text(
                      context,
                      size: 11,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.saleConfirmation != null) widget.saleConfirmation!,
          if (widget.error != null) ...[
            SizedBox(height: metrics.spacing(8)),
            Text(
              widget.error!,
              key: const ValueKey('approved-meeting-error'),
              textAlign: TextAlign.center,
              style: _text(
                context,
                size: 11,
                color: const Color(0xffc23131),
                height: 1.3,
              ),
            ),
          ],
          SizedBox(height: metrics.spacing(compactViewport ? 9 : 16)),
          if (widget.busy)
            const Center(
              key: ValueKey('approved-meeting-busy'),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else if (!realMode || canDecline)
            BuyerPrimaryButton(
              key: const ValueKey('approved-confirm-meeting-button'),
              label: 'Confirm meeting',
              onPressed: widget.onConfirm,
              compact: compactViewport,
            ),
          if (canDecline) ...[
            SizedBox(height: metrics.spacing(6)),
            TextButton(
              key: const ValueKey('approved-decline-meeting-button'),
              onPressed: widget.busy ? null : widget.onDecline,
              child: const Text('Decline this time'),
            ),
          ],
          if (canCancel) ...[
            SizedBox(height: metrics.spacing(6)),
            TextButton(
              key: const ValueKey('approved-cancel-meeting-button'),
              onPressed: widget.busy ? null : widget.onCancel,
              child: const Text('Cancel meeting'),
            ),
          ],
          if (realMode &&
              _meeting!.hasAcceptedSchedule &&
              !_meeting!.isCancelled &&
              widget.onDirections != null)
            TextButton.icon(
              key: const ValueKey('approved-meeting-directions'),
              onPressed: widget.busy || !_hasDirections
                  ? null
                  : widget.onDirections,
              icon: const Icon(Icons.directions_outlined),
              label: const Text('View directions in Hocalist'),
            ),
          if (realMode &&
              _meeting!.status == 'accepted' &&
              !widget.purchaseConfirmed &&
              widget.onReschedule != null)
            TextButton(
              key: const ValueKey('approved-reschedule-meeting-button'),
              onPressed: widget.busy ? null : widget.onReschedule,
              child: const Text('Reschedule meeting'),
            ),
        ],
      ),
    );
  }
}

/// Upgraded Buyer continuation after a confirmed meetup.
///
/// This page intentionally carries the same deal facts shown in the approved
/// chat sheet. The Buyer shows the PIN to the seller after inspecting the item;
/// the seller submits it from Meets. Item payment remains offline.
class ApprovedRequestPostedDialog extends StatelessWidget {
  const ApprovedRequestPostedDialog({
    required this.onViewRequest,
    required this.onHome,
    super.key,
  });
  final VoidCallback onViewRequest;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
    backgroundColor: HocalistPalette.surface(context, Colors.white),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BuyerStateNotice(
              icon: Icons.check_circle_outline,
              title: 'Request posted',
              body:
                  'Your request is ready for sellers to review. Item payment stays offline.',
            ),
            const SizedBox(height: 20),
            BuyerPrimaryButton(label: 'View request', onPressed: onViewRequest),
            const SizedBox(height: 12),
            BuyerSecondaryButton(label: 'Back to dashboard', onPressed: onHome),
          ],
        ),
      ),
    ),
  );
}

class ApprovedRequestSuccessPage extends StatelessWidget {
  const ApprovedRequestSuccessPage({
    required this.navigation,
    required this.onViewRequest,
    required this.onHome,
    super.key,
  });
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onViewRequest;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => _ApprovedBuyerLifecycleScaffold(
    pageKey: const ValueKey('approved-request-success-page'),
    navigation: navigation,
    selected: ApprovedBuyerNavSelection.home,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ApprovedDetailHeading(
          title: 'Request posted',
          subtitle: 'Your request is ready for sellers to review.',
          onBack: onHome,
        ),
        const SizedBox(height: 20),
        const BuyerStateNotice(
          icon: Icons.check_circle_outline,
          title: 'You’re ready to receive offers',
          body:
              'Review your request or return home to follow its progress. Item payment stays offline.',
        ),
        const SizedBox(height: 20),
        BuyerPrimaryButton(label: 'View request', onPressed: onViewRequest),
        const SizedBox(height: 12),
        BuyerSecondaryButton(label: 'Back to dashboard', onPressed: onHome),
      ],
    ),
  );
}

class ApprovedBuyerAfterMeetupPage extends StatelessWidget {
  const ApprovedBuyerAfterMeetupPage({
    required this.onBack,
    required this.navigation,
    required this.onReview,
    required this.onDealIssue,
    required this.onReport,
    this.requestTitle,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onReview;
  final VoidCallback onDealIssue;
  final VoidCallback onReport;
  final String? requestTitle;

  @override
  Widget build(BuildContext context) {
    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-after-meetup-page'),
      navigation: navigation,
      selected: ApprovedBuyerNavSelection.home,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'After the meetup',
            subtitle:
                'Confirm what happened only after you meet and inspect the item.',
            onBack: onBack,
          ),
          const SizedBox(height: 16),
          const _ApprovedLifecycleDealSummary(
            status: 'Meeting confirmed',
            statusColor: _green,
          ),
          const SizedBox(height: 12),
          const _ApprovedLifecycleFacts(),
          const SizedBox(height: 12),
          _ApprovedLifecyclePinNotice(
            title: 'Your confirmation PIN: 15230',
            body:
                'Show this PIN to the seller only after you check ${requestTitle?.trim().isNotEmpty == true ? requestTitle!.trim() : 'the agreed product or service'} and pay them offline. The seller submits it in Meets to confirm the purchase. Any eligible reward follows the configured policy.',
          ),
          const SizedBox(height: 16),
          Text(
            'How did the meetup go?',
            style: _text(
              context,
              size: 16,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const SizedBox(height: 8),
          _ApprovedLifecycleAction(
            key: const ValueKey('approved-deal-completed-action'),
            asset: 'detail-select.png',
            title: 'Deal completed',
            body: 'The item was inspected and payment was completed offline.',
            accent: _green,
            onTap: onReview,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            key: const ValueKey('approved-deal-recovery-action'),
            asset: 'chat-time.png',
            title: 'The deal did not happen',
            body:
                'Return to backup offers or reopen the request without starting over.',
            accent: _blue,
            onTap: onDealIssue,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            key: const ValueKey('approved-deal-report-action'),
            asset: 'chat-safety.png',
            title: 'Report a safety issue',
            body: 'Report an unsafe meetup, seller, or item concern.',
            accent: const Color(0xffc62828),
            onTap: onReport,
          ),
        ],
      ),
    );
  }
}

/// Current Buyer deal history, replacing the legacy single-record surface.
class ApprovedBuyerDealHistoryPage extends StatefulWidget {
  const ApprovedBuyerDealHistoryPage({
    required this.onBack,
    required this.navigation,
    required this.dealCompleted,
    required this.dealFailed,
    required this.requestReopened,
    required this.supportReviewRequested,
    required this.onSupport,
    this.requestTitle = 'iPad Air, 5th gen or newer',
    this.sellerName = 'Northside Tech',
    this.offerPrice = '\$650',
    this.realContent,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final Widget? realContent;
  final bool dealCompleted;
  final bool dealFailed;
  final bool requestReopened;
  final bool supportReviewRequested;
  final VoidCallback onSupport;
  final String requestTitle;
  final String sellerName;
  final String offerPrice;

  @override
  State<ApprovedBuyerDealHistoryPage> createState() =>
      _ApprovedBuyerDealHistoryPageState();
}

class _ApprovedBuyerDealHistoryPageState
    extends State<ApprovedBuyerDealHistoryPage> {
  _ApprovedDealHistoryFilter _filter = _ApprovedDealHistoryFilter.all;
  _ApprovedDealHistoryRecord? _selectedRecord;

  List<_ApprovedDealHistoryRecord> get _records {
    final currentStatus = widget.dealCompleted
        ? _ApprovedDealHistoryStatus.completed
        : widget.requestReopened
        ? _ApprovedDealHistoryStatus.reopened
        : widget.dealFailed
        ? _ApprovedDealHistoryStatus.attention
        : _ApprovedDealHistoryStatus.confirmed;
    return [
      _ApprovedDealHistoryRecord(
        id: 'current-ipad-deal',
        item: widget.requestTitle,
        seller: widget.sellerName,
        price: widget.offerPrice,
        date: 'May 17, 2025 • 2:00 PM',
        location: 'Yonkers, NY',
        reward: '\$1.40',
        status: currentStatus,
        productAsset: 'assets/approved_offers_chat/chat-ipad.png',
        supportReviewRequested: widget.supportReviewRequested,
      ),
      const _ApprovedDealHistoryRecord(
        id: 'samsung-tv-deal',
        item: 'Samsung 65-inch TV',
        seller: 'Citywide Electronics',
        price: '\$480',
        date: 'May 9, 2025 • 6:30 PM',
        location: 'Hocalist Safe Meet Center',
        reward: '\$1.15',
        status: _ApprovedDealHistoryStatus.completed,
        productAsset: 'assets/approved_offers_chat/chat-tv.png',
      ),
      const _ApprovedDealHistoryRecord(
        id: 'macbook-deal',
        item: 'MacBook Air M2',
        seller: 'Gadget Buyer',
        price: '\$525',
        date: 'May 2, 2025 • 4:00 PM',
        location: 'Your Home',
        reward: '\$0.00',
        status: _ApprovedDealHistoryStatus.cancelled,
        productAsset: 'assets/approved_offers_chat/chat-ipad.png',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selectedRecord = _selectedRecord;
    if (widget.realContent != null) {
      return _ApprovedBuyerLifecycleScaffold(
        pageKey: const ValueKey('real-buyer-deal-history-page'),
        navigation: widget.navigation,
        selected: ApprovedBuyerNavSelection.more,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedDetailHeading(
              title: 'Buyer deal history',
              subtitle: 'Your confirmed Hocalist purchases.',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 16),
            widget.realContent!,
          ],
        ),
      );
    }
    if (selectedRecord != null) {
      return _buildDetail(context, selectedRecord);
    }

    final records = _records
        .where((record) => _filter.includes(record.status))
        .toList(growable: false);

    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-deal-history-page'),
      navigation: widget.navigation,
      selected: ApprovedBuyerNavSelection.more,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Buyer deal history',
            subtitle:
                'Review every deal, meetup outcome, and reward in one place.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: 16),
          _ApprovedHistoryMetrics(
            completed: _records
                .where((record) => record.status.isCompleted)
                .length,
            active: _records.where((record) => record.status.isActive).length,
            attention: _records
                .where((record) => record.status.needsAttention)
                .length,
          ),
          const SizedBox(height: 14),
          _ApprovedDealHistoryFilters(
            selected: _filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _filter == _ApprovedDealHistoryFilter.all
                      ? 'All deals'
                      : _filter.label,
                  style: _text(
                    context,
                    size: 16,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                '${records.length} ${records.length == 1 ? 'record' : 'records'}',
                style: _text(context, size: 10.5, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const _ApprovedDealHistoryEmptyState()
          else
            for (var index = 0; index < records.length; index++) ...[
              _ApprovedDealHistoryCard(
                record: records[index],
                onTap: () => setState(() => _selectedRecord = records[index]),
              ),
              if (index != records.length - 1) const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context, _ApprovedDealHistoryRecord record) {
    final completed = record.status.isCompleted;
    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-deal-history-detail-page'),
      navigation: widget.navigation,
      selected: ApprovedBuyerNavSelection.more,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Deal record',
            subtitle: 'Review the saved details and outcome of this deal.',
            onBack: () => setState(() => _selectedRecord = null),
          ),
          const SizedBox(height: 16),
          _ApprovedLifecycleDealSummary(record: record),
          const SizedBox(height: 10),
          _ApprovedLifecycleFacts(record: record),
          const SizedBox(height: 10),
          _ApprovedLifecyclePinNotice(
            title: completed ? 'PIN verified' : 'Confirmation PIN: 15230',
            body: completed
                ? 'The seller verified the meetup and ${record.reward} was credited to your rewards.'
                : 'Share this PIN only after the meetup, inspection, and offline payment are complete.',
            completed: completed,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xffeef9f2)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BuyerAssetIcon(
                  asset: 'assets/approved_offers_chat/chat-deal-shield.png',
                  slotSize: 30,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Hocalist records the deal and rewards only. The ${record.price} item payment was arranged directly with the seller and was not processed or verified by Hocalist.',
                    style: _text(
                      context,
                      size: 11,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (record.supportReviewRequested) ...[
            const SizedBox(height: 10),
            const _ApprovedHistorySupportNotice(),
          ],
          const SizedBox(height: 16),
          BuyerSecondaryButton(
            key: const ValueKey('approved-deal-history-support'),
            label: record.supportReviewRequested
                ? 'Support review requested'
                : 'Ask support to review this deal',
            onPressed: record.supportReviewRequested ? null : widget.onSupport,
            fontSize: 12.5,
          ),
        ],
      ),
    );
  }
}

/// Real-mode binding for the approved Buyer deal-history sections.
///
/// The approved metrics, filters, record cards and detail blocks are
/// preserved. Records and drill-downs come from `commercial_sale_history` and
/// `commercial_sale_detail`; counts or statuses without an authoritative
/// backend field render designed unavailable states, never fabricated values.
class ApprovedBuyerDealHistoryRealSections extends StatefulWidget {
  const ApprovedBuyerDealHistoryRealSections({
    this.load,
    this.loadDetail,
    this.loadSummary,
    this.onSupport,
    this.onReview,
    this.supportReviewRequested = false,
    super.key,
  });

  final Future<List<SaleHistoryEntryView>> Function({
    DateTime? beforeTime,
    String? beforeId,
  })?
  load;
  final Future<SaleDetailView> Function(String outcomeId)? loadDetail;
  final Future<DealSummaryView> Function()? loadSummary;
  final VoidCallback? onSupport;
  final ValueChanged<SaleDetailView>? onReview;
  final bool supportReviewRequested;

  @override
  State<ApprovedBuyerDealHistoryRealSections> createState() =>
      _ApprovedBuyerDealHistoryRealSectionsState();
}

class _ApprovedBuyerDealHistoryRealSectionsState
    extends State<ApprovedBuyerDealHistoryRealSections> {
  final _entries = <SaleHistoryEntryView>[];
  bool _busy = false;
  bool _more = true;
  String? _error;
  int _generation = 0;
  String? _expandedId;
  SaleDetailView? _detail;
  bool _detailBusy = false;
  String? _detailError;
  DealSummaryView? _summary;
  int _summaryGeneration = 0;
  _ApprovedDealHistoryFilter _filter = _ApprovedDealHistoryFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadSummary());
  }

  Future<void> _loadSummary() async {
    final generation = ++_summaryGeneration;
    final load = widget.loadSummary;
    if (load == null) return;
    try {
      final value = await load();
      if (mounted && generation == _summaryGeneration) {
        setState(() => _summary = value);
      }
    } catch (_) {
      if (mounted && generation == _summaryGeneration) {
        setState(() => _summary = null);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    if (refresh) unawaited(_loadSummary());
    final run = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      if (refresh) {
        _entries.clear();
        _more = true;
        _expandedId = null;
        _detail = null;
      }
    });
    final load = widget.load;
    if (load == null) {
      if (mounted && run == _generation) {
        setState(() {
          _busy = false;
          _error = 'The live deal history has not been enabled for this build.';
        });
      }
      return;
    }
    try {
      final rows = await load(
        beforeTime: _entries.isEmpty ? null : _entries.last.confirmedAt,
        beforeId: _entries.isEmpty ? null : _entries.last.id,
      );
      if (!mounted || run != _generation) return;
      setState(() {
        for (final row in rows) {
          if (!_entries.any((old) => old.id == row.id)) _entries.add(row);
        }
        _more = rows.length == 25;
      });
    } catch (_) {
      if (mounted && run == _generation) {
        setState(
          () =>
              _error = 'Completed purchases could not be loaded. Please retry.',
        );
      }
    } finally {
      if (mounted && run == _generation) setState(() => _busy = false);
    }
  }

  /// Every row in the confirmed sale-history read is a completed outcome; the
  /// read carries no active/attention status, so those filters render the
  /// approved empty state instead of an invented record.
  bool _matchesFilter(SaleHistoryEntryView entry) => switch (_filter) {
    _ApprovedDealHistoryFilter.all => true,
    _ApprovedDealHistoryFilter.completed => true,
    _ApprovedDealHistoryFilter.attention => false,
  };

  Future<void> _toggleDetail(SaleHistoryEntryView entry) async {
    if (_expandedId == entry.id) {
      setState(() {
        _expandedId = null;
        _detail = null;
        _detailError = null;
      });
      return;
    }
    setState(() {
      _expandedId = entry.id;
      _detail = null;
      _detailError = null;
      _detailBusy = true;
    });
    await _loadDetail(entry);
  }

  Future<void> _loadDetail(SaleHistoryEntryView entry) async {
    final load = widget.loadDetail;
    if (load == null) {
      if (mounted && _expandedId == entry.id) {
        setState(() {
          _detailBusy = false;
          _detailError = 'Deal details are not connected in this build.';
        });
      }
      return;
    }
    try {
      final value = await load(entry.id);
      if (!mounted || _expandedId != entry.id) return;
      setState(() {
        _detail = value;
        _detailBusy = false;
      });
    } catch (_) {
      if (!mounted || _expandedId != entry.id) return;
      setState(() {
        _detailBusy = false;
        _detailError = 'Deal details could not be loaded. Please retry.';
      });
    }
  }

  static String _money(String currency, int minor) {
    final symbol = currency == 'USD' ? '\$' : '$currency ';
    return '$symbol${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  }

  static String _date(DateTime value) {
    final date = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'} ${date.timeZoneName}';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final visible = _entries.where(_matchesFilter).toList(growable: false);
    return Column(
      key: const ValueKey('approved-deal-history-real-sections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy && _entries.isEmpty)
          const BuyerProgressStrip(label: 'Loading your history…'),
        if (_error != null) ...[
          BuyerStateNotice(
            key: const ValueKey('approved-history-error'),
            icon: Icons.cloud_off_rounded,
            tone: BuyerNoticeTone.error,
            title: 'Deal history is unavailable',
            body: _error,
            actionLabel: 'Retry',
            onAction: () => unawaited(_load()),
          ),
          SizedBox(height: metrics.spacing(12)),
        ],
        _ApprovedHistoryMetrics(
          completed: _summary?.completed,
          active: _summary?.active,
          attention: _summary?.attention,
          unavailableNote: _summary != null
              ? null
              : 'Live deal counts are not available from this read yet; the '
                    'records below are the server history.',
        ),
        SizedBox(height: metrics.spacing(14)),
        _ApprovedDealHistoryFilters(
          selected: _filter,
          onChanged: (value) => setState(() => _filter = value),
        ),
        SizedBox(height: metrics.spacing(14)),
        Row(
          children: [
            Expanded(
              child: Text(
                _filter == _ApprovedDealHistoryFilter.all
                    ? 'Completed purchases'
                    : _filter.label,
                style: _text(
                  context,
                  size: 16,
                  weight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ),
            Text(
              '${visible.length} loaded',
              style: _text(context, size: 10.5, color: _muted),
            ),
          ],
        ),
        SizedBox(height: metrics.geometry(8)),
        if (!_busy && _error == null && visible.isEmpty)
          _ApprovedDealHistoryEmptyState(
            message: _entries.isEmpty
                ? 'No confirmed purchases yet'
                : 'No deals match this filter',
            detail: _entries.isEmpty
                ? 'Completed Hocalist purchases will appear here.'
                : null,
          )
        else
          for (var index = 0; index < visible.length; index++) ...[
            _ApprovedHistoryRealCard(
              entry: visible[index],
              expanded: _expandedId == visible[index].id,
              onTap: () => unawaited(_toggleDetail(visible[index])),
            ),
            if (_expandedId == visible[index].id) ...[
              SizedBox(height: metrics.spacing(8)),
              _detailSection(visible[index], metrics),
            ],
            if (index != visible.length - 1)
              SizedBox(height: metrics.spacing(9)),
          ],
        if (_more && _entries.isNotEmpty) ...[
          SizedBox(height: metrics.spacing(12)),
          BuyerSecondaryButton(
            key: const ValueKey('approved-history-load-more'),
            label: 'Load more',
            onPressed: _busy ? null : () => unawaited(_load()),
          ),
        ],
        SizedBox(height: metrics.spacing(8)),
        BuyerSecondaryButton(
          key: const ValueKey('approved-history-refresh'),
          label: 'Refresh history',
          onPressed: _busy ? null : () => unawaited(_load(refresh: true)),
        ),
      ],
    );
  }

  Widget _detailSection(
    SaleHistoryEntryView entry,
    ApprovedReplicaMetrics metrics,
  ) {
    if (_detailBusy) {
      return const _ApprovedDetailSurface(
        child: BuyerProgressStrip(label: 'Loading deal details…'),
      );
    }
    if (_detailError != null) {
      return _ApprovedDetailSurface(
        child: BuyerStateNotice(
          key: ValueKey('approved-history-detail-error-${entry.id}'),
          icon: Icons.error_outline_rounded,
          tone: BuyerNoticeTone.error,
          title: 'Deal details are unavailable',
          body: _detailError,
          actionLabel: 'Retry details',
          onAction: () => unawaited(_loadDetail(entry)),
        ),
      );
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ApprovedHistoryRealSummary(detail: detail),
        SizedBox(height: metrics.spacing(10)),
        _ApprovedHistoryRealFacts(detail: detail),
        SizedBox(height: metrics.spacing(10)),
        const _ApprovedLifecyclePinNotice(
          title: 'Purchase confirmed',
          body:
              'Hocalist recorded the confirmed outcome for this deal. The '
              'purchase PIN itself is not stored in this history.',
          completed: true,
        ),
        SizedBox(height: metrics.spacing(10)),
        Container(
          padding: metrics.geometryInsets(const EdgeInsets.all(13)),
          decoration: BoxDecoration(
            color: const Color(0xffeef9f2),
            borderRadius: BorderRadius.circular(metrics.geometry(14)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BuyerAssetIcon(
                asset: 'assets/approved_offers_chat/chat-deal-shield.png',
                slotSize: 30,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Hocalist records the deal and rewards only. The '
                  '${_money(detail.currency, detail.priceMinor)} item payment '
                  'was arranged directly with the seller and was not processed '
                  'or verified by Hocalist.',
                  style: _text(context, size: 11, color: _muted, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        if (widget.supportReviewRequested) ...[
          SizedBox(height: metrics.spacing(10)),
          const _ApprovedHistorySupportNotice(),
        ],
        SizedBox(height: metrics.spacing(16)),
        if (widget.onReview != null && detail.side == SaleSide.purchase) ...[
          BuyerPrimaryButton(
            key: const ValueKey('approved-deal-history-review'),
            label: 'Review seller',
            onPressed: () => widget.onReview!(detail),
          ),
          SizedBox(height: metrics.spacing(10)),
        ],
        BuyerSecondaryButton(
          key: const ValueKey('approved-deal-history-support'),
          label: widget.supportReviewRequested
              ? 'Support review requested'
              : 'Ask support to review this deal',
          onPressed: widget.supportReviewRequested ? null : widget.onSupport,
          fontSize: 12.5,
        ),
      ],
    );
  }
}

class _ApprovedHistoryRealCard extends StatelessWidget {
  const _ApprovedHistoryRealCard({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final SaleHistoryEntryView entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        key: ValueKey('approved-deal-history-record-${entry.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: HocalistPalette.border(context, expanded ? _blue : _line),
              width: expanded ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 58,
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, _lavender),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: BuyerGlyphIcon(
                    icon: Icons.devices_other_outlined,
                    slotSize: 30,
                    color: HocalistPalette.text(context, _blue),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              context,
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _ApprovedDealHistoryBadge(
                          status: _ApprovedDealHistoryStatus.completed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.side == SaleSide.purchase
                          ? 'Confirmed offline purchase'
                          : 'Confirmed offline sale',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(context, size: 10.5, color: _muted),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _ApprovedBuyerDealHistoryRealSectionsState._date(
                              entry.confirmedAt,
                            ),
                            maxLines: 2,
                            style: _text(context, size: 9.5, color: _muted),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _ApprovedBuyerDealHistoryRealSectionsState._money(
                            entry.currency,
                            entry.priceMinor,
                          ),
                          style: _text(
                            context,
                            size: 13,
                            weight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                        const SizedBox(width: 2),
                        BuyerGlyphIcon(
                          icon: expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.chevron_right_rounded,
                          slotSize: 20,
                          glyphSize: 20,
                          color: HocalistPalette.text(context, _blue),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovedHistoryRealSummary extends StatelessWidget {
  const _ApprovedHistoryRealSummary({required this.detail});

  final SaleDetailView detail;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedDetailSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 66,
            height: 76,
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xfff6f5ff)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: BuyerGlyphIcon(
                icon: Icons.devices_other_outlined,
                slotSize: 34,
                color: HocalistPalette.text(context, _blue),
              ),
            ),
          ),
          SizedBox(width: metrics.geometry(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    context,
                    size: 13,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.geometry(3)),
                Text(
                  '${detail.side == SaleSide.purchase ? 'Purchase' : 'Sale'}'
                  ' • Confirmed '
                  '${_ApprovedBuyerDealHistoryRealSectionsState._date(detail.confirmedAt)}',
                  style: _text(context, size: 10.5, color: _muted),
                ),
                SizedBox(height: metrics.geometry(5)),
                Text(
                  _ApprovedBuyerDealHistoryRealSectionsState._money(
                    detail.currency,
                    detail.priceMinor,
                  ),
                  style: _text(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: _blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const _ApprovedDealHistoryBadge(
            status: _ApprovedDealHistoryStatus.completed,
          ),
        ],
      ),
    );
  }
}

class _ApprovedHistoryRealFacts extends StatelessWidget {
  const _ApprovedHistoryRealFacts({required this.detail});

  final SaleDetailView detail;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'chat-location.png',
                  label: 'Pickup location',
                  value: detail.schedule.placeLabel ?? 'Not specified',
                ),
              ),
              const _ApprovedLifecycleFactDivider(),
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'chat-time.png',
                  label: 'Meet date',
                  value: '${detail.schedule.date}'.split(' ').first,
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: _line),
          Row(
            children: [
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'chat-time.png',
                  label: 'Meet time',
                  value:
                      '${detail.schedule.time} • ${detail.schedule.timezone}',
                ),
              ),
              const _ApprovedLifecycleFactDivider(),
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'detail-star.png',
                  label: 'Item payment',
                  value: 'Offline',
                  valueColor: _green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ApprovedBuyerReviewPage extends StatefulWidget {
  const ApprovedBuyerReviewPage({
    required this.onBack,
    required this.navigation,
    required this.onFinish,
    this.backend,
    this.requestId,
    this.sellerName,
    this.purchase,
    this.chatEnabled = false,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onFinish;

  /// Configured review backend. Null keeps the prototype presentation.
  final ReviewBackend? backend;

  /// Confirmed-purchase request under review. Required in configured mode.
  final String? requestId;
  final String? sellerName;
  final SaleDetailView? purchase;

  /// Reserved for the communications package: a review-based chat entry opens
  /// only through the authorized conversation boundary.
  final bool chatEnabled;

  @override
  State<ApprovedBuyerReviewPage> createState() =>
      _ApprovedBuyerReviewPageState();
}

class _ApprovedBuyerReviewPageState extends State<ApprovedBuyerReviewPage> {
  int _rating = 0;
  final TextEditingController _bodyController = TextEditingController();
  ReviewEligibilityView? _eligibility;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  bool _outcomeUncertain = false;
  String? _operationKey;
  bool _submitted = false;
  int? _lastAttemptRating;
  String? _lastAttemptBody;

  bool get _configured => widget.backend != null && widget.requestId != null;

  @override
  void initState() {
    super.initState();
    if (_configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadEligibility());
      });
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadEligibility() async {
    final backend = widget.backend;
    final requestId = widget.requestId;
    if (backend == null || requestId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final eligibility = await backend.loadEligibility(requestId);
      if (!mounted) return;
      setState(() {
        _eligibility = eligibility;
        final review = eligibility.review;
        if (review != null) {
          _rating = review.rating;
          _bodyController.text = review.body;
          _submitted = true;
        }
      });
    } on StoreBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _outcomeUncertain = error.ambiguous;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating < 1 || _rating > 5) {
      setState(
        () => _error = 'Choose a star rating before submitting your review.',
      );
      return;
    }
    final backend = widget.backend;
    final requestId = widget.requestId;
    if (backend == null || requestId == null) {
      widget.onFinish();
      return;
    }
    final review = _eligibility?.review;
    final body = _bodyController.text.trim();
    // An unchanged payload keeps the same intent key so an uncertain retry
    // cannot create a duplicate review; a changed payload starts a new intent.
    final unchangedIntent =
        _operationKey != null &&
        _lastAttemptRating == _rating &&
        _lastAttemptBody == body;
    if (!unchangedIntent) {
      _operationKey = LocalMarketplaceRepository.newStoreOperationKey('review');
    }
    final key = _operationKey!;
    _lastAttemptRating = _rating;
    _lastAttemptBody = body;
    setState(() {
      _submitting = true;
      _error = null;
      _outcomeUncertain = false;
    });
    try {
      final OutcomeReview saved;
      if (review == null) {
        saved = await backend.submitReview(
          SubmitReviewCommand(
            requestId: requestId,
            rating: _rating,
            body: body,
            idempotencyKey: key,
          ),
        );
      } else {
        saved = await backend.updateReview(
          UpdateReviewCommand(
            reviewId: review.id,
            expectedRevision: review.revision,
            rating: _rating,
            body: body,
            idempotencyKey: key,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _eligibility = ReviewEligibilityView(
          requestId: requestId,
          eligible: true,
          reason: 'confirmed_purchase',
          outcomeId: _eligibility?.outcomeId,
          review: saved,
        );
      });
      widget.onFinish();
    } on StoreBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _outcomeUncertain = error.ambiguous;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_configured) return _buildConfigured(context);
    return _buildPrototype(context);
  }

  Widget _buildConfigured(BuildContext context) {
    final eligibility = _eligibility;
    final eligible = eligibility?.eligible ?? false;
    final review = eligibility?.review;
    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-review-page'),
      navigation: widget.navigation,
      selected: ApprovedBuyerNavSelection.home,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Review seller',
            subtitle: widget.sellerName == null
                ? 'Rate your confirmed purchase experience.'
                : 'Rate your purchase from ${widget.sellerName}.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: 16),
          _ApprovedDetailSurface(
            child: Row(
              children: [
                BuyerGlyphIcon(
                  icon: Icons.receipt_long_outlined,
                  slotSize: BuyerIconTokens.feature,
                  color: HocalistPalette.text(context, _blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.purchase?.title ??
                            'Purchase details unavailable',
                        style: _text(
                          context,
                          size: 14,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      if (widget.purchase case final purchase?)
                        Text(
                          _ApprovedBuyerDealHistoryRealSectionsState._money(
                            purchase.currency,
                            purchase.priceMinor,
                          ),
                          style: _text(
                            context,
                            size: 18,
                            color: _blue,
                            weight: FontWeight.w800,
                          ),
                        ),
                      Text(
                        _loading
                            ? 'Checking confirmed purchase…'
                            : eligible
                            ? 'Purchase confirmed'
                            : 'Purchase verification required',
                        style: _text(context, size: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && !eligible)
            _ApprovedDetailSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: _text(context, size: 12.5, color: _navy),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('approved-review-retry'),
                    onPressed: _loadEligibility,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (!eligible)
            _ApprovedDetailSurface(
              child: Text(
                eligibility?.reason == 'not_confirmed'
                    ? 'A review is available after a confirmed purchase for '
                          'this request.'
                    : 'You cannot review this purchase from this account.',
                style: _text(context, size: 12.5, color: _navy, height: 1.4),
              ),
            )
          else ...[
            _ApprovedDetailSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review == null
                        ? 'How was your experience?'
                        : 'Your published review',
                    style: _text(
                      context,
                      size: 14,
                      weight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(5, (index) {
                      final selected = index < _rating;
                      return IconButton(
                        key: ValueKey('approved-review-star-$index'),
                        tooltip: '${index + 1} stars',
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _rating = index + 1),
                        icon: BuyerAssetIcon(
                          asset: 'assets/approved_offers_chat/detail-star.png',
                          slotSize: BuyerIconTokens.card,
                          color: HocalistPalette.textOrNull(
                            context,
                            selected ? null : const Color(0xffc9cbe0),
                          ),
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  const BuyerFieldLabel('Your review'),
                  const SizedBox(height: 5),
                  TextField(
                    key: const ValueKey('approved-review-body'),
                    controller: _bodyController,
                    minLines: 3,
                    maxLines: 5,
                    enabled: !_submitting,
                    decoration: buyerInputDecoration(
                      context,
                      hintText: 'Share what future buyers should know.',
                    ),
                  ),
                  if (review != null && review.moderationReason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Moderation note: ${review.moderationReason}',
                      style: _text(
                        context,
                        size: 11,
                        color: _navy,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _outcomeUncertain
                    ? '$_error Retry to check safely; the same submission '
                          'will not create a duplicate.'
                    : _error!,
                style: TextStyle(
                  color: HocalistPalette.text(
                    context,
                    Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            BuyerPrimaryButton(
              key: const ValueKey('approved-submit-review'),
              label: _submitting
                  ? 'Saving…'
                  : review == null
                  ? 'Submit review'
                  : 'Update review',
              onPressed: _submitting || _rating == 0 ? null : _submit,
            ),
            if (_submitted) ...[
              const SizedBox(height: 8),
              Text(
                'Review saved. Thank you for helping future buyers.',
                style: _text(context, size: 11.5, color: _green),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPrototype(BuildContext context) {
    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-review-page'),
      navigation: widget.navigation,
      selected: ApprovedBuyerNavSelection.home,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Review seller',
            subtitle: 'Help future buyers understand this seller experience.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: 16),
          const _ApprovedLifecycleDealSummary(
            status: 'Deal completed',
            statusColor: _green,
          ),
          const SizedBox(height: 12),
          _ApprovedDetailSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How was your experience?',
                  style: _text(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(5, (index) {
                    final selected = index < _rating;
                    return IconButton(
                      key: ValueKey('approved-review-star-$index'),
                      tooltip: '${index + 1} stars',
                      onPressed: () => setState(() => _rating = index + 1),
                      icon: BuyerAssetIcon(
                        asset: 'assets/approved_offers_chat/detail-star.png',
                        slotSize: BuyerIconTokens.card,
                        color: HocalistPalette.textOrNull(
                          context,
                          selected ? null : const Color(0xffc9cbe0),
                        ),
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                const BuyerFieldLabel('Your review'),
                const SizedBox(height: 5),
                TextFormField(
                  initialValue:
                      'Clear photos, fair price, and an easy public pickup.',
                  minLines: 3,
                  maxLines: 5,
                  decoration: buyerInputDecoration(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BuyerPrimaryButton(
            key: const ValueKey('approved-submit-review'),
            label: 'Submit review',
            onPressed: widget.onFinish,
          ),
        ],
      ),
    );
  }
}

class ApprovedBuyerDealRecoveryPage extends StatelessWidget {
  const ApprovedBuyerDealRecoveryPage({
    required this.onBack,
    required this.navigation,
    required this.onReopen,
    required this.onBackup,
    required this.onReport,
    this.actionBusy = false,
    this.actionError,
    this.actionUncertain = false,
    this.onDiscard,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onReopen;
  final VoidCallback onBackup;
  final VoidCallback onReport;

  /// True while a reopen/backup server command is in flight; actions stay
  /// disabled so a second unknown outcome cannot start.
  final bool actionBusy;

  /// User-safe failure from the last reopen/backup command.
  final String? actionError;

  /// True when the last reopen outcome is unknown and the intent is retained.
  final bool actionUncertain;

  /// Abandons the retained reopen intent before changing anything.
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return _ApprovedBuyerLifecycleScaffold(
      pageKey: const ValueKey('approved-buyer-deal-recovery-page'),
      navigation: navigation,
      selected: ApprovedBuyerNavSelection.home,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedDetailHeading(
            title: 'Deal did not happen',
            subtitle:
                'Keep your request moving if the seller or meetup did not work out.',
            onBack: onBack,
          ),
          const SizedBox(height: 16),
          const _ApprovedLifecycleDealSummary(
            status: 'Needs action',
            statusColor: Color(0xffb35b00),
          ),
          const SizedBox(height: 12),
          _ApprovedLifecycleAction(
            asset: 'offers-envelope.png',
            title: 'Compare backup offers',
            body: 'Return to sellers whose offers are still valid.',
            accent: _blue,
            onTap: actionBusy ? null : onBackup,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            asset: 'detail-description.png',
            title: 'Reopen this request',
            body: 'Let sellers respond again without rebuilding the request.',
            accent: _blue,
            onTap: actionBusy ? null : onReopen,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            asset: 'chat-safety.png',
            title: 'Report a safety issue',
            body: 'Use this for unsafe behavior, fraud, or a serious concern.',
            accent: const Color(0xffc62828),
            onTap: onReport,
          ),
          if (actionBusy) ...[
            const SizedBox(height: 10),
            Text(
              'Sending the request…',
              key: const ValueKey('approved-recovery-busy'),
              style: _text(context, size: 11.5, color: _muted),
            ),
          ],
          if (actionError != null) ...[
            const SizedBox(height: 10),
            Text(
              actionError!,
              key: const ValueKey('approved-recovery-error'),
              style: TextStyle(
                color: HocalistPalette.text(
                  context,
                  Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            if (actionUncertain && onDiscard != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('approved-recovery-discard'),
                  onPressed: onDiscard,
                  child: const Text('Discard attempt'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedBuyerLifecycleScaffold extends StatelessWidget {
  const _ApprovedBuyerLifecycleScaffold({
    required this.pageKey,
    required this.navigation,
    required this.selected,
    required this.child,
  });

  final Key pageKey;
  final ApprovedBuyerNavigation navigation;
  final ApprovedBuyerNavSelection selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Material(
        key: pageKey,
        color: HocalistPalette.surface(context, const Color(0xfffafbff)),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: metrics.geometryInsets(
                    const EdgeInsets.fromLTRB(16, 10, 16, 22),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: metrics.innerContentMaxWidth(
                          referenceHorizontalInset: 16,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
              BuyerBottomNavigation(
                selected: selected,
                accentColor: _blue,
                callbacks: navigation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ApprovedDealHistoryStatus {
  confirmed,
  completed,
  attention,
  reopened,
  cancelled;

  String get label => switch (this) {
    confirmed => 'Meeting confirmed',
    completed => 'Completed',
    attention => 'Needs attention',
    reopened => 'Request reopened',
    cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    completed => _green,
    attention || reopened => const Color(0xffb35b00),
    cancelled => _muted,
    confirmed => _blue,
  };

  bool get isCompleted => this == completed;
  bool get isActive => this == confirmed;
  bool get needsAttention => this == attention || this == reopened;
}

enum _ApprovedDealHistoryFilter {
  all('All'),
  completed('Completed'),
  attention('Needs attention');

  const _ApprovedDealHistoryFilter(this.label);
  final String label;

  bool includes(_ApprovedDealHistoryStatus status) => switch (this) {
    all => true,
    completed => status.isCompleted,
    attention => status.needsAttention,
  };
}

class _ApprovedDealHistoryRecord {
  const _ApprovedDealHistoryRecord({
    required this.id,
    required this.item,
    required this.seller,
    required this.price,
    required this.date,
    required this.location,
    required this.reward,
    required this.status,
    required this.productAsset,
    this.supportReviewRequested = false,
  });

  final String id;
  final String item;
  final String seller;
  final String price;
  final String date;
  final String location;
  final String reward;
  final _ApprovedDealHistoryStatus status;
  final String productAsset;
  final bool supportReviewRequested;
}

const _approvedDefaultDealRecord = _ApprovedDealHistoryRecord(
  id: 'default-ipad-deal',
  item: 'iPad Air 5th Gen 64GB',
  seller: 'Northside Tech',
  price: '\$650',
  date: 'May 17, 2025 • 2:00 PM',
  location: 'Yonkers, NY',
  reward: '\$1.40',
  status: _ApprovedDealHistoryStatus.confirmed,
  productAsset: 'assets/approved_offers_chat/chat-ipad.png',
);

class _ApprovedDealHistoryFilters extends StatelessWidget {
  const _ApprovedDealHistoryFilters({
    required this.selected,
    required this.onChanged,
  });

  final _ApprovedDealHistoryFilter selected;
  final ValueChanged<_ApprovedDealHistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final filter in _ApprovedDealHistoryFilter.values)
          ChoiceChip(
            key: ValueKey('approved-deal-history-filter-${filter.name}'),
            label: Text(filter.label),
            selected: filter == selected,
            onSelected: (_) => onChanged(filter),
            showCheckmark: false,
            labelStyle: _text(
              context,
              size: 10.5,
              weight: FontWeight.w700,
              color: filter == selected ? Colors.white : _navy,
            ),
            selectedColor: _blue,
            backgroundColor: HocalistPalette.surface(context, Colors.white),
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                filter == selected ? _blue : _line,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(99),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _ApprovedDealHistoryCard extends StatelessWidget {
  const _ApprovedDealHistoryCard({required this.record, required this.onTap});

  final _ApprovedDealHistoryRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        key: ValueKey('approved-deal-history-record-${record.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: HocalistPalette.border(context, _line)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 58,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, _lavender),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Image.asset(
                  record.productAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => BuyerGlyphIcon(
                    icon: Icons.devices_other_outlined,
                    slotSize: 30,
                    color: HocalistPalette.text(context, _blue),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            record.item,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              context,
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ApprovedDealHistoryBadge(status: record.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(context, size: 10.5, color: _muted),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.date,
                            maxLines: 2,
                            style: _text(context, size: 9.5, color: _muted),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          record.price,
                          style: _text(
                            context,
                            size: 13,
                            weight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                        const SizedBox(width: 2),
                        BuyerGlyphIcon(
                          icon: Icons.chevron_right_rounded,
                          slotSize: 20,
                          glyphSize: 20,
                          color: HocalistPalette.text(context, _blue),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovedDealHistoryBadge extends StatelessWidget {
  const _ApprovedDealHistoryBadge({required this.status});
  final _ApprovedDealHistoryStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(
          context,
          status.color.withValues(alpha: .1),
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _text(
          context,
          size: 8.5,
          weight: FontWeight.w800,
          color: status.color,
        ),
      ),
    );
  }
}

class _ApprovedDealHistoryEmptyState extends StatelessWidget {
  const _ApprovedDealHistoryEmptyState({
    this.message = 'No deals match this filter',
    this.detail,
  });

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailSurface(
      child: Column(
        children: [
          BuyerGlyphIcon(
            icon: Icons.history_rounded,
            slotSize: BuyerIconTokens.feature,
            color: HocalistPalette.text(context, _blue),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: _text(
              context,
              size: 12.5,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: _text(context, size: 10.5, color: _muted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedLifecycleDealSummary extends StatelessWidget {
  const _ApprovedLifecycleDealSummary({
    this.record = _approvedDefaultDealRecord,
    this.status,
    this.statusColor,
  });

  final _ApprovedDealHistoryRecord record;
  final String? status;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = status ?? record.status.label;
    final effectiveStatusColor = statusColor ?? record.status.color;
    return _ApprovedDetailSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 66,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xfff6f5ff)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              record.productAsset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.item,
                  style: _text(
                    context,
                    size: 14.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.seller} • Verified seller',
                  style: _text(context, size: 10.5, color: _muted),
                ),
                const SizedBox(height: 5),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final reflow =
                        constraints.maxWidth < 185 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                    final price = Text(
                      record.price,
                      style: _text(
                        context,
                        size: 19,
                        weight: FontWeight.w800,
                        color: _blue,
                      ),
                    );
                    final badge = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: HocalistPalette.surface(
                          context,
                          effectiveStatusColor.withValues(alpha: .11),
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        effectiveStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          context,
                          size: 9.5,
                          weight: FontWeight.w800,
                          color: effectiveStatusColor,
                        ),
                      ),
                    );
                    if (reflow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          price,
                          const SizedBox(height: 4),
                          Align(alignment: Alignment.centerLeft, child: badge),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        price,
                        const Spacer(),
                        Flexible(child: badge),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedLifecycleFacts extends StatelessWidget {
  const _ApprovedLifecycleFacts({this.record = _approvedDefaultDealRecord});

  final _ApprovedDealHistoryRecord record;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'chat-location.png',
                  label: 'Pickup location',
                  value: record.location,
                ),
              ),
              const _ApprovedLifecycleFactDivider(),
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'chat-time.png',
                  label: 'Meet date',
                  value: record.date,
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: _line),
          Row(
            children: [
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'detail-star.png',
                  label: record.status.isCompleted
                      ? 'Reward credited'
                      : 'Estimated reward',
                  value: record.reward,
                  valueColor: _green,
                ),
              ),
              const _ApprovedLifecycleFactDivider(),
              Expanded(
                child: _ApprovedLifecycleFact(
                  asset: 'detail-pin.png',
                  label: 'Meetup verification',
                  value: record.status.isCompleted
                      ? 'PIN verified'
                      : 'PIN pending',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedLifecycleFactDivider extends StatelessWidget {
  const _ApprovedLifecycleFactDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 42,
      child: VerticalDivider(width: 12, color: _line),
    );
  }
}

class _ApprovedLifecycleFact extends StatelessWidget {
  const _ApprovedLifecycleFact({
    required this.asset,
    required this.label,
    required this.value,
    this.valueColor = _navy,
  });

  final String asset;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BuyerAssetIcon(
          asset: 'assets/approved_offers_chat/$asset',
          slotSize: 26,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _text(context, size: 9.5, color: _muted)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                style: _text(
                  context,
                  size: 10.5,
                  weight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApprovedLifecyclePinNotice extends StatelessWidget {
  const _ApprovedLifecyclePinNotice({
    required this.title,
    required this.body,
    this.completed = false,
  });

  final String title;
  final String body;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(
          context,
          completed ? const Color(0xffeef9f2) : _lavender,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HocalistPalette.border(
            context,
            completed ? const Color(0xffcdebd7) : _line,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerAssetIcon(
            asset: 'assets/approved_offers_chat/detail-pin.png',
            slotSize: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _text(
                    context,
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: _text(
                    context,
                    size: 10.5,
                    color: _muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedLifecycleAction extends StatelessWidget {
  const _ApprovedLifecycleAction({
    required this.asset,
    required this.title,
    required this.body,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final String asset;
  final String title;
  final String body;
  final Color accent;

  /// Null renders the action disabled (for example while a server command is
  /// in flight) without changing the approved layout.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: HocalistPalette.border(context, _line)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              BuyerAssetIconSurface(
                asset: 'assets/approved_offers_chat/$asset',
                surfaceSize: 42,
                iconSize: 26,
                backgroundColor: HocalistPalette.surface(
                  context,
                  accent.withValues(alpha: .1),
                ),
                shape: BuyerIconSurfaceShape.circle,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _text(
                        context,
                        size: 13,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: _text(
                        context,
                        size: 10.5,
                        color: _muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              BuyerGlyphIcon(
                icon: Icons.chevron_right_rounded,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: HocalistPalette.text(context, _blue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovedHistoryMetrics extends StatelessWidget {
  const _ApprovedHistoryMetrics({
    required this.completed,
    required this.active,
    required this.attention,
    this.unavailableNote,
  });

  /// Null renders the designed unavailable placeholder instead of a count.
  final int? completed;
  final int? active;
  final int? attention;
  final String? unavailableNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ApprovedHistoryMetric(
                value: active == null ? '—' : '$active',
                label: 'Active',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ApprovedHistoryMetric(
                value: completed == null ? '—' : '$completed',
                label: 'Completed',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ApprovedHistoryMetric(
                value: attention == null ? '—' : '$attention',
                label: 'Needs attention',
              ),
            ),
          ],
        ),
        if (unavailableNote != null) ...[
          const SizedBox(height: 8),
          Text(
            unavailableNote!,
            key: const ValueKey('approved-history-counts-unavailable'),
            textAlign: TextAlign.center,
            style: _text(context, size: 10.5, color: _muted, height: 1.35),
          ),
        ],
      ],
    );
  }
}

class _ApprovedHistoryMetric extends StatelessWidget {
  const _ApprovedHistoryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: _text(
              context,
              size: 22,
              weight: FontWeight.w800,
              color: _blue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: _text(context, size: 9.5, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _ApprovedHistorySupportNotice extends StatelessWidget {
  const _ApprovedHistorySupportNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfffff7e8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Support review requested. Your local deal record remains available while support tools are connected.',
        style: _text(context, size: 10.5, color: _muted, height: 1.35),
      ),
    );
  }
}

class _ApprovedDetailHeading extends StatelessWidget {
  const _ApprovedDetailHeading({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return BuyerNestedHeader(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      backKey: ValueKey(
        'approved-${title.toLowerCase().replaceAll(' ', '-')}-back',
      ),
    );
  }
}

class _ApprovedDetailSurface extends StatelessWidget {
  const _ApprovedDetailSurface({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      padding: metrics.geometryInsets(padding),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        borderRadius: BorderRadius.circular(metrics.geometry(16)),
        border: Border.all(color: HocalistPalette.border(context, _line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0c00036c),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ApprovedRewardMetric extends StatelessWidget {
  const _ApprovedRewardMetric({
    required this.asset,
    required this.label,
    required this.value,
    this.note,
    this.valueKey,
  });

  final String asset;
  final String label;
  final String value;

  /// Designed unavailable note (for example when a policy is not configured).
  final String? note;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedDetailSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerAssetIcon(
            asset: '$_approvedAssetRoot/$asset',
            slotSize: metrics.artSize(40),
          ),
          SizedBox(height: metrics.geometry(8)),
          Text(
            value,
            key: valueKey,
            style: _text(
              context,
              size: 20,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(3)),
          Text(label, style: _text(context, size: 11, color: _muted)),
          if (note != null) ...[
            SizedBox(height: metrics.geometry(3)),
            Text(
              note!,
              style: _text(
                context,
                size: 9.5,
                weight: FontWeight.w700,
                color: const Color(0xffb35b00),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedRewardActivityRow extends StatelessWidget {
  const _ApprovedRewardActivityRow({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.value,
    this.valueColor = _green,
  });

  final String asset;
  final String title;
  final String subtitle;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Padding(
      padding: metrics.geometryInsets(const EdgeInsets.symmetric(vertical: 12)),
      child: Row(
        children: [
          BuyerAssetIcon(
            asset: '$_approvedAssetRoot/$asset',
            slotSize: metrics.artSize(42),
          ),
          SizedBox(width: metrics.geometry(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _text(
                    context,
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.geometry(2)),
                Text(
                  subtitle,
                  style: _text(context, size: 10.5, color: _muted),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: _text(
              context,
              size: 12,
              weight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedMeetingField extends StatelessWidget {
  const _ApprovedMeetingField({
    required this.asset,
    required this.label,
    required this.initialValue,
    this.maxLines = 1,
    this.readOnly = false,
    super.key,
  });

  final String asset;
  final String label;
  final String initialValue;
  final int maxLines;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuyerFieldLabel(label),
        SizedBox(height: metrics.spacing(5)),
        Semantics(
          label: label,
          textField: true,
          readOnly: readOnly,
          child: TextFormField(
            key: ValueKey(initialValue),
            readOnly: readOnly,
            initialValue: initialValue,
            maxLines: maxLines,
            style: _text(context, size: 12.5, color: _navy),
            decoration: buyerInputDecoration(
              context,
              prefixIcon: Padding(
                padding: metrics.geometryInsets(const EdgeInsets.all(12)),
                child: BuyerAssetIcon(
                  asset: 'assets/approved_offers_chat/$asset',
                  slotSize: metrics.artSize(24),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovedDashboardHero extends StatelessWidget {
  const _ApprovedDashboardHero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = metrics.usesStackedLayout;
        final copy = Column(
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Good morning! 👋' : 'Good morning, $name! 👋',
              textAlign: stacked ? TextAlign.center : TextAlign.left,
              style: _text(
                context,
                size: 18,
                weight: FontWeight.w800,
                color: _navy,
                height: 1.15,
              ),
            ),
            SizedBox(height: metrics.geometry(4)),
            Text(
              'You\'re earning rewards while sellers compete for your business.',
              textAlign: stacked ? TextAlign.center : TextAlign.left,
              style: _text(context, size: 11.5, color: _muted, height: 1.3),
            ),
          ],
        );
        final art = Image.asset(
          '$_approvedAssetRoot/dashboard-gift.png',
          width: metrics.geometry(90),
          height: metrics.geometry(70),
          fit: BoxFit.contain,
        );
        if (stacked) {
          return Column(
            children: [
              copy,
              SizedBox(height: metrics.geometry(8)),
              art,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            SizedBox(width: metrics.geometry(8)),
            art,
          ],
        );
      },
    );
  }
}

class _ApprovedRealRewardCards extends StatefulWidget {
  const _ApprovedRealRewardCards({required this.load, required this.onTap});

  final Future<Map<String, dynamic>> Function() load;
  final VoidCallback onTap;

  @override
  State<_ApprovedRealRewardCards> createState() =>
      _ApprovedRealRewardCardsState();
}

class _ApprovedRealRewardCardsState extends State<_ApprovedRealRewardCards> {
  late Future<Map<String, dynamic>> _result;

  @override
  void initState() {
    super.initState();
    _result = widget.load();
  }

  @override
  void didUpdateWidget(covariant _ApprovedRealRewardCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) _result = widget.load();
  }

  String _usd(int minor) =>
      '\$${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _result,
    builder: (context, snapshot) {
      int? earned;
      int? held;
      final data = snapshot.data;
      if (data != null &&
          data['currency'] == 'USD' &&
          data['earned_minor'] is int &&
          (data['earned_minor'] as int) >= 0 &&
          data['items'] is List) {
        var valid = true;
        var heldTotal = 0;
        for (final item in data['items'] as List) {
          if (item is! Map ||
              item['amount_minor'] is! int ||
              (item['amount_minor'] as int) <= 0 ||
              !['earned', 'held'].contains(item['status'])) {
            valid = false;
            break;
          }
          if (item['status'] == 'held') {
            heldTotal += item['amount_minor'] as int;
          }
        }
        if (valid) {
          earned = data['earned_minor'] as int;
          held = heldTotal;
        }
      }
      final loading = snapshot.connectionState != ConnectionState.done;
      final metrics = _replicaMetrics(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final stacked = metrics.accessibilityReflow;
          final cards = [
            _ApprovedRewardCard(
              onTap: widget.onTap,
              alignActionToBottom: !stacked,
              amount: earned == null ? '—' : _usd(earned),
              detail: loading
                  ? 'Loading rewards…'
                  : earned == null
                  ? 'Rewards unavailable'
                  : 'From confirmed, eligible sales',
            ),
            _ApprovedPendingCard(
              amount: held == null ? '—' : _usd(held),
              detail: loading
                  ? 'Checking reward status…'
                  : held == null
                  ? 'Status unavailable'
                  : 'After fee reversals',
              realMode: true,
            ),
          ];
          if (stacked) {
            return Column(
              children: [
                cards[0],
                SizedBox(height: metrics.geometry(10)),
                cards[1],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              SizedBox(width: metrics.geometry(8)),
              Expanded(child: cards[1]),
            ],
          );
        },
      );
    },
  );
}

class _ApprovedRewardCard extends StatelessWidget {
  const _ApprovedRewardCard({
    required this.onTap,
    required this.alignActionToBottom,
    this.amount = '\$128.45',
    this.detail = 'From 42 completed purchases',
  });

  final VoidCallback onTap;
  final bool alignActionToBottom;
  final String amount;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedDashboardCard(
      key: const ValueKey('approved-total-rewards-card'),
      referenceHeight: 144,
      padding: EdgeInsets.all(metrics.geometry(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total rewards earned  ⓘ',
            style: _text(
              context,
              size: 10.5,
              weight: FontWeight.w700,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(4)),
          LayoutBuilder(
            builder: (context, constraints) {
              final iconSize = metrics.artSize(
                constraints.maxWidth < 180 ? 36 : BuyerIconTokens.feature + 4,
              );
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      amount,
                      style: _text(
                        context,
                        size: 23,
                        weight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                  ),
                  BuyerAssetIcon(
                    asset: '$_approvedAssetRoot/dashboard-trophy.png',
                    slotSize: iconSize,
                  ),
                ],
              );
            },
          ),
          SizedBox(height: metrics.geometry(5)),
          Text(detail, style: _text(context, size: 10.5, color: _muted)),
          SizedBox(height: metrics.geometry(6)),
          if (alignActionToBottom) const Spacer(),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: HocalistPalette.surface(context, _lavender),
              foregroundColor: HocalistPalette.text(context, _blue),
              minimumSize: metrics.geometrySize(const Size(0, 30)),
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(99)),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'View all rewards  ›',
              style: _text(
                context,
                size: 10.5,
                weight: FontWeight.w700,
                color: _blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedPendingCard extends StatelessWidget {
  const _ApprovedPendingCard({
    this.amount = '\$24.80',
    this.detail = 'Pay date: May 20, 2025',
    this.realMode = false,
  });

  final String amount;
  final String detail;
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedDashboardCard(
      key: const ValueKey('approved-pending-rewards-card'),
      referenceHeight: 144,
      padding: metrics.geometryInsets(const EdgeInsets.fromLTRB(10, 10, 10, 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            realMode ? 'Rewards on hold  ⓘ' : 'Pending rewards  ⓘ',
            style: _text(
              context,
              size: 10.5,
              weight: FontWeight.w700,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(3)),
          LayoutBuilder(
            builder: (context, constraints) {
              final iconSize = metrics.artSize(
                constraints.maxWidth < 180 ? 36 : BuyerIconTokens.feature + 4,
              );
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      amount,
                      style: _text(
                        context,
                        size: 23,
                        weight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                  ),
                  BuyerAssetIcon(
                    asset: '$_approvedAssetRoot/dashboard-calendar.png',
                    slotSize: iconSize,
                  ),
                ],
              );
            },
          ),
          SizedBox(height: metrics.geometry(3)),
          Text(detail, style: _text(context, size: 10.5, color: _muted)),
          if (!realMode) ...[
            SizedBox(height: metrics.geometry(4)),
            ClipRRect(
              borderRadius: BorderRadius.circular(metrics.geometry(99)),
              child: LinearProgressIndicator(
                value: .992,
                minHeight: metrics.geometry(6),
                backgroundColor: HocalistPalette.surface(context, _lavender),
                valueColor: AlwaysStoppedAnimation<Color>(_blue),
              ),
            ),
            SizedBox(height: metrics.geometry(2)),
            Text(
              '\$24.80 of \$25.00',
              style: _text(
                context,
                size: 10.5,
                weight: FontWeight.w700,
                color: _navy,
              ),
            ),
            Text(
              '\$0.20 until next payout',
              style: _text(context, size: 10, color: _muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedPostRequest extends StatelessWidget {
  const _ApprovedPostRequest({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Material(
      color: HocalistPalette.surface(context, const Color(0xfffbfaff)),
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        child: Container(
          key: const ValueKey('approved-dashboard-post-request'),
          padding: metrics.geometryInsets(
            const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
            border: Border.all(
              color: HocalistPalette.border(context, const Color(0xffa997ff)),
              width: metrics.geometry(1),
            ),
          ),
          child: Row(
            children: [
              BuyerAssetIcon(
                asset: '$_approvedAssetRoot/dashboard-plus.png',
                slotSize: metrics.artSize(BuyerIconTokens.feature - 2),
              ),
              SizedBox(width: metrics.geometry(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Post a new request',
                      style: _text(
                        context,
                        size: 12.5,
                        weight: FontWeight.w800,
                        color: _blue,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(2)),
                    Text(
                      'Need something else? Post another product or service.',
                      maxLines: metrics.screenshotLocked ? 1 : null,
                      style: _text(context, size: 10, color: _muted),
                    ),
                  ],
                ),
              ),
              Text('›', style: _text(context, size: 23, color: _blue)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact loading/error/empty notice for the real dashboard request list.
class _ApprovedDashboardNotice extends StatelessWidget {
  const _ApprovedDashboardNotice({
    required this.message,
    this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: _text(
              context,
              size: 10.5,
              weight: FontWeight.w700,
              color: _navy,
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(height: metrics.geometry(2)),
            TextButton(
              key: const Key('buyerRequestsRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: Size(0, metrics.geometry(32)),
                padding: EdgeInsets.zero,
                foregroundColor: HocalistPalette.text(context, _blue),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Designed empty card that keeps an approved section's place and card
/// geometry when an authoritative list is genuinely empty.
class _ApprovedEmptySectionCard extends StatelessWidget {
  const _ApprovedEmptySectionCard({
    required this.asset,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String asset;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      padding: EdgeInsets.all(metrics.geometry(12)),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerAssetIcon(
                asset: '$_approvedAssetRoot/$asset',
                slotSize: metrics.artSize(44),
              ),
              SizedBox(width: metrics.geometry(9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _text(
                        context,
                        size: 12,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(3)),
                    Text(
                      body,
                      style: _text(
                        context,
                        size: 10,
                        weight: FontWeight.w500,
                        color: _muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: metrics.geometry(8)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: HocalistPalette.surface(context, _lavender),
                  minimumSize: Size(0, metrics.geometry(34)),
                  padding: metrics.geometryInsets(
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  actionLabel!,
                  style: _text(
                    context,
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: _blue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedActiveRequest extends StatelessWidget {
  const _ApprovedActiveRequest({
    required this.title,
    required this.onDetails,
    required this.onOffers,
    this.showPin = true,
    this.metaLabel,
  });

  final String title;
  final VoidCallback onDetails;
  final VoidCallback onOffers;

  /// Real mode hides the prototype PIN claim until PIN policy is approved.
  final bool showPin;

  /// Real status/budget summary replacing the prototype posted-date text.
  final String? metaLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = metrics.accessibilityReflow;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPin)
              Text(
                'Product PIN: 12345',
                style: _text(
                  context,
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: _navy,
                ),
              ),
            if (showPin) SizedBox(height: metrics.geometry(2)),
            Text(
              title,
              style: _text(
                context,
                size: 14,
                weight: FontWeight.w800,
                color: _navy,
              ),
            ),
            SizedBox(height: metrics.geometry(2)),
            Text(
              metaLabel ?? 'Posted on May 13    2 offers received',
              maxLines: metrics.screenshotLocked ? 1 : null,
              style: _text(context, size: 9.5, color: _muted),
            ),
          ],
        );
        final action = TextButton(
          onPressed: onOffers,
          style: TextButton.styleFrom(
            backgroundColor: HocalistPalette.surface(context, _lavender),
            minimumSize: Size.zero,
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'View offers  ›',
            style: _text(
              context,
              size: 10,
              weight: FontWeight.w700,
              color: _blue,
            ),
          ),
        );
        return _ApprovedDashboardCard(
          key: const ValueKey('approved-active-request-card'),
          padding: metrics.geometryInsets(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          child: InkWell(
            onTap: onDetails,
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          BuyerAssetIcon(
                            asset:
                                '$_approvedAssetRoot/dashboard-clipboard.png',
                            slotSize: metrics.artSize(44),
                          ),
                          SizedBox(width: metrics.geometry(8)),
                          Expanded(child: details),
                        ],
                      ),
                      SizedBox(height: metrics.geometry(6)),
                      action,
                    ],
                  )
                : Row(
                    children: [
                      BuyerAssetIcon(
                        asset: '$_approvedAssetRoot/dashboard-clipboard.png',
                        slotSize: metrics.artSize(44),
                      ),
                      SizedBox(width: metrics.geometry(8)),
                      Expanded(child: details),
                      action,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ApprovedRealMeetingsPanel extends StatelessWidget {
  const _ApprovedRealMeetingsPanel({
    required this.meetings,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final List<MeetingView> meetings;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<MeetingView>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _ApprovedDashboardNotice(
        key: Key('buyerMeetingsLoading'),
        message: 'Loading your meetings…',
      );
    }
    if (error != null) {
      return _ApprovedDashboardNotice(
        key: const Key('buyerMeetingsError'),
        message: error!,
        onRetry: onRetry,
      );
    }
    final now = DateTime.now();
    final upcoming = meetings
        .where((meeting) {
          if (meeting.isCancelled || meeting.status == 'rejected') return false;
          final cutoff = meeting.meetingExpiresAt;
          return cutoff == null || cutoff.isAfter(now);
        })
        .take(3)
        .toList(growable: false);
    if (upcoming.isEmpty) {
      return const _ApprovedEmptySectionCard(
        key: Key('buyerMeetingsEmpty'),
        asset: 'dashboard-calendar.png',
        title: 'No upcoming meetings yet',
        body:
            'Agreed meetings appear here after you select a seller and confirm '
            'a time.',
      );
    }
    final metrics = _replicaMetrics(context);
    return Container(
      key: const Key('buyerRealMeetings'),
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (final meeting in upcoming)
            InkWell(
              key: ValueKey('buyerMeeting-${meeting.meetingId}'),
              onTap: onOpen == null ? null : () => onOpen!(meeting),
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      meeting.offerSummary?.title ?? 'Meeting',
                      style: _text(
                        context,
                        size: 12,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    if (meeting.acceptedSchedule ?? meeting.pendingSchedule
                        case final schedule?) ...[
                      Text(
                        '${schedule.date} · ${schedule.startTime} · ${schedule.timezoneId}',
                        style: _text(context, size: 10.5, color: _muted),
                      ),
                      if (schedule.placeLabel ?? schedule.placeAddress
                          case final place?)
                        Text(
                          place,
                          style: _text(context, size: 10.5, color: _muted),
                        ),
                    ],
                    Text(switch (meeting.status) {
                      'accepted' => 'Confirmed',
                      'proposed' => 'Proposed',
                      'reschedule_proposed' => 'Reschedule requested',
                      _ => 'Awaiting update',
                    }, style: _text(context, size: 10, color: _blue)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovedUpcomingMeetingsPanel extends StatelessWidget {
  const _ApprovedUpcomingMeetingsPanel({
    required this.onTap,
    required this.meetingConfirmed,
  });

  final VoidCallback onTap;
  final bool meetingConfirmed;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final meetings = [
      _ApprovedMeeting(
        day: '17',
        weekday: 'SAT',
        initials: 'NT',
        seller: 'Northside Tech',
        item: 'Samsung TV 65"',
        location: 'Starbucks – Main St.',
        time: 'May 17, 2025  •  2:00 PM',
        status: meetingConfirmed ? 'On schedule' : 'Pending confirmation',
        statusColor: meetingConfirmed ? _green : _blue,
      ),
      const _ApprovedMeeting(
        day: '18',
        weekday: 'SUN',
        initials: 'LR',
        seller: 'Loop Resale',
        item: 'iPad Air 5, 256GB',
        location: 'Hocalist Safe Meet Center',
        time: 'May 18, 2025  •  11:00 AM',
        status: 'On schedule',
        statusColor: _green,
      ),
      const _ApprovedMeeting(
        day: '19',
        weekday: 'MON',
        initials: 'GB',
        seller: 'Gadget Buyer',
        item: 'MacBook Air M2',
        location: 'Your Home',
        time: 'May 19, 2025  •  4:00 PM',
        status: 'Pending confirmation',
        statusColor: _blue,
      ),
    ];
    return Container(
      key: const ValueKey('approved-upcoming-meetings-panel'),
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (var index = 0; index < meetings.length; index++) ...[
            InkWell(
              key: ValueKey('approved-upcoming-meeting-$index'),
              onTap: onTap,
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                ),
                child: _ApprovedMeetingRow(meeting: meetings[index]),
              ),
            ),
            if (index != meetings.length - 1)
              Divider(
                height: metrics.geometry(1),
                color: const Color(0xffedf0f8),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedMeetingRow extends StatelessWidget {
  const _ApprovedMeetingRow({required this.meeting});

  final _ApprovedMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        final date = Container(
          width: metrics.geometry(39),
          padding: EdgeInsets.only(bottom: metrics.geometry(4)),
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, const Color(0xfff2f1ff)),
            borderRadius: BorderRadius.circular(metrics.geometry(6)),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: metrics.geometry(2)),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, _blue),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(metrics.geometry(6)),
                  ),
                ),
                child: Text(
                  'MAY',
                  textAlign: TextAlign.center,
                  style: _text(
                    context,
                    size: 7,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                meeting.day,
                style: _text(
                  context,
                  size: 14,
                  weight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              Text(
                meeting.weekday,
                style: _text(context, size: 7.5, color: _muted),
              ),
            ],
          ),
        );
        final identity = CircleAvatar(
          radius: metrics.geometry(17),
          backgroundColor: HocalistPalette.surface(context, Colors.black),
          child: Text(
            meeting.initials,
            style: _text(
              context,
              size: 10,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
        final details = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      meeting.seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.geometry(2)),
                  BuyerGlyphIcon(
                    icon: Icons.verified,
                    slotSize: metrics.geometry(11),
                    glyphSize: metrics.geometry(11),
                    color: HocalistPalette.text(context, _blue),
                  ),
                ],
              ),
              Text(
                meeting.item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(context, size: 9, color: _navy),
              ),
              SizedBox(height: metrics.geometry(1.5)),
              Row(
                children: [
                  BuyerGlyphIcon(
                    icon: Icons.location_on,
                    slotSize: metrics.geometry(9),
                    glyphSize: metrics.geometry(9),
                    color: HocalistPalette.text(context, _blue),
                  ),
                  SizedBox(width: metrics.geometry(2)),
                  Expanded(
                    child: Text(
                      meeting.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(context, size: 8, color: _muted),
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(1.5)),
              Row(
                children: [
                  BuyerGlyphIcon(
                    icon: Icons.schedule,
                    slotSize: metrics.geometry(9),
                    glyphSize: metrics.geometry(9),
                    color: HocalistPalette.text(context, _blue),
                  ),
                  SizedBox(width: metrics.geometry(2)),
                  Expanded(
                    child: Text(
                      meeting.time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(context, size: 8, color: _muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        final action = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.geometry(6),
                vertical: metrics.geometry(3),
              ),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  meeting.statusColor.withValues(alpha: 0.1),
                ),
                borderRadius: BorderRadius.circular(metrics.geometry(999)),
              ),
              child: Text(
                compact && meeting.status.startsWith('Pending')
                    ? 'Pending'
                    : meeting.status,
                style: _text(
                  context,
                  size: 7.5,
                  weight: FontWeight.w700,
                  color: meeting.statusColor,
                ),
              ),
            ),
            SizedBox(height: metrics.geometry(9)),
            Text(
              'View details  ›',
              style: _text(
                context,
                size: 8.5,
                weight: FontWeight.w700,
                color: _blue,
              ),
            ),
          ],
        );
        return Row(
          children: [
            date,
            SizedBox(width: metrics.geometry(9)),
            identity,
            SizedBox(width: metrics.geometry(9)),
            details,
            SizedBox(width: metrics.geometry(7)),
            action,
          ],
        );
      },
    );
  }
}

class _ApprovedMeeting {
  const _ApprovedMeeting({
    required this.day,
    required this.weekday,
    required this.initials,
    required this.seller,
    required this.item,
    required this.location,
    required this.time,
    required this.status,
    required this.statusColor,
  });

  final String day;
  final String weekday;
  final String initials;
  final String seller;
  final String item;
  final String location;
  final String time;
  final String status;
  final Color statusColor;
}

// Kept for the dedicated recent-activity route while the dashboard now shows
// upcoming meetings.
// ignore: unused_element
class _ApprovedActivityPanel extends StatelessWidget {
  const _ApprovedActivityPanel({required this.onTap});

  final VoidCallback onTap;

  static const _items = [
    _ApprovedActivity(
      'activity-chat.png',
      'Northside Tech sent you a new offer',
      '2 minutes ago',
      '\$420',
      _green,
    ),
    _ApprovedActivity(
      'activity-check.png',
      'Loop Resale accepted your request',
      '1 hour ago',
      '\$390',
      _green,
    ),
    _ApprovedActivity(
      'activity-star.png',
      'You earned a new review',
      'Yesterday',
      '★★★★★',
      Color(0xffffb300),
    ),
    _ApprovedActivity(
      'activity-reward.png',
      'Rewards will be paid on May 20',
      '2 days ago',
      '\$24.80',
      _blue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const ValueKey('approved-dashboard-activity-panel'),
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (var index = 0; index < _items.length; index++) ...[
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                ),
                child: Row(
                  children: [
                    BuyerAssetIcon(
                      asset: '$_approvedAssetRoot/${_items[index].asset}',
                      slotSize: metrics.geometry(30),
                    ),
                    SizedBox(width: metrics.geometry(8)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _items[index].title,
                            style: _text(
                              context,
                              size: 10,
                              weight: FontWeight.w700,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: metrics.geometry(2)),
                          Text(
                            _items[index].time,
                            style: _text(context, size: 9, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.geometry(6)),
                    Text(
                      _items[index].value,
                      style: _text(
                        context,
                        size: _items[index].value.length > 5 ? 11 : 12,
                        weight: FontWeight.w700,
                        color: _items[index].color,
                      ),
                    ),
                    SizedBox(width: metrics.geometry(2)),
                    Text('›', style: _text(context, size: 20, color: _muted)),
                  ],
                ),
              ),
            ),
            if (index != _items.length - 1)
              Divider(
                height: metrics.geometry(1),
                indent: metrics.geometry(48),
                color: const Color(0xffedf0f8),
              ),
          ],
        ],
      ),
    );
  }
}

/// Home Recent activity section backed by safe inbox summaries. It keeps the
/// approved row grammar and distinguishes loading, error, empty and populated
/// states without inventing amounts, reviews or payout dates.
class _ApprovedRealActivityPanel extends StatelessWidget {
  const _ApprovedRealActivityPanel({
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final List<ApprovedActivityView> items;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const _ApprovedDashboardNotice(
        key: Key('buyerActivityLoading'),
        message: 'Loading recent activity…',
      );
    }
    if (error != null && items.isEmpty) {
      return _ApprovedDashboardNotice(
        key: const Key('buyerActivityError'),
        message: error!,
        onRetry: onRetry,
      );
    }
    if (items.isEmpty) {
      return const _ApprovedEmptySectionCard(
        key: Key('buyerActivityEmpty'),
        asset: 'activity-star.png',
        title: 'No recent activity yet',
        body: 'Offer, meeting and account updates appear here as they happen.',
      );
    }
    final metrics = _replicaMetrics(context);
    final visible = items.take(4).toList(growable: false);
    return Container(
      key: const ValueKey('approved-real-activity-panel'),
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            InkWell(
              key: ValueKey('buyerActivity-${visible[index].id}'),
              onTap: onOpen,
              child: Padding(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                ),
                child: Row(
                  children: [
                    BuyerAssetIcon(
                      asset: '$_approvedAssetRoot/${visible[index].asset}',
                      slotSize: metrics.geometry(30),
                    ),
                    SizedBox(width: metrics.geometry(8)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visible[index].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              context,
                              size: 10,
                              weight: visible[index].unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: metrics.geometry(2)),
                          Text(
                            visible[index].timeLabel,
                            style: _text(context, size: 9, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.geometry(6)),
                    if (visible[index].unread)
                      Container(
                        key: const ValueKey('buyerActivityUnreadDot'),
                        width: metrics.geometry(7),
                        height: metrics.geometry(7),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(context, _blue),
                          shape: BoxShape.circle,
                        ),
                      ),
                    SizedBox(width: metrics.geometry(2)),
                    Text('›', style: _text(context, size: 20, color: _muted)),
                  ],
                ),
              ),
            ),
            if (index != visible.length - 1)
              Divider(
                height: metrics.geometry(1),
                indent: metrics.geometry(48),
                color: const Color(0xffedf0f8),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedKeepEarningBanner extends StatelessWidget {
  const _ApprovedKeepEarningBanner({this.realMode = false});

  /// The referral promise is prototype-only. Real accounts keep the approved
  /// banner composition with honest reward copy.
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const ValueKey('approved-keep-earning-banner'),
      padding: metrics.geometryInsets(const EdgeInsets.fromLTRB(10, 8, 10, 8)),
      constraints: BoxConstraints(minHeight: metrics.geometry(64)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 && metrics.textScale >= 1.6;
          final shield = BuyerAssetIcon(
            key: const ValueKey('approved-keep-earning-shield'),
            asset: '$_approvedAssetRoot/home-benefit-shield.png',
            slotSize: metrics.artSize(BuyerIconTokens.feature + 8),
          );
          final copy = SizedBox(
            key: const ValueKey('approved-keep-earning-copy'),
            width: metrics.geometry(170),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  realMode
                      ? 'Keep earning rewards'
                      : 'Keep earning more rewards',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: _text(
                    context,
                    size: 11,
                    weight: FontWeight.w800,
                    color: _blue,
                  ),
                ),
                SizedBox(height: metrics.geometry(4)),
                Text(
                  realMode
                      ? 'Confirm each purchase with your PIN\nto earn rewards.'
                      : 'Refer friends, complete purchases,\nand unlock bigger rewards.',
                  key: const ValueKey('approved-keep-earning-description'),
                  style: _text(context, size: 9, color: _muted, height: 1.3),
                ),
              ],
            ),
          );
          final artwork = Image.asset(
            '$_approvedAssetRoot/reward-network-full.png',
            key: const ValueKey('approved-keep-earning-artwork'),
            width: metrics.artSize(stacked ? 150 : 110),
            height: metrics.artSize(stacked ? 62 : 44),
            fit: BoxFit.contain,
            alignment: Alignment.centerRight,
            filterQuality: FilterQuality.high,
          );
          if (metrics.accessibilityReflow) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                shield,
                SizedBox(width: metrics.geometry(8)),
                Expanded(
                  child: Column(
                    key: const ValueKey('approved-keep-earning-copy-adaptive'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        realMode
                            ? 'Keep earning rewards'
                            : 'Keep earning more rewards',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          context,
                          size: 11,
                          weight: FontWeight.w800,
                          color: _blue,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(4)),
                      Text(
                        realMode
                            ? 'Confirm each purchase with your PIN to earn rewards.'
                            : 'Refer friends, complete purchases, and unlock bigger rewards.',
                        key: const ValueKey(
                          'approved-keep-earning-description-adaptive',
                        ),
                        style: _text(
                          context,
                          size: 9,
                          color: _muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.geometry(6)),
                SizedBox(
                  width: metrics.artSize(86),
                  height: metrics.artSize(52),
                  child: Image.asset(
                    '$_approvedAssetRoot/reward-network-full.png',
                    key: const ValueKey(
                      'approved-keep-earning-artwork-adaptive',
                    ),
                    fit: BoxFit.contain,
                    alignment: Alignment.topRight,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ],
            );
          }
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    shield,
                    SizedBox(width: metrics.geometry(10)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: copy,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: metrics.geometry(8)),
                Align(alignment: Alignment.centerRight, child: artwork),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SizedBox(
                  height: metrics.geometry(48),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(left: 0, top: 0, child: shield),
                      Positioned(
                        left: metrics.geometry(50),
                        top: metrics.geometry(2),
                        child: copy,
                      ),
                      Positioned(
                        right: 0,
                        top: metrics.geometry(-7),
                        child: SizedBox(
                          width: metrics.artSize(176),
                          height: metrics.artSize(62),
                          child: Image.asset(
                            '$_approvedAssetRoot/reward-network-full.png',
                            key: const ValueKey(
                              'approved-keep-earning-artwork',
                            ),
                            fit: BoxFit.contain,
                            alignment: Alignment.centerRight,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedDashboardCard extends StatelessWidget {
  const _ApprovedDashboardCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.referenceHeight,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? referenceHeight;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final approvedHeight = referenceHeight == null
        ? null
        : metrics.geometry(referenceHeight!);
    final fixedHeight = approvedHeight == null
        ? null
        : approvedHeight * (1 + (textScale - 1).clamp(0, .15)) +
              (metrics.isTablet ? 8 : 0);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          height: metrics.screenshotLocked && referenceHeight != null
              ? fixedHeight
              : null,
          padding: padding,
          decoration: _panelDecoration(context),
          child: child,
        ),
      ),
    );
  }
}

class _ApprovedActivity {
  const _ApprovedActivity(
    this.asset,
    this.title,
    this.time,
    this.value,
    this.color,
  );

  final String asset;
  final String title;
  final String time;
  final String value;
  final Color color;
}

TextStyle _text(
  BuildContext context, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double? height,
}) {
  final metrics = _replicaMetrics(context);
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: metrics.fontSize(size),
    fontWeight: weight,
    color: HocalistPalette.text(context, color),
    height: height,
    letterSpacing: 0,
  );
}
