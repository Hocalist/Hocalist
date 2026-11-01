import 'package:flutter/material.dart';
import '../../data/phase2/reviews/buyer_reviews_backend.dart';
import '../../data/local_marketplace_repository.dart';
import '../../components/account_role_components.dart';
import '../../components/hocalist_account_field.dart';
import '../../theme/control_foundation.dart';
import 'profile_ui.dart';

String reviewDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

class BuyerReviewsSection extends StatefulWidget {
  const BuyerReviewsSection({super.key, required this.repository});
  final BuyerReviewsRepository repository;
  @override
  State<BuyerReviewsSection> createState() => _BuyerReviewsSectionState();
}

class _BuyerReviewsSectionState extends State<BuyerReviewsSection> {
  BuyerReviewsPageData? data;
  final List<BuyerReviewEntry> items = [];
  bool busy = false;
  String? error;
  int offset = 0;
  final reported = <String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.load(offset: more ? offset : 0);
      if (!mounted) return;
      setState(() {
        if (!more) {
          items.clear();
          offset = 0;
        }
        if (!result.available) {
          items.clear();
          offset = 0;
        } else {
          final ids = items.map((e) => e.id).toSet();
          items.addAll(result.items.where((e) => !ids.contains(e.id)));
          offset += result.items.length;
        }
        data = result;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Reviews could not be loaded. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> compose() async {
    final purchases = data?.purchases ?? [];
    if (purchases.isEmpty) return;
    await showProfileEditor(
      context,
      'Review buyer',
      BuyerReviewEditor(repository: widget.repository, purchases: purchases),
    );
    if (mounted) await load();
  }

  Future<void> report(BuyerReviewEntry review) async {
    await showProfileEditor(
      context,
      'Report review',
      BuyerReviewReportEditor(
        repository: widget.repository,
        reviewId: review.id,
        onReported: () {
          if (mounted) setState(() => reported.add(review.id));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ProfileSection(
    'Reviews from sellers',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) ...[
          AccountStateNotice(
            seller: false,
            icon: Icons.info_outline,
            title: error!,
          ),
          ProfileSecondaryAction(
            label: 'Retry reviews',
            onPressed: busy ? null : () => load(),
          ),
        ],
        if (data?.available == false)
          const ProfileCard(
            child: Text('Reviews are not available for this account.'),
          ),
        if (data?.available == true) ...[
          ProfileStats(
            values: {
              'Buyer rating': data!.count == 0
                  ? 'No reviews yet'
                  : (data!.sum / data!.count).toStringAsFixed(1),
              'Reviews': '${data!.count}',
            },
          ),
          const SizedBox(height: 12),
          if (data!.purchases.isNotEmpty) ...[
            AccountActionButton(
              seller: true,
              label: 'Review buyer',
              onPressed: busy ? null : compose,
            ),
            const SizedBox(height: 12),
          ],
          if (items.isEmpty)
            const ProfileCard(
              child: Text(
                'No seller reviews yet. Reviews can be written after a confirmed purchase.',
              ),
            ),
          for (final review in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      review.seller,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ReviewStars(rating: review.rating),
                    const SizedBox(height: 6),
                    Text(
                      'Confirmed purchase · ${reviewDate(review.createdAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (review.body.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(review.body),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: reported.contains(review.id)
                            ? null
                            : () => report(review),
                        child: Text(
                          reported.contains(review.id)
                              ? 'Report sent'
                              : 'Report review',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data!.hasMore)
            ProfileSecondaryAction(
              label: 'Show more reviews',
              onPressed: busy ? null : () => load(more: true),
            ),
        ],
      ],
    ),
  );
}

class ReviewStars extends StatelessWidget {
  const ReviewStars({super.key, required this.rating});
  final int rating;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating out of 5 stars',
    child: ExcludeSemantics(
      child: Wrap(
        children: List.generate(
          5,
          (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: const Color(0xffffad00),
            size: 22,
          ),
        ),
      ),
    ),
  );
}

class BuyerReviewEditor extends StatefulWidget {
  const BuyerReviewEditor({
    super.key,
    required this.repository,
    required this.purchases,
  });
  final BuyerReviewsRepository repository;
  final List<BuyerReviewPurchase> purchases;
  @override
  State<BuyerReviewEditor> createState() => _BuyerReviewEditorState();
}

class _BuyerReviewEditorState extends State<BuyerReviewEditor> {
  late String selected = widget.purchases.first.id;
  final body = TextEditingController();
  int rating = 0;
  bool busy = false, attempted = false;
  String? error;
  final intentKey = LocalMarketplaceRepository.newStoreOperationKey(
    'buyer-review',
  );
  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || rating < 1) return;
    setState(() {
      busy = true;
      attempted = true;
      error = null;
    });
    try {
      await widget.repository.submit(
        intentKey,
        selected,
        rating,
        body.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'We could not confirm your review. Retry to check or save this same review.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Share your experience with this buyer. Keep comments respectful and leave out private contact or address details.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Confirmed purchase',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      if (!attempted)
        HocalistSelectMenu<String>(
          role: HocalistControlRole.seller,
          value: selected,
          options: widget.purchases.map((p) => p.id).toList(),
          expanded: true,
          labelBuilder: (id) {
            final p = widget.purchases.firstWhere((p) => p.id == id);
            return '${p.title} · ${reviewDate(p.date)}';
          },
          onSelected: (id) => setState(() => selected = id),
        )
      else
        Text(widget.purchases.firstWhere((p) => p.id == selected).title),
      const SizedBox(height: 18),
      const Text('Your rating', style: TextStyle(fontWeight: FontWeight.w800)),
      Wrap(
        spacing: 4,
        children: List.generate(
          5,
          (i) => IconButton(
            tooltip: '${i + 1} star${i == 0 ? '' : 's'}',
            onPressed: attempted ? null : () => setState(() => rating = i + 1),
            icon: Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xffffad00),
              size: 30,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      HocalistAccountField(
        label: 'Comment (optional)',
        seller: true,
        controller: body,
        enabled: !attempted,
        maxLines: 4,
        maxLength: 1500,
      ),
      if (error != null) ...[
        const SizedBox(height: 12),
        AccountStateNotice(
          seller: true,
          icon: Icons.info_outline,
          title: error!,
        ),
      ],
      const SizedBox(height: 18),
      AccountActionButton(
        seller: true,
        label: busy
            ? 'Saving…'
            : attempted
            ? 'Retry review'
            : 'Publish review',
        onPressed: busy || rating == 0 ? null : save,
      ),
    ],
  );
}

class BuyerReviewReportEditor extends StatefulWidget {
  const BuyerReviewReportEditor({
    super.key,
    required this.repository,
    required this.reviewId,
    required this.onReported,
  });
  final BuyerReviewsRepository repository;
  final String reviewId;
  final VoidCallback onReported;
  @override
  State<BuyerReviewReportEditor> createState() =>
      _BuyerReviewReportEditorState();
}

class _BuyerReviewReportEditorState extends State<BuyerReviewReportEditor> {
  final reason = TextEditingController();
  bool busy = false, attempted = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || reason.text.trim().length < 10) return;
    setState(() {
      busy = true;
      attempted = true;
      error = null;
    });
    try {
      await widget.repository.report(widget.reviewId, reason.text.trim());
      if (mounted) {
        widget.onReported();
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Your report could not be confirmed. Please retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Tell our support team what is wrong with this review. Reporting does not automatically remove it.',
      ),
      const SizedBox(height: 16),
      HocalistAccountField(
        label: 'Reason (at least 10 characters)',
        controller: reason,
        enabled: !attempted,
        maxLines: 4,
        maxLength: 1000,
        onChanged: (_) => setState(() {}),
      ),
      if (error != null) ...[
        const SizedBox(height: 12),
        AccountStateNotice(
          seller: false,
          icon: Icons.info_outline,
          title: error!,
        ),
      ],
      const SizedBox(height: 16),
      AccountActionButton(
        seller: false,
        label: busy ? 'Sending…' : 'Send report',
        onPressed: busy || reason.text.trim().length < 10 ? null : send,
      ),
    ],
  );
}
