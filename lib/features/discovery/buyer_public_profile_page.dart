import '../profiles/buyer_reviews_section.dart';
import '../../data/phase2/reviews/buyer_reviews_backend.dart';
import '../../domain/phase2/requests.dart';
import '../../components/account_role_components.dart';
import '../profiles/profile_request_card.dart';
import '../profiles/profile_ui.dart';
import '../profiles/public_profile_header.dart';
import 'package:flutter/material.dart';
import '../../components/pull_refresh.dart';
import '../../domain/phase2/discovery.dart';

/// Only displays the consent-filtered public projection, never account contacts.
class BuyerPublicProfilePage extends StatefulWidget {
  const BuyerPublicProfilePage({
    required this.onBack,
    required this.load,
    this.loadAvatar,
    this.reviews,
    this.loadRequest,
    this.onOpenChat,
    this.embedded = false,
    super.key,
  });
  final VoidCallback onBack;
  final Future<PublicBuyerProfile> Function() load;
  final Future<String?> Function()? loadAvatar;
  final bool embedded;
  final BuyerReviewsRepository? reviews;
  final Future<SellerLeadProjection?> Function()? loadRequest;
  final VoidCallback? onOpenChat;
  @override
  State<BuyerPublicProfilePage> createState() => _BuyerPublicProfilePageState();
}

class _BuyerPublicProfilePageState extends State<BuyerPublicProfilePage> {
  PublicBuyerProfile? profile;
  bool loading = true;
  String? error;
  String? avatarId;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.load();
      String? photo;
      if (result.available &&
          result.displayName != null &&
          widget.loadAvatar != null) {
        try {
          photo = await widget.loadAvatar!();
        } catch (_) {}
      }
      if (mounted)
        setState(() {
          profile = result;
          avatarId = photo;
        });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The buyer profile could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PullRefreshAction(
    onRefresh: loading ? null : refresh,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          ProfileHeading('Buyer profile', onBack: widget.onBack),
        if (loading)
          const LinearProgressIndicator()
        else if (error != null)
          ProfileCard(
            child: Column(
              children: [
                Text(error!),
                TextButton(onPressed: refresh, child: const Text('Retry')),
              ],
            ),
          )
        else if (profile?.available != true)
          const ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline),
                SizedBox(height: 12),
                Text(
                  'This profile is private',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'The buyer has not shared a public profile. You can continue your conversation.',
                ),
              ],
            ),
          )
        else ...[
          PublicProfileHeader(
              role: 'Buyer',
              name: profile!.displayName ?? 'Buyer',
              subtitle: profile!.areaLabel,
              avatarId: avatarId,
            stats: PublicProfileStats(
            values: {
              'Confirmed purchases': '${profile!.verifiedPurchaseCount}',
              'Verification':
                  profile!.emailVerified == true &&
                      profile!.phoneVerified == true
                  ? 'Email & phone verified'
                  : profile!.emailVerified == true
                  ? 'Email verified'
                  : profile!.phoneVerified == true
                  ? 'Phone verified'
                  : profile!.emailVerified == null
                  ? 'Unavailable'
                  : 'Not yet verified',
            },
            ),
          ),
          if (profile!.memberSince != null) ...[
            const SizedBox(height: 16),
            Text(
              'Member since ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][profile!.memberSince!.month - 1]} ${profile!.memberSince!.year}',
            ),
          ],
          if (profile!.categories.isNotEmpty)
            ProfileSection(
              'Interests',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile!.categories
                    .map((c) => Chip(label: Text(c)))
                    .toList(),
              ),
            ),
          const SizedBox(height: 24),
          const ProfileCard(
            soft: true,
            child: Text('Exact meeting details are shared in your deal.'),
          ),
        ],
        if (widget.reviews != null)
          BuyerReviewsSection(repository: widget.reviews!),
        if (widget.loadRequest != null)
          ProfileRequestCard(load: widget.loadRequest!),
        if (widget.onOpenChat != null) ...[
          const SizedBox(height: 16),
          AccountActionButton(
            seller: true,
            label: 'Back to chat',
            onPressed: widget.onOpenChat,
          ),
        ],
        const SizedBox(height: 20),
      ],
    ),
  );
}
