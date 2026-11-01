import 'package:flutter/material.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../media/private_remote_image.dart';
import '../../components/hocalist_account_field.dart';
import '../../components/account_role_components.dart';
import '../../theme/seller_ui_foundation.dart';

Future<void> showProfileEditor(
  BuildContext context,
  String title,
  Widget child,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (sheet) => BuyerModalSheet(
    title: title == 'Public profile preview' ? 'View public profile' : title,
    icon: title == 'Public profile preview' ? Icons.visibility_outlined : Icons.edit_outlined,
    onClose: () => Navigator.pop(sheet),
    child: child,
  ),
);

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.child,
    this.soft = false,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final bool soft;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: HocalistPalette.surface(
        context,
        soft ? BuyerUiTokens.softSurface : Colors.white,
      ),
      border: Border.all(
        color: HocalistPalette.border(context, BuyerUiTokens.border),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class ProfileHeading extends StatelessWidget {
  const ProfileHeading(this.title, {super.key, this.onBack, this.action});
  final String title;
  final VoidCallback? onBack;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class ProfileIdentity extends StatelessWidget {
  const ProfileIdentity({
    super.key,
    required this.name,
    this.subtitle,
    this.avatarId,
    this.badges = const [],
    this.onPhoto,
  });
  final String name;
  final String? subtitle, avatarId;
  final List<String> badges;
  final VoidCallback? onPhoto;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Semantics(
        label: onPhoto == null ? 'Profile photo' : 'Change profile photo',
        button: onPhoto != null,
        child: InkWell(
          onTap: onPhoto,
          borderRadius: BorderRadius.circular(40),
          child: ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: avatarId == null
                  ? ColoredBox(
                      color: HocalistPalette.surface(
                        context,
                        BuyerUiTokens.softSurface,
                      ),
                      child: Center(
                        child: Text(
                          name.trim().isEmpty
                              ? '?'
                              : name.trim().characters.first.toUpperCase(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: HocalistPalette.text(context, BuyerUiTokens.action),
                          ),
                        ),
                      ),
                    )
                  : PrivateRemoteImage(id: avatarId!),
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(subtitle!),
            ],
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: badges
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            BuyerUiTokens.softSurface,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class ProfileActionRow extends StatelessWidget {
  const ProfileActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: HocalistPalette.text(context, BuyerUiTokens.text),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: HocalistPalette.text(context, BuyerUiTokens.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    ),
  );
}

class ProfileSection extends StatelessWidget {
  const ProfileSection(this.title, {super.key, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w800, color: HocalistPalette.text(context, BuyerUiTokens.muted)),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class ProfileStats extends StatelessWidget {
  const ProfileStats({super.key, required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => ProfileCard(
    padding: EdgeInsets.zero,
    child: Column(children: [
      for (final entry in values.entries) ...[
        if (entry.key != values.keys.first) Divider(height: 1, indent: 54,
          color: HocalistPalette.border(context, BuyerUiTokens.border)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
          Container(width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: HocalistPalette.surface(context, BuyerUiTokens.softSurface)),
            child: Icon(entry.key.toLowerCase().contains('rating') ? Icons.star_outline_rounded
              : entry.key == 'Verification' ? Icons.verified_user_outlined : Icons.handshake_outlined,
              size: 18, color: HocalistPalette.text(context, BuyerUiTokens.action))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.key, style: TextStyle(fontSize: 12, color: HocalistPalette.text(context, BuyerUiTokens.muted))),
            const SizedBox(height: 3),
            Text(entry.value, style: const TextStyle(fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w800)),
          ])),
        ])),
      ],
    ]),
  );
}

class ProfileNameEditor extends StatefulWidget {
  const ProfileNameEditor({
    super.key,
    required this.name,
    required this.save,
    this.extra,
    this.seller = false,
  });
  final bool seller;
  final String name;
  final Future<bool> Function(String) save;
  final Widget? extra;
  @override
  State<ProfileNameEditor> createState() => _ProfileNameEditorState();
}

class _ProfileNameEditorState extends State<ProfileNameEditor> {
  late final controller = TextEditingController(text: widget.name);
  bool busy = false;
  String? message;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HocalistAccountField(
        label: 'Display name',
        seller: widget.seller,
        controller: controller,
        enabled: !busy,
        maxLength: 100,
      ),
      const SizedBox(height: 12),
      AccountActionButton(
        seller: widget.seller,
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final ok = await widget.save(controller.text.trim());
                  if (mounted)
                    setState(
                      () => message = ok
                          ? 'Name saved.'
                          : 'Your name could not be saved.',
                    );
                } catch (_) {
                  if (mounted)
                    setState(
                      () => message =
                          'Your name could not be saved. Please try again.',
                    );
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        label: busy ? 'Saving…' : 'Save name',
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        AccountStateNotice(
          seller: widget.seller,
          icon: Icons.info_outline,
          title: message!,
        ),
      ],
      if (widget.extra != null) ...[const SizedBox(height: 20), widget.extra!],
    ],
  );
}

/// Role-aware secondary action using the approved account controls.
class ProfileSecondaryAction extends StatelessWidget {
  const ProfileSecondaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.seller = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool seller;
  @override
  Widget build(BuildContext context) => seller
      ? SellerSecondaryButton(label: label, onPressed: onPressed)
      : BuyerSecondaryButton(label: label, onPressed: onPressed);
}

/// Compact selection card shared by profile visibility controls.
class ProfileSharingChoice extends StatelessWidget {
  const ProfileSharingChoice({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.checkbox = false,
    this.icon = Icons.visibility_outlined,
  });
  final String label;
  final IconData icon;
  final String? description;
  final bool value, checkbox;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: HocalistPalette.surface(
        context,
        value ? BuyerUiTokens.softSurface : Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: HocalistPalette.border(
            context,
            value
                ? BuyerUiTokens.action.withValues(alpha: .35)
                : BuyerUiTokens.border,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Container(width: 32, height: 32, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: HocalistPalette.surface(context, BuyerUiTokens.softSurface)),
                child: Icon(icon, size: 18, color: HocalistPalette.text(context, BuyerUiTokens.action))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (checkbox)
                Checkbox(
                  value: value,
                  activeColor: BuyerUiTokens.action,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(v ?? false),
                )
              else
                Switch(
                  value: value,
                  activeTrackColor: BuyerUiTokens.action,
                  activeThumbColor: Colors.white,
                  inactiveTrackColor: BuyerUiTokens.border,
                  inactiveThumbColor: Colors.white,
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
