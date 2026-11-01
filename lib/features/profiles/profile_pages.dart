import 'package:flutter/material.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import '../../domain/phase2/reviews.dart';
import '../media/private_remote_image.dart';
import 'profile_ui.dart';
import 'public_profile_header.dart';
import 'profile_rating_stars.dart';
import '../../components/account_role_components.dart';

class ProfileOverviewPage extends StatelessWidget {
  const ProfileOverviewPage({
    super.key,
    required this.seller,
    required this.name,
    required this.onBack,
    required this.onPreview,
    required this.onEdit,
    required this.onAddress,
    required this.onSavedPlaces,
    required this.onVisibility,
    required this.onVerification,
    required this.onSettings,
    required this.onActivity,
    this.photoEditor,
    this.menuBuilder,
    this.onPhoto,
    this.onCategories,
    this.onPayments,
    this.onHistory,
    this.onMeeting,
    this.avatarId,
    this.area,
    this.addressSummary,
    this.verificationSummary,
    this.meetingPreference,
    this.categories = const [],
    this.stats = const {},
    this.about,
  });
  final Widget Function(VoidCallback, VoidCallback, VoidCallback?)? menuBuilder;
  final Widget? photoEditor;
  final bool seller;
  final String name;
  final String? avatarId,
      area,
      addressSummary,
      verificationSummary,
      meetingPreference,
      about;
  final List<String> categories;
  final Map<String, String> stats;
  final VoidCallback onBack,
      onPreview,
      onEdit,
      onAddress,
      onSavedPlaces,
      onVisibility,
      onVerification,
      onSettings,
      onActivity;
  final VoidCallback? onPhoto, onCategories, onPayments, onHistory, onMeeting;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness, availableWidth: media.size.width, textScaler: media.textScaler);
    return ApprovedReplicaScope(metrics: metrics, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BuyerNestedHeader(
          title: 'Edit Profile',
          subtitle: seller
              ? 'Keep your seller information accurate and concise.'
              : 'Keep your buyer information accurate and concise.',
          onBack: onBack,
        ),
        SizedBox(height: metrics.spacing(10)),
        if (photoEditor != null)
          photoEditor!
        else
          ProfileIdentity(name: name, subtitle: seller ? 'Seller' : 'Buyer', avatarId: avatarId, onPhoto: onPhoto),
        SizedBox(height: metrics.spacing(18)),
        if (menuBuilder != null) menuBuilder!(onEdit, onVisibility, onCategories),
        SizedBox(height: metrics.spacing(18)),
      ],
    ));
  }
}

class SellerPublicProfileView extends StatefulWidget {
  const SellerPublicProfileView({
    super.key,
    required this.name,
    required this.onBack,
    required this.load,
    this.listings,
    this.reputation,
    this.reputationLoading = false,
    this.reputationError,
    this.onSelect,
    this.onOpenChat,
    this.selectionBusy = false,
    this.selectionError,
    this.embedded = false,
  });
  final String name;
  final VoidCallback onBack;
  final Future<Map<String, dynamic>> Function() load;
  final Widget? listings;
  final PublicSellerReputation? reputation;
  final bool reputationLoading, selectionBusy;
  final String? reputationError, selectionError;
  final VoidCallback? onSelect, onOpenChat;
  final bool embedded;
  @override
  State<SellerPublicProfileView> createState() =>
      _SellerPublicProfileViewState();
}

class _SellerPublicProfileViewState extends State<SellerPublicProfileView> {
  Map<String, dynamic>? details;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => details = d);
    } catch (_) {
      if (mounted)
        setState(() => error = 'Profile details could not be loaded.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = details;
    final reputation = widget.reputation;
    final categories = (d?['categories'] as List? ?? [])
        .whereType<String>()
        .toList();
    final locations = (d?['locations'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final available = !loading && error == null && d?['available'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          ProfileHeading('Seller profile', onBack: widget.onBack),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          ProfileCard(
            child: Column(
              children: [
                Text(error!),
                TextButton(onPressed: reload, child: const Text('Try again')),
              ],
            ),
          ),
        if (!loading && error == null && !available)
          const ProfileCard(
            child: Text('This seller profile is not available.'),
          ),
        if (available) ...[
          PublicProfileHeader(
            role: 'Seller',
            name: d?['display_name'] as String? ?? widget.name,
            avatarId: d?['avatar_media_id'] as String?,
            subtitle: d?['area_label'] as String?,
            badges: (d?['badges'] as List? ?? []).whereType<String>().toList(),
            stats: PublicProfileStats(rating: reputation?.available == true ? reputation!.averageRating : null, values: {
            'Rating': reputation?.available == true
              ? reputation!.averageRating == null ? 'No reviews yet' : '${reputation.averageRating!.toStringAsFixed(1)} (${reputation.ratingCount} ${reputation.ratingCount == 1 ? 'review' : 'reviews'})'
              : widget.reputationLoading ? 'Loading…' : 'Unavailable',
            'Completed sales': d?['completed_sales'] is num ? '${d!['completed_sales']}'
              : reputation?.available == true ? '${reputation!.completedDeals}'
              : widget.reputationLoading ? 'Loading…' : 'Unavailable',
            'Verification': d?['verification_status'] as String? ??
              ((d?['badges'] as List? ?? []).contains('Admin reviewed') ? 'Admin reviewed' : 'Not yet verified'),
            }),
          ),
          if ((d?['about'] as String?)?.trim().isNotEmpty == true)
            ProfileSection('About', child: ProfileCard(child: Text(d!['about'] as String))),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: categories.map((c) => Chip(label: Text(c))).toList(),
            ),
          ],
          if ((d?['area_label'] as String?)?.isNotEmpty == true ||
              locations.isNotEmpty)
            ProfileSection(
              'Locations & service area',
              child: ProfileCard(
                soft: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((d?['area_label'] as String?)?.isNotEmpty == true)
                      Text(
                        '${d!['area_label']}${d['radius_miles'] == null ? '' : ' · Within ${d['radius_miles']} miles'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    for (final location in locations) ...[
                      const SizedBox(height: 14),
                      Text(
                        location['name'] as String? ?? 'Business location',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(location['address'] as String? ?? ''),
                    ],
                    if (locations.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Locations shared by this seller',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if ((d?['phone'] as String?)?.isNotEmpty == true ||
              (d?['email'] as String?)?.isNotEmpty == true)
            ProfileSection(
              'Business contact',
              child: ProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((d?['phone'] as String?)?.isNotEmpty == true)
                      SelectableText(d!['phone'] as String),
                    if ((d?['email'] as String?)?.isNotEmpty == true && (d?['phone'] as String?)?.isNotEmpty == true)
                      const SizedBox(height: 10),
                    if ((d?['email'] as String?)?.isNotEmpty == true)
                      SelectableText(d!['email'] as String),
                  ],
                ),
              ),
            ),
          if (widget.listings != null) ...[
            const SizedBox(height: 24),
            widget.listings!,
          ],
          ProfileSection(
            'Ratings & reviews',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.reputationLoading)
                  const LinearProgressIndicator()
                else if (widget.reputationError != null)
                  Text(widget.reputationError!)
                else if (reputation?.available != true)
                  const Text('Reviews are not available right now.')
                else if (reputation!.reviews.isEmpty)
                  const ProfileCard(child: Text('No reviews yet.'))
                else ...[
                  for (final review in reputation.reviews)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProfileCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CircleAvatar(radius: 18, backgroundColor: const Color(0xfff1edff),
                                child: Text(review.reviewerLabel.isEmpty ? '?' : review.reviewerLabel.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: Color(0xff3320b7), fontWeight: FontWeight.w800))),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(review.reviewerLabel, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
                                const SizedBox(height: 5),
                                ProfileRatingStars(rating: review.rating.toDouble()),
                              ])),
                            ]),
                            if (review.body.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(review.body),
                            ],
                            if (review.imageMediaIds.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: review.imageMediaIds
                                    .map(
                                      (id) => SizedBox(
                                        width: 80,
                                        height: 80,
                                        child: PrivateRemoteImage(id: id),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (widget.selectionError != null) Text(widget.selectionError!),
          if (widget.onSelect != null) ...[
            const SizedBox(height: 16),
            AccountActionButton(
              seller: false,
              onPressed: widget.selectionBusy ? null : widget.onSelect,
              label: widget.selectionBusy ? 'Selecting…' : 'Select this offer',
            ),
          ],
        ],
        if (widget.onOpenChat != null) ...[
          const SizedBox(height: 16),
          AccountActionButton(seller: false, label: 'Back to chat', onPressed: widget.onOpenChat),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
