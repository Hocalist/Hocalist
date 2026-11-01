import '../media/private_remote_image.dart';
import '../approved/category_question_editor.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../components/pull_refresh.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../components/hocalist_section_intro.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/repositories.dart';
import '../../domain/phase2/store_listings.dart';

/// Only renders the server's public projection. No private seller lookup.
class PublicSellerListings extends StatefulWidget {
  const PublicSellerListings({
    required this.repository,
    required this.sellerProfileId,
    this.onEnquire,
    super.key,
  });
  final StoreListingRepository repository;
  final String sellerProfileId;
  final Future<void> Function(PublicStoreListing)? onEnquire;
  @override
  State<PublicSellerListings> createState() => _PublicSellerListingsState();
}

class _PublicSellerListingsState extends State<PublicSellerListings> {
  List<PublicStoreListing> _items = [];
  String? _cursor, _error;
  bool _loading = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PublicSellerListings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerProfileId != widget.sellerProfileId) {
      _items = [];
      _cursor = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final seller = widget.sellerProfileId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.fetchPublicSellerListings(
        sellerProfileId: seller,
        page: PageQuery(limit: 20, cursor: more ? _cursor : null),
      );
      if (!mounted || generation != _generation) return;
      if (result.isFailure) throw StateError('unavailable');
      final page = result.valueOrNull!;
      if (page.items.any((item) => item.sellerProfileId != seller) ||
          (more && page.nextCursor != null && page.nextCursor == _cursor)) {
        throw StateError('invalid_page');
      }
      setState(() {
        final merged = <String, PublicStoreListing>{
          if (more)
            for (final item in _items) item.id: item,
          for (final item in page.items) item.id: item,
        };
        _items = List.unmodifiable(merged.values);
        _cursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) {
          _items = [];
          _cursor = null;
        }
        _error = 'Could not load store listings. Try again.';
      });
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HocalistSectionIntro(
        title: 'Store listings',
        icon: Icons.storefront_outlined,
        trailing: PullRefreshAction(onRefresh: _loading ? null : () => _load()),
      ),
      if (_loading) const BuyerProgressStrip(label: 'Updating listings…'),
      if (_error != null) Text(_error!),
      if (!_loading && _error == null && _items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No published listings available.'),
        ),
      LayoutBuilder(
        builder: (context, box) {
          final columns =
              box.maxWidth >= 760 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.3
              ? 2
              : 1;
          final width = ((box.maxWidth - (columns - 1) * 12) / columns).clamp(
            0.0,
            400.0,
          );
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in _items)
                SizedBox(
                  width: width,
                  child: _PublicListingCard(
                    key: ValueKey('public-listing-${item.id}'),
                    item: item,
                    onEnquire: widget.onEnquire,
                  ),
                ),
            ],
          );
        },
      ),
      if (_cursor != null)
        TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: const Text('Load more listings'),
        ),
      if (_error != null && _cursor == null)
        TextButton(
          onPressed: _loading ? null : () => _load(),
          child: const Text('Retry listings'),
        ),
    ],
  );
}

class _PublicListingCard extends StatefulWidget {
  const _PublicListingCard({required this.item, this.onEnquire, super.key});
  final PublicStoreListing item;
  final Future<void> Function(PublicStoreListing)? onEnquire;
  @override
  State<_PublicListingCard> createState() => _PublicListingCardState();
}

class _PublicListingCardState extends State<_PublicListingCard> {
  void _showDetails() {
    final item = widget.item;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => BuyerModalSheet(
        title: 'Listing details',
        icon: Icons.storefront_outlined,
        onClose: () => Navigator.pop(sheet),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _displayPrice,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: HocalistPalette.text(sheet, BuyerUiTokens.action),
              ),
            ),
            if (item.availability.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item.availability),
            ],
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.description),
            ],
            CategoryAnswersView(answers: item.categoryAnswers),
            if (item.serviceArea.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Pickup or service area',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(item.serviceArea),
            ],
          ],
        ),
      ),
    );
  }

  String get _displayPrice {
    final label = widget.item.priceLabel.trim();
    return RegExp(r'^\d[\d,]*(?:\.\d{1,2})?$').hasMatch(label)
        ? String.fromCharCode(36) + label
        : label;
  }

  bool opening = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        border: Border.all(
          color: HocalistPalette.border(context, BuyerUiTokens.border),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        key: ValueKey('public-listing-photo-${item.id}'),
                        width: 76,
                        height: 76,
                        child: item.imageMediaIds.isEmpty
                            ? ColoredBox(
                                color: HocalistPalette.surface(
                                  context,
                                  BuyerUiTokens.softSurface,
                                ),
                                child: const Icon(
                                  Icons.storefront_outlined,
                                  size: 28,
                                ),
                              )
                            : PrivateRemoteImage(
                                id: item.imageMediaIds.first,
                                size: 76,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: _showDetails,
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _displayPrice,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: HocalistPalette.text(
                                context,
                                BuyerUiTokens.action,
                              ),
                            ),
                          ),
                          if (item.availability.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              item.availability,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: HocalistPalette.text(
                                  context,
                                  BuyerUiTokens.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 12,
                  overflowSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _showDetails,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('View details'),
                    ),

                    if (widget.onEnquire != null)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: BuyerUiTokens.action,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        key: ValueKey('enquire-${item.id}'),
                        onPressed: opening
                            ? null
                            : () async {
                                if (opening) return;
                                setState(() => opening = true);
                                try {
                                  await widget.onEnquire!(item);
                                } catch (_) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Your enquiry could not be opened. Please try again.',
                                        ),
                                      ),
                                    );
                                } finally {
                                  if (mounted) setState(() => opening = false);
                                }
                              },
                        child: Text(opening ? 'Opening…' : 'Ask a question'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
