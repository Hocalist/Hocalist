import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/accessibility_visuals.dart';
import '../../theme/buyer_ui_foundation.dart';
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

class ApprovedAccountCreationPage extends StatefulWidget {
  const ApprovedAccountCreationPage({
    required this.role,
    required this.name,
    required this.onNameChanged,
    required this.onRoleChanged,
    required this.onClose,
    required this.onSignup,
    required this.onLogin,
    this.onGoogle,
    this.onApple,
    this.onFacebook,
    this.onUploadProfile,
    super.key,
  });

  final ApprovedAccountRole role;
  final String name;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<ApprovedAccountRole> onRoleChanged;
  final VoidCallback onClose;
  final VoidCallback onSignup;
  final VoidCallback onLogin;
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final VoidCallback? onFacebook;
  final VoidCallback? onUploadProfile;

  @override
  State<ApprovedAccountCreationPage> createState() =>
      _ApprovedAccountCreationPageState();
}

class _ApprovedAccountCreationPageState
    extends State<ApprovedAccountCreationPage> {
  bool _loginMode = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final accessibilityReflow = metrics.accessibilityReflow;
    final loginMode = _loginMode;

    return Material(
      color: Colors.white,
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
                    height: metrics.geometry(103),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: metrics.geometry(38),
                            height: metrics.geometry(4),
                            decoration: BoxDecoration(
                              color: const Color(0xffc8c9d9),
                              borderRadius: BorderRadius.circular(
                                metrics.geometry(99),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: metrics.geometry(4),
                          right: 0,
                          child: _ApprovedAssetButton(
                            tooltip: 'Close',
                            asset: 'account-close.png',
                            size: 36,
                            onTap: widget.onClose,
                          ),
                        ),
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
                    loginMode
                        ? 'Log in to your account'
                        : 'Create your account',
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
                    loginMode
                        ? 'Welcome back to Hocalist.'
                        : 'Join Hocalist to get started.',
                    textAlign: TextAlign.center,
                    style: _text(context, size: 12.5, color: _muted),
                  ),
                  SizedBox(height: metrics.geometry(23)),
                  _ApprovedRoleSelector(
                    role: widget.role,
                    stacked: accessibilityReflow,
                    onChanged: widget.onRoleChanged,
                  ),
                  SizedBox(height: metrics.geometry(23)),
                  if (!loginMode) ...[
                    _ApprovedField(
                      key: const ValueKey('approved-account-name-field'),
                      iconAsset: 'account-person.png',
                      hint: widget.role == ApprovedAccountRole.buyer
                          ? 'Full name'
                          : 'Store or seller name',
                      initialValue: widget.name,
                      onChanged: widget.onNameChanged,
                    ),
                    SizedBox(height: metrics.geometry(9)),
                  ],
                  const _ApprovedField(
                    key: ValueKey('approved-account-email-field'),
                    iconAsset: 'account-mail.png',
                    hint: 'Email address',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: metrics.geometry(9)),
                  if (!loginMode) ...[
                    const _ApprovedField(
                      key: ValueKey('approved-account-phone-field'),
                      iconAsset: 'account-phone.png',
                      hint: 'Phone number (optional)',
                      keyboardType: TextInputType.phone,
                    ),
                    SizedBox(height: metrics.geometry(9)),
                  ],
                  _ApprovedField(
                    key: const ValueKey('approved-account-password-field'),
                    iconAsset: 'account-lock.png',
                    hint: 'Password',
                    obscureText: !_passwordVisible,
                    suffix: _ApprovedFieldAssetButton(
                      key: const ValueKey('approved-account-password-eye'),
                      tooltip: _passwordVisible
                          ? 'Hide password'
                          : 'Show password',
                      asset: 'account-eye.png',
                      onTap: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
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
                  SizedBox(height: metrics.geometry(15)),
                  _ApprovedPrimaryButton(
                    key: const ValueKey('approved-account-primary-action'),
                    label: loginMode ? 'Log in' : 'Create account',
                    onTap: loginMode ? widget.onLogin : widget.onSignup,
                  ),
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
                    onTap: widget.onGoogle,
                  ),
                  SizedBox(height: metrics.geometry(5)),
                  _ApprovedSocialButton(
                    key: const ValueKey('approved-account-apple-action'),
                    label: 'Continue with Apple',
                    asset: 'social-apple.png',
                    onTap: widget.onApple,
                  ),
                  SizedBox(height: metrics.geometry(5)),
                  _ApprovedSocialButton(
                    key: const ValueKey('approved-account-facebook-action'),
                    label: 'Continue with Facebook',
                    asset: 'social-facebook.png',
                    onTap: widget.onFacebook,
                  ),
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
                        onPressed: () =>
                            setState(() => _loginMode = !loginMode),
                        style: TextButton.styleFrom(
                          minimumSize: metrics.geometrySize(const Size(44, 36)),
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
        color: selected ? const Color(0xfff7f6ff) : Colors.white,
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
                color: selected
                    ? const Color(0xffaaa6ff)
                    : const Color(0xffdfe3ee),
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
    super.key,
  });

  final String iconAsset;
  final String hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
          borderSide: BorderSide(
            color: const Color(0xffdfe3ee),
            width: metrics.geometry(1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
          borderSide: BorderSide(color: _blue, width: metrics.geometry(1.5)),
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
            color: Colors.transparent,
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
        onPressed: onTap ?? () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          minimumSize: Size.fromHeight(metrics.geometry(42)),
          side: BorderSide(
            color: const Color(0xffdfe3ee),
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
            color: _navy,
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
    _videoPreviewTimer = Timer(_videoPreviewDuration, _showSecondVideo);
  }

  void _showSecondVideo() {
    if (!mounted || _videoIndex == _videoPreviews.length - 1) return;
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
        ? 'Jonathan'
        : widget.name.trim().split(RegExp(r'\s+')).first;
    final videoPreview = _videoPreviews[_videoIndex];
    return Material(
      color: Colors.white,
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
                              color: Colors.black,
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
                                    decoration: const BoxDecoration(
                                      color: Color(0xffa9a9a9),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
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
                              duration: const Duration(milliseconds: 180),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00ffffff), Colors.white],
        ),
      ),
      child: BuyerGlyphIcon(
        icon: Icons.keyboard_arrow_down_rounded,
        slotSize: metrics.geometry(24),
        glyphSize: metrics.geometry(24),
        color: _blue,
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
              'Welcome, $name  🎉',
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
        color: Colors.white,
        border: Border.all(color: _line, width: metrics.geometry(1)),
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
        color: const Color(0xffeef7f1),
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
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double referenceHeight;

  @override
  Widget build(BuildContext context) {
    return BuyerPrimaryButton(
      label: label,
      onPressed: onTap,
      compact: referenceHeight <= 44,
      minimumHeight: referenceHeight,
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
      icon: BuyerAssetIcon(
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
      color: const Color(0xfffbfcff),
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
        color: _lavender,
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
        color: Colors.transparent,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(metrics.geometry(12)),
              border: Border.all(
                color: const Color(0xffe8ebf5),
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
                      color: _navy,
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
            backgroundColor: accessibility.backgroundOr(_blue),
            foregroundColor: accessibility.foregroundOr(Colors.white),
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
            color: _lavender,
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
            color: Colors.white,
            border: Border(
              top: BorderSide(
                color: const Color(0xffedf0f8),
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
                          color: index == selectedIndex
                              ? _lavender
                              : Colors.white,
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
        availableWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
      );
}

BoxDecoration _panelDecoration(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(metrics.geometry(8)),
    border: Border.all(
      color: const Color(0xffe8ebf5),
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
    this.meetingConfirmed = false,
    this.onMeetingDetails,
    this.onNotifications,
    this.onHome,
    this.onTrends,
    this.onOffersTab,
    this.onChats,
    this.onMore,
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
  final bool meetingConfirmed;
  final VoidCallback? onMeetingDetails;
  final VoidCallback? onNotifications;
  final VoidCallback? onHome;
  final VoidCallback? onTrends;
  final VoidCallback? onOffersTab;
  final VoidCallback? onChats;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().isEmpty
        ? 'Alex'
        : name.trim().split(RegExp(r'\s+')).first;
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
          availableWidth: viewport.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return ApprovedReplicaScope(
          metrics: metrics,
          child: Material(
            color: const Color(0xfffbfcff),
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
                        if (requestPosted) ...[
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
                        _ApprovedUpcomingMeetingsPanel(
                          onTap: onMeetingDetails ?? onRecentActivity,
                          meetingConfirmed: meetingConfirmed,
                        ),
                        SizedBox(height: metrics.geometry(12)),
                        const _ApprovedKeepEarningBanner(),
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
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onDealHistory;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
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
              color: _lavender,
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
                  backgroundColor: const Color(0xffe9e4ff),
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
                  child: const LinearProgressIndicator(
                    value: .992,
                    minHeight: 9,
                    backgroundColor: _lavender,
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
                      decoration: const BoxDecoration(
                        color: _lavender,
                        shape: BoxShape.circle,
                      ),
                      child: BuyerGlyphIcon(
                        icon: Icons.account_balance_outlined,
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
                      color: _muted,
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
                  color: _blue,
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
                    backgroundColor: const Color(0xffe7f7ef),
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
                const BuyerFieldLabel('Withdrawal amount'),
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
                  color: Colors.transparent,
                  child: ListTile(
                    key: const Key('approved-withdrawal-destination'),
                    contentPadding: EdgeInsets.zero,
                    leading: BuyerGlyphIcon(
                      icon: Icons.account_balance_outlined,
                      slotSize: metrics.artSize(30),
                      glyphSize: metrics.artSize(24),
                      color: _blue,
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
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: _blue,
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
    required this.onSelect,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
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
          BuyerGlyphIcon(icon: icon, slotSize: 26, glyphSize: 23, color: _blue),
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
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  State<ApprovedMeetingDetailsPage> createState() =>
      _ApprovedMeetingDetailsPageState();
}

class _ApprovedMeetingDetailsPageState
    extends State<ApprovedMeetingDetailsPage> {
  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final viewport = MediaQuery.sizeOf(context);
    final compactViewport = viewport.width <= 340 || viewport.height <= 700;
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
                    color: const Color(0xfff8f8ff),
                    borderRadius: BorderRadius.circular(metrics.geometry(12)),
                  ),
                  child: Image.asset(
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
                        'iPad Air 5th Gen 64GB',
                        style: _text(
                          context,
                          size: 15,
                          weight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(4)),
                      Text(
                        '\$650',
                        style: _text(
                          context,
                          size: 20,
                          weight: FontWeight.w800,
                          color: _blue,
                        ),
                      ),
                      SizedBox(height: metrics.geometry(6)),
                      Container(
                        padding: metrics.geometryInsets(
                          const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffe9f8ee),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Offer accepted',
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
                  initialValue: 'Yonkers, NY',
                ),
                SizedBox(height: metrics.geometry(compactViewport ? 8 : 12)),
                _ApprovedMeetingField(
                  key: const ValueKey('approved-meeting-time-field'),
                  asset: 'chat-time.png',
                  label: 'Date and time',
                  initialValue: 'Today • 5:00 PM',
                ),
                SizedBox(height: metrics.geometry(compactViewport ? 8 : 12)),
                _ApprovedMeetingField(
                  asset: 'chat-safety.png',
                  label: 'Meeting note',
                  initialValue: 'Inspect the item before paying offline',
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
              color: const Color(0xffeef9f2),
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
          SizedBox(height: metrics.spacing(compactViewport ? 9 : 16)),
          BuyerPrimaryButton(
            key: const ValueKey('approved-confirm-meeting-button'),
            label: 'Confirm meeting',
            onPressed: widget.onConfirm,
            compact: compactViewport,
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
class ApprovedBuyerAfterMeetupPage extends StatelessWidget {
  const ApprovedBuyerAfterMeetupPage({
    required this.onBack,
    required this.navigation,
    required this.onReview,
    required this.onDealIssue,
    required this.onReport,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onReview;
  final VoidCallback onDealIssue;
  final VoidCallback onReport;

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
          const _ApprovedLifecyclePinNotice(
            title: 'Your confirmation PIN: 15230',
            body:
                'Show this PIN to the seller only after you inspect the iPad and pay them offline. The seller submits it in Meets so your \$1.40 reward can be honored.',
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
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
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
              color: const Color(0xffeef9f2),
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

class ApprovedBuyerReviewPage extends StatefulWidget {
  const ApprovedBuyerReviewPage({
    required this.onBack,
    required this.navigation,
    required this.onFinish,
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onFinish;

  @override
  State<ApprovedBuyerReviewPage> createState() =>
      _ApprovedBuyerReviewPageState();
}

class _ApprovedBuyerReviewPageState extends State<ApprovedBuyerReviewPage> {
  int _rating = 5;

  @override
  Widget build(BuildContext context) {
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
                        color: selected ? null : const Color(0xffc9cbe0),
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
    super.key,
  });

  final VoidCallback onBack;
  final ApprovedBuyerNavigation navigation;
  final VoidCallback onReopen;
  final VoidCallback onBackup;
  final VoidCallback onReport;

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
            onTap: onBackup,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            asset: 'detail-description.png',
            title: 'Reopen this request',
            body: 'Let sellers respond again without rebuilding the request.',
            accent: _blue,
            onTap: onReopen,
          ),
          const SizedBox(height: 9),
          _ApprovedLifecycleAction(
            asset: 'chat-safety.png',
            title: 'Report a safety issue',
            body: 'Use this for unsafe behavior, fraud, or a serious concern.',
            accent: const Color(0xffc62828),
            onTap: onReport,
          ),
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
        color: const Color(0xfffafbff),
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
            backgroundColor: Colors.white,
            side: BorderSide(color: filter == selected ? _blue : _line),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        key: ValueKey('approved-deal-history-record-${record.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _line),
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
                  color: _lavender,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Image.asset(
                  record.productAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const BuyerGlyphIcon(
                    icon: Icons.devices_other_outlined,
                    slotSize: 30,
                    color: _blue,
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
                        const BuyerGlyphIcon(
                          icon: Icons.chevron_right_rounded,
                          slotSize: 20,
                          glyphSize: 20,
                          color: _blue,
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
        color: status.color.withValues(alpha: .1),
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
  const _ApprovedDealHistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailSurface(
      child: Column(
        children: [
          const BuyerGlyphIcon(
            icon: Icons.history_rounded,
            slotSize: BuyerIconTokens.feature,
            color: _blue,
          ),
          const SizedBox(height: 8),
          Text(
            'No deals match this filter',
            textAlign: TextAlign.center,
            style: _text(
              context,
              size: 12.5,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
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
              color: const Color(0xfff6f5ff),
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
                        color: effectiveStatusColor.withValues(alpha: .11),
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
        color: completed ? const Color(0xffeef9f2) : _lavender,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: completed ? const Color(0xffcdebd7) : _line),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              BuyerAssetIconSurface(
                asset: 'assets/approved_offers_chat/$asset',
                surfaceSize: 42,
                iconSize: 26,
                backgroundColor: accent.withValues(alpha: .1),
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
              const BuyerGlyphIcon(
                icon: Icons.chevron_right_rounded,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: _blue,
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
  });

  final int completed;
  final int active;
  final int attention;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ApprovedHistoryMetric(value: '$active', label: 'Active'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ApprovedHistoryMetric(
            value: '$completed',
            label: 'Completed',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ApprovedHistoryMetric(
            value: '$attention',
            label: 'Needs attention',
          ),
        ),
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
        color: _lavender,
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
        color: const Color(0xfffff7e8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(metrics.geometry(16)),
        border: Border.all(color: _line),
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
  });

  final String asset;
  final String label;
  final String value;

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
            style: _text(
              context,
              size: 20,
              weight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: metrics.geometry(3)),
          Text(label, style: _text(context, size: 11, color: _muted)),
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
    super.key,
  });

  final String asset;
  final String label;
  final String initialValue;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuyerFieldLabel(label),
        SizedBox(height: metrics.spacing(5)),
        TextFormField(
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
              'Good morning, $name! 👋',
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

class _ApprovedRewardCard extends StatelessWidget {
  const _ApprovedRewardCard({
    required this.onTap,
    required this.alignActionToBottom,
  });

  final VoidCallback onTap;
  final bool alignActionToBottom;

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
                      '\$128.45',
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
          Text(
            'From 42 completed purchases',
            style: _text(context, size: 10.5, color: _muted),
          ),
          SizedBox(height: metrics.geometry(6)),
          if (alignActionToBottom) const Spacer(),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: _lavender,
              foregroundColor: _blue,
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
  const _ApprovedPendingCard();

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
            'Pending rewards  ⓘ',
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
                      '\$24.80',
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
          Text(
            'Pay date: May 20, 2025',
            style: _text(context, size: 10.5, color: _muted),
          ),
          SizedBox(height: metrics.geometry(4)),
          ClipRRect(
            borderRadius: BorderRadius.circular(metrics.geometry(99)),
            child: LinearProgressIndicator(
              value: .992,
              minHeight: metrics.geometry(6),
              backgroundColor: _lavender,
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
      color: const Color(0xfffbfaff),
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
              color: const Color(0xffa997ff),
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

class _ApprovedActiveRequest extends StatelessWidget {
  const _ApprovedActiveRequest({
    required this.title,
    required this.onDetails,
    required this.onOffers,
  });

  final String title;
  final VoidCallback onDetails;
  final VoidCallback onOffers;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = metrics.accessibilityReflow;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Product PIN: 12345',
              style: _text(
                context,
                size: 10.5,
                weight: FontWeight.w700,
                color: _navy,
              ),
            ),
            SizedBox(height: metrics.geometry(2)),
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
              'Posted on May 13  •  2 offers received',
              maxLines: metrics.screenshotLocked ? 1 : null,
              style: _text(context, size: 9.5, color: _muted),
            ),
          ],
        );
        final action = TextButton(
          onPressed: onOffers,
          style: TextButton.styleFrom(
            backgroundColor: _lavender,
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
            color: const Color(0xfff2f1ff),
            borderRadius: BorderRadius.circular(metrics.geometry(6)),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: metrics.geometry(2)),
                decoration: BoxDecoration(
                  color: _blue,
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
          backgroundColor: Colors.black,
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
                    color: _blue,
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
                    color: _blue,
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
                    color: _blue,
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
                color: meeting.statusColor.withValues(alpha: 0.1),
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

class _ApprovedKeepEarningBanner extends StatelessWidget {
  const _ApprovedKeepEarningBanner();

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const ValueKey('approved-keep-earning-banner'),
      padding: metrics.geometryInsets(const EdgeInsets.fromLTRB(10, 8, 10, 8)),
      constraints: BoxConstraints(minHeight: metrics.geometry(64)),
      decoration: BoxDecoration(
        color: _lavender,
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
                  'Keep earning more rewards',
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
                  'Refer friends, complete purchases,\nand unlock bigger rewards.',
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
                        'Keep earning more rewards',
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
                        'Refer friends, complete purchases, and unlock bigger rewards.',
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
    return Container(
      height: metrics.screenshotLocked && referenceHeight != null
          ? fixedHeight
          : null,
      padding: padding,
      decoration: _panelDecoration(context),
      child: child,
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
    color: color,
    height: height,
    letterSpacing: 0,
  );
}
