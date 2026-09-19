part of '../main.dart';

class NoAccountHomeHeader extends StatelessWidget {
  const NoAccountHomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    final logoWidth = compact ? 172.0 : 174.0;
    final logoHeight = compact ? 82.0 : 90.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Hocalist Reverse Marketplace',
          image: true,
          child: SizedBox(
            width: logoWidth,
            height: logoHeight,
            child: const _HocalistWordmarkImage(),
          ),
        ),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {},
              icon: const Icon(
                Icons.notifications_none_outlined,
                color: HocalistTheme.primary,
                size: 32,
              ),
            ),
            Positioned(
              top: 11,
              right: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xffff1616),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HocalistWordmarkImage extends StatelessWidget {
  const _HocalistWordmarkImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/hocalist-wordmark.png',
      fit: BoxFit.contain,
      alignment: Alignment.topLeft,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}

class HocalistGlobalHeader extends StatelessWidget {
  const HocalistGlobalHeader({
    required this.role,
    required this.accent,
    required this.onNotifications,
    this.logoSlotReferenceWidth,
    this.showSavedIndicator = false,
    super.key,
  });

  final UserRole role;
  final Color accent;
  final VoidCallback onNotifications;
  final double? logoSlotReferenceWidth;
  final bool showSavedIndicator;

  @override
  Widget build(BuildContext context) {
    if (role == UserRole.buyer) {
      return BuyerTopLevelHeader(onNotifications: onNotifications);
    }

    final label = role == UserRole.buyer ? 'Buyer mode' : 'Seller mode';
    final media = MediaQuery.of(context);
    final compact = media.size.width < 430;
    final logoWidth = logoSlotReferenceWidth == null
        ? (compact ? 138.0 : 126.0)
        : ApprovedReplicaMetrics.resolve(
            availableWidth: media.size.width,
            textScaler: media.textScaler,
          ).geometry(logoSlotReferenceWidth!);
    final logoHeight = compact ? 62.0 : 60.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          label: 'Hocalist Reverse Marketplace',
          image: true,
          child: SizedBox(
            key: const ValueKey('hocalist-global-header-logo-slot'),
            width: logoWidth,
            height: logoHeight,
            child: const _HocalistWordmarkImage(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.topRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Container(
                    height: 44,
                    padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12),
                    decoration: BoxDecoration(
                      color: HocalistTheme.roleSurface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          role == UserRole.buyer
                              ? Icons.check_circle_outline
                              : Icons.storefront_outlined,
                          color: accent,
                          size: 21,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: accent,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Notifications',
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onNotifications,
                      icon: const Icon(
                        Icons.notifications_none_outlined,
                        color: HocalistTheme.primary,
                        size: 30,
                      ),
                    ),
                    Positioned(
                      top: 9,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xffff1616),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HomeRoleActionCard extends StatelessWidget {
  const HomeRoleActionCard({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.icon,
    required this.color,
    required this.surface,
    required this.imageAsset,
    required this.onTap,
    this.aspectRatio = 786 / 303,
    super.key,
  });

  final String title;
  final String body;
  final String buttonLabel;
  final IconData icon;
  final Color color;
  final Color surface;
  final String imageAsset;
  final VoidCallback onTap;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $body',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    imageAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
                IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(title), Text(body), Text(buttonLabel)],
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

class HomeBenefitPanel extends StatelessWidget {
  const HomeBenefitPanel({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const benefits = [
      _HomeBenefitData(
        Icons.volunteer_activism,
        'Buyers Earn Commissions From Sellers Targeting',
        'You get rewards every time you buy through the app.',
        HocalistTheme.giftPurple,
        Colors.white,
      ),
      _HomeBenefitData(
        Icons.track_changes,
        'Businesses Don\'t Waste Money On Ads Just To Reach People',
        'Sellers target real buyers who are actively looking.',
        HocalistTheme.sellerGreen,
        Colors.white,
      ),
      _HomeBenefitData(
        Icons.handshake_outlined,
        'A System designed to give both sides & Better Outcome',
        'Fair, transparent, and built to create more value for everyone.',
        HocalistTheme.actionBlue,
        Colors.white,
      ),
      _HomeBenefitData(
        Icons.verified_user_outlined,
        'Safe, private, and in your control',
        'You decide who to talk to and complete the deal on your terms.',
        Color(0xffd9d7ff),
        HocalistTheme.actionBlue,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe8ebf5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1200036c),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: List.generate(benefits.length, (index) {
          final item = benefits[index];
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 18,
                  vertical: compact ? 13 : 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: item.background,
                      foregroundColor: item.foreground,
                      child: Icon(item.icon, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.body,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: HocalistTheme.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index != benefits.length - 1)
                const Divider(height: 1, indent: 78, color: Color(0xffedf0f8)),
            ],
          );
        }),
      ),
    );
  }
}

class _HomeBenefitData {
  const _HomeBenefitData(
    this.icon,
    this.title,
    this.body,
    this.background,
    this.foreground,
  );

  final IconData icon;
  final String title;
  final String body;
  final Color background;
  final Color foreground;
}

class HocalistVideoPreview extends StatelessWidget {
  const HocalistVideoPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 390;
    return AspectRatio(
      aspectRatio: narrow ? 1.45 : 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: HocalistTheme.roleSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1400036c),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/buyer_onboarding/buyer-video-welcome.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      HocalistTheme.primary.withValues(alpha: 0.16),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: HocalistTheme.actionBlue,
                  size: 44,
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoControls(),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  '0:00 / 1:00',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: HocalistTheme.badgeSize,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: 0.18,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.24),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      HocalistTheme.actionBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.volume_up_outlined,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Icon(Icons.fullscreen, color: Colors.white, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeFaqList extends StatefulWidget {
  const HomeFaqList({this.expandAll = false, super.key});

  final bool expandAll;

  @override
  State<HomeFaqList> createState() => _HomeFaqListState();
}

class _HomeFaqListState extends State<HomeFaqList> {
  int openIndex = 0;

  @override
  Widget build(BuildContext context) {
    const questions = [
      _FaqData(
        Icons.question_mark,
        'What is Hocalist?',
        'Hocalist is a reverse marketplace where buyers post what they need and sellers compete for the opportunity to earn your business.',
        HocalistTheme.roleSurface,
        HocalistTheme.actionBlue,
      ),
      _FaqData(
        Icons.card_giftcard,
        'Does Hocalist sell the items I buy?',
        'No. Buyers choose sellers and arrange the item handoff directly after selection.',
        Color(0xfffff1d8),
        HocalistTheme.rewardGold,
      ),
      _FaqData(
        Icons.storefront_outlined,
        'Why pay through Hocalist?',
        'Seller payments are for seller tools, credits, and access. Item payment stays outside Hocalist.',
        HocalistTheme.roleSurface,
        HocalistTheme.actionBlue,
      ),
      _FaqData(
        Icons.volunteer_activism,
        'What Incentive do I get as a buyer?',
        'Buyers can earn rewards when sellers target and win their business through the app.',
        Color(0xffe8f7ed),
        HocalistTheme.sellerGreen,
      ),
      _FaqData(
        Icons.track_changes,
        'What Incentive do I get as a seller?',
        'Sellers can target real buyers who are actively looking instead of spending broadly on ads.',
        Color(0xfffff0df),
        Color(0xffff7b20),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe8ebf5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1200036c),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: List.generate(questions.length, (index) {
          final item = questions[index];
          final expanded = widget.expandAll || index == openIndex;
          return Column(
            children: [
              InkWell(
                onTap: () {
                  if (widget.expandAll) return;
                  setState(() => openIndex = expanded ? -1 : index);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: expanded ? 15 : 10,
                  ),
                  child: Row(
                    crossAxisAlignment: expanded
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: item.background,
                        foregroundColor: item.color,
                        child: Icon(item.icon, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.question,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (expanded)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  item.answer,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: HocalistTheme.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: HocalistTheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (index != questions.length - 1)
                const Divider(height: 1, indent: 72, color: Color(0xffedf0f8)),
            ],
          );
        }),
      ),
    );
  }
}

class _FaqData {
  const _FaqData(
    this.icon,
    this.question,
    this.answer,
    this.background,
    this.color,
  );

  final IconData icon;
  final String question;
  final String answer;
  final Color background;
  final Color color;
}

class HomeStartBanner extends StatelessWidget {
  const HomeStartBanner({required this.onCreateAccount, super.key});

  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xfff0edff),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1000036c),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ready to start earning?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: HocalistTheme.actionBlue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Join thousands of buyers earning rewards every day on Hocalist.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
          final button = _HomeStartButton(onCreateAccount: onCreateAccount);
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _RewardGiftMark(),
                    const SizedBox(width: 12),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }
          return Row(
            children: [
              const _RewardGiftMark(),
              const SizedBox(width: 12),
              Expanded(child: copy),
              const SizedBox(width: 10),
              SizedBox(width: 190, child: button),
            ],
          );
        },
      ),
    );
  }
}

class _RewardGiftMark extends StatelessWidget {
  const _RewardGiftMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 82,
      child: Image.asset(
        'assets/home/ready-gift-art.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _HomeStartButton extends StatelessWidget {
  const _HomeStartButton({required this.onCreateAccount});

  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: HocalistTheme.actionBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          onPressed: onCreateAccount,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('Create Free Account')),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'It\'s free and takes 1 minute',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: HocalistTheme.muted),
        ),
      ],
    );
  }
}

class NoAccountHomeNavigation extends StatelessWidget {
  const NoAccountHomeNavigation({
    required this.onHome,
    required this.onTrends,
    required this.onWinners,
    required this.onSignup,
    this.selectedIndex = 0,
    super.key,
  });

  final VoidCallback onHome;
  final VoidCallback onTrends;
  final VoidCallback onWinners;
  final VoidCallback onSignup;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ApprovedNoAccountBottomNavigation(
      selectedIndex: selectedIndex,
      onHome: onHome,
      onHocatrends: onTrends,
      onWinners: onWinners,
      onSignup: onSignup,
    );
  }
}

class HocalistBrandTitle extends StatelessWidget {
  const HocalistBrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hocalist',
      image: true,
      child: Container(
        height: 38,
        constraints: const BoxConstraints(maxWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: HocalistTheme.primary.withValues(alpha: 0.14),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Image.asset(
          'assets/brand/hocalist-wordmark.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class MockFieldData {
  const MockFieldData(this.label, this.value);
  final String label;
  final String value;
}

class AppPreviewPanel extends StatelessWidget {
  const AppPreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, color: HocalistTheme.buyer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Buyer request',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SoftChip(
                label: '2 offers',
                color: HocalistTheme.roleSurface,
                foreground: HocalistTheme.buyer,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'iPad Air, 5th gen or newer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '\$350 - \$480 - pickup within 12 miles',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
          const Divider(height: 22),
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                color: HocalistTheme.seller,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Northside Tech - \$420',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: HocalistTheme.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProcessStrip extends StatelessWidget {
  const ProcessStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        Icons.edit_note_outlined,
        'Post a request',
        'Tell nearby sellers what you need.',
      ),
      (
        Icons.local_offer_outlined,
        'Compare offers',
        'Review price, condition, and timing.',
      ),
      (
        Icons.chat_bubble_outline,
        'Select and chat',
        'Choose a seller before private chat opens.',
      ),
      (
        Icons.handshake_outlined,
        'Meet and pay offline',
        'Arrange the handoff; item payment stays outside Hocalist.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Semantics(
          label: 'How Hocalist works in four steps',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(items.length, (index) {
              final item = items[index];
              return SizedBox(
                width: width,
                child: AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: HocalistTheme.roleSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              item.$1,
                              color: HocalistTheme.primary,
                              size: 22,
                            ),
                            Positioned(
                              right: -8,
                              top: -8,
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: HocalistTheme.primary,
                                foregroundColor: Colors.white,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: HocalistTheme.badgeSize,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? HocalistTheme.darkMuted
                                        : HocalistTheme.muted,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    required this.children,
    this.breakpoint = 680,
    super.key,
  });

  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= breakpoint ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      },
    );
  }
}

class DashboardHero extends StatelessWidget {
  const DashboardHero({
    required this.accent,
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final Color accent;
  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
            child: Icon(icon),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: actionLabel,
            icon: Icons.arrow_forward,
            color: accent,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({required this.title, required this.action, super.key});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(action, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class RouteContextBanner extends StatelessWidget {
  const RouteContextBanner({
    required this.accent,
    required this.label,
    required this.text,
    super.key,
  });

  final Color accent;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.route_outlined, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: accent),
                  ),
                  TextSpan(
                    text: text,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBackScope extends InheritedWidget {
  const _TitleBackScope({required this.onBack, required super.child});

  final VoidCallback? onBack;

  static VoidCallback? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TitleBackScope>()
        ?.onBack;
  }

  @override
  bool updateShouldNotify(_TitleBackScope oldWidget) {
    return oldWidget.onBack != onBack;
  }
}

class ScreenBlock extends StatelessWidget {
  const ScreenBlock({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final onBack = _TitleBackScope.maybeOf(context);
    final titleStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
      color: HocalistTheme.primary,
      fontWeight: FontWeight.w900,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
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
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title, style: titleStyle)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
        ),
        const SizedBox(height: 18),
        ...children.expand((child) => [child, const SizedBox(height: 12)]),
      ],
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.foreground = Colors.white,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accessibility = Theme.of(
      context,
    ).extension<HocalistAccessibilityVisuals>();
    final highContrast = accessibility?.buttonBorderWidth == 2;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: highContrast
              ? accessibility!.buttonBackground
              : color,
          foregroundColor: highContrast
              ? accessibility!.buttonForeground
              : foreground,
          minimumSize: const Size.fromHeight(
            HocalistButtonTokens.minimumHeight,
          ),
          padding: HocalistButtonTokens.contentPadding,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              accessibility?.buttonRadius ?? HocalistButtonTokens.radius,
            ),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: HocalistButtonTokens.iconSize),
        label: Text(label),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.color,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accessibility = Theme.of(
      context,
    ).extension<HocalistAccessibilityVisuals>();
    final effectiveColor = accessibility?.buttonBorderWidth == 2
        ? accessibility!.buttonBackground
        : color;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: effectiveColor,
          side: BorderSide(
            color: effectiveColor,
            width: accessibility?.buttonBorderWidth ?? 1,
          ),
          minimumSize: const Size.fromHeight(
            HocalistButtonTokens.minimumHeight,
          ),
          padding: HocalistButtonTokens.contentPadding,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              accessibility?.buttonRadius ?? HocalistButtonTokens.radius,
            ),
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class RoleCard extends StatelessWidget {
  const RoleCard({
    required this.title,
    required this.body,
    required this.color,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String body;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
        ],
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  const MenuCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: HocalistTheme.muted),
        ],
      ),
    );
  }
}

class LocationSearchPanel extends StatelessWidget {
  const LocationSearchPanel({
    required this.accent,
    required this.title,
    required this.locationValue,
    required this.radiusValue,
    required this.hint,
    super.key,
  });

  final Color accent;
  final String title;
  final String locationValue;
  final String radiusValue;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
                child: const Icon(Icons.travel_explore_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MapOptionsButton(
                accent: accent,
                title: title,
                address: locationValue,
                distance: radiusValue,
                note: hint,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: locationValue,
            decoration: const InputDecoration(
              labelText: 'City, area, address, or map pin',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: radiusValue,
            decoration: const InputDecoration(
              labelText: 'Search radius or distance',
              prefixIcon: Icon(Icons.radar_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
        ],
      ),
    );
  }
}

class LocationSummaryCard extends StatelessWidget {
  const LocationSummaryCard({
    required this.accent,
    required this.title,
    required this.address,
    required this.distance,
    required this.privacyNote,
    super.key,
  });

  final Color accent;
  final String title;
  final String address;
  final String distance;
  final String privacyNote;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
                child: const Icon(Icons.location_on_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              MapOptionsButton(
                accent: accent,
                title: title,
                address: address,
                distance: distance,
                note: privacyNote,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip(
                label: distance,
                color: accent.withValues(alpha: 0.12),
                foreground: accent,
              ),
              const SoftChip(
                label: 'Approximate until selected',
                color: HocalistTheme.roleSurface,
                foreground: HocalistTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            privacyNote,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
        ],
      ),
    );
  }
}

class MapOptionsButton extends StatelessWidget {
  const MapOptionsButton({
    required this.accent,
    required this.title,
    required this.address,
    required this.distance,
    required this.note,
    super.key,
  });

  final Color accent;
  final String title;
  final String address;
  final String distance;
  final String note;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Map options',
      icon: const Icon(Icons.more_horiz),
      color: accent,
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      address,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    MapPreviewSurface(accent: accent),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SoftChip(
                          label: distance,
                          color: accent.withValues(alpha: 0.12),
                          foreground: accent,
                        ),
                        const SoftChip(
                          label: 'Future Google Maps',
                          color: Color(0xffeff4ff),
                          foreground: HocalistTheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      note,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: HocalistTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Close',
                            color: accent,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class MapPreviewSurface extends StatelessWidget {
  const MapPreviewSurface({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 136,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xffeaf1f4),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _MapPreviewPainter(accent: accent)),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HocalistTheme.surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: HocalistTheme.text.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(Icons.location_pin, color: accent, size: 30),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: HocalistTheme.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Google Maps preview placeholder',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final thinRoadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final radiusPaint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final radiusBorderPaint = Paint()
      ..color = accent.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.46),
      size.shortestSide * 0.36,
      radiusPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.46),
      size.shortestSide * 0.36,
      radiusBorderPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.25),
      Offset(size.width * 0.92, size.height * 0.18),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.85),
      Offset(size.width * 0.82, size.height * 0.28),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.05, size.height * 0.58),
      Offset(size.width * 0.95, size.height * 0.72),
      thinRoadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.02),
      Offset(size.width * 0.22, size.height * 0.96),
      thinRoadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

class SettingsProfileHeader extends StatelessWidget {
  const SettingsProfileHeader({
    required this.accent,
    required this.role,
    super.key,
  });

  final Color accent;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final isSeller = role == UserRole.seller;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: accent.withValues(alpha: 0.14),
                foregroundColor: accent,
                child: const Icon(Icons.person_outline, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSeller ? 'Northside Tech profile' : 'Maya Chen profile',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSeller
                          ? 'Seller profile, service area, request alerts, and local progress.'
                          : 'Buyer profile, request privacy, offer alerts, and local progress.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: HocalistTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip(
                label: 'Verified email',
                color: accent.withValues(alpha: 0.12),
                foreground: accent,
              ),
              const SoftChip(
                label: 'Approximate location',
                color: Color(0xffeff4ff),
                foreground: HocalistTheme.primary,
              ),
              const SoftChip(
                label: 'Offline item payment',
                color: HocalistTheme.roleSurface,
                foreground: HocalistTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title: title, action: 'Settings'),
        AppCard(
          child: Column(
            children: children.indexed.map((entry) {
              final index = entry.$1;
              final child = entry.$2;
              final isLast = index == children.length - 1;
              return Column(
                children: [child, if (!isLast) const Divider(height: 24)],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.status,
    required this.accent,
    this.asset,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String status;
  final Color accent;
  final String? asset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap:
          onTap ??
          () {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text('$title is ready for backend wiring.')),
              );
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.12),
              foregroundColor: accent,
              child: asset == null
                  ? Icon(icon)
                  : Image.asset(asset!, width: 24, height: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SoftChip(
                        label: status,
                        color: accent.withValues(alpha: 0.1),
                        foreground: accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HocalistTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: HocalistTheme.muted),
          ],
        ),
      ),
    );
  }
}

class SettingsPreferenceRow extends StatefulWidget {
  const SettingsPreferenceRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.enabled,
    required this.accent,
    this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool enabled;
  final Color accent;
  final ValueChanged<bool>? onChanged;

  @override
  State<SettingsPreferenceRow> createState() => _SettingsPreferenceRowState();
}

class _SettingsPreferenceRowState extends State<SettingsPreferenceRow> {
  late bool localEnabled;

  @override
  void initState() {
    super.initState();
    localEnabled = widget.enabled;
  }

  @override
  void didUpdateWidget(covariant SettingsPreferenceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      localEnabled = widget.enabled;
    }
  }

  void toggle(bool value) {
    if (widget.onChanged != null) {
      widget.onChanged!(value);
      return;
    }

    setState(() => localEnabled = value);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${widget.title} ${value ? 'enabled' : 'disabled'}.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged == null ? localEnabled : widget.enabled;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: widget.accent.withValues(alpha: 0.12),
          foregroundColor: widget.accent,
          child: Icon(widget.icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                widget.body,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Switch(
          value: enabled,
          activeThumbColor: widget.accent,
          onChanged: toggle,
        ),
      ],
    );
  }
}

class TextSizePreferenceCard extends StatelessWidget {
  const TextSizePreferenceCard({
    required this.accent,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Color accent;
  final AppTextSize value;
  final ValueChanged<AppTextSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          foregroundColor: accent,
          child: const Icon(Icons.text_fields_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text size', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Make app text easier to read on this device.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: AppTextSize.values.indexOf(value).toDouble(),
                      min: 0,
                      max: (AppTextSize.values.length - 1).toDouble(),
                      divisions: AppTextSize.values.length - 1,
                      label: value.label,
                      activeColor: accent,
                      onChanged: (next) {
                        onChanged(AppTextSize.values[next.round()]);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 78),
                    child: Text(
                      value.label,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
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

class AlertBanner extends StatelessWidget {
  const AlertBanner({
    required this.accent,
    required this.title,
    required this.body,
    required this.icon,
    super.key,
  });

  final Color accent;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: accent),
                ),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    super.key,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String body;
  final String time;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        time,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
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

class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({
    required this.accent,
    required this.title,
    required this.body,
    super.key,
  });

  final Color accent;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, color: accent, size: 36),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
          ),
        ],
      ),
    );
  }
}

class LoadingStatePanel extends StatelessWidget {
  const LoadingStatePanel({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: accent, strokeWidth: 3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading updated safety content from admin-managed settings...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorStatePanel extends StatelessWidget {
  const ErrorStatePanel({
    required this.accent,
    required this.title,
    required this.body,
    super.key,
  });

  final Color accent;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: HocalistTheme.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Retry',
                  color: accent,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ModePill extends StatelessWidget {
  const ModePill({required this.role, required this.accent, super.key});

  final UserRole role;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SoftChip(
      label: role == UserRole.buyer ? 'Buyer mode' : 'Seller mode',
      color: accent.withValues(alpha: 0.12),
      foreground: accent,
    );
  }
}

class SoftChip extends StatelessWidget {
  const SoftChip({
    required this.label,
    required this.color,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class Metric {
  const Metric(this.value, this.label);
  final String value;
  final String label;
}

class MetricRow extends StatelessWidget {
  const MetricRow({required this.accent, required this.values, super.key});

  final Color accent;
  final List<Metric> values;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: values.map((metric) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class BuyerRequestCard extends StatelessWidget {
  const BuyerRequestCard({
    required this.title,
    required this.budget,
    required this.location,
    required this.status,
    required this.onTap,
    super.key,
  });

  final String title;
  final String budget;
  final String location;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(
                child: SoftChip(
                  label: 'Buyer request',
                  color: HocalistTheme.roleSurface,
                  foreground: HocalistTheme.buyer,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    status,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  budget,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HocalistTheme.primary,
                  ),
                ),
              ),
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: HocalistTheme.muted,
              ),
              Flexible(
                child: Text(
                  location,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SellerOfferCard extends StatelessWidget {
  const SellerOfferCard({
    required this.seller,
    required this.price,
    required this.detail,
    required this.status,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final String seller;
  final String price;
  final String detail;
  final String status;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  seller,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                price,
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.star, size: 16, color: Color(0xffffba35)),
              const SizedBox(width: 4),
              Text('4.9 rating', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              SoftChip(
                label: status,
                color: accent.withValues(alpha: 0.12),
                foreground: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    required this.accent,
    required this.title,
    required this.body,
    super.key,
  });

  final Color accent;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
            child: const Icon(Icons.verified_user_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  body,
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

class UploadBox extends StatelessWidget {
  const UploadBox({required this.accent, required this.label, super.key});

  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_outlined, color: accent),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: accent),
            ),
            Text(
              'Uploads are saved as part of this local review flow.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class OfflinePaymentNotice extends StatelessWidget {
  const OfflinePaymentNotice({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Offline payment reminder: Hocalist does not process, hold, ship, escrow, or guarantee item payment. Buyer and seller finalize item payment outside the app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class DealSummary extends StatelessWidget {
  const DealSummary({
    required this.accent,
    required this.title,
    required this.price,
    required this.detail,
    super.key,
  });

  final Color accent;
  final String title;
  final String price;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          const Divider(height: 24),
          Row(
            children: [
              const Text('Agreed item price'),
              const Spacer(),
              Text(
                price,
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: color == HocalistTheme.softSurface
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text),
      ),
    );
  }
}

class ActionChoice extends StatelessWidget {
  const ActionChoice({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  body,
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

class RecordCard extends StatelessWidget {
  const RecordCard({
    required this.title,
    required this.meta,
    required this.amount,
    super.key,
  });

  final String title;
  final String meta;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  meta,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: HocalistTheme.muted),
                ),
              ],
            ),
          ),
          Text(amount, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class InfoList extends StatelessWidget {
  const InfoList({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.chevron_right, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class StatusTimeline extends StatelessWidget {
  const StatusTimeline({required this.accent, required this.items, super.key});

  final Color accent;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: accent, size: 19),
                const SizedBox(width: 10),
                Expanded(child: Text(item)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
