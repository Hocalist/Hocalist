import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local_marketplace_repository.dart';
import '../../theme/input_foundation.dart';
import '../../theme/seller_ui_foundation.dart';

enum SellerProfilePhotoAction { camera, gallery, remove }

class ApprovedSellerProfilePage extends StatelessWidget {
  const ApprovedSellerProfilePage({
    required this.sellerName,
    required this.onBack,
    required this.onEditProfile,
    this.onProfilePhotoAction,
    super.key,
  });

  final String sellerName;
  final VoidCallback onBack;
  final VoidCallback onEditProfile;
  final ValueChanged<SellerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerProfilePage'),
      title: 'Seller Profile',
      subtitle: 'Review the trust and service details buyers can see.',
      onBack: onBack,
      children: [
        _SellerProfileSummary(
          sellerName: sellerName,
          onProfilePhotoAction: onProfilePhotoAction,
        ),
        const _SellerSubpageSection(
          title: 'Public details',
          children: [
            _SellerSubpageRow(
              icon: Icons.category_outlined,
              title: 'Seller categories',
              body: 'Electronics, tablets, and accessories.',
              status: 'Visible to buyers',
            ),
            _SellerSubpageRow(
              icon: Icons.travel_explore_outlined,
              title: 'Service area',
              body: 'Chicago north side and nearby public meetup locations.',
              status: 'Within 15 miles',
            ),
            _SellerSubpageRow(
              icon: Icons.verified_user_outlined,
              title: 'Trust details',
              body: 'Verification, ratings, and completed-deal history.',
              status: 'Verified seller',
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerProfileEdit'),
          label: 'Edit profile',
          onPressed: onEditProfile,
          leading: const Icon(
            Icons.edit_outlined,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class ApprovedSellerSettingsPage extends StatelessWidget {
  const ApprovedSellerSettingsPage({
    required this.darkMode,
    required this.textSizeLabel,
    required this.onBack,
    required this.onEditProfile,
    required this.onThemeChanged,
    required this.onAccessibility,
    super.key,
  });

  final bool darkMode;
  final String textSizeLabel;
  final VoidCallback onBack;
  final VoidCallback onEditProfile;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onAccessibility;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerSettingsPage'),
      title: 'Account Settings',
      subtitle: 'Manage your Seller account, preferences, and privacy.',
      onBack: onBack,
      children: [
        _SellerSubpageSection(
          title: 'Account',
          children: [
            _SellerSubpageRow(
              icon: Icons.storefront_outlined,
              title: 'Seller information',
              body: 'Review and update your Seller profile information.',
              onTap: onEditProfile,
            ),
            const _SellerSubpageRow(
              icon: Icons.lock_outline,
              title: 'Password & security',
              body:
                  'Password changes require connected account authentication.',
              status: 'Not currently available',
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Preferences',
          children: [
            _SellerPreferenceSwitch(
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
            _SellerSubpageRow(
              icon: Icons.accessibility_new,
              title: 'Accessibility',
              body: 'Text size, font readability, and button visibility.',
              status: textSizeLabel,
              onTap: onAccessibility,
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Marketplace privacy',
          children: [
            _SellerSubpageRow(
              icon: Icons.visibility_outlined,
              title: 'Public Seller visibility',
              body:
                  'Buyers see trust and service details without private contact information.',
              status: 'Limited profile',
            ),
            _SellerSubpageRow(
              icon: Icons.location_on_outlined,
              title: 'Service-area privacy',
              body:
                  'Only your approximate service area is shown before a meeting is confirmed.',
              status: 'Approximate location',
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Account management',
          children: [
            _SellerSubpageRow(
              icon: Icons.manage_accounts_outlined,
              title: 'No account-management actions available',
              body:
                  'Delete and export actions remain hidden until secure account services support them.',
            ),
          ],
        ),
      ],
    );
  }
}

class ApprovedSellerEditProfilePage extends StatelessWidget {
  const ApprovedSellerEditProfilePage({
    required this.name,
    required this.onNameChanged,
    required this.onBack,
    required this.onDone,
    this.onProfilePhotoAction,
    super.key,
  });

  final String name;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final ValueChanged<SellerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerEditProfilePage'),
      title: 'Edit Profile',
      subtitle: 'Keep your Seller information accurate and concise.',
      onBack: onBack,
      children: [
        _SellerSubpageSection(
          title: 'Profile picture',
          children: [
            _SellerProfilePhotoEditor(
              sellerName: name,
              onProfilePhotoAction: onProfilePhotoAction,
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Seller information',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Builder(
                builder: (context) {
                  final metrics = ApprovedReplicaScope.of(context);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SellerProfileField(
                        initialValue: name,
                        label: 'Store or seller name',
                        textInputAction: TextInputAction.next,
                        onChanged: onNameChanged,
                      ),
                      SizedBox(
                        height: metrics.spacing(
                          HocalistInputTokens.relatedFieldSpacing,
                        ),
                      ),
                      const _SellerProfileField(
                        initialValue: 'northside.tech@example.com',
                        label: 'Email',
                        readOnly: true,
                        helperText:
                            'Email changes require account verification.',
                      ),
                      SizedBox(height: metrics.spacing(14)),
                      const _SellerProfileField(
                        initialValue: 'Electronics, tablets, accessories',
                        label: 'Seller categories',
                      ),
                      SizedBox(height: metrics.spacing(14)),
                      const _SellerProfileField(
                        initialValue: 'Chicago north side',
                        label: 'Service area',
                        helperText:
                            'Your exact meetup location remains private until confirmed in chat.',
                      ),
                      SizedBox(height: metrics.spacing(14)),
                      const _SellerProfileField(
                        initialValue:
                            'Verified seller; public pickup preferred.',
                        label: 'Profile note',
                        maxLines: 2,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerSaveProfile'),
          label: 'Save profile',
          onPressed: onDone,
          leading: const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class ApprovedSellerSafetyGuidePage extends StatelessWidget {
  const ApprovedSellerSafetyGuidePage({
    required this.onBack,
    required this.onHelp,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerSafetyGuidePage'),
      title: 'Safety guide',
      subtitle: 'Practical steps for safer local Seller meetups.',
      onBack: onBack,
      children: [
        const _SellerSubpageSection(
          title: 'Before the meetup',
          children: [
            _SellerSubpageRow(
              icon: Icons.location_on_outlined,
              title: 'Choose a public meeting place',
              body:
                  'Use a busy, well-lit location and keep the agreed location visible in the deal.',
              status: 'Recommended for every meetup',
            ),
            _SellerSubpageRow(
              icon: Icons.inventory_2_outlined,
              title: 'Prepare the exact agreed item',
              body:
                  'Bring the product, included accessories, and any condition details shared with the buyer.',
              status: 'Match the active offer',
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'During the meetup',
          children: [
            _SellerSubpageRow(
              icon: Icons.fact_check_outlined,
              title: 'Let the buyer inspect first',
              body:
                  'Give the buyer time to confirm the item matches the agreed offer before completing the deal.',
            ),
            _SellerSubpageRow(
              icon: Icons.password_outlined,
              title: 'Use the buyer PIN only after the deal',
              body:
                  'Enter the PIN only after the buyer confirms the offline transaction is complete.',
            ),
            _SellerSubpageRow(
              icon: Icons.payments_outlined,
              title: 'Remember item payment stays offline',
              body:
                  'Hocalist does not hold item payments, provide escrow, ship items, or guarantee payment.',
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Need help?',
          children: [
            _SellerSubpageRow(
              icon: Icons.support_agent_outlined,
              title: 'Open Help & Support',
              body:
                  'Ask a question or save a safety concern for support review.',
              status: 'Get support',
              onTap: onHelp,
            ),
          ],
        ),
      ],
    );
  }
}

class ApprovedSellerHelpSupportPage extends StatelessWidget {
  const ApprovedSellerHelpSupportPage({
    required this.onBack,
    required this.onSafety,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onSafety;

  Future<void> _showAnswer(
    BuildContext context, {
    required String title,
    required String answer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _SellerHelpAnswerSheet(title: title, answer: answer),
    );
  }

  Future<void> _showForm(BuildContext context, {required bool safety}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SellerSupportFormSheet(safety: safety),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safety
                ? 'Safety concern saved for support connection.'
                : 'Support request saved for ticket connection.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerHelpSupportPage'),
      title: 'Help & Support',
      subtitle: 'Answers and support for your Seller activity.',
      onBack: onBack,
      children: [
        _SellerSubpageSection(
          title: 'Frequently asked questions',
          children: [
            _SellerSubpageRow(
              icon: Icons.toll_outlined,
              title: 'How targeting credits work',
              body: 'See when credits are used, restored, or charged.',
              status: 'Read answer',
              onTap: () => _showAnswer(
                context,
                title: 'How targeting credits work',
                answer:
                    'Your available balance is used only for Seller targeting and platform access. Credit activity and restoration appear in Plans & credits. Exact rules will come from backend-managed configuration.',
              ),
            ),
            _SellerSubpageRow(
              icon: Icons.handshake_outlined,
              title: 'After a buyer selects your offer',
              body: 'Review the chat, deal details, meetup, and PIN flow.',
              status: 'Read answer',
              onTap: () => _showAnswer(
                context,
                title: 'After a buyer selects your offer',
                answer:
                    'The selected deal opens in chat. Confirm the offer and meeting details there, complete the meetup offline, then enter the buyer PIN only after the buyer confirms the transaction.',
              ),
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Contact support',
          children: [
            _SellerSubpageRow(
              icon: Icons.support_agent_outlined,
              title: 'Ask for help',
              body: 'Save a question with the details support will need.',
              status: 'Open support form',
              onTap: () => _showForm(context, safety: false),
            ),
            _SellerSubpageRow(
              icon: Icons.report_problem_outlined,
              title: 'Report a safety concern',
              body: 'Save details about an unsafe user, message, or meetup.',
              status: 'Open safety form',
              onTap: () => _showForm(context, safety: true),
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Safety',
          children: [
            _SellerSubpageRow(
              icon: Icons.health_and_safety_outlined,
              title: 'Seller safety guide',
              body: 'Review the current meetup and PIN safety guidance.',
              status: 'View guide',
              onTap: onSafety,
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Connection status',
          children: [
            _SellerSubpageRow(
              icon: Icons.cloud_sync_outlined,
              title: 'Support UI is ready',
              body:
                  'Ticket delivery, attachments, and live case updates connect when support services are enabled.',
              status: 'Local preview data',
            ),
          ],
        ),
      ],
    );
  }
}

class _SellerHelpAnswerSheet extends StatelessWidget {
  const _SellerHelpAnswerSheet({required this.title, required this.answer});

  final String title;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return _SellerActionSheet(
      key: const Key('sellerHelpAnswerSheet'),
      icon: Icons.help_outline_rounded,
      title: title,
      subtitle: 'Seller help answer',
      onClose: () => Navigator.pop(context),
      children: [
        Text(
          answer,
          style: sellerText(
            metrics,
            12,
            color: SellerUiColors.body,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        SellerPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _SellerSupportFormSheet extends StatefulWidget {
  const _SellerSupportFormSheet({required this.safety});

  final bool safety;

  @override
  State<_SellerSupportFormSheet> createState() =>
      _SellerSupportFormSheetState();
}

class _SellerSupportFormSheetState extends State<_SellerSupportFormSheet> {
  String _topic = 'Deal or meetup';

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final accent = widget.safety
        ? SellerUiColors.red
        : SellerUiColors.primaryBright;
    return _SellerActionSheet(
      key: const Key('sellerSupportFormSheet'),
      icon: widget.safety
          ? Icons.report_problem_outlined
          : Icons.support_agent_outlined,
      title: widget.safety ? 'Report a safety concern' : 'Contact support',
      subtitle: widget.safety
          ? 'Share the details our safety team should review.'
          : 'Share the details our support team should review.',
      accentColor: accent,
      onClose: () => Navigator.pop(context),
      children: [
        Text(
          'TOPIC',
          style: sellerText(
            metrics,
            10,
            weight: FontWeight.w800,
            color: SellerUiColors.muted,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          key: const Key('sellerSupportTopic'),
          initialValue: _topic,
          isExpanded: true,
          dropdownColor: SellerUiColors.white,
          borderRadius: BorderRadius.circular(metrics.geometry(12)),
          menuMaxHeight: metrics.geometry(240),
          style: sellerText(metrics, 12.5, weight: FontWeight.w700),
          decoration: _sellerSheetInputDecoration(context, ''),
          items: const [
            DropdownMenuItem(
              value: 'Deal or meetup',
              child: Text('Deal or meetup'),
            ),
            DropdownMenuItem(
              value: 'Credits or billing',
              child: Text('Credits or billing'),
            ),
            DropdownMenuItem(
              value: 'Account or safety',
              child: Text('Account or safety'),
            ),
          ],
          onChanged: (value) => setState(() => _topic = value ?? _topic),
        ),
        const SizedBox(height: 12),
        _SellerSheetField(
          fieldKey: const Key('sellerSupportDetails'),
          label: widget.safety ? 'What happened?' : 'How can we help?',
          hintText: 'Add the details support should review',
          minLines: 3,
          maxLines: 5,
        ),
        const SizedBox(height: 14),
        SellerPrimaryButton(
          key: const Key('sellerSupportSave'),
          label: widget.safety ? 'Save safety report' : 'Save support request',
          onPressed: () => Navigator.pop(context, true),
          colors: [accent, accent],
        ),
        const SizedBox(height: 8),
        const _SellerSheetNote(
          icon: Icons.cloud_sync_outlined,
          text:
              'Saved locally for now. Online ticket delivery connects with the backend later.',
        ),
      ],
    );
  }
}

class _SellerActionSheet extends StatelessWidget {
  const _SellerActionSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.children,
    this.accentColor = SellerUiColors.primaryBright,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final List<Widget> children;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SellerModalSheet(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onClose: onClose,
      accentColor: accentColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SellerSheetField extends StatelessWidget {
  const _SellerSheetField({
    required this.label,
    required this.hintText,
    this.fieldKey,
    this.keyboardType,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String hintText;
  final Key? fieldKey;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: sellerText(
            metrics,
            10,
            weight: FontWeight.w800,
            color: SellerUiColors.muted,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          key: fieldKey,
          keyboardType: keyboardType,
          obscureText: obscureText,
          minLines: obscureText ? 1 : minLines,
          maxLines: obscureText ? 1 : maxLines,
          style: sellerText(metrics, 12.5),
          decoration: _sellerSheetInputDecoration(context, hintText),
        ),
      ],
    );
  }
}

InputDecoration _sellerSheetInputDecoration(
  BuildContext context,
  String hintText,
) {
  final metrics = ApprovedReplicaMetrics.resolve(
    availableWidth: MediaQuery.sizeOf(context).width,
    textScaler: MediaQuery.textScalerOf(context),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: sellerText(metrics, 11.5, color: SellerUiColors.muted),
    filled: true,
    fillColor: const Color(0xfff7f7ff),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: SellerUiColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: SellerUiColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(
        color: SellerUiColors.primaryBright,
        width: 1.4,
      ),
    ),
  );
}

class _SellerSheetNote extends StatelessWidget {
  const _SellerSheetNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: SellerUiColors.primaryBright),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: sellerText(
                metrics,
                10.5,
                color: SellerUiColors.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSheetActionRow extends StatelessWidget {
  const _SellerSheetActionRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.accentColor = SellerUiColors.primaryBright,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Material(
      color: const Color(0xfff7f7ff),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: sellerText(
                        metrics,
                        12.5,
                        weight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: sellerText(
                        metrics,
                        10.5,
                        color: SellerUiColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }
}

class ApprovedSellerNotificationPreferencesPage extends StatefulWidget {
  const ApprovedSellerNotificationPreferencesPage({
    required this.onBack,
    super.key,
  });

  final VoidCallback onBack;

  @override
  State<ApprovedSellerNotificationPreferencesPage> createState() =>
      _ApprovedSellerNotificationPreferencesPageState();
}

enum _SellerNotificationFilter { all, leads, offers, meetings, billing }

class _SellerNotificationData {
  const _SellerNotificationData({
    required this.filter,
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    this.unread = false,
  });

  final _SellerNotificationFilter filter;
  final IconData icon;
  final String title;
  final String body;
  final String time;
  final bool unread;
}

class ApprovedSellerNotificationsPage extends StatefulWidget {
  const ApprovedSellerNotificationsPage({
    required this.onBack,
    required this.onPreferences,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPreferences;

  @override
  State<ApprovedSellerNotificationsPage> createState() =>
      _ApprovedSellerNotificationsPageState();
}

class _ApprovedSellerNotificationsPageState
    extends State<ApprovedSellerNotificationsPage> {
  static const _notifications = <_SellerNotificationData>[
    _SellerNotificationData(
      filter: _SellerNotificationFilter.leads,
      icon: Icons.person_search_outlined,
      title: 'New buyer request nearby',
      body: 'A buyer in Yonkers is looking for an iPad Air (5th gen).',
      time: '8 min ago',
      unread: true,
    ),
    _SellerNotificationData(
      filter: _SellerNotificationFilter.offers,
      icon: Icons.local_offer_outlined,
      title: 'Your offer was selected',
      body: 'Maya selected your iPad Air offer. The conversation is ready.',
      time: '32 min ago',
      unread: true,
    ),
    _SellerNotificationData(
      filter: _SellerNotificationFilter.meetings,
      icon: Icons.event_available_outlined,
      title: 'Meeting confirmed for today',
      body: 'Your meetup with James is confirmed for 5:00 PM in Yonkers.',
      time: '1 hr ago',
    ),
    _SellerNotificationData(
      filter: _SellerNotificationFilter.billing,
      icon: Icons.toll_outlined,
      title: 'Targeting credit restored',
      body: r'$1.90 was returned to your available targeting balance.',
      time: 'Yesterday',
    ),
    _SellerNotificationData(
      filter: _SellerNotificationFilter.offers,
      icon: Icons.edit_notifications_outlined,
      title: 'Buyer request changed',
      body: 'Review the updated price before continuing with this request.',
      time: 'Yesterday',
    ),
  ];

  _SellerNotificationFilter _filter = _SellerNotificationFilter.all;

  List<_SellerNotificationData> get _visible =>
      _filter == _SellerNotificationFilter.all
      ? _notifications
      : _notifications.where((item) => item.filter == _filter).toList();

  String _label(_SellerNotificationFilter filter) => switch (filter) {
    _SellerNotificationFilter.all => 'All',
    _SellerNotificationFilter.leads => 'Leads',
    _SellerNotificationFilter.offers => 'Offers',
    _SellerNotificationFilter.meetings => 'Meetings',
    _SellerNotificationFilter.billing => 'Billing',
  };

  Future<void> _showDetails(_SellerNotificationData item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SellerNotificationDetailsSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerNotificationsInboxPage'),
      title: 'Notifications',
      subtitle: 'Seller activity, deal updates, and account alerts.',
      onBack: widget.onBack,
      children: [
        Builder(
          builder: (context) {
            final metrics = ApprovedReplicaScope.of(context);
            return SingleChildScrollView(
              key: const Key('sellerNotificationFilters'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _SellerNotificationFilter.values) ...[
                    ChoiceChip(
                      key: ValueKey('sellerNotificationFilter-${filter.name}'),
                      label: Text(_label(filter)),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: SellerUiColors.lavender,
                      side: const BorderSide(color: SellerUiColors.line),
                      labelStyle: sellerText(
                        metrics,
                        11.5,
                        weight: FontWeight.w700,
                        color: _filter == filter
                            ? SellerUiColors.primaryBright
                            : SellerUiColors.ink,
                      ),
                    ),
                    if (filter != _SellerNotificationFilter.values.last)
                      SizedBox(width: metrics.spacing(7)),
                  ],
                ],
              ),
            );
          },
        ),
        _SellerSubpageSection(
          title: _label(_filter) == 'All'
              ? 'Latest activity'
              : '${_label(_filter)} notifications',
          children: [
            for (final item in _visible)
              _SellerNotificationRow(
                item: item,
                onTap: () => _showDetails(item),
              ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Controls',
          children: [
            _SellerSubpageRow(
              icon: Icons.tune_outlined,
              title: 'Notification preferences',
              body: 'Choose which Seller alerts are delivered to your device.',
              status: 'Manage preferences',
              onTap: widget.onPreferences,
            ),
          ],
        ),
      ],
    );
  }
}

class _SellerNotificationRow extends StatelessWidget {
  const _SellerNotificationRow({required this.item, required this.onTap});

  final _SellerNotificationData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.spacing(12),
          vertical: metrics.spacing(11),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: metrics.artSize(36),
                  height: metrics.artSize(36),
                  decoration: const BoxDecoration(
                    color: SellerUiColors.lavender,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    color: SellerUiColors.primaryBright,
                    size: metrics.artSize(18),
                  ),
                ),
                if (item.unread)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: metrics.artSize(8),
                      height: metrics.artSize(8),
                      decoration: const BoxDecoration(
                        color: SellerUiColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: metrics.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: sellerText(
                      metrics,
                      13.5,
                      weight: item.unread ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: metrics.spacing(3)),
                  Text(
                    item.body,
                    style: sellerText(
                      metrics,
                      11.5,
                      color: SellerUiColors.muted,
                    ),
                  ),
                  SizedBox(height: metrics.spacing(5)),
                  Text(
                    item.time,
                    style: sellerText(
                      metrics,
                      10.5,
                      weight: FontWeight.w700,
                      color: SellerUiColors.primaryBright,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: metrics.spacing(6)),
            Icon(
              Icons.chevron_right,
              size: metrics.artSize(19),
              color: SellerUiColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerNotificationDetailsSheet extends StatelessWidget {
  const _SellerNotificationDetailsSheet({required this.item});

  final _SellerNotificationData item;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return _SellerActionSheet(
      key: const Key('sellerNotificationDetailsSheet'),
      icon: item.icon,
      title: item.title,
      subtitle: item.time,
      onClose: () => Navigator.pop(context),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xfff7f7ff),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SellerUiColors.line),
          ),
          child: Text(
            item.body,
            style: sellerText(
              metrics,
              11.5,
              color: SellerUiColors.body,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SellerPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _ApprovedSellerNotificationPreferencesPageState
    extends State<ApprovedSellerNotificationPreferencesPage> {
  static const _leadsKey = 'hocalist.seller.notifications.leads';
  static const _offersKey = 'hocalist.seller.notifications.offers';
  static const _messagesKey = 'hocalist.seller.notifications.messages';
  static const _meetingsKey = 'hocalist.seller.notifications.meetings';
  static const _safetyKey = 'hocalist.seller.notifications.safety';

  bool leads = true;
  bool offers = true;
  bool messages = true;
  bool meetings = true;
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
      leads = preferences.getBool(_leadsKey) ?? true;
      offers = preferences.getBool(_offersKey) ?? true;
      messages = preferences.getBool(_messagesKey) ?? true;
      meetings = preferences.getBool(_meetingsKey) ?? true;
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
    return _SellerSubpageBlock(
      key: const Key('approvedSellerNotificationsPage'),
      title: 'Notification Preferences',
      subtitle:
          'Choose the Seller updates you want. Preferences are saved on this device.',
      onBack: widget.onBack,
      children: [
        _SellerSubpageSection(
          title: 'Seller notifications',
          children: [
            _SellerPreferenceSwitch(
              icon: Icons.person_search_outlined,
              title: 'New leads',
              body: 'New buyer requests that match your Seller profile.',
              value: leads,
              onChanged: (value) =>
                  _update(_leadsKey, value, () => leads = value),
            ),
            _SellerPreferenceSwitch(
              icon: Icons.local_offer_outlined,
              title: 'Offer updates',
              body: 'Offer changes, buyer selections, and deal updates.',
              value: offers,
              onChanged: (value) =>
                  _update(_offersKey, value, () => offers = value),
            ),
            _SellerPreferenceSwitch(
              icon: Icons.chat_bubble_outline,
              title: 'Messages & chats',
              body: 'Messages from buyers and active conversation updates.',
              value: messages,
              onChanged: (value) =>
                  _update(_messagesKey, value, () => messages = value),
            ),
            _SellerPreferenceSwitch(
              icon: Icons.event_available_outlined,
              title: 'Meetings',
              body:
                  'Meeting reminders, confirmations, and reschedule requests.',
              value: meetings,
              onChanged: (value) =>
                  _update(_meetingsKey, value, () => meetings = value),
            ),
            _SellerPreferenceSwitch(
              icon: Icons.health_and_safety_outlined,
              title: 'Account & safety alerts',
              body: 'Security, verification, and important safety notices.',
              value: safety,
              onChanged: (value) =>
                  _update(_safetyKey, value, () => safety = value),
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Delivery',
          children: [
            _SellerSubpageRow(
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

class ApprovedSellerProfileSetupPage extends StatelessWidget {
  const ApprovedSellerProfileSetupPage({
    required this.onBack,
    required this.onContinue,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerProfileSetupPage'),
      title: 'Set up seller profile',
      subtitle: 'Your profile helps buyers trust your offers.',
      onBack: onBack,
      children: [
        const _SellerSubpageSection(
          title: 'Seller information',
          children: [
            Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                children: [
                  _SellerProfileField(
                    initialValue: 'Electronics, tablets, accessories',
                    label: 'Business category',
                  ),
                  SizedBox(height: 14),
                  _SellerProfileField(
                    initialValue: '15 miles',
                    label: 'Service radius',
                  ),
                  SizedBox(height: 14),
                  _SellerProfileField(
                    initialValue: 'Weekdays and Saturday afternoon',
                    label: 'Pickup availability',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerProfileSetupContinue'),
          label: 'Start verification',
          onPressed: onContinue,
          leading: const Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class ApprovedSellerVerificationPage extends StatelessWidget {
  const ApprovedSellerVerificationPage({
    required this.onBack,
    required this.onFinish,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerVerificationPage'),
      title: 'Seller verification',
      subtitle: 'Complete the trust checks buyers see on your profile.',
      onBack: onBack,
      children: [
        const _SellerSubpageSection(
          title: 'Verification checklist',
          children: [
            _SellerSubpageRow(
              icon: Icons.badge_outlined,
              title: 'Identity details',
              body: 'Confirm the name attached to your Seller account.',
              status: 'Ready to submit',
            ),
            _SellerSubpageRow(
              icon: Icons.phone_iphone_outlined,
              title: 'Phone verification',
              body: 'Verify a phone number for important account alerts.',
              status: 'Ready to submit',
            ),
            _SellerSubpageRow(
              icon: Icons.location_on_outlined,
              title: 'Service area',
              body: 'Confirm the local area where you can meet buyers.',
              status: 'Ready to submit',
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerVerificationFinish'),
          label: 'Finish setup',
          onPressed: onFinish,
          leading: const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class ApprovedSellerOfferHistoryPage extends StatelessWidget {
  const ApprovedSellerOfferHistoryPage({
    required this.onBack,
    required this.onOpen,
    required this.sellerOfferSent,
    required this.offerSelected,
    this.latestOffer,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onOpen;
  final bool sellerOfferSent;
  final bool offerSelected;
  final LocalOfferRecord? latestOffer;

  @override
  Widget build(BuildContext context) {
    final currentStatus = offerSelected
        ? 'Buyer selected your offer'
        : sellerOfferSent
        ? 'Waiting for buyer'
        : 'Draft preview';
    return _SellerSubpageBlock(
      key: const Key('approvedSellerOfferHistoryPage'),
      title: 'Offer history',
      subtitle: 'Review the offers you sent and their current status.',
      onBack: onBack,
      children: [
        _SellerSubpageSection(
          title: 'Current',
          children: [
            _SellerSubpageRow(
              icon: Icons.tablet_mac_outlined,
              title: latestOffer?.requestTitle ?? 'iPad Air (5th gen)',
              body: latestOffer == null
                  ? r'$650 • Yonkers, NY'
                  : '${latestOffer!.price} • ${latestOffer!.location}',
              status: currentStatus,
              onTap: onOpen,
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Previous',
          children: [
            _SellerSubpageRow(
              icon: Icons.tv_outlined,
              title: 'Samsung 65” QLED 4K TV',
              body: r'$480 • Completed local meetup',
              status: 'Completed',
            ),
          ],
        ),
      ],
    );
  }
}

class ApprovedSellerOfferDetailPage extends StatelessWidget {
  const ApprovedSellerOfferDetailPage({
    required this.onBack,
    required this.onChat,
    this.latestOffer,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onChat;
  final LocalOfferRecord? latestOffer;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerOfferDetailPage'),
      title: 'Offer details',
      subtitle: 'Review the terms currently shared with the buyer.',
      onBack: onBack,
      children: [
        _SellerSubpageSection(
          title: 'Agreed offer',
          children: [
            _SellerSubpageRow(
              icon: Icons.tablet_mac_outlined,
              title: latestOffer?.requestTitle ?? 'iPad Air 5th Gen 64GB',
              body: latestOffer == null
                  ? 'Good condition • Pickup in Yonkers, NY'
                  : 'Good condition • ${latestOffer!.location}',
              status: latestOffer?.price ?? r'$650',
            ),
            _SellerSubpageRow(
              icon: Icons.schedule_outlined,
              title: 'Meeting time',
              body: latestOffer == null
                  ? 'Today • 5:00 PM'
                  : '${latestOffer!.meetingDate} • ${latestOffer!.meetingTime}',
              status: 'Meeting set',
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerOfferDetailChat'),
          label: 'Open conversation',
          onPressed: onChat,
          leading: const Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

enum _SellerBillingFilter { all, spent, restored, purchased }

class _SellerCreditActivity {
  const _SellerCreditActivity({
    required this.title,
    required this.body,
    required this.amount,
    required this.balanceAfter,
    required this.date,
    required this.reference,
    required this.filter,
    required this.icon,
  });

  final String title;
  final String body;
  final String amount;
  final String balanceAfter;
  final String date;
  final String reference;
  final _SellerBillingFilter filter;
  final IconData icon;
}

class ApprovedSellerBillingPage extends StatefulWidget {
  const ApprovedSellerBillingPage({
    required this.onBack,
    required this.onPayment,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPayment;

  @override
  State<ApprovedSellerBillingPage> createState() =>
      _ApprovedSellerBillingPageState();
}

class _ApprovedSellerBillingPageState extends State<ApprovedSellerBillingPage> {
  static const _activities = <_SellerCreditActivity>[
    _SellerCreditActivity(
      title: 'Targeted James M. request',
      body: 'Initial targeting credit used',
      amount: r'−$1.90',
      balanceAfter: r'$36.25',
      date: 'Aug 25, 2026 • 9:12 AM',
      reference: 'TGT-250826-1042',
      filter: _SellerBillingFilter.spent,
      icon: Icons.person_search_outlined,
    ),
    _SellerCreditActivity(
      title: 'Targeting credit restored',
      body: 'Buyer request changed and seller withdrew',
      amount: r'+$1.90',
      balanceAfter: r'$38.15',
      date: 'Aug 24, 2026 • 6:08 PM',
      reference: 'RST-240826-8831',
      filter: _SellerBillingFilter.restored,
      icon: Icons.restore_outlined,
    ),
    _SellerCreditActivity(
      title: 'Winning-bid balance',
      body: 'Remaining offer targeting cost',
      amount: r'−$4.75',
      balanceAfter: r'$36.25',
      date: 'Aug 22, 2026 • 5:30 PM',
      reference: 'WIN-220826-7340',
      filter: _SellerBillingFilter.spent,
      icon: Icons.emoji_events_outlined,
    ),
    _SellerCreditActivity(
      title: 'Credit balance added',
      body: 'Seller targeting-credit purchase',
      amount: r'+$25.00',
      balanceAfter: r'$41.00',
      date: 'Aug 20, 2026 • 10:05 AM',
      reference: 'CRD-200826-5127',
      filter: _SellerBillingFilter.purchased,
      icon: Icons.add_card_outlined,
    ),
  ];

  _SellerBillingFilter _filter = _SellerBillingFilter.all;

  String _filterLabel(_SellerBillingFilter filter) => switch (filter) {
    _SellerBillingFilter.all => 'All activity',
    _SellerBillingFilter.spent => 'Credits used',
    _SellerBillingFilter.restored => 'Credits restored',
    _SellerBillingFilter.purchased => 'Credits added',
  };

  List<_SellerCreditActivity> get _visibleActivities =>
      _filter == _SellerBillingFilter.all
      ? _activities
      : _activities.where((item) => item.filter == _filter).toList();

  Future<void> _showTransaction(_SellerCreditActivity item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SellerTransactionDetailsSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerBillingPage'),
      title: 'Plans & credits',
      subtitle: 'Track available credit, spending, and Seller billing.',
      onBack: widget.onBack,
      children: [
        const _SellerCreditBalanceCard(),
        const _SellerSubpageSection(
          title: 'Current plan',
          children: [
            _SellerSubpageRow(
              icon: Icons.workspace_premium_outlined,
              title: 'Pro Seller plan',
              body: 'Access to targeted leads and Seller tools.',
              status: r'$19.99 • renews Sep 1, 2026',
            ),
          ],
        ),
        Builder(
          builder: (context) {
            final metrics = ApprovedReplicaScope.of(context);
            return Row(
              children: [
                Expanded(
                  child: Text(
                    'CREDIT ACTIVITY',
                    style: sellerText(
                      metrics,
                      11,
                      weight: FontWeight.w800,
                      color: SellerUiColors.muted,
                      letterSpacing: .8,
                    ),
                  ),
                ),
                PopupMenuButton<_SellerBillingFilter>(
                  key: const Key('sellerBillingFilter'),
                  initialValue: _filter,
                  position: PopupMenuPosition.under,
                  color: SellerUiColors.white,
                  surfaceTintColor: SellerUiColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(metrics.geometry(12)),
                    side: const BorderSide(color: SellerUiColors.line),
                  ),
                  onSelected: (value) => setState(() => _filter = value),
                  itemBuilder: (context) => [
                    for (final value in _SellerBillingFilter.values)
                      PopupMenuItem(
                        value: value,
                        height: metrics.geometry(44),
                        child: Text(
                          _filterLabel(value),
                          style: sellerText(
                            metrics,
                            11.5,
                            weight: value == _filter
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.spacing(10),
                      vertical: metrics.spacing(7),
                    ),
                    decoration: BoxDecoration(
                      color: SellerUiColors.lavender,
                      borderRadius: BorderRadius.circular(metrics.geometry(10)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _filterLabel(_filter),
                          style: sellerText(
                            metrics,
                            10.5,
                            weight: FontWeight.w800,
                            color: SellerUiColors.primaryBright,
                          ),
                        ),
                        SizedBox(width: metrics.spacing(4)),
                        Icon(
                          Icons.expand_more,
                          size: metrics.artSize(16),
                          color: SellerUiColors.primaryBright,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        _SellerSubpageSection(
          title: _filterLabel(_filter),
          children: [
            for (final item in _visibleActivities)
              _SellerCreditActivityRow(
                item: item,
                onTap: () => _showTransaction(item),
              ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Billing history',
          children: [
            _SellerBillingHistoryRow(
              title: 'Pro Seller plan',
              date: 'Aug 1, 2026',
              amount: r'$19.99',
              status: 'Paid',
            ),
            _SellerBillingHistoryRow(
              title: 'Targeting credits',
              date: 'Jul 20, 2026',
              amount: r'$25.00',
              status: 'Paid',
            ),
            _SellerBillingHistoryRow(
              title: 'Pro Seller plan',
              date: 'Jul 1, 2026',
              amount: r'$19.99',
              status: 'Paid',
            ),
          ],
        ),
        _SellerSubpageSection(
          title: 'Payment',
          children: [
            _SellerSubpageRow(
              icon: Icons.credit_card_outlined,
              title: 'Payment method',
              body: 'Used only for Seller plans and targeting credits.',
              status: 'Add or review',
              onTap: widget.onPayment,
            ),
          ],
        ),
      ],
    );
  }
}

class _SellerCreditBalanceCard extends StatelessWidget {
  const _SellerCreditBalanceCard();

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerCreditBalanceCard'),
      padding: EdgeInsets.all(metrics.spacing(15)),
      decoration: BoxDecoration(
        color: SellerUiColors.ink,
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: metrics.artSize(36),
                height: metrics.artSize(36),
                decoration: const BoxDecoration(
                  color: SellerUiColors.lavender,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.toll_outlined,
                  color: SellerUiColors.primaryBright,
                  size: metrics.artSize(19),
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Text(
                  'Available targeting credit',
                  style: sellerText(
                    metrics,
                    12,
                    weight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(
            r'$36.25',
            style: sellerText(
              metrics,
              28,
              weight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: metrics.spacing(14)),
          Row(
            children: [
              Expanded(
                child: _SellerBalanceMetric(
                  label: 'Used this cycle',
                  value: r'$8.75',
                ),
              ),
              Container(
                width: 1,
                height: metrics.geometry(34),
                color: Colors.white24,
              ),
              Expanded(
                child: _SellerBalanceMetric(label: 'Restored', value: r'$1.90'),
              ),
            ],
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(
            'Sample balance until billing and credit records are connected.',
            style: sellerText(metrics, 9.5, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class _SellerBalanceMetric extends StatelessWidget {
  const _SellerBalanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: sellerText(metrics, 9.5, color: Colors.white60)),
        SizedBox(height: metrics.spacing(2)),
        Text(
          value,
          style: sellerText(
            metrics,
            14,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SellerCreditActivityRow extends StatelessWidget {
  const _SellerCreditActivityRow({required this.item, required this.onTap});

  final _SellerCreditActivity item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final positive = item.amount.startsWith('+');
    return InkWell(
      key: ValueKey('sellerCreditActivity-${item.reference}'),
      onTap: onTap,
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
                color: SellerUiColors.lavender,
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.icon,
                color: SellerUiColors.primaryBright,
                size: metrics.artSize(18),
              ),
            ),
            SizedBox(width: metrics.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: sellerText(metrics, 13, weight: FontWeight.w700),
                  ),
                  SizedBox(height: metrics.spacing(2)),
                  Text(
                    item.body,
                    style: sellerText(
                      metrics,
                      10.5,
                      color: SellerUiColors.muted,
                    ),
                  ),
                  SizedBox(height: metrics.spacing(4)),
                  Text(
                    item.date,
                    style: sellerText(
                      metrics,
                      9.5,
                      color: SellerUiColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: metrics.spacing(6)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.amount,
                  style: sellerText(
                    metrics,
                    12,
                    weight: FontWeight.w900,
                    color: positive ? SellerUiColors.green : SellerUiColors.ink,
                  ),
                ),
                SizedBox(height: metrics.spacing(6)),
                Icon(
                  Icons.chevron_right,
                  color: SellerUiColors.muted,
                  size: metrics.artSize(18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerBillingHistoryRow extends StatelessWidget {
  const _SellerBillingHistoryRow({
    required this.title,
    required this.date,
    required this.amount,
    required this.status,
  });

  final String title;
  final String date;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(12),
        vertical: metrics.spacing(11),
      ),
      child: Row(
        children: [
          Container(
            width: metrics.artSize(34),
            height: metrics.artSize(34),
            decoration: const BoxDecoration(
              color: SellerUiColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: SellerUiColors.primaryBright,
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
                  style: sellerText(metrics, 13, weight: FontWeight.w700),
                ),
                SizedBox(height: metrics.spacing(2)),
                Text(
                  '$date • $status',
                  style: sellerText(metrics, 10.5, color: SellerUiColors.muted),
                ),
              ],
            ),
          ),
          Text(amount, style: sellerText(metrics, 12, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SellerTransactionDetailsSheet extends StatelessWidget {
  const _SellerTransactionDetailsSheet({required this.item});

  final _SellerCreditActivity item;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return _SellerActionSheet(
      key: const Key('sellerTransactionDetailsSheet'),
      icon: Icons.receipt_long_outlined,
      title: 'Transaction details',
      subtitle: item.body,
      onClose: () => Navigator.pop(context),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xfff7f7ff),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SellerUiColors.line),
          ),
          child: Column(
            children: [
              _SellerTransactionLine(label: 'Activity', value: item.title),
              _SellerTransactionLine(label: 'Amount', value: item.amount),
              _SellerTransactionLine(
                label: 'Balance after',
                value: item.balanceAfter,
              ),
              _SellerTransactionLine(label: 'Date', value: item.date),
              _SellerTransactionLine(label: 'Reference', value: item.reference),
              const _SellerTransactionLine(label: 'Status', value: 'Completed'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _SellerSheetNote(
          icon: Icons.info_outline,
          text:
              'Preview data for now. Billing records and downloadable receipts connect with the backend and payment provider later.',
        ),
        SizedBox(height: metrics.spacing(14)),
        SellerPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _SellerTransactionLine extends StatelessWidget {
  const _SellerTransactionLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.spacing(7)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: metrics.geometry(94),
            child: Text(
              label,
              style: sellerText(metrics, 11, color: SellerUiColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: sellerText(metrics, 11.5, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ApprovedBuyerPublicProfilePage extends StatelessWidget {
  const ApprovedBuyerPublicProfilePage({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedBuyerPublicProfilePage'),
      title: 'Buyer profile',
      subtitle: 'Review the buyer details shared for this active request.',
      onBack: onBack,
      children: [
        Builder(
          builder: (context) {
            final metrics = ApprovedReplicaScope.of(context);
            return Container(
              padding: EdgeInsets.all(metrics.spacing(14)),
              decoration: BoxDecoration(
                color: SellerUiColors.white,
                border: Border.all(color: SellerUiColors.line),
                borderRadius: BorderRadius.circular(metrics.geometry(12)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: metrics.artSize(31),
                    backgroundColor: SellerUiColors.lavender,
                    child: Text(
                      'MC',
                      style: sellerText(
                        metrics,
                        19,
                        weight: FontWeight.w900,
                        color: SellerUiColors.primaryBright,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.spacing(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maya Chen',
                          style: sellerText(
                            metrics,
                            18,
                            weight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: metrics.spacing(3)),
                        Text(
                          'Verified buyer • Active now',
                          style: sellerText(
                            metrics,
                            11.5,
                            weight: FontWeight.w700,
                            color: SellerUiColors.green,
                          ),
                        ),
                        SizedBox(height: metrics.spacing(3)),
                        Text(
                          'Yonkers, NY • 2.1 mi',
                          style: sellerText(
                            metrics,
                            11,
                            color: SellerUiColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const _SellerSubpageSection(
          title: 'Marketplace history',
          children: [
            _SellerSubpageRow(
              icon: Icons.verified_user_outlined,
              title: 'Buyer verification',
              body: 'Account and marketplace identity checks are complete.',
              status: 'Verified buyer',
            ),
            _SellerSubpageRow(
              icon: Icons.handshake_outlined,
              title: 'Completed meetups',
              body:
                  'Past deal outcomes shared through the marketplace profile.',
              status: '42 completed purchases',
            ),
            _SellerSubpageRow(
              icon: Icons.schedule_outlined,
              title: 'Response pattern',
              body: 'Usually replies to active offers within an hour.',
              status: 'Responsive',
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Privacy',
          children: [
            _SellerSubpageRow(
              icon: Icons.lock_outline,
              title: 'Limited public details',
              body:
                  'Private contact information stays hidden until the deal allows it.',
              status: 'Protected',
            ),
          ],
        ),
      ],
    );
  }
}

class ApprovedSellerOriginalRequestPage extends StatelessWidget {
  const ApprovedSellerOriginalRequestPage({
    required this.onBack,
    required this.onReturnToChat,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onReturnToChat;

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerOriginalRequestPage'),
      title: 'Original request',
      subtitle:
          'The buyer details that were active when you targeted this request.',
      onBack: onBack,
      children: [
        const _SellerSubpageSection(
          title: 'Request summary',
          children: [
            _SellerSubpageRow(
              icon: Icons.sell_outlined,
              title: 'iPad Air, 5th gen or newer',
              body: 'Product request • PIN 12345',
              status: 'Original version',
            ),
            _SellerSubpageRow(
              icon: Icons.description_outlined,
              title: 'What the buyer needs',
              body:
                  'Looking for an iPad Air 5th generation or newer, in good condition, with the charger included.',
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Original preferences',
          children: [
            _SellerSubpageRow(
              icon: Icons.payments_outlined,
              title: 'Budget',
              body: '\$350–\$480',
              status: 'Higher offers accepted',
            ),
            _SellerSubpageRow(
              icon: Icons.inventory_2_outlined,
              title: 'Condition and quantity',
              body: 'New or used • Quantity 1',
            ),
            _SellerSubpageRow(
              icon: Icons.location_on_outlined,
              title: 'Preferred location',
              body: 'Yonkers, NY and nearby public meetup locations.',
            ),
          ],
        ),
        const _SellerSubpageSection(
          title: 'Version note',
          children: [
            _SellerSubpageRow(
              icon: Icons.history_outlined,
              title: 'Why this is preserved',
              body:
                  'Original request details remain available when a buyer later changes price or preferences.',
              status: 'Read-only record',
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerOriginalRequestReturnToChat'),
          label: 'Return to conversation',
          onPressed: onReturnToChat,
        ),
      ],
    );
  }
}

class ApprovedSellerPaymentMethodPage extends StatefulWidget {
  const ApprovedSellerPaymentMethodPage({
    required this.onBack,
    required this.onDone,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<ApprovedSellerPaymentMethodPage> createState() =>
      _ApprovedSellerPaymentMethodPageState();
}

class _ApprovedSellerPaymentMethodPageState
    extends State<ApprovedSellerPaymentMethodPage> {
  final List<_SellerPaymentMethodData> _methods = [
    const _SellerPaymentMethodData(
      id: 'visa-4242',
      label: 'Visa ending in 4242',
      expiry: 'Expires 08/29',
    ),
  ];
  String _selectedId = 'visa-4242';

  Future<void> _addPaymentMethod() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SellerAddPaymentMethodSheet(
        onClose: () => Navigator.pop(sheetContext, false),
        onSave: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (added == true && mounted) {
      const method = _SellerPaymentMethodData(
        id: 'mastercard-4444',
        label: 'Mastercard ending in 4444',
        expiry: 'Expires 11/30',
      );
      setState(() {
        if (!_methods.any((item) => item.id == method.id)) {
          _methods.add(method);
        }
        _selectedId = method.id;
      });
    }
  }

  Future<void> _managePaymentMethod(_SellerPaymentMethodData method) async {
    final action = await showModalBottomSheet<_SellerPaymentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SellerManagePaymentMethodSheet(
        method: method,
        isDefault: method.id == _selectedId,
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (!mounted || action == null) return;
    setState(() {
      if (action == _SellerPaymentAction.makeDefault) {
        _selectedId = method.id;
      } else if (_methods.length > 1) {
        _methods.removeWhere((item) => item.id == method.id);
        if (_selectedId == method.id) _selectedId = _methods.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SellerSubpageBlock(
      key: const Key('approvedSellerPaymentMethodPage'),
      title: 'Payment method',
      subtitle: 'Seller billing is separate from offline item payment.',
      onBack: widget.onBack,
      children: [
        _SellerSubpageSection(
          title: 'Saved payment methods',
          children: [
            for (final method in _methods)
              _SellerPaymentMethodRow(
                method: method,
                selected: method.id == _selectedId,
                onSelect: () => setState(() => _selectedId = method.id),
                onManage: () => _managePaymentMethod(method),
              ),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('sellerAddPaymentMethod'),
          onPressed: _addPaymentMethod,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: SellerUiColors.primaryBright,
            side: const BorderSide(color: SellerUiColors.primaryBright),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add_card_outlined),
          label: const Text('Add payment method'),
        ),
        const _SellerSubpageSection(
          title: 'Payment use',
          children: [
            _SellerSubpageRow(
              icon: Icons.workspace_premium_outlined,
              title: 'Seller billing only',
              body:
                  'The selected method is used for Seller plans and targeting credits.',
              status: 'Stripe connection pending',
            ),
            _SellerSubpageRow(
              icon: Icons.storefront_outlined,
              title: 'Item payment stays offline',
              body:
                  'Buyers still pay sellers directly after inspecting the item.',
              status: 'Not charged here',
            ),
          ],
        ),
        SellerPrimaryButton(
          key: const Key('sellerPaymentMethodDone'),
          label: 'Save selected method',
          onPressed: widget.onDone,
        ),
      ],
    );
  }
}

@immutable
class _SellerPaymentMethodData {
  const _SellerPaymentMethodData({
    required this.id,
    required this.label,
    required this.expiry,
  });

  final String id;
  final String label;
  final String expiry;
}

enum _SellerPaymentAction { makeDefault, remove }

class _SellerPaymentMethodRow extends StatelessWidget {
  const _SellerPaymentMethodRow({
    required this.method,
    required this.selected,
    required this.onSelect,
    required this.onManage,
  });

  final _SellerPaymentMethodData method;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return InkWell(
      key: ValueKey('seller-payment-${method.id}'),
      onTap: onSelect,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.spacing(12),
          vertical: metrics.spacing(10),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? SellerUiColors.primaryBright
                  : SellerUiColors.muted,
            ),
            SizedBox(width: metrics.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: sellerText(metrics, 13.5, weight: FontWeight.w800),
                  ),
                  SizedBox(height: metrics.spacing(3)),
                  Text(
                    method.expiry,
                    style: sellerText(
                      metrics,
                      11.5,
                      color: SellerUiColors.muted,
                    ),
                  ),
                  if (selected) ...[
                    SizedBox(height: metrics.spacing(4)),
                    Text(
                      'Selected for Seller billing',
                      style: sellerText(
                        metrics,
                        10.5,
                        weight: FontWeight.w700,
                        color: SellerUiColors.primaryBright,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              key: ValueKey('seller-manage-${method.id}'),
              tooltip: 'Manage payment method',
              onPressed: onManage,
              icon: const Icon(Icons.more_vert),
              color: SellerUiColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerAddPaymentMethodSheet extends StatefulWidget {
  const _SellerAddPaymentMethodSheet({
    required this.onClose,
    required this.onSave,
  });

  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  State<_SellerAddPaymentMethodSheet> createState() =>
      _SellerAddPaymentMethodSheetState();
}

class _SellerAddPaymentMethodSheetState
    extends State<_SellerAddPaymentMethodSheet> {
  bool _billingMatches = true;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return _SellerActionSheet(
      key: const Key('sellerAddPaymentMethodSheet'),
      icon: Icons.add_card_outlined,
      title: 'Add payment method',
      subtitle:
          'Secure card collection will be handled by Stripe when connected.',
      onClose: widget.onClose,
      children: [
        const _SellerSheetField(
          fieldKey: Key('sellerPaymentCardNumber'),
          label: 'Card number',
          hintText: '4242 4242 4242 4242',
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: metrics.spacing(10)),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SellerSheetField(label: 'Expiry', hintText: 'MM/YY'),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SellerSheetField(
                label: 'Security code',
                hintText: 'CVC',
                obscureText: true,
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(6)),
        CheckboxListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          contentPadding: EdgeInsets.zero,
          value: _billingMatches,
          onChanged: (value) => setState(() => _billingMatches = value ?? true),
          activeColor: SellerUiColors.primaryBright,
          title: Text(
            'Billing address matches my Seller profile',
            style: sellerText(metrics, 11, weight: FontWeight.w700),
          ),
        ),
        SizedBox(height: metrics.spacing(8)),
        SellerPrimaryButton(
          key: const Key('sellerSavePaymentMethod'),
          label: 'Add payment method',
          onPressed: widget.onSave,
        ),
        const SizedBox(height: 8),
        const _SellerSheetNote(
          icon: Icons.lock_outline,
          text:
              'This preview does not store card details. Stripe remains the only missing payment connection.',
        ),
      ],
    );
  }
}

class _SellerManagePaymentMethodSheet extends StatelessWidget {
  const _SellerManagePaymentMethodSheet({
    required this.method,
    required this.isDefault,
    required this.onClose,
  });

  final _SellerPaymentMethodData method;
  final bool isDefault;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _SellerActionSheet(
      key: const Key('sellerManagePaymentMethodSheet'),
      icon: Icons.credit_card_outlined,
      title: 'Manage payment method',
      subtitle: method.label,
      onClose: onClose,
      children: [
        if (!isDefault)
          _SellerSheetActionRow(
            key: const Key('sellerMakeDefaultPaymentMethod'),
            icon: Icons.check_circle_outline,
            title: 'Make default',
            body: 'Use this card for Seller billing.',
            onTap: () =>
                Navigator.pop(context, _SellerPaymentAction.makeDefault),
          ),
        if (!isDefault) const SizedBox(height: 8),
        _SellerSheetActionRow(
          key: const Key('sellerRemovePaymentMethod'),
          icon: Icons.delete_outline,
          title: 'Remove payment method',
          body: 'Stop using this card for future Seller charges.',
          accentColor: SellerUiColors.red,
          onTap: () => Navigator.pop(context, _SellerPaymentAction.remove),
        ),
      ],
    );
  }
}

class _SellerSubpageBlock extends StatelessWidget {
  const _SellerSubpageBlock({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
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
                  key: const Key('sellerSubpageBack'),
                  tooltip: 'Back',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.arrow_back,
                    color: SellerUiColors.ink,
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
                        style: sellerText(metrics, 16, weight: FontWeight.w800),
                      ),
                      SizedBox(height: metrics.spacing(3)),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: sellerText(
                          metrics,
                          12,
                          color: SellerUiColors.muted,
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

class _SellerSubpageSection extends StatelessWidget {
  const _SellerSubpageSection({required this.title, required this.children});

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
            style: sellerText(
              metrics,
              11,
              weight: FontWeight.w800,
              color: SellerUiColors.muted,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(height: metrics.spacing(7)),
        Material(
          color: SellerUiColors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: SellerUiColors.line),
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
                    color: SellerUiColors.line,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SellerSubpageRow extends StatelessWidget {
  const _SellerSubpageRow({
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
                  color: SellerUiColors.lavender,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: SellerUiColors.primaryBright,
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
                      style: sellerText(metrics, 14, weight: FontWeight.w700),
                    ),
                    SizedBox(height: metrics.spacing(3)),
                    Text(
                      body,
                      style: sellerText(
                        metrics,
                        12,
                        color: SellerUiColors.muted,
                      ),
                    ),
                    if (status != null) ...[
                      SizedBox(height: metrics.spacing(5)),
                      Text(
                        status!,
                        style: sellerText(
                          metrics,
                          11,
                          weight: FontWeight.w700,
                          color: onTap == null
                              ? SellerUiColors.muted
                              : SellerUiColors.primaryBright,
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
                    color: SellerUiColors.muted,
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

class _SellerPreferenceSwitch extends StatelessWidget {
  const _SellerPreferenceSwitch({
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
      activeThumbColor: SellerUiColors.primaryBright,
      contentPadding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(12),
        vertical: metrics.spacing(4),
      ),
      secondary: Container(
        width: metrics.artSize(34),
        height: metrics.artSize(34),
        decoration: const BoxDecoration(
          color: SellerUiColors.lavender,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: SellerUiColors.primaryBright,
          size: metrics.artSize(18),
        ),
      ),
      title: Text(
        title,
        style: sellerText(metrics, 14, weight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: metrics.spacing(3)),
        child: Text(
          body,
          style: sellerText(metrics, 12, color: SellerUiColors.muted),
        ),
      ),
    );
  }
}

class _SellerProfileSummary extends StatelessWidget {
  const _SellerProfileSummary({
    required this.sellerName,
    this.onProfilePhotoAction,
  });

  final String sellerName;
  final ValueChanged<SellerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final initial = sellerName.trim().isEmpty ? 'S' : sellerName.trim()[0];
    Future<void> changePhoto() => _showSellerProfilePhotoOptions(
      context,
      onSelected: onProfilePhotoAction,
    );
    return Container(
      padding: EdgeInsets.all(metrics.spacing(14)),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        border: Border.all(color: SellerUiColors.lavenderBorder),
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
      ),
      child: Row(
        children: [
          _SellerProfileAvatar(
            initial: initial,
            metrics: metrics,
            onChangePhoto: changePhoto,
            actionKey: const Key('sellerProfilePhotoAction'),
          ),
          SizedBox(width: metrics.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sellerText(metrics, 17, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  'Electronics seller',
                  style: sellerText(metrics, 12, color: SellerUiColors.body),
                ),
                SizedBox(height: metrics.spacing(6)),
                Wrap(
                  spacing: metrics.spacing(6),
                  runSpacing: metrics.spacing(4),
                  children: [
                    _SellerStatusChip(
                      icon: Icons.verified_outlined,
                      label: 'Verified',
                      metrics: metrics,
                    ),
                    _SellerStatusChip(
                      icon: Icons.star_outline,
                      label: '4.9 rating',
                      metrics: metrics,
                    ),
                  ],
                ),
                SizedBox(height: metrics.spacing(4)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('sellerProfileChangePhoto'),
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
                      style: sellerText(
                        metrics,
                        12,
                        weight: FontWeight.w700,
                        color: SellerUiColors.primaryBright,
                      ),
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

class _SellerProfilePhotoEditor extends StatelessWidget {
  const _SellerProfilePhotoEditor({
    required this.sellerName,
    this.onProfilePhotoAction,
  });

  final String sellerName;
  final ValueChanged<SellerProfilePhotoAction>? onProfilePhotoAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final initial = sellerName.trim().isEmpty ? 'S' : sellerName.trim()[0];
    Future<void> changePhoto() => _showSellerProfilePhotoOptions(
      context,
      onSelected: onProfilePhotoAction,
    );
    return Padding(
      padding: EdgeInsets.all(metrics.spacing(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SellerProfileAvatar(
            initial: initial,
            metrics: metrics,
            onChangePhoto: changePhoto,
            actionKey: const Key('sellerEditProfilePhotoAction'),
          ),
          SizedBox(width: metrics.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Seller photo',
                  style: sellerText(metrics, 14, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  'Use a clear photo that buyers can recognize.',
                  style: sellerText(metrics, 12, color: SellerUiColors.muted),
                ),
                SizedBox(height: metrics.spacing(5)),
                TextButton.icon(
                  key: const Key('sellerEditProfileChangePhoto'),
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
                    style: sellerText(
                      metrics,
                      12,
                      weight: FontWeight.w700,
                      color: SellerUiColors.primaryBright,
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

class _SellerProfileAvatar extends StatelessWidget {
  const _SellerProfileAvatar({
    required this.initial,
    required this.metrics,
    required this.onChangePhoto,
    required this.actionKey,
  });

  final String initial;
  final ApprovedReplicaMetrics metrics;
  final VoidCallback onChangePhoto;
  final Key actionKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: metrics.artSize(62),
      height: metrics.artSize(62),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CircleAvatar(
              backgroundColor: SellerUiColors.primaryBright,
              child: Text(
                initial.toUpperCase(),
                style: sellerText(
                  metrics,
                  20,
                  weight: FontWeight.w800,
                  color: SellerUiColors.white,
                ),
              ),
            ),
          ),
          Positioned(
            right: -metrics.spacing(2),
            bottom: -metrics.spacing(2),
            child: Material(
              color: SellerUiColors.white,
              shape: const CircleBorder(),
              elevation: 1,
              child: IconButton(
                key: actionKey,
                tooltip: 'Change profile picture',
                onPressed: onChangePhoto,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.all(metrics.spacing(6)),
                constraints: BoxConstraints.tightFor(
                  width: metrics.artSize(32),
                  height: metrics.artSize(32),
                ),
                icon: Icon(
                  Icons.photo_camera_outlined,
                  color: SellerUiColors.primaryBright,
                  size: metrics.artSize(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSellerProfilePhotoOptions(
  BuildContext context, {
  ValueChanged<SellerProfilePhotoAction>? onSelected,
}) async {
  final metrics = ApprovedReplicaScope.of(context);
  final selected = await showModalBottomSheet<SellerProfilePhotoAction>(
    context: context,
    backgroundColor: SellerUiColors.white,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.spacing(20),
          metrics.spacing(10),
          metrics.spacing(20),
          metrics.spacing(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: metrics.artSize(42),
                height: metrics.geometry(4),
                decoration: BoxDecoration(
                  color: SellerUiColors.lavenderBorder,
                  borderRadius: BorderRadius.circular(metrics.geometry(10)),
                ),
              ),
            ),
            SizedBox(height: metrics.spacing(14)),
            Text(
              'Change profile picture',
              style: sellerText(metrics, 18, weight: FontWeight.w800),
            ),
            SizedBox(height: metrics.spacing(4)),
            Text(
              'Choose how you want to update your Seller photo.',
              style: sellerText(metrics, 12, color: SellerUiColors.muted),
            ),
            SizedBox(height: metrics.spacing(12)),
            _SellerPhotoOption(
              metrics: metrics,
              optionKey: const Key('sellerPhotoTakePhoto'),
              icon: Icons.photo_camera_outlined,
              title: 'Take a photo',
              subtitle: 'Use your device camera',
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(SellerProfilePhotoAction.camera),
            ),
            _SellerPhotoOption(
              metrics: metrics,
              optionKey: const Key('sellerPhotoChooseGallery'),
              icon: Icons.photo_library_outlined,
              title: 'Choose from photo library',
              subtitle: 'Select a photo already on your device',
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(SellerProfilePhotoAction.gallery),
            ),
            _SellerPhotoOption(
              metrics: metrics,
              optionKey: const Key('sellerPhotoRemove'),
              icon: Icons.delete_outline,
              title: 'Remove current photo',
              subtitle: 'Show your Seller initials instead',
              isDestructive: true,
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(SellerProfilePhotoAction.remove),
            ),
          ],
        ),
      );
    },
  );

  if (selected != null) {
    onSelected?.call(selected);
  }
}

class _SellerPhotoOption extends StatelessWidget {
  const _SellerPhotoOption({
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
    final color = isDestructive
        ? SellerUiColors.red
        : SellerUiColors.primaryBright;
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(8)),
      child: Material(
        color: isDestructive
            ? SellerUiColors.red.withValues(alpha: 0.05)
            : SellerUiColors.lavender.withValues(alpha: 0.7),
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
                        style: sellerText(
                          metrics,
                          13,
                          weight: FontWeight.w800,
                          color: isDestructive ? color : SellerUiColors.ink,
                        ),
                      ),
                      SizedBox(height: metrics.spacing(2)),
                      Text(
                        subtitle,
                        style: sellerText(
                          metrics,
                          11,
                          color: SellerUiColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: SellerUiColors.muted,
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

class _SellerStatusChip extends StatelessWidget {
  const _SellerStatusChip({
    required this.icon,
    required this.label,
    required this.metrics,
  });

  final IconData icon;
  final String label;
  final ApprovedReplicaMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(7),
        vertical: metrics.spacing(4),
      ),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: metrics.artSize(13), color: SellerUiColors.primary),
          SizedBox(width: metrics.spacing(4)),
          Text(label, style: sellerText(metrics, 10, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SellerProfileField extends StatelessWidget {
  const _SellerProfileField({
    required this.initialValue,
    required this.label,
    this.helperText,
    this.maxLines = 1,
    this.readOnly = false,
    this.textInputAction,
    this.onChanged,
  });

  final String initialValue;
  final String label;
  final String? helperText;
  final int maxLines;
  final bool readOnly;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Semantics(
      textField: true,
      label: label,
      readOnly: readOnly,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: sellerText(metrics, 13, weight: FontWeight.w700)),
          SizedBox(height: metrics.spacing(6)),
          TextFormField(
            initialValue: initialValue,
            readOnly: readOnly,
            maxLines: maxLines,
            textInputAction:
                textInputAction ??
                (maxLines == 1
                    ? TextInputAction.next
                    : TextInputAction.newline),
            onChanged: onChanged,
            style: sellerText(metrics, 13, weight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: SellerUiColors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: metrics.spacing(12),
                vertical: metrics.spacing(12),
              ),
              constraints: BoxConstraints(
                minHeight: metrics.geometry(maxLines == 1 ? 48 : 72),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
                borderSide: const BorderSide(color: SellerUiColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
                borderSide: const BorderSide(
                  color: SellerUiColors.primaryBright,
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (helperText != null) ...[
            SizedBox(height: metrics.spacing(6)),
            Text(
              helperText!,
              style: sellerText(metrics, 11, color: SellerUiColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
