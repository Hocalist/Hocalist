part of '../main.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    required this.onStart,
    required this.onBuyer,
    required this.onSeller,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onBuyer;
  final VoidCallback onSeller;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool showAllFaqs = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NoAccountHomeHeader(),
        const SizedBox(height: 24),
        HomeRoleActionCard(
          title: 'I am buying',
          body: 'Get Paid To Buy And\nGet The Best Offers',
          buttonLabel: 'Post a request',
          icon: Icons.shopping_bag_outlined,
          color: HocalistTheme.actionBlue,
          surface: HocalistTheme.roleSurface,
          imageAsset: 'assets/home/buyer-home-card-full.png',
          aspectRatio: 786 / 460,
          onTap: widget.onBuyer,
        ),
        const SizedBox(height: 16),
        HomeRoleActionCard(
          title: 'I am selling',
          body: 'Target Real Customers\n& Beat The Competition.',
          buttonLabel: 'Browse requests',
          icon: Icons.storefront_outlined,
          color: HocalistTheme.sellerGreen,
          surface: HocalistTheme.sellerSurface,
          imageAsset: 'assets/home/seller-home-card.png',
          onTap: widget.onSeller,
        ),
        const SizedBox(height: 24),
        Text(
          'We Are The Better Option',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Our reverse marketplace works, plain and simple',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        const HomeBenefitPanel(compact: false),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'See How Hocalist Works',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.play_circle_outline,
              color: HocalistTheme.actionBlue,
              size: 23,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Watch a quick 60-second overview',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: HocalistTheme.muted),
        ),
        const SizedBox(height: 18),
        const HocalistVideoPreview(),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'Frequently Asked Questions',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 22),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => showAllFaqs = !showAllFaqs);
              },
              child: Text(showAllFaqs ? 'Collapse all' : 'View all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeFaqList(expandAll: showAllFaqs),
        const SizedBox(height: 36),
        HomeStartBanner(onCreateAccount: widget.onStart),
      ],
    );
  }
}

class ChooseRolePage extends StatelessWidget {
  const ChooseRolePage({
    required this.onBuyer,
    required this.onSeller,
    super.key,
  });

  final VoidCallback onBuyer;
  final VoidCallback onSeller;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'How will you use Hocalist?',
      subtitle:
          'This starts the right onboarding flow. You can switch later from profile.',
      children: [
        const ProcessStrip(),
        RoleCard(
          title: 'Buyer',
          body:
              'Post buying intent, review offers, select a seller, chat, confirm, and review.',
          color: HocalistTheme.buyer,
          icon: Icons.shopping_bag_outlined,
          onTap: onBuyer,
        ),
        RoleCard(
          title: 'Seller',
          body:
              'Create a seller profile, browse active requests, send offers, chat, and manage seller tools.',
          color: HocalistTheme.seller,
          icon: Icons.storefront_outlined,
          onTap: onSeller,
        ),
      ],
    );
  }
}

class AccountAccessPage extends StatefulWidget {
  const AccountAccessPage({
    required this.role,
    required this.name,
    required this.onNameChanged,
    required this.onRoleChanged,
    required this.onClose,
    required this.onSignup,
    required this.onLogin,
    super.key,
  });

  final UserRole role;
  final String name;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<UserRole> onRoleChanged;
  final VoidCallback onClose;
  final VoidCallback onSignup;
  final VoidCallback onLogin;

  @override
  State<AccountAccessPage> createState() => _AccountAccessPageState();
}

class _AccountAccessPageState extends State<AccountAccessPage> {
  bool loginMode = false;
  bool passwordVisible = false;
  bool confirmPasswordVisible = false;
  bool imageUploaded = false;

  @override
  Widget build(BuildContext context) {
    final title = loginMode ? 'Log in to your account' : 'Create your account';
    final subtitle = loginMode
        ? 'Welcome back to Hocalist.'
        : 'Join Hocalist to get started.';
    final primaryLabel = loginMode ? 'Log in' : 'Create account';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xffc8c9d9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close',
              onPressed: widget.onClose,
              icon: const Icon(
                Icons.close,
                color: HocalistTheme.muted,
                size: 32,
              ),
            ),
          ),
          _AccountHeroIcon(
            uploaded: imageUploaded,
            onTap: () {
              setState(() => imageUploaded = true);
            },
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: 30,
              color: HocalistTheme.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: HocalistTheme.muted),
          ),
          const SizedBox(height: 34),
          _AccountRoleToggle(
            role: widget.role,
            onChanged: widget.onRoleChanged,
          ),
          const SizedBox(height: 28),
          if (!loginMode) ...[
            _AccountInput(
              icon: Icons.person_outline,
              hint: widget.role == UserRole.buyer
                  ? 'Full name'
                  : 'Store or seller name',
              initialValue: widget.name,
              onChanged: widget.onNameChanged,
            ),
            const SizedBox(height: 14),
          ],
          const _AccountInput(
            icon: Icons.mail_outline,
            hint: 'Email address',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          if (!loginMode) ...[
            const _AccountInput(
              icon: Icons.phone_outlined,
              hint: 'Phone number (optional)',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
          ],
          _AccountInput(
            icon: Icons.lock_outline,
            hint: 'Password',
            obscureText: !passwordVisible,
            suffix: IconButton(
              tooltip: passwordVisible ? 'Hide password' : 'Show password',
              onPressed: () {
                setState(() => passwordVisible = !passwordVisible);
              },
              icon: const Icon(Icons.visibility_outlined),
            ),
          ),
          if (!loginMode) ...[
            const SizedBox(height: 14),
            _AccountInput(
              icon: Icons.lock_outline,
              hint: 'Confirm password',
              obscureText: !confirmPasswordVisible,
              suffix: IconButton(
                tooltip: confirmPasswordVisible
                    ? 'Hide confirm password'
                    : 'Show confirm password',
                onPressed: () {
                  setState(
                    () => confirmPasswordVisible = !confirmPasswordVisible,
                  );
                },
                icon: const Icon(Icons.visibility_outlined),
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: HocalistTheme.actionBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: loginMode ? widget.onLogin : widget.onSignup,
              child: Text(
                primaryLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _AccountDivider(),
          const SizedBox(height: 18),
          const _SocialAuthButton(
            label: 'Continue with Google',
            asset: 'assets/auth/social-google.png',
          ),
          const SizedBox(height: 12),
          const _SocialAuthButton(
            label: 'Continue with Apple',
            asset: 'assets/auth/social-apple.png',
          ),
          const SizedBox(height: 12),
          const _SocialAuthButton(
            label: 'Continue with Facebook',
            asset: 'assets/auth/social-facebook.png',
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                loginMode
                    ? 'Don\'t have an account? '
                    : 'Already have an account? ',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: HocalistTheme.muted),
              ),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() => loginMode = !loginMode);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      loginMode ? 'Sign up' : 'Log in',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: HocalistTheme.actionBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountHeroIcon extends StatelessWidget {
  const _AccountHeroIcon({required this.uploaded, required this.onTap});

  final bool uploaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: uploaded ? 'Profile image added' : 'Upload profile image',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              children: [
                ClipOval(
                  child: uploaded
                      ? Image.asset(
                          'assets/buyer_onboarding/buyer-avatar.png',
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            color: HocalistTheme.roleSurface,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.person_outline,
                              color: HocalistTheme.actionBlue,
                              size: 74,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 4,
                  bottom: 24,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: HocalistTheme.actionBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
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

class _AccountRoleToggle extends StatelessWidget {
  const _AccountRoleToggle({required this.role, required this.onChanged});

  final UserRole role;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AccountRoleButton(
            selected: role == UserRole.buyer,
            icon: Icons.shopping_bag_outlined,
            label: 'I am buying',
            onTap: () => onChanged(UserRole.buyer),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AccountRoleButton(
            selected: role == UserRole.seller,
            icon: Icons.storefront_outlined,
            label: 'I am selling',
            onTap: () => onChanged(UserRole.seller),
          ),
        ),
      ],
    );
  }
}

class _AccountRoleButton extends StatelessWidget {
  const _AccountRoleButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HocalistTheme.actionBlue : HocalistTheme.muted;
    return Material(
      color: selected ? HocalistTheme.roleSurface : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xffaaa6ff)
                  : const Color(0xffdfe3ee),
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: selected
                        ? HocalistTheme.actionBlue
                        : HocalistTheme.text,
                    fontSize: 16,
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

class _AccountInput extends StatelessWidget {
  const _AccountInput({
    required this.icon,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
  });

  final IconData icon;
  final String hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: HocalistTheme.muted, size: 28),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 22,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdfe3ee)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HocalistTheme.actionBlue),
        ),
      ),
    );
  }
}

class _AccountDivider extends StatelessWidget {
  const _AccountDivider();

  @override
  Widget build(BuildContext context) {
    final highText = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    if (highText) {
      return Row(
        children: [
          const Expanded(child: Divider(color: Color(0xffdfe3ee))),
          const SizedBox(width: 10),
          Flexible(
            flex: 4,
            child: Text(
              'or continue with',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Color(0xffdfe3ee))),
        ],
      );
    }
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xffdfe3ee))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xffdfe3ee))),
      ],
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({required this.label, required this.asset});

  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: HocalistTheme.text,
          side: const BorderSide(color: Color(0xffdfe3ee)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        onPressed: () {},
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              asset,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuyerBenefitOnboardingPage extends StatefulWidget {
  const BuyerBenefitOnboardingPage({
    required this.name,
    required this.onClose,
    required this.onFinish,
    super.key,
  });

  final String name;
  final VoidCallback onClose;
  final VoidCallback onFinish;

  @override
  State<BuyerBenefitOnboardingPage> createState() =>
      _BuyerBenefitOnboardingPageState();
}

class _BuyerBenefitOnboardingPageState
    extends State<BuyerBenefitOnboardingPage> {
  final benefitScrollController = ScrollController();
  bool showBenefitScrollCue = true;

  static const benefits = [
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-reward.png',
      'Earn rewards on every purchase',
      'Sellers pay you to have the chance to earn your business. Choose one to buy from and keep your earnings.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-tag.png',
      'Receive the best offers',
      'Sellers compete for your business so you get better deals.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-shield.png',
      'Post safely and privately',
      'Sellers only see a name, but can\'t contact you until you choose to talk to them.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-chat.png',
      'Chat and compare easily',
      'Chat with sellers, compare offers, and choose what\'s best for you.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-location.png',
      'Mileage logic for less driving',
      'Only sellers within the mileage distance you choose will be able to target you.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-medal.png',
      'Build your reputation for better offers',
      'Buying more means you\'re a prime customer, sellers get a notification when you post to offer you special deals.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-payment-shield.png',
      'We protect your choices & reward you for it',
      'Choose who to talk to, meet safely, and complete item payment on your terms outside the app.',
    ),
    _BuyerBenefitData(
      'assets/buyer_onboarding/benefit-review-dollar.png',
      'Reviewing Your Seller Pays Off',
      'Get extra commissions when reviewing a seller; honesty pays off every time.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    benefitScrollController.addListener(_updateBenefitScrollCue);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateBenefitScrollCue(),
    );
  }

  void _updateBenefitScrollCue() {
    if (!mounted || !benefitScrollController.hasClients) {
      return;
    }
    final position = benefitScrollController.position;
    final shouldShow = position.maxScrollExtent > 8 && position.pixels < 12;
    if (showBenefitScrollCue != shouldShow) {
      setState(() => showBenefitScrollCue = shouldShow);
    }
  }

  @override
  void dispose() {
    benefitScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.name.trim().isEmpty
        ? 'Jonathan'
        : widget.name.trim().split(RegExp(r'\s+')).first;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close',
              onPressed: widget.onClose,
              icon: const Icon(
                Icons.close,
                color: HocalistTheme.muted,
                size: 31,
              ),
            ),
          ),
          _BuyerWelcomeHeader(name: firstName),
          const SizedBox(height: 8),
          const _BuyerVideoCard(
            asset: 'assets/buyer_onboarding/buyer-video-welcome.png',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: benefitScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'As a buyer, you will:',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: HocalistTheme.primary,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 12),
                      for (final item in benefits) ...[
                        _BuyerBenefitCard(data: item),
                        const SizedBox(height: 10),
                      ],
                      const _BuyerFairnessBanner(),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: HocalistTheme.actionBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: widget.onFinish,
                          child: Text(
                            'Jump to dashboard',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.white, fontSize: 17),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: showBenefitScrollCue ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const _BenefitScrollCue(),
                    ),
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

class _BenefitScrollCue extends StatelessWidget {
  const _BenefitScrollCue();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      alignment: Alignment.bottomCenter,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00ffffff), Colors.white],
        ),
      ),
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xff00036c).withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: HocalistTheme.actionBlue,
          size: 28,
          semanticLabel: 'More buyer benefits below',
        ),
      ),
    );
  }
}

class _BuyerWelcomeHeader extends StatelessWidget {
  const _BuyerWelcomeHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.asset(
            'assets/buyer_onboarding/buyer-avatar.png',
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $name 🎉',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: HocalistTheme.text,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'With your Hocalist buyer account, you get paid to buy and enjoy the best offers.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: HocalistTheme.muted,
                  height: 1.28,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuyerVideoCard extends StatelessWidget {
  const _BuyerVideoCard({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 158),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _BuyerBenefitCard extends StatelessWidget {
  const _BuyerBenefitCard({required this.data});

  final _BuyerBenefitData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe2e3f3)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BuyerBenefitIcon(asset: data.iconAsset, size: 72, imageSize: 68),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HocalistTheme.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HocalistTheme.muted,
                    height: 1.2,
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

class _BuyerFairnessBanner extends StatelessWidget {
  const _BuyerFairnessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xffeef7f1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const _BuyerBenefitIcon(
            asset: 'assets/buyer_onboarding/benefit-green-shield.png',
            size: 58,
            imageSize: 54,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fair, transparent, and built for you.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HocalistTheme.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We\'re here to give you more value every time you buy.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyerBenefitIcon extends StatelessWidget {
  const _BuyerBenefitIcon({
    required this.asset,
    required this.size,
    required this.imageSize,
  });

  final String asset;
  final double size;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Image.asset(
          asset,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _BuyerBenefitData {
  const _BuyerBenefitData(this.iconAsset, this.title, this.body);

  final String iconAsset;
  final String title;
  final String body;
}

class BuyerDashboard extends StatelessWidget {
  const BuyerDashboard({
    required this.name,
    required this.accent,
    required this.requestTitle,
    required this.requestBudget,
    required this.requestPosted,
    required this.offerSelected,
    required this.meetingConfirmed,
    required this.dealFailed,
    required this.requestReopened,
    required this.dealCompleted,
    required this.withdrawalRequested,
    required this.restoredSession,
    required this.onCreate,
    required this.onRequestDetails,
    required this.onOffers,
    required this.onRecentActivity,
    required this.onWallet,
    super.key,
  });

  final String name;
  final Color accent;
  final String requestTitle;
  final String requestBudget;
  final bool requestPosted;
  final bool offerSelected;
  final bool meetingConfirmed;
  final bool dealFailed;
  final bool requestReopened;
  final bool dealCompleted;
  final bool withdrawalRequested;
  final bool restoredSession;
  final VoidCallback onCreate;
  final VoidCallback onRequestDetails;
  final VoidCallback onOffers;
  final VoidCallback onRecentActivity;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().isEmpty
        ? 'Alex'
        : name.trim().split(RegExp(r'\s+')).first;
    final activeRequests = [
      _DashboardRequestData(
        requestPosted ? requestTitle : 'iPad Air 5, 256GB',
        requestPosted ? 'Just posted' : 'Posted on May 13',
        requestPosted ? '2 offers received' : '2 offers received',
      ),
      const _DashboardRequestData(
        'MacBook Pro M2',
        'Posted on May 12',
        '4 offers received',
      ),
      const _DashboardRequestData(
        'Dining table set',
        'Posted on May 11',
        '3 offers received',
      ),
      const _DashboardRequestData(
        'Weekend cleaning service',
        'Posted on May 10',
        '1 offer received',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BuyerDashboardHero(name: firstName),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final totalRewards = _RewardSummaryCard(
              title: 'Total rewards earned',
              amount: '\$128.45',
              detail: 'From 42 completed purchases',
              infoTitle: 'Total rewards earned',
              infoBody:
                  'This is the total reward amount you have earned from completed purchases in this preview account.',
              icon: Icons.emoji_events_outlined,
              iconColor: HocalistTheme.actionBlue,
              actionLabel: 'View all rewards',
              onTap: onWallet,
            );
            const pendingRewards = _PendingRewardsCard();
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final stackRewards = constraints.maxWidth < 350 || textScale > 1.15;
            final rewardRowHeight = constraints.maxWidth < 390 ? 270.0 : 258.0;

            if (stackRewards) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totalRewards,
                  const SizedBox(height: 10),
                  pendingRewards,
                ],
              );
            }

            return SizedBox(
              height: rewardRowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: totalRewards),
                  const SizedBox(width: 8),
                  const Expanded(child: pendingRewards),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        _PostNewRequestPanel(onTap: onCreate),
        const SizedBox(height: 18),
        for (final request in activeRequests.take(4)) ...[
          _ActiveRequestCard(
            data: request,
            onDetails: onRequestDetails,
            onOffers: onOffers,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        _DashboardSectionHeader(
          title: 'Recent activity',
          action: 'View all',
          onTap: onRecentActivity,
        ),
        const SizedBox(height: 12),
        _RecentActivityPanel(onTap: onRecentActivity),
        const SizedBox(height: 22),
        const _KeepEarningBanner(),
      ],
    );
  }
}

class _BuyerDashboardHero extends StatelessWidget {
  const _BuyerDashboardHero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final giftWidth = constraints.maxWidth < 360 ? 112.0 : 138.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Good morning, $name! '),
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.waving_hand_outlined,
                            color: Color(0xffffb300),
                            size: 25,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: HocalistTheme.primary,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You\'re earning rewards while sellers compete for your business.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: HocalistTheme.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: giftWidth,
              height: 104,
              child: Image.asset(
                'assets/buyer_dashboard/dashboard-gift-art.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RewardSummaryCard extends StatelessWidget {
  const _RewardSummaryCard({
    required this.title,
    required this.amount,
    required this.detail,
    required this.infoTitle,
    required this.infoBody,
    required this.icon,
    required this.iconColor,
    this.actionLabel,
    this.onTap,
  });

  final String title;
  final String amount;
  final String detail;
  final String infoTitle;
  final String infoBody;
  final IconData icon;
  final Color iconColor;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = constraints.maxWidth < 180 ? 36.0 : 44.0;
        return _DashboardCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: HocalistTheme.primary,
                        fontSize: HocalistTheme.smallSize,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  _RewardInfoButton(
                    title: infoTitle,
                    body: infoBody,
                    color: HocalistTheme.muted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        amount,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: HocalistTheme.actionBlue,
                              fontSize: HocalistTheme.metricSize,
                            ),
                      ),
                    ),
                  ),
                  _DashboardCircleIcon(
                    icon: icon,
                    color: iconColor,
                    background: HocalistTheme.roleSurface,
                    size: iconSize,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: HocalistTheme.muted),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 12),
                _DashboardPillButton(label: actionLabel!, onTap: onTap),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PendingRewardsCard extends StatelessWidget {
  const _PendingRewardsCard();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = constraints.maxWidth < 180 ? 36.0 : 44.0;
        return _DashboardCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Pending rewards',
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: HocalistTheme.primary,
                        fontSize: HocalistTheme.smallSize,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const _RewardInfoButton(
                    title: 'Pending rewards',
                    body:
                        'Pending rewards are earned but not ready for payout yet. This preview shows the next payout target and date.',
                    color: HocalistTheme.muted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '\$24.80',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: HocalistTheme.primary,
                              fontSize: HocalistTheme.metricSize,
                            ),
                      ),
                    ),
                  ),
                  _DashboardCircleIcon(
                    icon: Icons.calendar_month_outlined,
                    color: HocalistTheme.sellerGreen,
                    background: Color(0xffdbf4e9),
                    size: iconSize,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Pay date: May 20, 2025',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: HocalistTheme.muted),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: 0.992,
                  backgroundColor: HocalistTheme.roleSurface,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    HocalistTheme.actionBlue,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '\$24.80 of \$25.00',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: HocalistTheme.primary,
                  fontSize: HocalistTheme.smallSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$0.20 until next payout',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: HocalistTheme.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RewardInfoButton extends StatelessWidget {
  const _RewardInfoButton({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '$title info',
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: const Color(0x990B1231),
          builder: (sheetContext) {
            final media = MediaQuery.of(sheetContext);
            final metrics =
                ApprovedReplicaScope.maybeOf(sheetContext) ??
                ApprovedReplicaMetrics.resolve(
                  availableWidth: media.size.width,
                  textScaler: media.textScaler,
                );
            return BuyerModalSheet(
              icon: Icons.info_outline_rounded,
              iconColor: color,
              title: title,
              subtitle: 'Reward information',
              onClose: () => Navigator.pop(sheetContext),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    body,
                    style: BuyerTypography.style(
                      sheetContext,
                      metrics,
                      BuyerTextRole.primaryBody,
                      color: BuyerUiTokens.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  BuyerPrimaryButton(
                    label: 'Done',
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            );
          },
        );
      },
      icon: Icon(Icons.info_outline, color: color, size: 17),
    );
  }
}

class _PostNewRequestPanel extends StatelessWidget {
  const _PostNewRequestPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xfffbfaff),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffa997ff), width: 1.2),
            color: const Color(0xfffdfcff),
          ),
          child: Row(
            children: [
              const _DashboardCircleIcon(
                icon: Icons.add,
                color: Colors.white,
                background: HocalistTheme.actionBlue,
                size: 50,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Post a new request',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: HocalistTheme.actionBlue,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Need something else? Post another product or service.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: HocalistTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: HocalistTheme.actionBlue,
                size: 27,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({
    required this.data,
    required this.onDetails,
    required this.onOffers,
  });

  final _DashboardRequestData data;
  final VoidCallback onDetails;
  final VoidCallback onOffers;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tight = constraints.maxWidth < 360;
            final highText = MediaQuery.textScalerOf(context).scale(1) > 1.15;
            final iconSize = tight ? 56.0 : 62.0;
            final titleBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My active request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: HocalistTheme.sellerGreen,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.title,
                  maxLines: tight ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontSize: tight
                        ? HocalistTheme.prominentTitleSize
                        : HocalistTheme.sectionTitleSize,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data.date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
              ],
            );
            final offerCount = Semantics(
              button: true,
              label: 'View offers',
              child: InkWell(
                onTap: onOffers,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Text(
                    data.offerCount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
            final offerButton = _DashboardPillButton(
              label: 'View offers',
              onTap: onOffers,
            );

            if (tight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _DashboardCircleIcon(
                        icon: Icons.assignment_outlined,
                        color: HocalistTheme.sellerGreen,
                        background: const Color(0xffe5f7ea),
                        size: iconSize,
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: titleBlock),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (highText) ...[
                    offerCount,
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: offerButton),
                  ] else
                    Row(
                      children: [
                        Expanded(child: offerCount),
                        const SizedBox(width: 10),
                        offerButton,
                      ],
                    ),
                ],
              );
            }

            return Row(
              children: [
                _DashboardCircleIcon(
                  icon: Icons.assignment_outlined,
                  color: HocalistTheme.sellerGreen,
                  background: const Color(0xffe5f7ea),
                  size: iconSize,
                ),
                const SizedBox(width: 16),
                Expanded(child: titleBlock),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 136),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      offerCount,
                      const SizedBox(height: 6),
                      offerButton,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: HocalistTheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ActivityData(
        Icons.chat_bubble_outline,
        HocalistTheme.actionBlue,
        HocalistTheme.roleSurface,
        'Northside Tech sent you a new offer',
        '2 minutes ago',
        '\$420',
        HocalistTheme.sellerGreen,
      ),
      _ActivityData(
        Icons.check_circle_outline,
        HocalistTheme.sellerGreen,
        const Color(0xffe5f7ea),
        'Loop Resale accepted your request',
        '1 hour ago',
        '\$390',
        HocalistTheme.sellerGreen,
      ),
      _ActivityData(
        Icons.star,
        const Color(0xffffb300),
        const Color(0xfffff5dc),
        'You earned a new review',
        'Yesterday',
        '★★★★★',
        const Color(0xffffb300),
      ),
      _ActivityData(
        Icons.account_balance_wallet_outlined,
        HocalistTheme.actionBlue,
        HocalistTheme.roleSurface,
        'Rewards will be paid on May 20',
        '2 days ago',
        '\$24.80',
        HocalistTheme.actionBlue,
      ),
    ];

    return _DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _ActivityRow(data: items[index], onTap: onTap),
            if (index != items.length - 1)
              const Divider(height: 1, indent: 74, color: Color(0xffe5e7f3)),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.data, required this.onTap});

  final _ActivityData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            _DashboardCircleIcon(
              icon: data.icon,
              color: data.iconColor,
              background: data.background,
              size: 48,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: HocalistTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.time,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              data.trailing,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: data.trailingColor,
                fontSize: data.trailing.contains('★') ? 18 : 17,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right,
              color: HocalistTheme.muted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class RecentActivityPage extends StatefulWidget {
  const RecentActivityPage({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<RecentActivityPage> createState() => _RecentActivityPageState();
}

class _RecentActivityPageState extends State<RecentActivityPage> {
  String selectedTab = 'All';

  static const tabs = ['All', 'Offers', 'Rewards', 'Reviews', 'Payouts'];

  static const activities = [
    _RecentActivityData(
      category: 'Offers',
      icon: Icons.chat_bubble_outline,
      iconColor: HocalistTheme.actionBlue,
      background: HocalistTheme.roleSurface,
      title: 'Northside Tech sent you a new offer',
      time: '2 minutes ago',
      value: '\$420',
      valueColor: HocalistTheme.sellerGreen,
    ),
    _RecentActivityData(
      category: 'Offers',
      icon: Icons.check_circle_outline,
      iconColor: HocalistTheme.sellerGreen,
      background: Color(0xffe5f7ea),
      title: 'Loop Resale accepted your request',
      time: '1 hour ago',
      value: '\$390',
      valueColor: HocalistTheme.sellerGreen,
    ),
    _RecentActivityData(
      category: 'Reviews',
      icon: Icons.star,
      iconColor: Color(0xffffb300),
      background: Color(0xfffff5dc),
      title: 'You earned a new review',
      time: 'Yesterday',
      starRating: 5,
    ),
    _RecentActivityData(
      category: 'Payouts',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: HocalistTheme.actionBlue,
      background: HocalistTheme.roleSurface,
      title: 'Rewards will be paid on May 20',
      time: '2 days ago',
      value: '\$24.80',
      valueColor: HocalistTheme.actionBlue,
    ),
    _RecentActivityData(
      category: 'Rewards',
      icon: Icons.check_circle_outline,
      iconColor: HocalistTheme.sellerGreen,
      background: Color(0xffe5f7ea),
      title: 'Tech World NY confirmed your purchase',
      time: '3 days ago',
      value: '+ \$8.60',
      valueColor: HocalistTheme.sellerGreen,
    ),
    _RecentActivityData(
      category: 'Offers',
      icon: Icons.chat_bubble_outline,
      iconColor: HocalistTheme.actionBlue,
      background: HocalistTheme.roleSurface,
      title: 'Gadget Hub sent you a new offer',
      time: '4 days ago',
      value: '\$350',
      valueColor: HocalistTheme.sellerGreen,
    ),
    _RecentActivityData(
      category: 'Reviews',
      icon: Icons.star,
      iconColor: Color(0xffffb300),
      background: Color(0xfffff5dc),
      title: 'You earned a new review',
      time: '5 days ago',
      starRating: 5,
    ),
    _RecentActivityData(
      category: 'Payouts',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: HocalistTheme.actionBlue,
      background: HocalistTheme.roleSurface,
      title: 'Rewards will be paid on May 13',
      time: '6 days ago',
      value: '\$19.40',
      valueColor: HocalistTheme.actionBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visible = selectedTab == 'All'
        ? activities
        : activities.where((item) => item.category == selectedTab).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecentActivityHeader(onBack: widget.onBack),
        const SizedBox(height: 24),
        _RecentActivityTabs(
          tabs: tabs,
          selected: selectedTab,
          onChanged: (value) => setState(() => selectedTab = value),
        ),
        const SizedBox(height: 28),
        for (var index = 0; index < visible.length; index++) ...[
          _RecentActivityListRow(data: visible[index]),
          if (index != visible.length - 1)
            const Divider(height: 36, color: Color(0xffe6e8f2)),
        ],
      ],
    );
  }
}

class _RecentActivityHeader extends StatelessWidget {
  const _RecentActivityHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to home',
          onPressed: onBack,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          icon: const Icon(
            Icons.arrow_back,
            color: HocalistTheme.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Recent activity',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: HocalistTheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentActivityTabs extends StatelessWidget {
  const _RecentActivityTabs({
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<String> tabs;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showScrollHint = constraints.maxWidth < 520;

        return SizedBox(
          height: 58,
          child: Stack(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xffdddff0)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in tabs)
                        _RecentActivityTab(
                          label: tab,
                          selected: selected == tab,
                          onTap: () => onChanged(tab),
                        ),
                    ],
                  ),
                ),
              ),
              if (showScrollHint)
                Positioned(
                  top: 13,
                  right: 4,
                  child: IgnorePointer(
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xffdddff0)),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: HocalistTheme.muted,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentActivityTab extends StatelessWidget {
  const _RecentActivityTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 96, minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? HocalistTheme.actionBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? Colors.white : HocalistTheme.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RecentActivityListRow extends StatelessWidget {
  const _RecentActivityListRow({required this.data});

  final _RecentActivityData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 430;
        final iconSize = tight ? 58.0 : 66.0;
        final trailing = _RecentActivityTrailing(data: data, compact: tight);
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              maxLines: tight ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: HocalistTheme.primary,
                fontWeight: FontWeight.w800,
                height: 1.28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.time,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HocalistTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (tight) ...[const SizedBox(height: 10), trailing],
          ],
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _DashboardCircleIcon(
              icon: data.icon,
              color: data.iconColor,
              background: data.background,
              size: iconSize,
            ),
            SizedBox(width: tight ? 14 : 22),
            Expanded(child: titleBlock),
            if (!tight) ...[
              const SizedBox(width: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RecentActivityTrailing extends StatelessWidget {
  const _RecentActivityTrailing({required this.data, required this.compact});

  final _RecentActivityData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (data.starRating != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < data.starRating!; index++)
            Icon(
              Icons.star,
              color: const Color(0xffffb300),
              size: compact ? 17 : 20,
            ),
        ],
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        data.value ?? '',
        maxLines: 1,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: data.valueColor ?? HocalistTheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecentActivityData {
  const _RecentActivityData({
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.title,
    required this.time,
    this.value,
    this.valueColor,
    this.starRating,
  });

  final String category;
  final IconData icon;
  final Color iconColor;
  final Color background;
  final String title;
  final String time;
  final String? value;
  final Color? valueColor;
  final int? starRating;
}

class _KeepEarningBanner extends StatelessWidget {
  const _KeepEarningBanner();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackContent = constraints.maxWidth < 360;
        final badgeSize = stackContent ? 46.0 : 58.0;
        final artwork = SizedBox(
          width: stackContent ? double.infinity : 148,
          height: stackContent ? 100 : 104,
          child: Image.asset(
            'assets/buyer_dashboard/reward-network-art.png',
            fit: BoxFit.contain,
            alignment: stackContent ? Alignment.topCenter : Alignment.center,
            filterQuality: FilterQuality.high,
          ),
        );
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep earning more rewards',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: HocalistTheme.actionBlue,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sellers pay to reach you. Buy from any seller within 5 days to earn rewards from all of them.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HocalistTheme.muted,
                height: 1.35,
              ),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.fromLTRB(18, 18, stackContent ? 18 : 12, 18),
          decoration: BoxDecoration(
            color: HocalistTheme.roleSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: stackContent
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DashboardCircleIcon(
                          icon: Icons.workspace_premium_outlined,
                          color: HocalistTheme.actionBlue,
                          background: const Color(0xffe6e3ff),
                          size: badgeSize,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: copy),
                      ],
                    ),
                    const SizedBox(height: 6),
                    artwork,
                  ],
                )
              : Row(
                  children: [
                    _DashboardCircleIcon(
                      icon: Icons.workspace_premium_outlined,
                      color: HocalistTheme.actionBlue,
                      background: const Color(0xffe6e3ff),
                      size: badgeSize,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: copy),
                    const SizedBox(width: 8),
                    artwork,
                  ],
                ),
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: HocalistTheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xffe5e6f2)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashboardCircleIcon extends StatelessWidget {
  const _DashboardCircleIcon({
    required this.icon,
    required this.color,
    required this.background,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class _DashboardPillButton extends StatelessWidget {
  const _DashboardPillButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistTheme.roleSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: HocalistTheme.actionBlue,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: HocalistTheme.actionBlue,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardRequestData {
  const _DashboardRequestData(this.title, this.date, this.offerCount);

  final String title;
  final String date;
  final String offerCount;
}

class _ActivityData {
  const _ActivityData(
    this.icon,
    this.iconColor,
    this.background,
    this.title,
    this.time,
    this.trailing,
    this.trailingColor,
  );

  final IconData icon;
  final Color iconColor;
  final Color background;
  final String title;
  final String time;
  final String trailing;
  final Color trailingColor;
}

enum _RequestKind { product, service }

enum _CreateRequestStep { details, location }

const _postRequestBlue = Color(0xff2017ff);
const _postRequestText = Color(0xff11155e);
const _postRequestMuted = Color(0xff5e6684);
const _postRequestBorder = Color(0xffdfe2ee);
const _postRequestProgressTrack = Color(0xffd8dae4);
const _postIconKindProduct = 'assets/post_request/kind-product.png';
const _postIconKindService = 'assets/post_request/kind-service.png';
const _postIconTitleTag = 'assets/post_request/field-title-tag.png';
const _postIconDescription = 'assets/post_request/field-description.png';
const _postIconCondition = 'assets/post_request/panel-condition.png';
const _postIconServiceType = 'assets/post_request/panel-service-type.png';
const _postIconBudget = 'assets/post_request/panel-budget.png';
const _postIconQuantity = 'assets/post_request/panel-quantity.png';
const _postIconCategory = 'assets/post_request/panel-category.png';
const _postIconHigherOffers = 'assets/post_request/panel-higher-offers.png';
const _postIconChoiceNew = 'assets/post_request/choice-new.png';
const _postIconChoiceUsed = 'assets/post_request/choice-used.png';
const _postIconChoiceOneTime = 'assets/post_request/choice-one-time.png';
const _postIconChoiceOngoing = 'assets/post_request/choice-ongoing.png';
const _postIconPriceMin = 'assets/post_request/price-min.png';
const _postIconPriceMax = 'assets/post_request/price-max.png';
const _postIconCategoryGrid = 'assets/post_request/category-grid.png';
const _postIconCategoryDown = 'assets/post_request/category-down.png';
const _postIconInfo = 'assets/post_request/info.png';
const _postIconSend = 'assets/post_request/button-send.png';
const _postIconLocationHome = 'assets/post_request/location-home.png';
const _postIconLocationRadioSelected =
    'assets/post_request/location-radio-selected.png';

class HocatrendsPage extends StatelessWidget {
  const HocatrendsPage({
    required this.accent,
    required this.onSeeSellers,
    super.key,
  });

  final Color accent;
  final VoidCallback onSeeSellers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HocatrendsHero(),
        const SizedBox(height: 18),
        const _HocatrendsSavingsNotice(),
        const SizedBox(height: 20),
        const _HocatrendsSearchBar(),
        const SizedBox(height: 24),
        const _HocatrendsSectionHeader(),
        const SizedBox(height: 12),
        _HocatrendsCategoryList(onSeeSellers: onSeeSellers),
      ],
    );
  }
}

class _HocatrendsHero extends StatelessWidget {
  const _HocatrendsHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final titleSize = (constraints.maxWidth * 0.072).clamp(24.0, 32.0);
        final bodySize = (constraints.maxWidth * 0.043).clamp(14.0, 17.0);
        final artWidth = (constraints.maxWidth * 0.39).clamp(112.0, 160.0);
        final artHeight = artWidth / 1.125;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 7,
              runSpacing: 3,
              children: [
                Text(
                  'Saving',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontSize: titleSize,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Opportunities',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: HocalistTheme.actionBlue,
                    fontSize: titleSize,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Icon(
                  Icons.trending_up,
                  color: HocalistTheme.actionBlue,
                  size: compact ? 22 : 30,
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(
              'Explore verified sellers offering\ndiscounts on products & services.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: HocalistTheme.muted,
                fontSize: bodySize,
                height: compact ? 1.42 : 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

        final art = Image.asset(
          'assets/hocatrends/gift-offers-transparent.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            Transform.translate(
              offset: Offset(0, compact ? -4 : -6),
              child: SizedBox(width: artWidth, height: artHeight, child: art),
            ),
          ],
        );
      },
    );
  }
}

class _HocatrendsSavingsNotice extends StatelessWidget {
  const _HocatrendsSavingsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfff2f0ff),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xffe2dcff),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: HocalistTheme.actionBlue,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skip the Rewards & save on current offers',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Hocatrends shows exclusive offers and discounts created by sellers for other buyers.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: HocalistTheme.muted,
                    height: 1.45,
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

class _HocatrendsSearchBar extends StatelessWidget {
  const _HocatrendsSearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffdddaf3), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1000036c),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: HocalistTheme.muted, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Search products or services',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: HocalistTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.tune, color: HocalistTheme.actionBlue, size: 31),
        ],
      ),
    );
  }
}

class _HocatrendsSectionHeader extends StatelessWidget {
  const _HocatrendsSectionHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: HocalistTheme.primary,
          fontWeight: FontWeight.w800,
          height: 1.12,
        );
        final title = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/hocatrends/competitive-flame.png',
              width: compact ? 26 : 30,
              height: compact ? 30 : 34,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Most Competitive Categories\n'),
                    TextSpan(
                      text: 'Today',
                      style: titleStyle?.copyWith(color: HocalistTheme.primary),
                    ),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(
                          Icons.info_outline,
                          color: HocalistTheme.muted,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ],
        );
        final action = Semantics(
          button: true,
          label: 'How it works',
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(999),
            child: compact
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.help_outline,
                      color: HocalistTheme.actionBlue,
                      size: 22,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'How it works',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: HocalistTheme.actionBlue),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          color: HocalistTheme.actionBlue,
                          size: 17,
                        ),
                      ],
                    ),
                  ),
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            action,
          ],
        );
      },
    );
  }
}

class _HocatrendsCategoryList extends StatelessWidget {
  const _HocatrendsCategoryList({required this.onSeeSellers});

  final VoidCallback onSeeSellers;

  static const items = [
    _HocatrendsCategoryData(
      rank: 1,
      title: 'iPad Air',
      competition: 'Very High',
      percent: 0.96,
      percentLabel: '96%',
      sellers: '23 sellers are actively competing for iPad buyers.',
      asset: 'assets/hocatrends/ipad-air.png',
      rankColor: Color(0xffffbc1b),
      progressColor: HocalistTheme.actionBlue,
      hot: true,
    ),
    _HocatrendsCategoryData(
      rank: 2,
      title: 'Gaming Laptops',
      competition: 'High',
      percent: 0.82,
      percentLabel: '82%',
      sellers: '17 sellers are actively competing for laptop buyers.',
      asset: 'assets/hocatrends/gaming-laptop.png',
      rankColor: Color(0xffeff0fa),
      progressColor: HocalistTheme.actionBlue,
      hot: true,
    ),
    _HocatrendsCategoryData(
      rank: 3,
      title: 'Pressure Washing',
      competition: 'High',
      percent: 0.74,
      percentLabel: '74%',
      sellers: '14 businesses are actively competing for new customers.',
      asset: 'assets/hocatrends/pressure-washer.png',
      rankColor: Color(0xffff7431),
      progressColor: HocalistTheme.actionBlue,
      hot: true,
    ),
    _HocatrendsCategoryData(
      rank: 4,
      title: 'Living Room Furniture',
      competition: 'Medium',
      percent: 0.58,
      percentLabel: '58%',
      sellers: '9 sellers are actively competing for furniture buyers.',
      asset: 'assets/hocatrends/living-room-furniture.png',
      rankColor: Color(0xffeff0fa),
      progressColor: Color(0xffffa600),
    ),
    _HocatrendsCategoryData(
      rank: 5,
      title: 'Used SUVs',
      competition: 'Medium',
      percent: 0.46,
      percentLabel: '46%',
      sellers: '6 dealerships are actively competing for SUV buyers.',
      asset: 'assets/hocatrends/used-suv.png',
      rankColor: Color(0xffeff0fa),
      progressColor: Color(0xffffa600),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items) ...[
          _HocatrendsCategoryCard(data: item, onSeeSellers: onSeeSellers),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _HocatrendsCategoryCard extends StatelessWidget {
  const _HocatrendsCategoryCard({
    required this.data,
    required this.onSeeSellers,
  });

  final _HocatrendsCategoryData data;
  final VoidCallback onSeeSellers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffeeeef7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0f00036c),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final copy = _HocatrendsCategoryCopy(
            data: data,
            showSellerCount: !compact,
          );
          final sellerCount = _HocatrendsSellerCount(data: data);
          final button = _HocatrendsSellerButton(onPressed: onSeeSellers);
          final leading = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HocatrendsRankBadge(data: data, compact: compact),
              SizedBox(width: compact ? 8 : 10),
              _HocatrendsProductImage(asset: data.asset, compact: compact),
              SizedBox(width: compact ? 12 : 14),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 10),
                sellerCount,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              Expanded(child: copy),
              const SizedBox(width: 10),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _HocatrendsCategoryCopy extends StatelessWidget {
  const _HocatrendsCategoryCopy({
    required this.data,
    this.showSellerCount = true,
  });

  final _HocatrendsCategoryData data;
  final bool showSellerCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 210;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: HocalistTheme.primary,
                fontSize: compact ? 18 : null,
                fontWeight: FontWeight.w900,
                height: 1.12,
              ),
            ),
            SizedBox(height: compact ? 8 : 7),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5,
              runSpacing: 2,
              children: [
                Text(
                  'Competition: ${data.competition}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontSize: compact ? 12 : null,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _HocatrendsCompetitionIcon(data: data),
              ],
            ),
            SizedBox(height: compact ? 12 : 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: data.percent,
                      minHeight: compact ? 8 : 9,
                      color: data.progressColor,
                      backgroundColor: const Color(0xffe6e6ef),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    data.percentLabel,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: HocalistTheme.actionBlue,
                      fontSize: compact ? 12 : null,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (showSellerCount) ...[
              SizedBox(height: compact ? 10 : 9),
              _HocatrendsSellerCount(data: data, compact: compact),
            ],
          ],
        );
      },
    );
  }
}

class _HocatrendsRankBadge extends StatelessWidget {
  const _HocatrendsRankBadge({required this.data, this.compact = false});

  final _HocatrendsCategoryData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final darkText = data.rank == 1 || data.rank == 3;
    final size = compact ? 36.0 : 38.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: data.rankColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${data.rank}',
        style: TextStyle(
          color: darkText ? HocalistTheme.primary : const Color(0xff252a5f),
          fontSize: compact ? 17 : 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HocatrendsProductImage extends StatelessWidget {
  const _HocatrendsProductImage({required this.asset, this.compact = false});

  final String asset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 62 : 82,
      height: compact ? 82 : 104,
      child: Align(
        alignment: Alignment.center,
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _HocatrendsSellerCount extends StatelessWidget {
  const _HocatrendsSellerCount({required this.data, this.compact = false});

  final _HocatrendsCategoryData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.people_outline, color: HocalistTheme.muted, size: 17),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            data.sellers,
            maxLines: compact ? 3 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: HocalistTheme.muted,
              fontSize: compact ? 12 : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HocatrendsCompetitionIcon extends StatelessWidget {
  const _HocatrendsCompetitionIcon({required this.data});

  final _HocatrendsCategoryData data;

  @override
  Widget build(BuildContext context) {
    if (data.hot) {
      return Image.asset(
        'assets/hocatrends/competitive-flame.png',
        width: 20,
        height: 22,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    return Icon(Icons.bar_chart, color: data.progressColor, size: 18);
  }
}

class _HocatrendsSellerButton extends StatelessWidget {
  const _HocatrendsSellerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: HocalistTheme.actionBlue,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'See Sellers',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _HocatrendsCategoryData {
  const _HocatrendsCategoryData({
    required this.rank,
    required this.title,
    required this.competition,
    required this.percent,
    required this.percentLabel,
    required this.sellers,
    required this.asset,
    required this.rankColor,
    required this.progressColor,
    this.hot = false,
  });

  final int rank;
  final String title;
  final String competition;
  final double percent;
  final String percentLabel;
  final String sellers;
  final String asset;
  final Color rankColor;
  final Color progressColor;
  final bool hot;
}

class HocatrendsSellersPage extends StatefulWidget {
  const HocatrendsSellersPage({
    required this.onBack,
    required this.onChatSeller,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onChatSeller;

  @override
  State<HocatrendsSellersPage> createState() => _HocatrendsSellersPageState();
}

class _HocatrendsSellersPageState extends State<HocatrendsSellersPage> {
  bool filtersOn = false;
  bool gridView = false;
  String sortLabel = 'Best deal';

  static const sellers = [
    _HocatrendsSellerData(
      name: 'Northside Tech',
      initials: 'GH',
      rating: '4.9 (128 reviews)',
      location: 'Yonkers, NY',
      distance: '2.1 mi',
      price: '\$820',
      savings: 'Save \$180',
      badge: 'Top Rated Seller',
      badgeIcon: Icons.emoji_events_outlined,
      badgeColor: HocalistTheme.actionBlue,
      deals: '230+ deals completed',
      response: 'Usually responds in a few hours',
      avatarAsset: null,
      online: true,
    ),
    _HocatrendsSellerData(
      name: 'Gadget Hub',
      initials: 'GH',
      rating: '4.7 (96 reviews)',
      location: 'Yonkers, NY',
      distance: '3.4 mi',
      price: '\$835',
      savings: 'Save \$165',
      badge: 'Great Deal',
      badgeIcon: Icons.sell_outlined,
      badgeColor: HocalistTheme.sellerGreen,
      deals: '150+ deals completed',
      response: 'Responds within 2 hours',
      avatarAsset: null,
      online: true,
    ),
    _HocatrendsSellerData(
      name: 'Prime Tech Solutions',
      initials: 'GH',
      rating: '4.6 (78 reviews)',
      location: 'Yonkers, NY',
      distance: '4.7 mi',
      price: '\$845',
      savings: 'Save \$155',
      badge: 'Fast Responder',
      badgeIcon: Icons.flash_on_outlined,
      badgeColor: Color(0xff1769ff),
      deals: '120+ deals completed',
      response: 'Usually responds in a few hours',
      avatarAsset: null,
      online: true,
    ),
    _HocatrendsSellerData(
      name: 'Tech World NY',
      initials: 'GH',
      rating: '4.5 (64 reviews)',
      location: 'Yonkers, NY',
      distance: '5.2 mi',
      price: '\$860',
      savings: 'Save \$140',
      badge: 'Good Value',
      badgeIcon: Icons.star,
      badgeColor: Color(0xffff9900),
      deals: '90+ deals completed',
      response: 'Responds within 3 hours',
      avatarAsset: null,
      online: true,
    ),
    _HocatrendsSellerData(
      name: 'Digital Depot',
      initials: 'GH',
      rating: '4.4 (52 reviews)',
      location: 'Yonkers, NY',
      distance: '6.0 mi',
      price: '\$875',
      savings: 'Save \$125',
      badge: 'Trusted Seller',
      badgeIcon: Icons.verified_user_outlined,
      badgeColor: HocalistTheme.actionBlue,
      deals: '110+ deals completed',
      response: 'Usually responds in a few hours',
      avatarAsset: null,
      online: true,
    ),
  ];

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HocatrendsSellersHeader(onBack: widget.onBack),
        const SizedBox(height: 22),
        const _HocatrendsSellersProductSummary(),
        const SizedBox(height: 22),
        _HocatrendsSellerControls(
          filtersOn: filtersOn,
          sortLabel: sortLabel,
          gridView: gridView,
          onFilters: () {
            setState(() => filtersOn = !filtersOn);
            showMessage(filtersOn ? 'Filters enabled.' : 'Filters cleared.');
          },
          onSortChanged: (value) {
            setState(() => sortLabel = value);
            showMessage('Sorted by $value.');
          },
          onViewChanged: (value) {
            setState(() => gridView = value);
            showMessage(value ? 'Grid view selected.' : 'List view selected.');
          },
        ),
        if (filtersOn) ...[
          const SizedBox(height: 12),
          const _HocatrendsActiveFilterBar(),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            if (gridView && constraints.maxWidth >= 360) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sellers.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth >= 620 ? 3 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: constraints.maxWidth >= 620 ? 250 : 268,
                ),
                itemBuilder: (context, index) {
                  return _HocatrendsSellerGridCard(
                    seller: sellers[index],
                    onChat: widget.onChatSeller,
                  );
                },
              );
            }

            return Column(
              children: [
                for (final seller in sellers) ...[
                  _HocatrendsSellerCard(
                    seller: seller,
                    onChat: widget.onChatSeller,
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HocatrendsSellersHeader extends StatelessWidget {
  const _HocatrendsSellersHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to Hocatrends',
          onPressed: onBack,
          icon: const Icon(
            Icons.arrow_back,
            color: HocalistTheme.primary,
            size: 30,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              Text(
                'iPad Air Sellers',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: HocalistTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '23 sellers are offering deals',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: HocalistTheme.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 46),
      ],
    );
  }
}

class _HocatrendsSellersProductSummary extends StatelessWidget {
  const _HocatrendsSellersProductSummary();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final imageWidth = (constraints.maxWidth * (compact ? 0.27 : 0.23))
            .clamp(76.0, 118.0);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: imageWidth,
              height: imageWidth * 1.25,
              child: Image.asset(
                'assets/hocatrends/ipad-air.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            SizedBox(width: compact ? 16 : 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'iPad Air',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: HocalistTheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Category: Tablets',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: HocalistTheme.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _HocatrendsCompetitionPill(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HocatrendsCompetitionPill extends StatelessWidget {
  const _HocatrendsCompetitionPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HocalistTheme.roleSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
            color: Color(0xffff3028),
            size: 19,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Competition: Very High',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: HocalistTheme.actionBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HocatrendsSellerControls extends StatelessWidget {
  const _HocatrendsSellerControls({
    required this.filtersOn,
    required this.sortLabel,
    required this.gridView,
    required this.onFilters,
    required this.onSortChanged,
    required this.onViewChanged,
  });

  final bool filtersOn;
  final String sortLabel;
  final bool gridView;
  final VoidCallback onFilters;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 430;
        final filter = _HocatrendsControlButton(
          icon: Icons.tune,
          label: 'Filters',
          selected: filtersOn,
          onTap: onFilters,
        );
        final sort = PopupMenuButton<String>(
          tooltip: 'Sort sellers',
          initialValue: sortLabel,
          onSelected: onSortChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'Best deal', child: Text('Best deal')),
            PopupMenuItem(value: 'Lowest price', child: Text('Lowest price')),
            PopupMenuItem(value: 'Nearest', child: Text('Nearest')),
          ],
          child: _HocatrendsSortButton(label: 'Sort by: $sortLabel'),
        );
        final compactSort = PopupMenuButton<String>(
          tooltip: 'Sort by $sortLabel',
          initialValue: sortLabel,
          onSelected: onSortChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'Best deal', child: Text('Best deal')),
            PopupMenuItem(value: 'Lowest price', child: Text('Lowest price')),
            PopupMenuItem(value: 'Nearest', child: Text('Nearest')),
          ],
          child: _HocatrendsSortIconButton(label: sortLabel),
        );
        final toggle = _HocatrendsViewToggle(
          gridView: gridView,
          onChanged: onViewChanged,
        );

        if (tight) {
          return Row(
            children: [
              filter,
              const Spacer(),
              toggle,
              const SizedBox(width: 8),
              compactSort,
            ],
          );
        }

        return Row(
          children: [
            filter,
            const SizedBox(width: 10),
            Flexible(flex: 2, child: sort),
            const SizedBox(width: 10),
            toggle,
          ],
        );
      },
    );
  }
}

class _HocatrendsControlButton extends StatelessWidget {
  const _HocatrendsControlButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(112, 56),
        foregroundColor: HocalistTheme.primary,
        backgroundColor: selected ? HocalistTheme.roleSurface : Colors.white,
        side: const BorderSide(color: Color(0xffdddff0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HocatrendsSortIconButton extends StatelessWidget {
  const _HocatrendsSortIconButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sort by $label',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffdddff0)),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.sort,
          color: HocalistTheme.actionBlue,
          size: 27,
        ),
      ),
    );
  }
}

class _HocatrendsSortButton extends StatelessWidget {
  const _HocatrendsSortButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 168, minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdddff0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: HocalistTheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down, color: HocalistTheme.primary),
        ],
      ),
    );
  }
}

class _HocatrendsViewToggle extends StatelessWidget {
  const _HocatrendsViewToggle({
    required this.gridView,
    required this.onChanged,
  });

  final bool gridView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdddff0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HocatrendsViewButton(
            icon: Icons.format_list_bulleted,
            selected: !gridView,
            onTap: () => onChanged(false),
          ),
          _HocatrendsViewButton(
            icon: Icons.grid_view_outlined,
            selected: gridView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _HocatrendsViewButton extends StatelessWidget {
  const _HocatrendsViewButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? HocalistTheme.roleSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: HocalistTheme.actionBlue, size: 26),
      ),
    );
  }
}

class _HocatrendsActiveFilterBar extends StatelessWidget {
  const _HocatrendsActiveFilterBar();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        SoftChip(
          label: 'Verified sellers',
          color: HocalistTheme.roleSurface,
          foreground: HocalistTheme.primary,
        ),
        SoftChip(
          label: 'Within 6 mi',
          color: HocalistTheme.roleSurface,
          foreground: HocalistTheme.primary,
        ),
        SoftChip(
          label: 'Saves \$125+',
          color: Color(0xffe7f7ec),
          foreground: HocalistTheme.sellerGreen,
        ),
      ],
    );
  }
}

class _HocatrendsSellerCard extends StatelessWidget {
  const _HocatrendsSellerCard({required this.seller, required this.onChat});

  final _HocatrendsSellerData seller;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe7e9f4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1000036c),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 390;
          final veryTight = constraints.maxWidth < 340;
          final identity = _HocatrendsSellerIdentity(
            seller: seller,
            compact: tight,
          );
          final price = _HocatrendsSellerPrice(seller: seller, compact: tight);
          final badge = _HocatrendsSellerBadge(seller: seller, compact: tight);
          final chat = _HocatrendsChatButton(
            onPressed: onChat,
            fullWidth: tight,
          );

          if (tight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: badge),
                const SizedBox(height: 16),
                price,
                const SizedBox(height: 12),
                chat,
                const SizedBox(height: 14),
                _HocatrendsSellerStats(seller: seller, stacked: veryTight),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  badge,
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [price, const SizedBox(width: 22), chat],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              _HocatrendsSellerStats(seller: seller),
            ],
          );
        },
      ),
    );
  }
}

class _HocatrendsSellerIdentity extends StatelessWidget {
  const _HocatrendsSellerIdentity({
    required this.seller,
    required this.compact,
  });

  final _HocatrendsSellerData seller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 66.0 : 78.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HocatrendsSellerAvatar(seller: seller, size: avatarSize),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      seller.name,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: HocalistTheme.primary,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.verified,
                    color: HocalistTheme.actionBlue,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.star, color: Color(0xffffb000), size: 18),
                  Text(
                    seller.rating,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(
                    seller.location,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    seller.distance,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HocatrendsSellerAvatar extends StatelessWidget {
  const _HocatrendsSellerAvatar({required this.seller, required this.size});

  final _HocatrendsSellerData seller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = seller.avatarAsset == null
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xff2c1648),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xffefe9ff), width: 1),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seller.initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size >= 70
                        ? HocalistTheme.sectionTitleSize
                        : HocalistTheme.prominentTitleSize,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'GADGET HUB',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: HocalistTheme.smallSize,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : ClipOval(
            child: Image.asset(
              seller.avatarAsset!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (seller.online)
          Positioned(
            right: -1,
            bottom: 2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xff20b42e),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
      ],
    );
  }
}

class _HocatrendsSellerBadge extends StatelessWidget {
  const _HocatrendsSellerBadge({required this.seller, required this.compact});

  final _HocatrendsSellerData seller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 128 : 178),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: seller.badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            seller.badgeIcon,
            color: seller.badgeColor,
            size: compact ? 17 : 19,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              seller.badge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: seller.badgeColor,
                fontWeight: FontWeight.w900,
                fontSize: compact ? HocalistTheme.smallSize : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HocatrendsSellerPrice extends StatelessWidget {
  const _HocatrendsSellerPrice({required this.seller, required this.compact});

  final _HocatrendsSellerData seller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            seller.price,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: HocalistTheme.primary,
              fontSize: HocalistTheme.pageTitleSize,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xffe8f7ed),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              seller.savings,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: HocalistTheme.sellerGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          seller.price,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: HocalistTheme.primary,
            fontSize: HocalistTheme.metricSize,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          seller.savings,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: HocalistTheme.sellerGreen,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HocatrendsChatButton extends StatelessWidget {
  const _HocatrendsChatButton({
    required this.onPressed,
    required this.fullWidth,
  });

  final VoidCallback onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : 150,
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.chat_bubble_outline, size: 22),
        label: const Text('Chat Seller'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff2716ff),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: HocalistTheme.buttonSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HocatrendsSellerStats extends StatelessWidget {
  const _HocatrendsSellerStats({required this.seller, this.stacked = false});

  final _HocatrendsSellerData seller;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final deal = _HocatrendsSellerStat(
      icon: Icons.people_outline,
      label: seller.deals,
    );
    final response = _HocatrendsSellerStat(
      icon: Icons.chat_bubble_outline,
      label: seller.response,
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [deal, const SizedBox(height: 8), response],
      );
    }

    return Row(
      children: [
        Expanded(child: deal),
        const SizedBox(width: 12),
        Expanded(child: response),
      ],
    );
  }
}

class _HocatrendsSellerStat extends StatelessWidget {
  const _HocatrendsSellerStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: HocalistTheme.muted, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: HocalistTheme.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HocatrendsSellerGridCard extends StatelessWidget {
  const _HocatrendsSellerGridCard({required this.seller, required this.onChat});

  final _HocatrendsSellerData seller;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe7e9f4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d00036c),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HocatrendsSellerAvatar(seller: seller, size: 54),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  seller.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HocatrendsSellerBadge(seller: seller, compact: true),
          const Spacer(),
          _HocatrendsSellerPrice(seller: seller, compact: true),
          const SizedBox(height: 10),
          _HocatrendsChatButton(onPressed: onChat, fullWidth: true),
        ],
      ),
    );
  }
}

class _HocatrendsSellerData {
  const _HocatrendsSellerData({
    required this.name,
    required this.initials,
    required this.rating,
    required this.location,
    required this.distance,
    required this.price,
    required this.savings,
    required this.badge,
    required this.badgeIcon,
    required this.badgeColor,
    required this.deals,
    required this.response,
    required this.avatarAsset,
    this.online = false,
  });

  final String name;
  final String initials;
  final String? avatarAsset;
  final String rating;
  final String location;
  final String distance;
  final String price;
  final String savings;
  final String badge;
  final IconData badgeIcon;
  final Color badgeColor;
  final String deals;
  final String response;
  final bool online;
}

class CreateRequestPage extends StatefulWidget {
  const CreateRequestPage({
    required this.accent,
    required this.requestTitle,
    required this.budget,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onBack,
    required this.onNotifications,
    required this.onSubmit,
    super.key,
  });

  final Color accent;
  final String requestTitle;
  final String budget;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onSubmit;

  @override
  State<CreateRequestPage> createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends State<CreateRequestPage> {
  _RequestKind kind = _RequestKind.product;
  _CreateRequestStep step = _CreateRequestStep.details;
  int quantity = 1;
  bool flexibleOffers = true;
  bool useHomeAddress = true;
  String condition = 'New';
  String serviceType = 'One-time';
  String minPrice = '';
  String maxPrice = '';

  bool get isProduct => kind == _RequestKind.product;
  bool get isLocation => step == _CreateRequestStep.location;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: HocalistTheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Post a new request',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: HocalistTheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!isLocation) _requestKindPicker(),
              if (!isLocation) const SizedBox(height: 26),
              _RequestStepProgress(currentStep: step),
              const SizedBox(height: 30),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLocation
                    ? _LocationRequestStep(
                        key: const ValueKey('location-step'),
                        useHomeAddress: useHomeAddress,
                        onUseHomeAddressChanged: (value) {
                          setState(() => useHomeAddress = value);
                        },
                        onBack: () {
                          setState(() => step = _CreateRequestStep.details);
                        },
                        onSubmit: widget.onSubmit,
                      )
                    : _DetailsRequestStep(
                        key: ValueKey(kind),
                        kind: kind,
                        requestTitle: widget.requestTitle,
                        budget: widget.budget,
                        quantity: quantity,
                        flexibleOffers: flexibleOffers,
                        selectedChoice: isProduct ? condition : serviceType,
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        onTitleChanged: widget.onTitleChanged,
                        onBudgetChanged: widget.onBudgetChanged,
                        onChoiceChanged: (value) {
                          setState(() {
                            if (isProduct) {
                              condition = value;
                            } else {
                              serviceType = value;
                            }
                          });
                        },
                        onMinPriceChanged: (value) {
                          setState(() => minPrice = value);
                        },
                        onMaxPriceChanged: (value) {
                          setState(() => maxPrice = value);
                        },
                        onQuantityChanged: (value) {
                          setState(() => quantity = value.clamp(1, 99));
                        },
                        onFlexibleOffersChanged: (value) {
                          setState(() => flexibleOffers = value);
                        },
                        onBack: widget.onBack,
                        onContinue: () {
                          setState(() => step = _CreateRequestStep.location);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestKindPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final product = _RequestKindCard(
          selected: isProduct,
          iconAsset: _postIconKindProduct,
          title: 'Product',
          subtitle: 'I want to buy a product',
          onTap: () => setState(() => kind = _RequestKind.product),
        );
        final service = _RequestKindCard(
          selected: !isProduct,
          iconAsset: _postIconKindService,
          title: 'Service',
          subtitle: 'I need a service',
          onTap: () => setState(() => kind = _RequestKind.service),
        );
        if (narrow) {
          return Column(
            children: [product, const SizedBox(height: 12), service],
          );
        }
        return Row(
          children: [
            Expanded(child: product),
            const SizedBox(width: 14),
            Expanded(child: service),
          ],
        );
      },
    );
  }
}

class _PostRequestImageIcon extends StatelessWidget {
  const _PostRequestImageIcon({
    required this.asset,
    this.size = 24,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (asset == _postIconSend) {
      return Icon(
        Icons.send_rounded,
        size: size,
        color: Colors.white,
        semanticLabel: semanticLabel,
      );
    }

    if (asset == _postIconKindService) {
      return Icon(
        Icons.home_repair_service_rounded,
        size: size,
        color: _postRequestBlue,
        semanticLabel: semanticLabel,
      );
    }

    if (asset == _postIconLocationHome) {
      return Icon(
        Icons.home_rounded,
        size: size,
        color: _postRequestBlue,
        semanticLabel: semanticLabel,
      );
    }

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
    );
  }
}

class _RequestKindCard extends StatelessWidget {
  const _RequestKindCard({
    required this.selected,
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? HocalistTheme.roleSurface : Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? _postRequestBlue : _postRequestBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _postRequestBlue.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PostRequestImageIcon(
                asset: iconAsset,
                size: 30,
                semanticLabel: title,
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: _postRequestText, fontSize: 21),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? _postRequestBlue : _postRequestText,
                      ),
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

class _RequestStepProgress extends StatelessWidget {
  const _RequestStepProgress({required this.currentStep});

  final _CreateRequestStep currentStep;

  @override
  Widget build(BuildContext context) {
    final location = currentStep == _CreateRequestStep.location;
    return Row(
      children: [
        const Spacer(),
        _StepDot(number: '1', label: 'Details', active: true),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final activeWidth = location
                    ? constraints.maxWidth
                    : constraints.maxWidth * 0.82;
                return Stack(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _postRequestProgressTrack,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Container(
                      width: activeWidth,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _postRequestBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        _StepDot(number: '2', label: 'Location', active: location),
        const Spacer(),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.active,
  });

  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? _postRequestBlue : const Color(0xffe5e6ee);
    final textColor = active ? Colors.white : _postRequestText;
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            number,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: textColor, fontSize: 18),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: active ? _postRequestBlue : _postRequestMuted,
          ),
        ),
      ],
    );
  }
}

class _DetailsRequestStep extends StatelessWidget {
  const _DetailsRequestStep({
    required this.kind,
    required this.requestTitle,
    required this.budget,
    required this.quantity,
    required this.flexibleOffers,
    required this.selectedChoice,
    required this.minPrice,
    required this.maxPrice,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onChoiceChanged,
    required this.onMinPriceChanged,
    required this.onMaxPriceChanged,
    required this.onQuantityChanged,
    required this.onFlexibleOffersChanged,
    required this.onBack,
    required this.onContinue,
    super.key,
  });

  final _RequestKind kind;
  final String requestTitle;
  final String budget;
  final int quantity;
  final bool flexibleOffers;
  final String selectedChoice;
  final String minPrice;
  final String maxPrice;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final ValueChanged<String> onChoiceChanged;
  final ValueChanged<String> onMinPriceChanged;
  final ValueChanged<String> onMaxPriceChanged;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<bool> onFlexibleOffersChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  bool get isProduct => kind == _RequestKind.product;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isProduct
              ? 'Tell us more about the product you need'
              : 'Tell us more about the service you need',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 24,
            color: _postRequestText,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The more details you provide, the better\nmatches you will receive.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _postRequestText,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        _RequestFieldCard(
          title: isProduct
              ? 'What are you looking for?'
              : 'What service do you need?',
          helper: 'Give your request a clear title.',
          iconAsset: _postIconTitleTag,
          initialValue: requestTitle,
          hint: isProduct
              ? 'e.g., iPad Air 5th Gen, 64GB, Space Gray'
              : 'e.g., House Cleaning, Car Detailing, Logo Design',
          onChanged: onTitleChanged,
        ),
        const SizedBox(height: 14),
        _RequestFieldCard(
          title: isProduct ? 'Describe the product' : 'Describe the service',
          helper:
              'Include key details so sellers can give you accurate offers.',
          iconAsset: _postIconDescription,
          hint: isProduct
              ? 'Describe what you need, preferred brand, model, size, color, condition, features, etc.'
              : 'Describe what you need, preferred outcome, specific requirements, etc.',
          maxLines: 4,
          maxLengthText: '0/500',
        ),
        const SizedBox(height: 14),
        ResponsiveCardGrid(
          children: [
            _ChoicePanel(
              iconAsset: isProduct ? _postIconCondition : _postIconServiceType,
              title: isProduct ? 'Condition' : 'Service Type',
              selected: selectedChoice,
              onSelected: onChoiceChanged,
              options: isProduct
                  ? const [
                      _ChoiceOption(_postIconChoiceNew, 'New'),
                      _ChoiceOption(_postIconChoiceUsed, 'Used'),
                    ]
                  : const [
                      _ChoiceOption(_postIconChoiceOneTime, 'One-time'),
                      _ChoiceOption(_postIconChoiceOngoing, 'Ongoing'),
                    ],
            ),
            _BudgetPanel(
              minPrice: minPrice,
              maxPrice: maxPrice,
              onMinChanged: onMinPriceChanged,
              onMaxChanged: onMaxPriceChanged,
              onRangeChanged: onBudgetChanged,
            ),
            isProduct
                ? _QuantityPanel(
                    quantity: quantity,
                    onChanged: onQuantityChanged,
                  )
                : const _CategoryPanel(),
            _HigherOffersPanel(
              value: flexibleOffers,
              onChanged: onFlexibleOffersChanged,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RequestActionRow(
          backLabel: 'Back',
          forwardLabel: 'Continue',
          onBack: onBack,
          onForward: onContinue,
        ),
      ],
    );
  }
}

class _RequestFieldCard extends StatelessWidget {
  const _RequestFieldCard({
    required this.title,
    required this.helper,
    required this.iconAsset,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.maxLines = 1,
    this.maxLengthText,
  });

  final String title;
  final String helper;
  final String iconAsset;
  final String hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final String? maxLengthText;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: _postRequestText,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: _postRequestText),
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            minLines: maxLines,
            maxLines: maxLines,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _postRequestText,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                width: 62,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xffedf0f8))),
                ),
                child: _PostRequestImageIcon(asset: iconAsset, size: 27),
              ),
              hintText: hint,
              suffixText: maxLengthText,
              hintMaxLines: maxLines,
              contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _postRequestBorder),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceOption {
  const _ChoiceOption(this.iconAsset, this.label);

  final String iconAsset;
  final String label;
}

class _ChoicePanel extends StatelessWidget {
  const _ChoicePanel({
    required this.iconAsset,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String iconAsset;
  final String title;
  final List<_ChoiceOption> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(iconAsset: iconAsset, title: title, optional: true),
          const SizedBox(height: 6),
          Text(
            'Select your preference',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _postRequestText),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                Expanded(
                  child: _MiniChoiceButton(
                    iconAsset: options[index].iconAsset,
                    label: options[index].label,
                    selected: options[index].label == selected,
                    onTap: () => onSelected(options[index].label),
                  ),
                ),
                if (index != options.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel({
    required this.minPrice,
    required this.maxPrice,
    required this.onMinChanged,
    required this.onMaxChanged,
    required this.onRangeChanged,
  });

  final String minPrice;
  final String maxPrice;
  final ValueChanged<String> onMinChanged;
  final ValueChanged<String> onMaxChanged;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            iconAsset: _postIconBudget,
            title: 'Budget',
            optional: true,
          ),
          const SizedBox(height: 6),
          Text(
            'Select your preference',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _postRequestText),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _PriceInput(
                  iconAsset: _postIconPriceMin,
                  label: 'Min',
                  value: minPrice,
                  onChanged: (value) {
                    onMinChanged(value);
                    onRangeChanged('$value - $maxPrice');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PriceInput(
                  iconAsset: _postIconPriceMax,
                  label: 'Max',
                  value: maxPrice,
                  onChanged: (value) {
                    onMaxChanged(value);
                    onRangeChanged('$minPrice - $value');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceInput extends StatelessWidget {
  const _PriceInput({
    required this.iconAsset,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String iconAsset;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(color: _postRequestText),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: _PostRequestImageIcon(asset: iconAsset, size: 27),
        ),
        hintText: label,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _postRequestBorder),
        ),
      ),
    );
  }
}

class _QuantityPanel extends StatelessWidget {
  const _QuantityPanel({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(iconAsset: _postIconQuantity, title: 'Quantity'),
          const SizedBox(height: 12),
          Text(
            'How many do you need?',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _postRequestText),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _QuantityButton(
                label: '-',
                leading: true,
                onTap: () => onChanged(quantity - 1),
              ),
              Container(
                width: 102,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: _postRequestBorder),
                  ),
                ),
                child: Text(
                  '$quantity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _postRequestText,
                    fontSize: 18,
                  ),
                ),
              ),
              _QuantityButton(
                label: '+',
                leading: false,
                onTap: () => onChanged(quantity + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            iconAsset: _postIconCategory,
            title: 'Category',
            optional: true,
          ),
          const SizedBox(height: 6),
          Text(
            'Select this if you do not want mismatch',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _postRequestText),
          ),
          const SizedBox(height: 22),
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: _postRequestBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const _PostRequestImageIcon(
                  asset: _postIconCategoryGrid,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Select a category',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: HocalistTheme.muted,
                    ),
                  ),
                ),
                const _PostRequestImageIcon(
                  asset: _postIconCategoryDown,
                  size: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HigherOffersPanel extends StatelessWidget {
  const _HigherOffersPanel({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            iconAsset: _postIconHigherOffers,
            title: 'Willing to receive higher offers?',
          ),
          const SizedBox(height: 8),
          Text(
            'Allow sellers to offer above\nyour budget.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _postRequestText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ToggleChoiceButton(
                  label: 'No, stay on budget',
                  selected: !value,
                  onTap: () => onChanged(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleChoiceButton(
                  label: 'Yes, I am open',
                  selected: value,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const _PostRequestImageIcon(asset: _postIconInfo, size: 17),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'You can still choose any offer you like.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _postRequestText,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.iconAsset,
    required this.title,
    this.optional = false,
  });

  final String iconAsset;
  final String title;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PostRequestImageIcon(asset: iconAsset, size: 27),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: title),
                if (optional)
                  const TextSpan(
                    text: '  (optional)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _postRequestText,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChoiceButton extends StatelessWidget {
  const _MiniChoiceButton({
    required this.iconAsset,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String iconAsset;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _postRequestBlue : _postRequestText;
    return Material(
      color: selected ? HocalistTheme.roleSurface : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _postRequestBlue : _postRequestBorder,
              width: selected ? 1.3 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PostRequestImageIcon(asset: iconAsset, size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleChoiceButton extends StatelessWidget {
  const _ToggleChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? _postRequestBlue : _postRequestText,
        side: BorderSide(
          color: selected ? _postRequestBlue : _postRequestBorder,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.label,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final bool leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: _postRequestBorder),
          borderRadius: BorderRadius.horizontal(
            left: leading ? const Radius.circular(8) : Radius.zero,
            right: leading ? Radius.zero : const Radius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: _postRequestBlue,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LocationRequestStep extends StatelessWidget {
  const _LocationRequestStep({
    required this.useHomeAddress,
    required this.onUseHomeAddressChanged,
    required this.onBack,
    required this.onSubmit,
    super.key,
  });

  final bool useHomeAddress;
  final ValueChanged<bool> onUseHomeAddressChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Where do you need this service?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 24,
            color: _postRequestText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sellers will be able to only see your\nlocation once you close the deal.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _postRequestMuted,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use my home address',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: _postRequestText),
              ),
              const SizedBox(height: 6),
              Text(
                'This is your default address in settings.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: _postRequestMuted),
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onUseHomeAddressChanged(true),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HocalistTheme.roleSurface,
                    border: Border.all(color: _postRequestBlue, width: 1.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final radio = useHomeAddress
                          ? const _PostRequestImageIcon(
                              asset: _postIconLocationRadioSelected,
                              size: 26,
                            )
                          : Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _postRequestBlue,
                                  width: 2,
                                ),
                                shape: BoxShape.circle,
                              ),
                            );
                      final address = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '123 Main Street',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: _postRequestText),
                          ),
                          Text(
                            'Miami, FL 33101, USA',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: _postRequestMuted),
                          ),
                        ],
                      );
                      const chip = SoftChip(
                        label: 'Recommended',
                        color: HocalistTheme.roleSurface,
                        foreground: _postRequestBlue,
                      );

                      if (constraints.maxWidth < 330) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                radio,
                                const SizedBox(width: 12),
                                const _PostRequestImageIcon(
                                  asset: _postIconLocationHome,
                                  size: 40,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            address,
                            const SizedBox(height: 10),
                            chip,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          radio,
                          const SizedBox(width: 14),
                          const _PostRequestImageIcon(
                            asset: _postIconLocationHome,
                            size: 46,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: address),
                          const SizedBox(width: 10),
                          chip,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xffe5e7f1))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'OR',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: HocalistTheme.muted),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xffe5e7f1))),
          ],
        ),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a different address',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: HocalistTheme.primary),
              ),
              const SizedBox(height: 4),
              Text(
                'Fill in the address where you need the service.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
              ),
              const SizedBox(height: 18),
              const _AddressFields(),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _PostRequestPrimaryButton(label: 'Post request', onPressed: onSubmit),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

class _AddressFields extends StatelessWidget {
  const _AddressFields();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 520;
        final city = TextFormField(
          decoration: InputDecoration(
            labelText: 'City',
            hintText: 'Enter city',
          ),
        );
        final state = TextFormField(
          decoration: InputDecoration(
            labelText: 'State',
            hintText: 'Select state',
            suffixIcon: const Padding(
              padding: EdgeInsets.all(14),
              child: _PostRequestImageIcon(
                asset: _postIconCategoryDown,
                size: 20,
              ),
            ),
          ),
        );
        final zip = TextFormField(
          decoration: InputDecoration(
            labelText: 'ZIP code',
            hintText: 'Enter ZIP code',
          ),
        );
        final country = TextFormField(
          initialValue: 'United States',
          decoration: InputDecoration(
            labelText: 'Country',
            suffixIcon: const Padding(
              padding: EdgeInsets.all(14),
              child: _PostRequestImageIcon(
                asset: _postIconCategoryDown,
                size: 20,
              ),
            ),
          ),
        );
        return Column(
          children: [
            TextFormField(
              initialValue: '123 Main St',
              decoration: InputDecoration(labelText: 'Street address'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Apartment, suite, etc. (optional)',
                hintText: 'Apt 4B, Suite 200, etc.',
              ),
            ),
            const SizedBox(height: 14),
            if (twoColumn)
              Row(
                children: [
                  Expanded(child: city),
                  const SizedBox(width: 14),
                  Expanded(child: state),
                ],
              )
            else ...[
              city,
              const SizedBox(height: 14),
              state,
            ],
            const SizedBox(height: 14),
            if (twoColumn)
              Row(
                children: [
                  Expanded(child: zip),
                  const SizedBox(width: 14),
                  Expanded(child: country),
                ],
              )
            else ...[
              zip,
              const SizedBox(height: 14),
              country,
            ],
          ],
        );
      },
    );
  }
}

class _RequestActionRow extends StatelessWidget {
  const _RequestActionRow({
    required this.backLabel,
    required this.forwardLabel,
    required this.onBack,
    required this.onForward,
  });

  final String backLabel;
  final String forwardLabel;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final back = SecondaryButton(
          label: backLabel,
          color: _postRequestBlue,
          onPressed: onBack,
        );
        final forward = _PostRequestPrimaryButton(
          label: forwardLabel,
          onPressed: onForward,
        );
        if (narrow) {
          return Column(children: [forward, const SizedBox(height: 10), back]);
        }
        return Row(
          children: [
            Expanded(child: back),
            const SizedBox(width: 14),
            Expanded(child: forward),
          ],
        );
      },
    );
  }
}

class _PostRequestPrimaryButton extends StatelessWidget {
  const _PostRequestPrimaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _postRequestBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        icon: const _PostRequestImageIcon(
          asset: _postIconSend,
          size: 24,
          semanticLabel: 'Send',
        ),
        label: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white, fontSize: 17),
        ),
      ),
    );
  }
}

class BuyerRequestDetailPage extends StatefulWidget {
  const BuyerRequestDetailPage({
    required this.accent,
    required this.requestTitle,
    required this.budget,
    required this.onBack,
    required this.onNotifications,
    required this.onOffers,
    super.key,
  });

  final Color accent;
  final String requestTitle;
  final String budget;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onOffers;

  @override
  State<BuyerRequestDetailPage> createState() => _BuyerRequestDetailPageState();
}

class _BuyerRequestDetailPageState extends State<BuyerRequestDetailPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _newCondition = true;
  bool _acceptHigherOffers = true;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: 'iPad Air, 5th gen or newer',
    );
    _descriptionController = TextEditingController(
      text:
          'Looking for an iPad Air 5th generation or newer.\n'
          'Prefer 64GB or higher, in excellent condition.\n'
          'Must include original charger and box.\n'
          'Color doesn’t matter.',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final metrics =
            ApprovedReplicaScope.maybeOf(sheetContext) ??
            ApprovedReplicaMetrics.resolve(
              availableWidth: media.size.width,
              textScaler: media.textScaler,
            );
        return BuyerModalSheet(
          icon: Icons.delete_outline_rounded,
          iconColor: const Color(0xffef1f29),
          iconSurface: const Color(0xffffecee),
          title: 'Delete this request?',
          subtitle: 'Review the effect before removing the request.',
          onClose: () => Navigator.pop(sheetContext, false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This prototype will only simulate deleting the request.',
                style: BuyerTypography.style(
                  sheetContext,
                  metrics,
                  BuyerTextRole.primaryBody,
                  color: BuyerUiTokens.muted,
                ),
              ),
              const SizedBox(height: 16),
              BuyerPrimaryButton(
                label: 'Delete request',
                colors: const [Color(0xffef1f29), Color(0xffd9101b)],
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 8),
              BuyerSecondaryButton(
                label: 'Keep request',
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      _message('Delete preview only — no request was removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: HocalistTheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request details',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: HocalistTheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Review and edit your request information.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: HocalistTheme.primary),
              ),
              const SizedBox(height: 20),
              _RequestSummaryCard(onDelete: _confirmDelete),
              const SizedBox(height: 22),
              Text(
                'Edit your request',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: HocalistTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              _ReplicaEditPanel(
                iconAsset: _postIconTitleTag,
                title: 'What are you looking for?',
                helper: 'Give your request a clear title.',
                onEdit: () => _message('Edit the request title below.'),
                child: TextField(
                  key: const Key('request-title-field'),
                  controller: _titleController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ReplicaEditPanel(
                iconAsset: _postIconDescription,
                title: 'Describe the product',
                helper:
                    'Include key details so sellers can give you accurate offers.',
                trailing: '${_descriptionController.text.length}/500',
                onEdit: () => _message('Edit the product description below.'),
                child: TextField(
                  key: const Key('request-description-field'),
                  controller: _descriptionController,
                  maxLength: 500,
                  minLines: 4,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 620;
                  final cards = [
                    _RequestConditionPanel(
                      isNew: _newCondition,
                      onChanged: (value) =>
                          setState(() => _newCondition = value),
                      onEdit: () => _message('Choose New or Used below.'),
                    ),
                    _RequestBudgetPanel(
                      onEdit: () => _message('Edit the budget range below.'),
                    ),
                    _RequestQuantityPanel(
                      quantity: _quantity,
                      onChanged: (value) => setState(() => _quantity = value),
                    ),
                    _ReplicaHigherOffersPanel(
                      accepting: _acceptHigherOffers,
                      onChanged: (value) =>
                          setState(() => _acceptHigherOffers = value),
                    ),
                  ];
                  if (!twoColumns) {
                    return Column(
                      children: cards
                          .expand((card) => [card, const SizedBox(height: 14)])
                          .toList(),
                    );
                  }
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: cards
                        .map(
                          (card) => SizedBox(
                            width: (constraints.maxWidth - 14) / 2,
                            child: card,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 620;
                  final location = _EditLocationCard(
                    onTap: () => _message('Location editor preview opened.'),
                  );
                  const rewards = _EstimatedRewardsPanel();
                  if (!twoColumns) {
                    return Column(
                      children: [location, const SizedBox(height: 14), rewards],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: location),
                      const SizedBox(width: 14),
                      const Expanded(child: rewards),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _SaveChangesPanel(
                onSave: () => _message('Request changes saved on this device.'),
                onOffers: widget.onOffers,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OffersPage extends StatefulWidget {
  const OffersPage({
    required this.accent,
    required this.requestPosted,
    required this.offerSelected,
    required this.onBack,
    required this.onNotifications,
    required this.onProfile,
    required this.onSelect,
    required this.onChat,
    super.key,
  });

  final Color accent;
  final bool requestPosted;
  final bool offerSelected;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onSelect;
  final VoidCallback onChat;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  String _sort = 'Best match';

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Offers received',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    color: HocalistTheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Compare offers and choose the best seller for you.',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: HocalistTheme.muted,
                                    height: 1.35,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Image.asset(
                          'assets/offers_received/offers-envelope-approved.png',
                          fit: BoxFit.contain,
                          semanticLabel: 'Offer arriving in an envelope',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const _OffersRewardsSummary(),
              const SizedBox(height: 16),
              _OfferToolbar(
                value: _sort,
                onChanged: (value) => setState(() => _sort = value),
                onFilter: () => _message('Filter options are a local preview.'),
              ),
              const SizedBox(height: 14),
              _DetailedOfferCard(
                topMatch: true,
                seller: 'Northside Tech',
                initials: 'NT',
                price: '\$420',
                reviews: '4.9  (128 reviews)',
                sellerStatus: 'Verified seller',
                description:
                    'iPad Air 5, 256GB, keyboard case, public pickup, Saturday.',
                firstFactTitle: 'Verified',
                firstFactBody: 'Identity verified',
                firstFactIcon: Icons.shield_outlined,
                distance: '1.2 mi away',
                availability: 'Sat, May 17',
                onDetails: widget.onProfile,
                chatEnabled: true,
                onChat: widget.onChat,
              ),
              const SizedBox(height: 14),
              _DetailedOfferCard(
                seller: 'Loop Resale',
                initials: 'LR',
                price: '\$390',
                reviews: '4.9  (86 reviews)',
                sellerStatus: 'Fast responder',
                description:
                    'iPad Air 5, 64GB, same-day pickup, no accessories.',
                firstFactTitle: 'Fast reply',
                firstFactBody: 'Usually responds in minutes',
                firstFactIcon: Icons.bolt,
                distance: '0.8 mi away',
                availability: 'Today',
                onDetails: widget.onProfile,
                chatEnabled: true,
                onChat: widget.onChat,
              ),
              const SizedBox(height: 14),
              const _SecurePrivateNotice(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplicaSurface extends StatelessWidget {
  const _ReplicaSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffe7e8f4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0a101054),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final image = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/buyer_request_detail/ipad-air-approved.png',
              width: compact ? 88 : 122,
              height: compact ? 106 : 146,
              fit: BoxFit.cover,
              semanticLabel: 'iPad Air request product',
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'iPad Air, 5th gen or newer',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: HocalistTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: const [
                  _SummaryFact(label: 'Budget range', value: '\$350 – \$480'),
                  _SummaryFact(
                    label: 'Location',
                    value: 'Chicago, IL',
                    icon: Icons.location_on_outlined,
                  ),
                ],
              ),
            ],
          );
          final statusActions = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const _ActiveBadge(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('delete-request'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  minimumSize: const Size(108, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    image,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [const _ActiveBadge(), statusActions.children.last],
                ),
              ],
            );
          }
          return Row(
            children: [
              image,
              const SizedBox(width: 24),
              Expanded(child: details),
              const SizedBox(width: 18),
              statusActions,
            ],
          );
        },
      ),
    );
  }
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({required this.label, required this.value, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: HocalistTheme.primary),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xff1616d8),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xffe8f8ed),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: Color(0xff0ca64a)),
          SizedBox(width: 7),
          Text(
            'Active',
            style: TextStyle(
              color: Color(0xff07933e),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplicaEditPanel extends StatelessWidget {
  const _ReplicaEditPanel({
    required this.iconAsset,
    required this.title,
    required this.helper,
    required this.child,
    required this.onEdit,
    this.trailing,
  });

  final String iconAsset;
  final String title;
  final String helper;
  final Widget child;
  final VoidCallback onEdit;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReplicaIconCircle(asset: iconAsset),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: HocalistTheme.primary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    const SizedBox(width: 8),
                    _ReplicaEditButton(
                      onPressed: onEdit,
                      tooltip: 'Edit $title',
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  helper,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: HocalistTheme.primary),
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplicaIconCircle extends StatelessWidget {
  const _ReplicaIconCircle({required this.asset});
  final String asset;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(11),
      decoration: const BoxDecoration(
        color: Color(0xfff1efff),
        shape: BoxShape.circle,
      ),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

class _ReplicaEditButton extends StatelessWidget {
  const _ReplicaEditButton({required this.onPressed, required this.tooltip});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xff1515df),
        backgroundColor: const Color(0xfff1efff),
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.edit, size: 18),
    );
  }
}

class _RequestConditionPanel extends StatelessWidget {
  const _RequestConditionPanel({
    required this.isNew,
    required this.onChanged,
    required this.onEdit,
  });
  final bool isNew;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    return _ReplicaChoicePanel(
      asset: _postIconCondition,
      title: 'Condition',
      optional: true,
      onEdit: onEdit,
      helper: 'Select your preference',
      child: Row(
        children: [
          Expanded(
            child: _ChoiceButton(
              label: 'New',
              selected: isNew,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ChoiceButton(
              label: 'Used',
              selected: !isNew,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestBudgetPanel extends StatelessWidget {
  const _RequestBudgetPanel({required this.onEdit});
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    return _ReplicaChoicePanel(
      asset: _postIconBudget,
      title: 'Budget',
      optional: true,
      onEdit: onEdit,
      helper: 'Set your budget range',
      child: const Row(
        children: [
          Expanded(child: _ValueBox(value: '\$350')),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('–'),
          ),
          Expanded(child: _ValueBox(value: '\$480')),
        ],
      ),
    );
  }
}

class _RequestQuantityPanel extends StatelessWidget {
  const _RequestQuantityPanel({
    required this.quantity,
    required this.onChanged,
  });
  final int quantity;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return _ReplicaChoicePanel(
      asset: _postIconQuantity,
      title: 'Quantity',
      helper: 'How many do you need?',
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xffe0e2f1)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Decrease quantity',
              onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$quantity',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Increase quantity',
              onPressed: () => onChanged(quantity + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplicaHigherOffersPanel extends StatelessWidget {
  const _ReplicaHigherOffersPanel({
    required this.accepting,
    required this.onChanged,
  });
  final bool accepting;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return _ReplicaChoicePanel(
      asset: _postIconHigherOffers,
      title: 'Willing to receive higher offers?',
      helper: 'Allow sellers to offer above your budget.',
      child: Row(
        children: [
          Expanded(
            child: _ChoiceButton(
              label: 'No, stay on budget',
              selected: !accepting,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ChoiceButton(
              label: "Yes, I'm open",
              selected: accepting,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplicaChoicePanel extends StatelessWidget {
  const _ReplicaChoicePanel({
    required this.asset,
    required this.title,
    required this.helper,
    required this.child,
    this.optional = false,
    this.onEdit,
  });
  final String asset;
  final String title;
  final String helper;
  final Widget child;
  final bool optional;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ReplicaIconCircle(asset: asset),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: HocalistTheme.primary,
                              ),
                        ),
                        if (optional)
                          const Text(
                            '(optional)',
                            style: TextStyle(
                              color: Color(0xff1515df),
                              fontSize: HocalistTheme.smallSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      helper,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xff1515df),
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                _ReplicaEditButton(onPressed: onEdit!, tooltip: 'Edit $title'),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: HocalistTheme.primary,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: selected ? const Color(0xff1515df) : const Color(0xffdfe1ef),
          width: selected ? 1.8 : 1,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffdfe1ef)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: HocalistTheme.primary,
        ),
      ),
    );
  }
}

class _EditLocationCard extends StatelessWidget {
  const _EditLocationCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 46,
                color: HocalistTheme.primary,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit location',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: HocalistTheme.primary,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('Change your location'),
                    Text(
                      'Chicago, IL',
                      style: TextStyle(
                        color: Color(0xff1515df),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: HocalistTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstimatedRewardsPanel extends StatelessWidget {
  const _EstimatedRewardsPanel();
  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xffffb21c),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current estimated rewards',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: HocalistTheme.primary,
                  ),
                ),
                SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '\$6.40',
                      style: TextStyle(
                        color: Color(0xff0ca64a),
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xffe3f7e9),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          '32 offers',
                          style: TextStyle(
                            color: Color(0xff0c9845),
                            fontSize: HocalistTheme.smallSize,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Mock estimate based on current offers.',
                  style: TextStyle(
                    fontSize: HocalistTheme.smallSize,
                    color: HocalistTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.info_outline, color: Color(0xff1515df)),
        ],
      ),
    );
  }
}

class _SaveChangesPanel extends StatelessWidget {
  const _SaveChangesPanel({required this.onSave, required this.onOffers});
  final VoidCallback onSave;
  final VoidCallback onOffers;
  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final copy = const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save changes',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: HocalistTheme.primary,
                  fontSize: 17,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Updating your request may refresh offers and estimated rewards.',
              ),
            ],
          );
          final buttons = Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onOffers,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Review 2 offers'),
              ),
              FilledButton.icon(
                key: const Key('save-request-changes'),
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff1515df),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 14), buttons],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 16),
              buttons,
            ],
          );
        },
      ),
    );
  }
}

class _OffersRewardsSummary extends StatelessWidget {
  const _OffersRewardsSummary();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfff7f6ff),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffdfdef5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final reward = Row(
            children: [
              Image.asset(
                'assets/offers_received/rewards-gift-approved.png',
                width: compact ? 72 : 132,
                height: compact ? 94 : 154,
                fit: BoxFit.contain,
              ),
              SizedBox(width: compact ? 8 : 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Your total rewards',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: HocalistTheme.primary,
                          ),
                        ),
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Color(0xff1515df),
                        ),
                      ],
                    ),
                    SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          '\$0.40',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff1515bd),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xffe9e5ff),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            child: Text(
                              'From 2 sellers',
                              style: TextStyle(
                                color: HocalistTheme.primary,
                                fontSize: HocalistTheme.smallSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '\$0.20 from each seller',
                      style: TextStyle(color: HocalistTheme.muted),
                    ),
                    SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xffeeeaff),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite,
                              size: 15,
                              color: Color(0xff1515df),
                            ),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'You earn when you buy',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: HocalistTheme.smallSize,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xff1515df),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          const rules = Column(
            children: [
              _RewardRule(
                icon: Icons.calendar_month_outlined,
                title: 'Buy from any seller within 5 days',
                bodyLead: 'To keep rewards from ',
                bodyEmphasis: 'all sellers',
              ),
              Divider(height: 22),
              _RewardRule(
                icon: Icons.card_giftcard,
                title: 'Rewards are added after purchase',
                bodyLead: 'Completed ',
                bodyEmphasis: 'through the app',
              ),
            ],
          );
          if (compact) {
            return Column(children: [reward, const Divider(height: 26), rules]);
          }
          return Row(
            children: [
              Expanded(child: reward),
              const SizedBox(width: 24),
              const SizedBox(height: 170, child: VerticalDivider()),
              const SizedBox(width: 20),
              const Expanded(child: rules),
            ],
          );
        },
      ),
    );
  }
}

class _RewardRule extends StatelessWidget {
  const _RewardRule({
    required this.icon,
    required this.title,
    required this.bodyLead,
    required this.bodyEmphasis,
  });
  final IconData icon;
  final String title;
  final String bodyLead;
  final String bodyEmphasis;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xffeeecff),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Color(0xff2020e8)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: HocalistTheme.primary,
                ),
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: bodyLead),
                    TextSpan(
                      text: bodyEmphasis,
                      style: const TextStyle(
                        color: Color(0xff1515df),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(color: HocalistTheme.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferToolbar extends StatelessWidget {
  const _OfferToolbar({
    required this.value,
    required this.onChanged,
    required this.onFilter,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;
  @override
  Widget build(BuildContext context) {
    final label = Text(
      'Sort by',
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );
    final menu = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdfe1ef)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('offers-sort'),
            value: value,
            isExpanded: true,
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(10),
            items: const ['Best match', 'Lowest price', 'Nearest']
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (item) {
              if (item != null) onChanged(item);
            },
          ),
        ),
      ),
    );
    final filter = OutlinedButton.icon(
      key: const Key('offers-filter'),
      onPressed: onFilter,
      icon: const Icon(Icons.tune),
      label: const Text('Filter'),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: menu),
                  const SizedBox(width: 10),
                  filter,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            label,
            const SizedBox(width: 10),
            Expanded(child: menu),
            const SizedBox(width: 10),
            filter,
          ],
        );
      },
    );
  }
}

class _DetailedOfferCard extends StatelessWidget {
  const _DetailedOfferCard({
    required this.seller,
    required this.initials,
    required this.price,
    required this.reviews,
    required this.sellerStatus,
    required this.description,
    required this.firstFactTitle,
    required this.firstFactBody,
    required this.firstFactIcon,
    required this.distance,
    required this.availability,
    required this.onDetails,
    required this.chatEnabled,
    required this.onChat,
    this.topMatch = false,
  });
  final String seller;
  final String initials;
  final String price;
  final String reviews;
  final String sellerStatus;
  final String description;
  final String firstFactTitle;
  final String firstFactBody;
  final IconData firstFactIcon;
  final String distance;
  final String availability;
  final VoidCallback onDetails;
  final bool chatEnabled;
  final VoidCallback onChat;
  final bool topMatch;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topMatch)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xffe7f7ee),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: const Text(
                '★  Top match',
                style: TextStyle(
                  color: Color(0xff189a55),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader = constraints.maxWidth < 340;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      seller,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        height: 1.12,
                                        fontWeight: FontWeight.w900,
                                        color: HocalistTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified,
                                    size: 20,
                                    color: Color(0xff1515a8),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                children: [
                                  const Text(
                                    '★',
                                    style: TextStyle(color: Color(0xffffb000)),
                                  ),
                                  Text(reviews),
                                  Text(
                                    '•  $sellerStatus',
                                    style: const TextStyle(
                                      color: Color(0xff159954),
                                    ),
                                  ),
                                ],
                              ),
                              if (compactHeader) ...[
                                const SizedBox(height: 6),
                                Text(
                                  price,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xff1515a8),
                                  ),
                                ),
                                const Text(
                                  'Total price',
                                  style: TextStyle(color: HocalistTheme.muted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!compactHeader) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 74,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    price,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xff1515a8),
                                    ),
                                  ),
                                  const Text(
                                    'Total price',
                                    style: TextStyle(
                                      color: HocalistTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/offers_received/ipad-offer-thumbnail-approved.png',
                        width: 108,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        description,
                        style: const TextStyle(
                          height: 1.35,
                          color: HocalistTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final facts = [
                      _OfferFact(
                        icon: firstFactIcon,
                        title: firstFactTitle,
                        body: firstFactBody,
                      ),
                      _OfferFact(
                        icon: Icons.location_on_outlined,
                        title: distance,
                        body: 'from you',
                      ),
                      _OfferFact(
                        icon: Icons.schedule,
                        title: 'Available',
                        body: availability,
                      ),
                    ];
                    final itemWidth = constraints.maxWidth < 360
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final fact in facts)
                          SizedBox(width: itemWidth, child: fact),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final details = FilledButton(
                      key: Key('view-offer-$initials'),
                      onPressed: onDetails,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: const Color(0xff14149e),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('View offer details'),
                    );
                    final chat = OutlinedButton.icon(
                      key: Key('chat-after-$initials'),
                      onPressed: chatEnabled ? onChat : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Chat after selection',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          SizedBox(width: double.infinity, child: details),
                          const SizedBox(height: 8),
                          SizedBox(width: double.infinity, child: chat),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 2, child: details),
                        const SizedBox(width: 12),
                        Expanded(child: chat),
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

class _OfferFact extends StatelessWidget {
  const _OfferFact({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xfff0efff),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Color(0xff7060ff)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: HocalistTheme.primary,
                ),
              ),
              Text(
                body,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: HocalistTheme.smallSize,
                  color: HocalistTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecurePrivateNotice extends StatelessWidget {
  const _SecurePrivateNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffeffaf4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, size: 34, color: Color(0xff0b9d58)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure & private',
                  style: TextStyle(
                    color: Color(0xff0b9d58),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'Your information is safe. Chat opens only after you select a seller.',
                  style: TextStyle(color: HocalistTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SellerPublicProfilePage extends StatelessWidget {
  const SellerPublicProfilePage({
    required this.accent,
    required this.onBack,
    required this.onSelect,
    super.key,
  });

  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 42,
                    height: 42,
                  ),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: HocalistTheme.primary,
                    size: 28,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Offer details',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: HocalistTheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _ApprovedOfferSellerCard(),
            const SizedBox(height: 16),
            const _ApprovedRewardsWindowCard(),
            const SizedBox(height: 18),
            const _ApprovedOfferDescriptionSection(),
            const SizedBox(height: 12),
            const _ApprovedMeetPinCard(),
            const SizedBox(height: 12),
            _ApprovedAboutSellerCard(
              onProfile: () => _mockAction(
                context,
                'Seller profile will open when profile data is connected.',
              ),
            ),
            const SizedBox(height: 12),
            const _ApprovedChatNotice(),
            const SizedBox(height: 12),
            _ApprovedSelectSellerBar(onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

String _profileInitials(String name) {
  final value = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
  return value.isEmpty ? 'NT' : value;
}

class BuyerChatsPage extends StatelessWidget {
  const BuyerChatsPage({
    required this.onBack,
    required this.onOpenChat,
    required this.onOffers,
    this.latestOffer,
    this.latestMessagePreview,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onOpenChat;
  final VoidCallback onOffers;
  final LocalOfferRecord? latestOffer;
  final String? latestMessagePreview;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final threads = [
      _BuyerChatThreadData(
        seller: latestOffer?.sellerName ?? 'Northside Tech',
        initials: _profileInitials(latestOffer?.sellerName ?? 'Northside Tech'),
        request: latestOffer?.requestTitle ?? 'iPad Air 5, 256GB',
        preview:
            latestMessagePreview ??
            latestOffer?.message ??
            'Hi! The iPad is in perfect condition like we discussed.',
        time: '9:30 AM',
        price: latestOffer?.price ?? r'$420',
        status: 'Selected seller',
        unread: 2,
        active: true,
      ),
      _BuyerChatThreadData(
        seller: 'Loop Resale',
        initials: 'LR',
        request: 'iPad Air 5, 256GB',
        preview: 'I can include a keyboard case and meet Saturday.',
        time: 'Yesterday',
        price: '\$440',
        status: 'Offer waiting',
      ),
      _BuyerChatThreadData(
        seller: 'City Gadgets',
        initials: 'CG',
        request: 'Gaming laptop',
        preview: 'Send a new request to compare more seller offers.',
        time: 'May 16',
        price: '\$1,050',
        status: 'Closed preview',
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chats',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.pageTitle,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onOffers,
                  style: TextButton.styleFrom(
                    minimumSize: Size(
                      metrics.geometry(44),
                      metrics.geometry(40),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.geometry(8),
                    ),
                    foregroundColor: BuyerUiTokens.action,
                  ),
                  icon: Icon(Icons.sell_outlined, size: metrics.artSize(17)),
                  label: Text(
                    'Offers',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.buttonLabel,
                      color: BuyerUiTokens.action,
                      weight: FontWeight.w700,
                    ).copyWith(fontSize: metrics.fontSize(12)),
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(8)),
            Container(
              padding: EdgeInsets.all(metrics.spacing(11)),
              decoration: BoxDecoration(
                color: BuyerUiTokens.softSurface,
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: BuyerUiTokens.action,
                    size: metrics.artSize(18),
                  ),
                  SizedBox(width: metrics.spacing(8)),
                  Expanded(
                    child: Text(
                      'Chats open after you select a seller. Compare active conversations here before finalizing meetup details.',
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                        color: BuyerUiTokens.text,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.spacing(10)),
            for (final thread in threads) ...[
              _BuyerChatThreadCard(data: thread, onTap: onOpenChat),
              SizedBox(height: metrics.spacing(9)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BuyerChatThreadCard extends StatelessWidget {
  const _BuyerChatThreadCard({required this.data, required this.onTap});

  final _BuyerChatThreadData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        side: const BorderSide(color: BuyerUiTokens.border),
      ),
      child: InkWell(
        key: ValueKey('buyer-chat-thread-${data.initials}'),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(metrics.spacing(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: metrics.artSize(21),
                backgroundColor: data.active
                    ? Colors.black
                    : BuyerUiTokens.softSurface,
                foregroundColor: data.active
                    ? Colors.white
                    : BuyerUiTokens.text,
                child: Text(
                  data.initials,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.badgeStatus,
                    color: data.active ? Colors.white : BuyerUiTokens.text,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (metrics.accessibilityReflow)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.seller,
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.cardTitle,
                            ),
                          ),
                          Text(
                            data.time,
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.metadata,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.seller,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BuyerTypography.style(
                                context,
                                metrics,
                                BuyerTextRole.cardTitle,
                              ),
                            ),
                          ),
                          SizedBox(width: metrics.spacing(8)),
                          Text(
                            data.time,
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.metadata,
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: metrics.spacing(3)),
                    Text(
                      data.request,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                        color: BuyerUiTokens.action,
                        weight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(5)),
                    Text(
                      data.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(7)),
                    Wrap(
                      spacing: metrics.spacing(6),
                      runSpacing: metrics.spacing(5),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ChatThreadChip(
                          label: data.status,
                          active: data.active,
                        ),
                        _ChatThreadChip(label: data.price),
                      ],
                    ),
                  ],
                ),
              ),
              if (data.unread > 0) ...[
                SizedBox(width: metrics.spacing(6)),
                _ChatUnreadDot(count: data.unread),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatThreadChip extends StatelessWidget {
  const _ChatThreadChip({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(8),
        vertical: metrics.geometry(4),
      ),
      decoration: BoxDecoration(
        color: active ? BuyerUiTokens.softSurface : const Color(0xfff5f6fb),
        borderRadius: BorderRadius.circular(metrics.geometry(999)),
      ),
      child: Text(
        label,
        style: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.badgeStatus,
          color: active ? BuyerUiTokens.action : BuyerUiTokens.muted,
        ),
      ),
    );
  }
}

class _ChatUnreadDot extends StatelessWidget {
  const _ChatUnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      width: metrics.artSize(18),
      height: metrics.artSize(18),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: BuyerUiTokens.action,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        style: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.badgeStatus,
          color: Colors.white,
          weight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _BuyerChatThreadData {
  const _BuyerChatThreadData({
    required this.seller,
    required this.initials,
    required this.request,
    required this.preview,
    required this.time,
    required this.price,
    required this.status,
    this.unread = 0,
    this.active = false,
  });

  final String seller;
  final String initials;
  final String request;
  final String preview;
  final String time;
  final String price;
  final String status;
  final int unread;
  final bool active;
}

void _mockAction(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _ApprovedOfferSellerCard extends StatelessWidget {
  const _ApprovedOfferSellerCard();

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ApprovedInitialsAvatar(size: 68),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Northside Tech',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: HocalistTheme.primary,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          color: Color(0xff1018ff),
                          size: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _TinyIconLabel(
                          icon: Icons.star,
                          iconColor: Color(0xffffa000),
                          text: '4.9 (128 reviews)',
                        ),
                        SizedBox.shrink(),
                        _TinyIconLabel(
                          icon: Icons.verified_user_outlined,
                          iconColor: Color(0xff0b8f31),
                          text: 'Verified seller',
                          textColor: Color(0xff0b8f31),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 82),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              runSpacing: 4,
              children: [
                const Text(
                  '\$420',
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Total price',
                    style: TextStyle(
                      color: HocalistTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final facts = [
                const _OfferDetailFact(
                  icon: Icons.shield_outlined,
                  title: 'Identity verified',
                ),
                const _OfferDetailFact(
                  icon: Icons.location_on_outlined,
                  title: '1.2 mi away',
                  body: 'from you',
                ),
                const _OfferDetailFact(
                  icon: Icons.schedule,
                  title: 'Available',
                  body: 'Sat, May 17',
                ),
              ];
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    for (var index = 0; index < facts.length; index++) ...[
                      _OfferDetailFactTile(child: facts[index]),
                      if (index != facts.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: facts[0]),
                  const _VerticalDivider(),
                  Expanded(child: facts[1]),
                  const _VerticalDivider(),
                  Expanded(child: facts[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ApprovedInitialsAvatar extends StatelessWidget {
  const _ApprovedInitialsAvatar({this.size = 86});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Text(
        'NT',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TinyIconLabel extends StatelessWidget {
  const _TinyIconLabel({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.textColor = HocalistTheme.primary,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _OfferDetailFact extends StatelessWidget {
  const _OfferDetailFact({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xfff1efff),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Color(0xff1520ff), size: 30),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HocalistTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 4),
                Text(
                  body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferDetailFactTile extends StatelessWidget {
  const _OfferDetailFactTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xfffbfbff),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffe8e8f6)),
      ),
      child: child,
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 62,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xffe3e4f5),
    );
  }
}

class _ApprovedRewardsWindowCard extends StatelessWidget {
  const _ApprovedRewardsWindowCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xfffff6e6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gift = Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xffffedc2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard,
              color: Color(0xffffa000),
              size: 44,
            ),
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You have 7 days left',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  fontSize: HocalistTheme.sectionTitleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Buy from any seller within 7 days to get your rewards.',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  fontSize: HocalistTheme.bodySize,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          final reward = Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xffffedc2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              children: [
                Text(
                  'Est. rewards',
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '\$12.40',
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontSize: HocalistTheme.metricSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    gift,
                    const SizedBox(width: 16),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: reward),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xff1520ff),
                      size: 30,
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              gift,
              const SizedBox(width: 18),
              Expanded(child: copy),
              const SizedBox(width: 14),
              reward,
              const SizedBox(width: 10),
              const Icon(
                Icons.info_outline,
                color: Color(0xff1520ff),
                size: 30,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedOfferDescriptionSection extends StatelessWidget {
  const _ApprovedOfferDescriptionSection();

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _SoftSquareIcon(icon: Icons.chat_bubble_outline),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Description Details',
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontSize: HocalistTheme.sectionTitleSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final image = ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  child: AspectRatio(
                    aspectRatio: stacked ? 1.16 : 1.18,
                    child: Image.asset(
                      'assets/offer_detail/ps5-approved.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              );
              final copy = const Column(
                children: [
                  _DescriptionCopyCard(
                    title: 'Your Request Description:',
                    body:
                        'I need to buy a PS5 console with a controller. I\'m a student and I\'m a bit short on cash.',
                  ),
                  SizedBox(height: 16),
                  _DescriptionCopyCard(
                    title: 'Seller\'s Pitch:',
                    body:
                        'Hi, I have a PS5 Disc Edition in excellent condition, gently used and works perfectly. I can meet you within your budget.',
                  ),
                ],
              );
              if (stacked) {
                return Column(
                  children: [image, const SizedBox(height: 18), copy],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: image),
                  const SizedBox(width: 20),
                  Expanded(child: copy),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DescriptionCopyCard extends StatelessWidget {
  const _DescriptionCopyCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xfff7f6ff),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffe6e5fb)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: HocalistTheme.primary,
              fontSize: HocalistTheme.bodySize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: const TextStyle(
              color: HocalistTheme.primary,
              fontSize: HocalistTheme.bodySize,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedMeetPinCard extends StatelessWidget {
  const _ApprovedMeetPinCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfff1edff),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffdcd5ff)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seller PIN for your rewards',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  fontSize: HocalistTheme.titleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'When you meet the seller, show them your confirmation PIN to complete the transaction. If the PIN isn\'t verified, you won\'t receive your rewards. Your PIN expires 24 hours after accepting your seller\'s offer.',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final pin = Container(
            width: constraints.maxWidth < 520 ? double.infinity : 122,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xffe6ddff),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Confirmation PIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontSize: HocalistTheme.captionSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '15230',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xff1520ff),
                    fontSize: HocalistTheme.metricSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SoftSquareIcon(
                  icon: Icons.admin_panel_settings_outlined,
                ),
                const SizedBox(height: 14),
                copy,
                const SizedBox(height: 14),
                pin,
              ],
            );
          }

          return Row(
            children: [
              const _SoftSquareIcon(icon: Icons.admin_panel_settings_outlined),
              const SizedBox(width: 18),
              const Expanded(child: copy),
              const SizedBox(width: 16),
              pin,
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedAboutSellerCard extends StatelessWidget {
  const _ApprovedAboutSellerCard({required this.onProfile});

  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'About the Seller',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  fontSize: HocalistTheme.sectionTitleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Local seller with 230+ successful deals. Usually responds in a few hours.',
                style: TextStyle(
                  color: HocalistTheme.primary,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final button = TextButton(
            onPressed: onProfile,
            style: TextButton.styleFrom(
              minimumSize: Size(
                constraints.maxWidth < 480 ? double.infinity : 132,
                52,
              ),
              backgroundColor: const Color(0xfff1efff),
              foregroundColor: const Color(0xff1520ff),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'View profile',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          );

          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SoftSquareIcon(icon: Icons.person_outline),
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 14),
                button,
              ],
            );
          }

          return Row(
            children: [
              const _SoftSquareIcon(icon: Icons.person_outline),
              const SizedBox(width: 18),
              Expanded(child: copy),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedChatNotice extends StatelessWidget {
  const _ApprovedChatNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfff3f2ff),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          _SoftSquareIcon(icon: Icons.security_outlined),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat opens only after you select this seller.',
                  style: TextStyle(
                    color: Color(0xff1520ff),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your PIN protects reward completion during meetup.',
                  style: TextStyle(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w600,
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

class _ApprovedSelectSellerBar extends StatelessWidget {
  const _ApprovedSelectSellerBar({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const Key('select-this-seller'),
            onPressed: onSelect,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 58),
              backgroundColor: const Color(0xff0618ff),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Select this seller',
              style: TextStyle(
                fontSize: HocalistTheme.buttonSize,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Selecting this seller will share your contact information.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HocalistTheme.muted,
              fontSize: HocalistTheme.captionSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftSquareIcon extends StatelessWidget {
  const _SoftSquareIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xfff1efff),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: const Color(0xff1520ff), size: 30),
    );
  }
}

class FinalizeDealPage extends StatelessWidget {
  const FinalizeDealPage({
    required this.accent,
    required this.price,
    required this.onContinue,
    super.key,
  });

  final Color accent;
  final String price;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MeetupAcceptedHero(price: price, accent: accent),
            const SizedBox(height: 14),
            _MeetupNextStepCard(accent: accent),
            const SizedBox(height: 14),
            _MeetupSafetyGrid(accent: accent),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Add meeting details'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 58),
                backgroundColor: const Color(0xff0618ff),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupAcceptedHero extends StatelessWidget {
  const _MeetupAcceptedHero({required this.price, required this.accent});

  final String price;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 380;
          final icon = Container(
            width: tight ? 56 : 64,
            height: tight ? 56 : 64,
            decoration: const BoxDecoration(
              color: Color(0xffeeebff),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Color(0xff0618ff),
              size: 38,
            ),
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meetup accepted',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: HocalistTheme.primary,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Northside Tech is selected. Set a public meetup before you inspect and pay offline.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: HocalistTheme.muted,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final priceBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xfff1efff),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: tight
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Seller price',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: HocalistTheme.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );

          if (tight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), priceBadge]),
                const SizedBox(height: 16),
                copy,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: copy),
              const SizedBox(width: 14),
              priceBadge,
            ],
          );
        },
      ),
    );
  }
}

class _MeetupNextStepCard extends StatelessWidget {
  const _MeetupNextStepCard({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SoftSquareIcon(icon: Icons.location_on_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next: choose where to meet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use a public place, confirm the time, and keep item payment outside Hocalist after inspection.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HocalistTheme.muted,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfff6f4ff),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Suggested: Wicker Park public pickup point',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: HocalistTheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
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

class _MeetupSafetyGrid extends StatelessWidget {
  const _MeetupSafetyGrid({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final cards = [
          _MeetupMiniCard(
            icon: Icons.verified_user_outlined,
            title: 'PIN protects rewards',
            body: 'Show the confirmation PIN only when the meetup is correct.',
            color: accent,
          ),
          const _MeetupMiniCard(
            icon: Icons.payments_outlined,
            title: 'Pay offline',
            body: 'Hocalist does not hold or process item payment.',
            color: HocalistTheme.sellerGreen,
          ),
        ];

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cards.first, const SizedBox(height: 12), cards.last],
          );
        }

        return Row(
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 12),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

class _MeetupMiniCard extends StatelessWidget {
  const _MeetupMiniCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _ReplicaSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HocalistTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HocalistTheme.muted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class MeetingDetailsPage extends StatelessWidget {
  const MeetingDetailsPage({
    required this.accent,
    required this.onContinue,
    super.key,
  });

  final Color accent;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Meeting details',
      subtitle:
          'Confirm where and when you will meet. Payment still happens outside Hocalist after inspection.',
      children: [
        LocationSearchPanel(
          accent: accent,
          title: 'Meeting place',
          locationValue: 'Wicker Park public pickup point',
          radiusValue: '4.2 miles from seller',
          hint:
              'This is the future Google Maps handoff point: search, select, and confirm an address both sides can see.',
        ),
        AppCard(
          child: Column(
            children: [
              TextFormField(
                initialValue: 'Saturday, 2:30 PM',
                decoration: const InputDecoration(labelText: 'Date and time'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Inspect item before paying offline',
                decoration: const InputDecoration(labelText: 'Safety note'),
              ),
            ],
          ),
        ),
        PrimaryButton(
          label: 'Confirm meeting',
          icon: Icons.event_available_outlined,
          color: accent,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class BuyerConfirmationPage extends StatelessWidget {
  const BuyerConfirmationPage({
    required this.accent,
    required this.onReview,
    required this.onDealIssue,
    required this.onReport,
    super.key,
  });

  final Color accent;
  final VoidCallback onReview;
  final VoidCallback onDealIssue;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'After the meetup',
      subtitle:
          'Record what happened after you met the seller. This keeps the buyer journey moving without adding payment checkout.',
      children: [
        ActionChoice(
          icon: Icons.check_circle_outline,
          title: 'Deal completed',
          body: 'Item inspected, offline payment handled outside Hocalist.',
          color: accent,
          onTap: onReview,
        ),
        ActionChoice(
          icon: Icons.replay_outlined,
          title: 'Deal failed or seller unavailable',
          body:
              'Return to valid backup offers, reopen the request, or report a safety issue.',
          color: HocalistTheme.seller,
          onTap: onDealIssue,
        ),
        ActionChoice(
          icon: Icons.report_problem_outlined,
          title: 'Report an issue',
          body: 'Use this if the item, seller, or meeting was unsafe.',
          color: HocalistTheme.danger,
          onTap: onReport,
        ),
      ],
    );
  }
}

class DealRecoveryPage extends StatelessWidget {
  const DealRecoveryPage({
    required this.accent,
    required this.onReopen,
    required this.onBackup,
    required this.onReport,
    super.key,
  });

  final Color accent;
  final VoidCallback onReopen;
  final VoidCallback onBackup;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Recover deal',
      subtitle:
          'If a selected seller is unavailable, the buyer can keep the request alive without starting over.',
      children: [
        AlertBanner(
          accent: HocalistTheme.danger,
          title: 'Selected deal needs action',
          body:
              'Use recovery when the seller stops responding, the item is unavailable, the meeting fails, or the buyer changes direction.',
          icon: Icons.warning_amber_outlined,
        ),
        StatusTimeline(
          accent: accent,
          items: const [
            'Keep previous valid offers available',
            'Let the buyer compare backup sellers',
            'Reopen the request if no backup offer fits',
            'Keep safety reporting separate from normal deal failure',
          ],
        ),
        ActionChoice(
          icon: Icons.local_offer_outlined,
          title: 'Compare backup offers',
          body:
              'Return to the offer list and choose another valid seller if the offer still fits.',
          color: accent,
          onTap: onBackup,
        ),
        ActionChoice(
          icon: Icons.refresh_outlined,
          title: 'Reopen request',
          body:
              'Move the request back to open status so sellers can respond again.',
          color: HocalistTheme.primary,
          onTap: onReopen,
        ),
        ActionChoice(
          icon: Icons.report_problem_outlined,
          title: 'Report safety issue',
          body:
              'Use this only for unsafe behavior, fraud concern, or a serious meeting problem.',
          color: HocalistTheme.danger,
          onTap: onReport,
        ),
      ],
    );
  }
}

class BuyerReviewPage extends StatelessWidget {
  const BuyerReviewPage({
    required this.accent,
    required this.onFinish,
    super.key,
  });

  final Color accent;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Review seller',
      subtitle: 'This helps future buyers compare offers safely.',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(
                  5,
                  (_) => Icon(Icons.star, color: accent),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Clear photos, fair price, easy public pickup.',
                decoration: InputDecoration(labelText: 'Review'),
              ),
            ],
          ),
        ),
        PrimaryButton(
          label: 'Submit review',
          icon: Icons.rate_review_outlined,
          color: accent,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class BuyerWalletPage extends StatelessWidget {
  const BuyerWalletPage({
    required this.accent,
    required this.dealCompleted,
    required this.dealFailed,
    required this.requestReopened,
    required this.withdrawalRequested,
    required this.onWithdraw,
    super.key,
  });

  final Color accent;
  final bool dealCompleted;
  final bool dealFailed;
  final bool requestReopened;
  final bool withdrawalRequested;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Buyer deal history',
      subtitle:
          'Review selected-seller outcomes, recovery states, and support notes. No item payment is processed here.',
      children: [
        MetricRow(
          accent: accent,
          values: [
            Metric(withdrawalRequested ? '1' : '0', 'In review'),
            Metric(dealCompleted ? '1' : '0', 'Completed'),
            Metric(requestReopened ? '1' : '0', 'Reopened'),
          ],
        ),
        if (dealCompleted)
          AlertBanner(
            accent: accent,
            title: 'Deal completion recorded',
            body:
                'Your record reflects the completed iPad Air deal. Item payment still happened offline.',
            icon: Icons.check_circle_outline,
          ),
        if (withdrawalRequested)
          AlertBanner(
            accent: accent,
            title: 'Support review requested',
            body:
                'Support review is pending. This prototype keeps the note local until admin tools are connected.',
            icon: Icons.pending_actions_outlined,
          ),
        if (dealFailed || requestReopened)
          AlertBanner(
            accent: HocalistTheme.danger,
            title: 'Recovery path recorded',
            body:
                'A failed or unresponsive selected seller does not erase the request. The buyer can return to backup offers.',
            icon: Icons.restore_page_outlined,
          ),
        RecordCard(
          title: 'iPad Air deal',
          meta: dealCompleted
              ? 'Completed locally, payment handled offline'
              : requestReopened
              ? 'Reopened after selected seller issue'
              : 'Pending confirmation',
          amount: dealCompleted
              ? 'Done'
              : requestReopened
              ? 'Reopened'
              : 'Open',
        ),
        const RecordCard(
          title: 'Espresso machine request',
          meta: 'Saved deal-history example',
          amount: 'Saved',
        ),
        PrimaryButton(
          label: 'Ask support to review deal',
          icon: Icons.support_agent_outlined,
          color: accent,
          onPressed: onWithdraw,
        ),
      ],
    );
  }
}

class WithdrawalPage extends StatelessWidget {
  const WithdrawalPage({
    required this.accent,
    required this.onSubmit,
    super.key,
  });

  final Color accent;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return FormStepPage(
      accent: accent,
      title: 'Ask support to review deal',
      subtitle:
          'This saves a local support note only. It does not create a payout, refund, escrow, or item-payment workflow.',
      fields: const [
        MockFieldData('Deal or request', 'Espresso machine request'),
        MockFieldData('Reason', 'Review deal-history status'),
        MockFieldData('Notes', 'Confirm this local support note is accurate'),
      ],
      primaryLabel: 'Submit support note',
      onPrimary: onSubmit,
    );
  }
}

enum BuyerProfilePhotoAction { camera, gallery, remove }

class SupportPage extends StatelessWidget {
  const SupportPage({
    required this.accent,
    required this.name,
    required this.email,
    required this.onNotifications,
    this.onRewards,
    required this.onSaved,
    required this.onSafety,
    required this.onReport,
    required this.onHelp,
    required this.onEditProfile,
    required this.onSettings,
    required this.onLogout,
    this.onProfilePhotoAction,
    super.key,
  });

  final Color accent;
  final String name;
  final String email;
  final VoidCallback onNotifications;
  final VoidCallback? onRewards;
  final VoidCallback onSaved;
  final VoidCallback onSafety;
  final VoidCallback onReport;
  final VoidCallback onHelp;
  final VoidCallback onEditProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;
  final ValueChanged<BuyerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'More',
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.pageTitle,
          ),
        ),
        SizedBox(height: metrics.spacing(10)),
        _BuyerMoreProfileCard(
          name: name,
          email: email,
          onEditProfile: onEditProfile,
          onProfilePhotoAction: onProfilePhotoAction,
        ),
        SizedBox(height: metrics.spacing(18)),
        const _BuyerMoreSectionLabel('ACCOUNT'),
        SizedBox(height: metrics.spacing(7)),
        _BuyerMoreMenuGroup(
          items: [
            _BuyerMoreItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Rewards & payouts',
              onTap: onRewards ?? () {},
            ),
            _BuyerMoreItem(
              icon: Icons.settings_outlined,
              title: 'Account Settings',
              onTap: onSettings,
            ),
            _BuyerMoreItem(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: onNotifications,
            ),
            _BuyerMoreItem(
              icon: Icons.bookmark_border,
              title: 'Saved',
              onTap: onSaved,
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(18)),
        const _BuyerMoreSectionLabel('SUPPORT & SAFETY'),
        SizedBox(height: metrics.spacing(7)),
        _BuyerMoreMenuGroup(
          items: [
            _BuyerMoreItem(
              icon: Icons.shield_outlined,
              title: 'Safety Guide',
              onTap: onSafety,
            ),
            _BuyerMoreItem(
              icon: Icons.support_agent_outlined,
              title: 'Help & Support',
              onTap: onHelp,
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(20)),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onLogout,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, metrics.geometry(46)),
              foregroundColor: HocalistTheme.danger,
              side: const BorderSide(color: HocalistTheme.danger),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(10)),
              ),
            ),
            child: Text(
              'Log out',
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.buttonLabel,
                color: HocalistTheme.danger,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BuyerMoreProfileCard extends StatelessWidget {
  const _BuyerMoreProfileCard({
    required this.name,
    required this.email,
    required this.onEditProfile,
    this.onProfilePhotoAction,
  });

  final String name;
  final String email;
  final VoidCallback onEditProfile;
  final ValueChanged<BuyerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    Future<void> changePhoto() => _showBuyerProfilePhotoOptions(
      context,
      onSelected: onProfilePhotoAction,
    );
    final avatar = _BuyerProfileAvatar(
      metrics: metrics,
      diameter: 46,
      onChangePhoto: changePhoto,
      actionKey: const Key('buyerMoreProfilePhotoAction'),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.cardTitle,
          ),
        ),
        SizedBox(height: metrics.spacing(2)),
        Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.secondaryBody,
          ),
        ),
      ],
    );
    final edit = TextButton(
      onPressed: onEditProfile,
      style: TextButton.styleFrom(
        minimumSize: Size(metrics.geometry(44), metrics.geometry(40)),
        foregroundColor: BuyerUiTokens.action,
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(8)),
      ),
      child: Text(
        'Edit profile',
        style: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.buttonLabel,
          color: BuyerUiTokens.action,
        ).copyWith(fontSize: metrics.fontSize(12)),
      ),
    );
    return Container(
      padding: EdgeInsets.all(metrics.spacing(13)),
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        border: Border.all(color: BuyerUiTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0a101054),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: metrics.accessibilityReflow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    avatar,
                    SizedBox(width: metrics.spacing(11)),
                    Expanded(child: details),
                  ],
                ),
                SizedBox(height: metrics.spacing(6)),
                Align(alignment: Alignment.centerRight, child: edit),
              ],
            )
          : Row(
              children: [
                avatar,
                SizedBox(width: metrics.spacing(11)),
                Expanded(child: details),
                SizedBox(width: metrics.spacing(8)),
                edit,
              ],
            ),
    );
  }
}

class _BuyerProfileAvatar extends StatelessWidget {
  const _BuyerProfileAvatar({
    required this.metrics,
    required this.diameter,
    required this.onChangePhoto,
    required this.actionKey,
  });

  final ApprovedReplicaMetrics metrics;
  final double diameter;
  final VoidCallback onChangePhoto;
  final Key actionKey;

  @override
  Widget build(BuildContext context) {
    final scaledDiameter = metrics.artSize(diameter);
    final actionDiameter = metrics.artSize(diameter >= 60 ? 30 : 22);
    return Tooltip(
      message: 'Change profile picture',
      child: Semantics(
        button: true,
        label: 'Change profile picture',
        child: InkResponse(
          key: actionKey,
          onTap: onChangePhoto,
          radius: scaledDiameter / 2,
          child: SizedBox(
            width: scaledDiameter,
            height: scaledDiameter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: BuyerUiTokens.softSurface,
                    foregroundColor: BuyerUiTokens.action,
                    child: Icon(
                      Icons.person_outline,
                      size: metrics.artSize(diameter >= 60 ? 31 : 23),
                    ),
                  ),
                ),
                Positioned(
                  right: -metrics.spacing(2),
                  bottom: -metrics.spacing(2),
                  child: Material(
                    color: BuyerUiTokens.action,
                    shape: const CircleBorder(),
                    elevation: 1,
                    child: SizedBox(
                      width: actionDiameter,
                      height: actionDiameter,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: metrics.artSize(diameter >= 60 ? 16 : 12),
                      ),
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

class _BuyerProfilePhotoEditor extends StatelessWidget {
  const _BuyerProfilePhotoEditor({this.onProfilePhotoAction});

  final ValueChanged<BuyerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    Future<void> changePhoto() => _showBuyerProfilePhotoOptions(
      context,
      onSelected: onProfilePhotoAction,
    );
    return Padding(
      padding: EdgeInsets.all(metrics.spacing(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BuyerProfileAvatar(
            metrics: metrics,
            diameter: 62,
            onChangePhoto: changePhoto,
            actionKey: const Key('buyerEditProfilePhotoAction'),
          ),
          SizedBox(width: metrics.spacing(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Buyer photo',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.cardTitle,
                    weight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  'Use a clear photo that sellers can recognize.',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.secondaryBody,
                  ),
                ),
                SizedBox(height: metrics.spacing(4)),
                TextButton.icon(
                  key: const Key('buyerEditProfileChangePhoto'),
                  onPressed: changePhoto,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.spacing(4),
                      vertical: metrics.spacing(4),
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    Icons.photo_camera_outlined,
                    size: metrics.artSize(15),
                  ),
                  label: Text(
                    'Change profile picture',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.buttonLabel,
                      color: BuyerUiTokens.action,
                    ).copyWith(fontSize: metrics.fontSize(12)),
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

Future<void> _showBuyerProfilePhotoOptions(
  BuildContext context, {
  ValueChanged<BuyerProfilePhotoAction>? onSelected,
}) async {
  final metrics = ApprovedReplicaScope.of(context);
  final selected = await showModalBottomSheet<BuyerProfilePhotoAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => BuyerModalSheet(
      title: 'Change profile picture',
      subtitle: 'Choose how you want to update your Buyer photo.',
      icon: Icons.account_circle_outlined,
      onClose: () => Navigator.of(sheetContext).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BuyerPhotoOption(
            metrics: metrics,
            optionKey: const Key('buyerPhotoTakePhoto'),
            icon: Icons.photo_camera_outlined,
            title: 'Take a photo',
            subtitle: 'Use your device camera',
            onTap: () =>
                Navigator.of(sheetContext).pop(BuyerProfilePhotoAction.camera),
          ),
          _BuyerPhotoOption(
            metrics: metrics,
            optionKey: const Key('buyerPhotoChooseGallery'),
            icon: Icons.photo_library_outlined,
            title: 'Choose from photo library',
            subtitle: 'Select a photo already on your device',
            onTap: () =>
                Navigator.of(sheetContext).pop(BuyerProfilePhotoAction.gallery),
          ),
          _BuyerPhotoOption(
            metrics: metrics,
            optionKey: const Key('buyerPhotoRemove'),
            icon: Icons.delete_outline,
            title: 'Remove current photo',
            subtitle: 'Show the default Buyer avatar instead',
            isDestructive: true,
            onTap: () =>
                Navigator.of(sheetContext).pop(BuyerProfilePhotoAction.remove),
          ),
        ],
      ),
    ),
  );

  if (selected != null) {
    onSelected?.call(selected);
  }
}

class _BuyerPhotoOption extends StatelessWidget {
  const _BuyerPhotoOption({
    required this.metrics,
    required this.optionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final ApprovedReplicaMetrics metrics;
  final Key optionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? HocalistTheme.danger : BuyerUiTokens.action;
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(8)),
      child: Material(
        color: isDestructive
            ? HocalistTheme.danger.withValues(alpha: 0.05)
            : BuyerUiTokens.softSurface,
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        child: InkWell(
          key: optionKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.geometry(12)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.spacing(12),
              vertical: metrics.spacing(11),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: metrics.artSize(22)),
                SizedBox(width: metrics.spacing(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.cardTitle,
                          color: color,
                          weight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: metrics.spacing(2)),
                      Text(
                        subtitle,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.secondaryBody,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: color,
                  size: metrics.artSize(20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BuyerMoreSectionLabel extends StatelessWidget {
  const _BuyerMoreSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Text(
      label,
      style: BuyerTypography.style(
        context,
        metrics,
        BuyerTextRole.metadata,
        color: BuyerUiTokens.muted,
        weight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _BuyerMoreMenuGroup extends StatelessWidget {
  const _BuyerMoreMenuGroup({required this.items});

  final List<_BuyerMoreItem> items;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        border: Border.all(color: BuyerUiTokens.border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _BuyerMoreMenuTile(item: items[index]),
            if (index != items.length - 1)
              Divider(
                height: 1,
                indent: metrics.spacing(52),
                color: BuyerUiTokens.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _BuyerMoreMenuTile extends StatelessWidget {
  const _BuyerMoreMenuTile({required this.item});

  final _BuyerMoreItem item;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(metrics.geometry(10)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.spacing(12),
          vertical: metrics.spacing(10),
        ),
        child: Row(
          children: [
            Container(
              width: metrics.artSize(34),
              height: metrics.artSize(34),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: BuyerUiTokens.softSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.icon,
                size: metrics.artSize(19),
                color: BuyerUiTokens.action,
              ),
            ),
            SizedBox(width: metrics.spacing(10)),
            Expanded(
              child: Text(
                item.title,
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.primaryBody,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: metrics.artSize(20),
              color: BuyerUiTokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerMoreItem {
  const _BuyerMoreItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

class _MoreQuickControls extends StatefulWidget {
  const _MoreQuickControls({required this.accent});

  final Color accent;

  @override
  State<_MoreQuickControls> createState() => _MoreQuickControlsState();
}

class _MoreQuickControlsState extends State<_MoreQuickControls> {
  bool offerAlerts = true;
  bool chatReminders = true;
  bool safetyTips = false;

  void update(String label, bool value, ValueChanged<bool> apply) {
    setState(() => apply(value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$label ${value ? 'enabled' : 'disabled'}.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Quick controls',
      children: [
        SettingsPreferenceRow(
          icon: Icons.local_offer_outlined,
          title: 'Offer alerts',
          body: 'Notify me when sellers respond to my active requests.',
          enabled: offerAlerts,
          accent: widget.accent,
          onChanged: (value) =>
              update('Offer alerts', value, (next) => offerAlerts = next),
        ),
        SettingsPreferenceRow(
          icon: Icons.chat_bubble_outline,
          title: 'Chat reminders',
          body: 'Remind me about selected-seller chats and meetups.',
          enabled: chatReminders,
          accent: widget.accent,
          onChanged: (value) =>
              update('Chat reminders', value, (next) => chatReminders = next),
        ),
        SettingsPreferenceRow(
          icon: Icons.health_and_safety_outlined,
          title: 'Safety tips',
          body: 'Show local meetup and offline payment reminders.',
          enabled: safetyTips,
          accent: widget.accent,
          onChanged: (value) =>
              update('Safety tips', value, (next) => safetyTips = next),
        ),
      ],
    );
  }
}

class _BuyerSubpageBlock extends StatelessWidget {
  const _BuyerSubpageBlock({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final onBack = _TitleBackScope.maybeOf(context);
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: metrics.artSize(44),
                height: metrics.artSize(44),
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.arrow_back,
                    color: BuyerUiTokens.text,
                    size: metrics.artSize(23),
                  ),
                ),
              ),
              SizedBox(width: metrics.spacing(6)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: metrics.spacing(3)),
                  child: Column(
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.pageTitle,
                          weight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: metrics.spacing(3)),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.secondaryBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: metrics.spacing(6)),
              SizedBox(width: metrics.artSize(44)),
            ],
          ),
          SizedBox(height: metrics.spacing(18)),
          ...children.expand(
            (child) => <Widget>[child, SizedBox(height: metrics.spacing(16))],
          ),
        ],
      ),
    );
  }
}

class _BuyerSubpageSection extends StatelessWidget {
  const _BuyerSubpageSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: metrics.spacing(2)),
          child: Text(
            title.toUpperCase(),
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.metadata,
              color: BuyerUiTokens.muted,
              weight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(height: metrics.spacing(7)),
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: BuyerUiTokens.border),
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  Divider(
                    height: 1,
                    indent: metrics.geometry(52),
                    color: BuyerUiTokens.border,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BuyerSubpageRow extends StatelessWidget {
  const _BuyerSubpageRow({
    required this.icon,
    required this.title,
    required this.body,
    this.status,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.spacing(12),
            vertical: metrics.spacing(11),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: metrics.artSize(34),
                height: metrics.artSize(34),
                decoration: const BoxDecoration(
                  color: BuyerUiTokens.softSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: BuyerUiTokens.action,
                  size: metrics.artSize(18),
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.cardTitle,
                        weight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(3)),
                    Text(
                      body,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                      ),
                    ),
                    if (status != null) ...[
                      SizedBox(height: metrics.spacing(5)),
                      Text(
                        status!,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.badgeStatus,
                          color: onTap == null
                              ? BuyerUiTokens.muted
                              : BuyerUiTokens.action,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                SizedBox(width: metrics.spacing(8)),
                Padding(
                  padding: EdgeInsets.only(top: metrics.spacing(7)),
                  child: Icon(
                    Icons.chevron_right,
                    color: BuyerUiTokens.muted,
                    size: metrics.artSize(20),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyerPreferenceSwitch extends StatelessWidget {
  const _BuyerPreferenceSwitch({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: BuyerUiTokens.action,
      contentPadding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(12),
        vertical: metrics.spacing(4),
      ),
      secondary: Container(
        width: metrics.artSize(34),
        height: metrics.artSize(34),
        decoration: const BoxDecoration(
          color: BuyerUiTokens.softSurface,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: BuyerUiTokens.action,
          size: metrics.artSize(18),
        ),
      ),
      title: Text(
        title,
        style: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.cardTitle,
          weight: FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: metrics.spacing(3)),
        child: Text(
          body,
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.secondaryBody,
          ),
        ),
      ),
    );
  }
}

class _BuyerAccountSettingsPage extends StatelessWidget {
  const _BuyerAccountSettingsPage({
    required this.darkMode,
    required this.textSize,
    required this.onEditProfile,
    required this.onThemeChanged,
    required this.onAccessibility,
  });

  final bool darkMode;
  final AppTextSize textSize;
  final VoidCallback onEditProfile;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback? onAccessibility;

  @override
  Widget build(BuildContext context) {
    return _BuyerSubpageBlock(
      title: 'Account Settings',
      subtitle: 'Manage your Buyer account, preferences, and privacy.',
      children: [
        _BuyerSubpageSection(
          title: 'Account',
          children: [
            _BuyerSubpageRow(
              icon: Icons.person_outline,
              title: 'Personal information',
              body: 'Review and update your Buyer profile information.',
              onTap: onEditProfile,
            ),
            const _BuyerSubpageRow(
              icon: Icons.lock_outline,
              title: 'Password & security',
              body:
                  'Password changes require connected account authentication.',
              status: 'Not currently available',
            ),
          ],
        ),
        _BuyerSubpageSection(
          title: 'Preferences',
          children: [
            _BuyerPreferenceSwitch(
              icon: darkMode
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              title: 'Appearance',
              body: darkMode
                  ? 'Dark theme is active.'
                  : 'Light theme is active.',
              value: darkMode,
              onChanged: onThemeChanged,
            ),
            _BuyerSubpageRow(
              icon: Icons.accessibility_new,
              title: 'Accessibility',
              body: 'Text size, font readability, and button visibility.',
              status: textSize.label,
              onTap: onAccessibility,
            ),
          ],
        ),
        const _BuyerSubpageSection(
          title: 'Privacy',
          children: [
            _BuyerSubpageRow(
              icon: Icons.location_on_outlined,
              title: 'Request & location privacy',
              body:
                  'Requests use an approximate area until meeting details are shared in chat.',
              status: 'Approximate location',
            ),
          ],
        ),
        const _BuyerSubpageSection(
          title: 'Account Management',
          children: [
            _BuyerSubpageRow(
              icon: Icons.manage_accounts_outlined,
              title: 'No account-management actions available',
              body:
                  'Delete and export actions are not shown until secure account services support them.',
            ),
          ],
        ),
      ],
    );
  }
}

class BuyerNotificationPreferencesPage extends StatefulWidget {
  const BuyerNotificationPreferencesPage({required this.accent, super.key});

  final Color accent;

  @override
  State<BuyerNotificationPreferencesPage> createState() =>
      _BuyerNotificationPreferencesPageState();
}

class _BuyerNotificationPreferencesPageState
    extends State<BuyerNotificationPreferencesPage> {
  static const _offersKey = 'hocalist.buyer.notifications.offers';
  static const _messagesKey = 'hocalist.buyer.notifications.messages';
  static const _dealsKey = 'hocalist.buyer.notifications.deals';
  static const _safetyKey = 'hocalist.buyer.notifications.safety';

  bool offers = true;
  bool messages = true;
  bool deals = true;
  bool safety = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      offers = preferences.getBool(_offersKey) ?? true;
      messages = preferences.getBool(_messagesKey) ?? true;
      deals = preferences.getBool(_dealsKey) ?? true;
      safety = preferences.getBool(_safetyKey) ?? true;
    });
  }

  Future<void> _update(String key, bool value, VoidCallback apply) async {
    setState(apply);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return _BuyerSubpageBlock(
      title: 'Notification Preferences',
      subtitle:
          'Choose the Buyer updates you want. These preferences are saved on this device.',
      children: [
        _BuyerSubpageSection(
          title: 'Buyer notifications',
          children: [
            _BuyerPreferenceSwitch(
              icon: Icons.local_offer_outlined,
              title: 'Offers',
              body: 'New offers, offer changes, and seller-selection updates.',
              value: offers,
              onChanged: (value) =>
                  _update(_offersKey, value, () => offers = value),
            ),
            _BuyerPreferenceSwitch(
              icon: Icons.chat_bubble_outline,
              title: 'Messages & chats',
              body: 'Messages from sellers and selected-seller chat updates.',
              value: messages,
              onChanged: (value) =>
                  _update(_messagesKey, value, () => messages = value),
            ),
            _BuyerPreferenceSwitch(
              icon: Icons.event_available_outlined,
              title: 'Meetings & deal updates',
              body: 'Meeting reminders, changes, and deal-status updates.',
              value: deals,
              onChanged: (value) =>
                  _update(_dealsKey, value, () => deals = value),
            ),
            _BuyerPreferenceSwitch(
              icon: Icons.health_and_safety_outlined,
              title: 'Account & safety alerts',
              body:
                  'Security, reporting, and important account safety notices.',
              value: safety,
              onChanged: (value) =>
                  _update(_safetyKey, value, () => safety = value),
            ),
          ],
        ),
        const _BuyerSubpageSection(
          title: 'Delivery',
          children: [
            _BuyerSubpageRow(
              icon: Icons.notifications_active_outlined,
              title: 'Device delivery',
              body:
                  'Delivery still depends on operating-system permissions and connected notification services.',
              status: 'Preference storage is active',
            ),
          ],
        ),
      ],
    );
  }
}

class BuyerSettingsPage extends StatelessWidget {
  const BuyerSettingsPage({
    required this.darkMode,
    required this.textSize,
    required this.onEditProfile,
    required this.onThemeChanged,
    this.onAccessibility,
    super.key,
  });

  final bool darkMode;
  final AppTextSize textSize;
  final VoidCallback onEditProfile;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback? onAccessibility;

  @override
  Widget build(BuildContext context) {
    return _BuyerAccountSettingsPage(
      darkMode: darkMode,
      textSize: textSize,
      onEditProfile: onEditProfile,
      onThemeChanged: onThemeChanged,
      onAccessibility: onAccessibility,
    );
  }
}

class BuyerProfileEditPage extends StatelessWidget {
  const BuyerProfileEditPage({
    required this.name,
    required this.onNameChanged,
    required this.onDone,
    this.onProfilePhotoAction,
    super.key,
  });

  final String name;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onDone;
  final ValueChanged<BuyerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    return _BuyerSubpageBlock(
      title: 'Edit Profile',
      subtitle: 'Keep your Buyer information accurate and concise.',
      children: [
        _BuyerSubpageSection(
          title: 'Profile picture',
          children: [
            _BuyerProfilePhotoEditor(
              onProfilePhotoAction: onProfilePhotoAction,
            ),
          ],
        ),
        _BuyerSubpageSection(
          title: 'Personal information',
          children: [
            Builder(
              builder: (context) {
                final metrics = ApprovedReplicaScope.of(context);
                return Padding(
                  padding: EdgeInsets.all(metrics.spacing(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BuyerProfileField(
                        label: 'Full name',
                        initialValue: name,
                        textInputAction: TextInputAction.done,
                        onChanged: onNameChanged,
                      ),
                      SizedBox(
                        height: metrics.spacing(
                          HocalistInputTokens.relatedFieldSpacing,
                        ),
                      ),
                      const _BuyerProfileField(
                        label: 'Email',
                        initialValue: 'maya.chen@example.com',
                        readOnly: true,
                        helperText:
                            'Email changes require account verification.',
                      ),
                      SizedBox(
                        height: metrics.spacing(
                          HocalistInputTokens.relatedFieldSpacing,
                        ),
                      ),
                      const _BuyerProfileField(
                        label: 'Phone number',
                        initialValue: '(914) 555-0182',
                        helperText:
                            'Used for important account and meetup alerts.',
                      ),
                      SizedBox(
                        height: metrics.spacing(
                          HocalistInputTokens.relatedFieldSpacing,
                        ),
                      ),
                      const _BuyerProfileField(
                        label: 'Home area',
                        initialValue: 'Yonkers, NY',
                        helperText:
                            'Your exact address stays private until you choose to share it.',
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        _BuyerSubpageSection(
          title: 'Buying preferences',
          children: [
            Builder(
              builder: (context) {
                final metrics = ApprovedReplicaScope.of(context);
                return Padding(
                  padding: EdgeInsets.all(metrics.spacing(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BuyerProfileField(
                        label: 'Preferred meetup type',
                        initialValue: 'Public safe-meet location',
                      ),
                      SizedBox(
                        height: metrics.spacing(
                          HocalistInputTokens.relatedFieldSpacing,
                        ),
                      ),
                      const _BuyerProfileField(
                        label: 'Profile note',
                        initialValue:
                            'Usually available on weekday evenings and Saturday afternoons.',
                        maxLines: 2,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        BuyerPrimaryButton(
          label: 'Save profile',
          onPressed: onDone,
          leading: const BuyerGlyphIcon(
            icon: Icons.check_circle_outline,
            slotSize: BuyerIconTokens.inline,
          ),
        ),
      ],
    );
  }
}

class _BuyerProfileField extends StatelessWidget {
  const _BuyerProfileField({
    required this.label,
    required this.initialValue,
    this.helperText,
    this.readOnly = false,
    this.textInputAction,
    this.onChanged,
    this.maxLines = 1,
  });

  final String label;
  final String initialValue;
  final String? helperText;
  final bool readOnly;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final valueStyle = BuyerTypography.style(
      context,
      metrics,
      BuyerTextRole.primaryBody,
      color: BuyerUiTokens.text,
      weight: FontWeight.w700,
    ).copyWith(fontSize: metrics.fontSize(13));

    return Semantics(
      textField: true,
      label: label,
      readOnly: readOnly,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerFieldLabel(label),
          SizedBox(height: metrics.spacing(5)),
          TextFormField(
            initialValue: initialValue,
            readOnly: readOnly,
            maxLines: maxLines,
            textInputAction: textInputAction,
            onChanged: onChanged,
            style: valueStyle,
            decoration: buyerInputDecoration(context),
          ),
          if (helperText != null) ...[
            SizedBox(height: metrics.spacing(6)),
            Text(
              helperText!,
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.metadata,
                color: BuyerUiTokens.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BuyerNotificationsPage extends StatelessWidget {
  const BuyerNotificationsPage({
    required this.accent,
    required this.requestPosted,
    required this.sellerOfferSent,
    required this.offerSelected,
    required this.meetingConfirmed,
    required this.dealCompleted,
    required this.withdrawalRequested,
    required this.reportSubmitted,
    super.key,
  });

  final Color accent;
  final bool requestPosted;
  final bool sellerOfferSent;
  final bool offerSelected;
  final bool meetingConfirmed;
  final bool dealCompleted;
  final bool withdrawalRequested;
  final bool reportSubmitted;

  void _showNotificationDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final metrics =
            ApprovedReplicaScope.maybeOf(sheetContext) ??
            ApprovedReplicaMetrics.resolve(
              availableWidth: media.size.width,
              textScaler: media.textScaler,
            );
        return BuyerModalSheet(
          icon: Icons.notifications_none_rounded,
          title: 'Notification details',
          subtitle: 'See the activity connected to this buyer notification.',
          onClose: () => Navigator.pop(sheetContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Northside Tech sent an offer for your iPad Air request.',
                style: BuyerTypography.style(
                  sheetContext,
                  metrics,
                  BuyerTextRole.primaryBody,
                ),
              ),
              const SizedBox(height: 12),
              const InfoList(
                items: [
                  'Request posted',
                  'Offer received',
                  'Seller selected',
                  'Chat and meeting details ready',
                ],
              ),
              const SizedBox(height: 16),
              BuyerPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Notifications',
      subtitle:
          'Offer updates, chat messages, meeting reminders, and safety alerts.',
      children: [
        AlertBanner(
          accent: accent,
          title: sellerOfferSent || requestPosted
              ? 'New offer received'
              : 'Notification center ready',
          body: sellerOfferSent || requestPosted
              ? 'Northside Tech sent an offer for your iPad Air request.'
              : 'Post a request to create offer, chat, meeting, deal-history, and safety alerts.',
          icon: Icons.local_offer_outlined,
        ),
        MenuCard(
          icon: Icons.article_outlined,
          title: 'View notification details',
          body: 'Review request, offer, chat, and meeting context.',
          color: accent,
          onTap: () => _showNotificationDetail(context),
        ),
        if (requestPosted)
          NotificationTile(
            accent: accent,
            icon: Icons.publish_outlined,
            title: 'Request posted',
            body: 'Your buying request is active for nearby verified sellers.',
            time: 'Just now',
          ),
        if (offerSelected)
          NotificationTile(
            accent: accent,
            icon: Icons.check_circle_outline,
            title: 'Seller selected',
            body:
                'Northside Tech is selected. Continue through chat and meeting details.',
            time: 'Just now',
          ),
        NotificationTile(
          accent: accent,
          icon: Icons.chat_bubble_outline,
          title: 'Chat message',
          body: 'Seller confirmed public pickup and keyboard case.',
          time: '4 min ago',
        ),
        NotificationTile(
          accent: accent,
          icon: Icons.event_available_outlined,
          title: 'Meeting reminder',
          body: meetingConfirmed
              ? 'Confirmed for Saturday, 2:30 PM at Wicker Park public pickup point.'
              : 'Meeting reminders appear after both sides confirm details.',
          time: meetingConfirmed ? 'Today' : 'Pending',
        ),
        if (dealCompleted)
          NotificationTile(
            accent: accent,
            icon: Icons.task_alt_outlined,
            title: 'Deal completed',
            body:
                'The app recorded completion; item payment stayed outside Hocalist.',
            time: 'Today',
          ),
        if (withdrawalRequested)
          NotificationTile(
            accent: accent,
            icon: Icons.support_agent_outlined,
            title: 'Support review in progress',
            body: 'Support will review this local note in a later phase.',
            time: 'Today',
          ),
        if (reportSubmitted)
          NotificationTile(
            accent: HocalistTheme.danger,
            icon: Icons.report_problem_outlined,
            title: 'Report submitted',
            body: 'The report is queued for admin moderation review.',
            time: 'Today',
          ),
        NotificationTile(
          accent: accent,
          icon: Icons.fact_check_outlined,
          title: 'Deal history pending',
          body:
              'Your buyer deal history is pending confirmation. Item payment remains offline.',
          time: 'Yesterday',
        ),
        EmptyStatePanel(
          accent: accent,
          title: 'All caught up',
          body:
              'Older notifications will appear here after backend history is connected.',
        ),
      ],
    );
  }
}

class SavedItemsPage extends StatelessWidget {
  const SavedItemsPage({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return const _BuyerSubpageBlock(
      title: 'Saved',
      subtitle: 'Buyer items, requests, and sellers you save will appear here.',
      children: [
        _BuyerSubpageSection(
          title: 'Saved content',
          children: [
            _BuyerSubpageRow(
              icon: Icons.bookmark_border,
              title: 'Nothing saved yet',
              body:
                  'Save a supported item, request, or seller and it will appear here.',
            ),
          ],
        ),
      ],
    );
  }
}

class SafetyGuidePage extends StatelessWidget {
  const SafetyGuidePage({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return const _BuyerSubpageBlock(
      title: 'Safety Guide',
      subtitle: 'Simple steps for safer local Buyer deals.',
      children: [
        _BuyerSubpageSection(
          title: 'Meet & inspect',
          children: [
            _BuyerSubpageRow(
              icon: Icons.place_outlined,
              title: 'Meet in public',
              body:
                  'Choose a busy, well-lit location and tell someone your plan.',
            ),
            _BuyerSubpageRow(
              icon: Icons.fact_check_outlined,
              title: 'Inspect before completing the deal',
              body: 'Check the item and confirm it matches the agreed offer.',
            ),
          ],
        ),
        _BuyerSubpageSection(
          title: 'Protect yourself',
          children: [
            _BuyerSubpageRow(
              icon: Icons.payments_outlined,
              title: 'Remember payment stays offline',
              body:
                  'Hocalist does not hold money, provide escrow, ship items, or guarantee payment.',
            ),
            _BuyerSubpageRow(
              icon: Icons.password_outlined,
              title: 'Protect private information',
              body:
                  'Never share passwords, verification codes, or private banking information.',
            ),
            _BuyerSubpageRow(
              icon: Icons.report_problem_outlined,
              title: 'Report a problem',
              body:
                  'Use Help & Support or the contextual report action if a user or deal feels unsafe.',
            ),
          ],
        ),
      ],
    );
  }
}

class ReportIssuePage extends StatelessWidget {
  const ReportIssuePage({
    required this.accent,
    required this.submitted,
    required this.onSubmit,
    super.key,
  });

  final Color accent;
  final bool submitted;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (submitted) {
      return const _BuyerSubpageBlock(
        title: 'Report Saved',
        subtitle:
            'Your report is available in the current support status flow.',
        children: [
          _BuyerSubpageSection(
            title: 'Status',
            children: [
              _BuyerSubpageRow(
                icon: Icons.schedule_outlined,
                title: 'Review pending',
                body:
                    'Online moderation delivery is not connected yet. Keep any evidence until support confirms receipt.',
              ),
            ],
          ),
        ],
      );
    }

    return _BuyerSubpageBlock(
      title: 'Report a Problem',
      subtitle: 'Describe an unsafe interaction, user, or deal concern.',
      children: [
        _BuyerSubpageSection(
          title: 'Report details',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  const BuyerFieldLabel('Report reason'),
                  const SizedBox(height: 5),
                  TextFormField(
                    decoration: buyerInputDecoration(
                      context,
                      hintText: 'Choose or describe the main concern',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const BuyerFieldLabel('What happened?'),
                  const SizedBox(height: 5),
                  TextFormField(
                    minLines: 3,
                    maxLines: 5,
                    decoration: buyerInputDecoration(
                      context,
                      hintText: 'Add the details support should review',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const _BuyerSubpageSection(
          title: 'Before you submit',
          children: [
            _BuyerSubpageRow(
              icon: Icons.cloud_off_outlined,
              title: 'Online delivery is not connected',
              body:
                  'This report is stored in the current on-device support flow only.',
            ),
          ],
        ),
        BuyerPrimaryButton(
          label: 'Save report',
          onPressed: onSubmit,
          colors: const [HocalistTheme.danger, Color(0xffd62f29)],
          leading: const BuyerGlyphIcon(
            icon: Icons.outgoing_mail,
            slotSize: BuyerIconTokens.inline,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({
    required this.accent,
    required this.onReport,
    required this.onContactSupport,
    super.key,
  });

  final Color accent;
  final VoidCallback onReport;
  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    return _BuyerSubpageBlock(
      title: 'Help & Support',
      subtitle: 'Find answers, contact support, or report a safety concern.',
      children: [
        const _BuyerSubpageSection(
          title: 'Frequently asked questions',
          children: [
            _BuyerSubpageRow(
              icon: Icons.help_outline,
              title: 'How Buyer requests work',
              body:
                  'Post what you need, compare offers, select a seller, and continue in chat.',
            ),
            _BuyerSubpageRow(
              icon: Icons.payments_outlined,
              title: 'Why payment is offline',
              body:
                  'Item payment happens outside Hocalist after you inspect the item and agree with the seller.',
            ),
          ],
        ),
        _BuyerSubpageSection(
          title: 'Support',
          children: [
            _BuyerSubpageRow(
              icon: Icons.support_agent_outlined,
              title: 'Contact support',
              body: 'Open the existing support request and status area.',
              onTap: onContactSupport,
            ),
            _BuyerSubpageRow(
              icon: Icons.report_problem_outlined,
              title: 'Report a problem or unsafe interaction',
              body: 'Share deal or user details for review.',
              onTap: onReport,
            ),
          ],
        ),
        const _BuyerSubpageSection(
          title: 'Availability',
          children: [
            _BuyerSubpageRow(
              icon: Icons.cloud_off_outlined,
              title: 'Support delivery status',
              body:
                  'On-device request status is available. Online ticket delivery is not connected yet.',
            ),
          ],
        ),
      ],
    );
  }
}

class BuyerRewardsDetailPage extends StatelessWidget {
  const BuyerRewardsDetailPage({
    required this.accent,
    required this.onWallet,
    super.key,
  });

  final Color accent;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Rewards detail',
      subtitle:
          'A buyer-facing breakdown for earned, pending, and review-only reward states.',
      children: [
        MetricRow(
          accent: accent,
          values: const [
            Metric('\$128.45', 'Total earned'),
            Metric('\$24.80', 'Pending'),
            Metric('\$0.20', 'Next payout'),
          ],
        ),
        AlertBanner(
          accent: accent,
          title: 'Rewards stay tied to completed purchases',
          body:
              'This screen is UI-only for now. Backend rules will decide eligibility, timing, and review status.',
          icon: Icons.emoji_events_outlined,
        ),
        const InfoList(
          items: [
            'iPad Air deal: pending reward review',
            'Compact espresso machine: saved example',
            'Backup offers: no reward until a completed purchase',
          ],
        ),
        PrimaryButton(
          label: 'View buyer deal history',
          icon: Icons.history_outlined,
          color: accent,
          onPressed: onWallet,
        ),
      ],
    );
  }
}

class BuyerSupportStatusPage extends StatelessWidget {
  const BuyerSupportStatusPage({
    required this.accent,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final Color accent;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return _BuyerSubpageBlock(
      title: 'Support Status',
      subtitle: 'Review the support request state available on this device.',
      children: [
        const _BuyerSubpageSection(
          title: 'Current status',
          children: [
            _BuyerSubpageRow(
              icon: Icons.save_outlined,
              title: 'Request saved on this device',
              body:
                  'Online support submission and staff responses are not connected yet.',
              status: 'On-device only',
            ),
          ],
        ),
        BuyerPrimaryButton(
          label: actionLabel,
          onPressed: onAction,
          leading: const BuyerGlyphIcon(
            icon: Icons.arrow_back_rounded,
            slotSize: BuyerIconTokens.inline,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class SellerVerificationPage extends StatelessWidget {
  const SellerVerificationPage({
    required this.accent,
    required this.onFinish,
    super.key,
  });

  final Color accent;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Seller verification',
      subtitle:
          'Show verification states before a seller starts sending offers.',
      children: [
        StatusTimeline(
          accent: accent,
          items: const [
            'Profile complete',
            'Identity pending',
            'Ready to browse requests',
          ],
        ),
        PrimaryButton(
          label: 'Enter seller dashboard',
          icon: Icons.verified_user_outlined,
          color: accent,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class SellerDashboard extends StatelessWidget {
  const SellerDashboard({
    required this.sellerName,
    required this.accent,
    required this.sellerOfferSent,
    required this.offerSelected,
    required this.meetingConfirmed,
    required this.restoredSession,
    required this.onBrowse,
    required this.onBilling,
    required this.onHistory,
    super.key,
  });

  final String sellerName;
  final Color accent;
  final bool sellerOfferSent;
  final bool offerSelected;
  final bool meetingConfirmed;
  final bool restoredSession;
  final VoidCallback onBrowse;
  final VoidCallback onBilling;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: sellerName,
      subtitle: 'Find ready buyers and send focused offers.',
      children: [
        DashboardHero(
          accent: accent,
          title: 'Demand you can act on',
          body:
              'Browse buyer requests, check fit, then spend mock seller credits only when you choose to send an offer.',
          icon: Icons.travel_explore_outlined,
          actionLabel: 'Browse requests',
          onAction: onBrowse,
        ),
        AlertBanner(
          accent: accent,
          title: sellerOfferSent
              ? restoredSession
                    ? 'Offer restored on this device'
                    : 'Offer saved on this device'
              : 'Ready for buyer demand',
          body: sellerOfferSent
              ? offerSelected
                    ? 'Your offer was selected. The chat and deal workflow are active.'
                    : 'Your latest offer appears in offer history and buyer comparison while you review the flow.'
              : 'Browse active requests and send an offer to see the seller state update.',
          icon: sellerOfferSent
              ? Icons.offline_pin_outlined
              : Icons.search_outlined,
        ),
        if (meetingConfirmed)
          AlertBanner(
            accent: accent,
            title: 'Meeting confirmed',
            body:
                'Bring the item Saturday at 2:30 PM. Payment is handled offline at pickup.',
            icon: Icons.event_available_outlined,
          ),
        SectionLabel(
          title: 'High-fit requests',
          action: sellerOfferSent ? 'Offer sent' : 'Ready to browse',
        ),
        BuyerRequestCard(
          title: 'Buyer wants iPad Air this week',
          budget: '\$350 - \$480',
          location: '4.2 miles away',
          status: 'High fit',
          onTap: onBrowse,
        ),
        PrimaryButton(
          label: 'Browse buyer requests',
          icon: Icons.search,
          color: accent,
          onPressed: onBrowse,
        ),
        SecondaryButton(
          label: 'Offer history',
          color: accent,
          onPressed: onHistory,
        ),
        SecondaryButton(
          label: 'Seller tools',
          color: accent,
          onPressed: onBilling,
        ),
      ],
    );
  }
}

class MarketplacePage extends StatelessWidget {
  const MarketplacePage({
    required this.accent,
    required this.onOpen,
    super.key,
  });

  final Color accent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Request marketplace',
      subtitle:
          'Filter active buyer demand before sending an offer. Values here are prototype examples, not backend business rules.',
      children: [
        TextFormField(
          initialValue: 'tablet, espresso, furniture',
          decoration: const InputDecoration(labelText: 'Search requests'),
        ),
        const SizedBox(height: 12),
        LocationSearchPanel(
          accent: accent,
          title: 'Search by location',
          locationValue: 'Chicago, IL',
          radiusValue: 'Within 15 miles',
          hint:
              'Future Google Maps search: sellers can search a city, area, or map pin before browsing buyer requests.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              [
                'Nearby',
                'Electronics',
                'Budget matched',
                'New today',
                'Saved',
              ].map((label) {
                return SoftChip(
                  label: label,
                  color: accent.withValues(alpha: 0.12),
                  foreground: accent,
                );
              }).toList(),
        ),
        AlertBanner(
          accent: accent,
          title: 'Seller tools only',
          body:
              'Credits are seller-tool examples in this prototype. Hocalist does not process buyer item payments.',
          icon: Icons.storefront_outlined,
        ),
        ResponsiveCardGrid(
          children: [
            BuyerRequestCard(
              title: 'Looking for a used iPad Air',
              budget: '\$350 - \$480',
              location: 'Wicker Park',
              status: 'New',
              onTap: onOpen,
            ),
            BuyerRequestCard(
              title: 'Need office bookshelf',
              budget: 'Up to \$160',
              location: 'Logan Square',
              status: 'Saved',
              onTap: onOpen,
            ),
          ],
        ),
        SectionLabel(title: 'Other request states', action: 'Mock-only'),
        ResponsiveCardGrid(
          children: [
            EmptyStatePanel(
              accent: accent,
              title: 'No requests found nearby',
              body:
                  'Try expanding the location radius, changing the category, or saving this search for later.',
            ),
            ErrorStatePanel(
              accent: accent,
              title: 'Expired request',
              body:
                  'This buyer request is no longer accepting offers. Sellers should choose another active request.',
            ),
          ],
        ),
      ],
    );
  }
}

class SellerRequestDetailPage extends StatelessWidget {
  const SellerRequestDetailPage({
    required this.accent,
    required this.onOffer,
    super.key,
  });

  final Color accent;
  final VoidCallback onOffer;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Buyer request detail',
      subtitle:
          'Review the request, budget, location, and timing before offering.',
      children: [
        RouteContextBanner(
          accent: accent,
          label: 'Seller flow',
          text: 'Browse request -> check fit -> send offer',
        ),
        BuyerRequestCard(
          title: 'Looking for a used iPad Air',
          budget: '\$350 - \$480',
          location: 'Wicker Park',
          status: '12 offers max',
          onTap: onOffer,
        ),
        LocationSummaryCard(
          accent: accent,
          title: 'Request geography',
          address: 'Wicker Park area, Chicago',
          distance: '4.2 miles from Northside Tech service area',
          privacyNote:
              'Seller sees approximate buyer area until the buyer selects an offer and chat opens.',
        ),
        const InfoList(
          items: [
            'Buyer prefers pickup this week',
            'Reference photos attached',
            'Seller credits required: shown from admin-managed rules',
          ],
        ),
        PrimaryButton(
          label: 'Send offer',
          icon: Icons.send_outlined,
          color: accent,
          onPressed: onOffer,
        ),
      ],
    );
  }
}

class SendOfferPage extends StatelessWidget {
  const SendOfferPage({
    required this.accent,
    required this.price,
    required this.onPriceChanged,
    required this.onSubmit,
    super.key,
  });

  final Color accent;
  final String price;
  final ValueChanged<String> onPriceChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Send offer',
      subtitle: 'Price, terms, message, availability, and item photos.',
      children: [
        AppCard(
          child: Column(
            children: [
              TextFormField(
                initialValue: price,
                decoration: const InputDecoration(labelText: 'Offer price'),
                onChanged: onPriceChanged,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Saturday afternoon',
                decoration: const InputDecoration(labelText: 'Availability'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Wicker Park public pickup points',
                decoration: const InputDecoration(
                  labelText: 'Meetup or service area',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Great condition iPad Air with keyboard case.',
                decoration: const InputDecoration(labelText: 'Message'),
              ),
            ],
          ),
        ),
        LocationSummaryCard(
          accent: accent,
          title: 'Offer location preview',
          address: 'Seller can meet near Wicker Park',
          distance:
              'Public place selection happens if buyer chooses this offer',
          privacyNote:
              'Do not expose exact private addresses before seller selection.',
        ),
        UploadBox(accent: accent, label: 'Attach item photos'),
        PrimaryButton(
          label: 'Send offer',
          icon: Icons.outgoing_mail,
          color: accent,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class SellerOfferHistoryPage extends StatelessWidget {
  const SellerOfferHistoryPage({
    required this.accent,
    required this.sellerOfferSent,
    required this.offerSelected,
    required this.onOpen,
    super.key,
  });

  final Color accent;
  final bool sellerOfferSent;
  final bool offerSelected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Offer history',
      subtitle: 'Track open, selected, and retracted offers.',
      children: [
        AlertBanner(
          accent: accent,
          title: sellerOfferSent ? 'Latest offer saved' : 'Offer history ready',
          body: sellerOfferSent
              ? 'This list is now reacting to the offer you sent in this walkthrough.'
              : 'Send an offer from marketplace to update this history.',
          icon: Icons.history_outlined,
        ),
        SellerOfferCard(
          seller: 'Maya Chen',
          price: '\$420',
          detail: sellerOfferSent
              ? 'iPad Air request. Your newly submitted offer is visible here.'
              : 'iPad Air request. Buyer selected this offer.',
          status: offerSelected
              ? 'Selected'
              : sellerOfferSent
              ? 'Open'
              : 'Selected',
          accent: accent,
          onTap: onOpen,
        ),
        SellerOfferCard(
          seller: 'Owen Patel',
          price: '\$155',
          detail: 'Office bookshelf request.',
          status: 'Open',
          accent: accent,
          onTap: onOpen,
        ),
      ],
    );
  }
}

class SellerOfferDetailPage extends StatelessWidget {
  const SellerOfferDetailPage({
    required this.accent,
    required this.onChat,
    super.key,
  });

  final Color accent;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Seller offer detail',
      subtitle: 'Offer state, buyer request, and next action.',
      children: [
        RouteContextBanner(
          accent: accent,
          label: 'Seller flow',
          text: 'Track offer status and open chat after selection',
        ),
        SellerOfferCard(
          seller: 'Maya Chen',
          price: '\$420',
          detail: 'Selected by buyer. Chat is now open.',
          status: 'Selected',
          accent: accent,
          onTap: onChat,
        ),
        const InfoList(
          items: [
            'Offer can no longer be retracted after buyer selection',
            'Chatroom created',
            'Deal details pending confirmation',
          ],
        ),
        PrimaryButton(
          label: 'Open chat',
          icon: Icons.chat_bubble_outline,
          color: accent,
          onPressed: onChat,
        ),
      ],
    );
  }
}

class SellerBillingPage extends StatelessWidget {
  const SellerBillingPage({
    required this.accent,
    required this.onPayment,
    super.key,
  });

  final Color accent;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: 'Seller tools and credits',
      subtitle:
          'Phase 1 shows seller access tools only. Live plans, prices, and payment setup are deferred.',
      children: [
        MetricRow(
          accent: accent,
          values: const [
            Metric('42', 'Credits'),
            Metric('Mock', 'Plan'),
            Metric('Active', 'Status'),
          ],
        ),
        const InfoList(
          items: [
            'Seller plan name and pricing are admin-managed mock values',
            'Credit package examples are mock-only until owner-approved',
            'Credit usage rules come from admin configuration',
          ],
        ),
        PrimaryButton(
          label: 'Review seller access placeholder',
          icon: Icons.storefront_outlined,
          color: accent,
          onPressed: onPayment,
        ),
      ],
    );
  }
}

class SellerPaymentPage extends StatelessWidget {
  const SellerPaymentPage({
    required this.accent,
    required this.onDone,
    super.key,
  });

  final Color accent;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return FormStepPage(
      accent: accent,
      title: 'Seller access placeholder',
      subtitle:
          'Mock seller tools setup only. No live prices, card collection, or buyer item payment processing.',
      fields: const [
        MockFieldData('Status', 'Mock setup only'),
        MockFieldData('Seller contact', 'seller-tools@northsidetech.example'),
        MockFieldData('Plan label', 'Admin-managed mock value'),
      ],
      primaryLabel: 'Save mock seller-tools note',
      onPrimary: onDone,
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    super.key,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: title,
      subtitle: body,
      children: [
        AppCard(
          child: Center(child: Icon(icon, color: accent, size: 56)),
        ),
        PrimaryButton(
          label: primaryLabel,
          icon: Icons.arrow_forward,
          color: accent,
          onPressed: onPrimary,
        ),
        SecondaryButton(
          label: secondaryLabel,
          color: accent,
          onPressed: onSecondary,
        ),
      ],
    );
  }
}

class FormStepPage extends StatelessWidget {
  const FormStepPage({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.primaryLabel,
    required this.onPrimary,
    super.key,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final List<MockFieldData> fields;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return ScreenBlock(
      title: title,
      subtitle: subtitle,
      children: [
        AppCard(
          child: Column(
            children: fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  initialValue: field.value,
                  decoration: InputDecoration(labelText: field.label),
                ),
              );
            }).toList(),
          ),
        ),
        PrimaryButton(
          label: primaryLabel,
          icon: Icons.arrow_forward,
          color: accent,
          onPressed: onPrimary,
        ),
      ],
    );
  }
}
