import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_section_intro.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/repositories.dart';
import '../../domain/phase2/store_listings.dart';

/// Only renders the server's public projection. No private seller lookup.
class PublicSellerListings extends StatefulWidget {
  const PublicSellerListings({
    required this.repository,
    required this.sellerProfileId,
    super.key,
  });
  final StoreListingRepository repository;
  final String sellerProfileId;
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
        _error = 'Could not load published listings. Try again.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HocalistSectionIntro(
        title: 'Published listings',
        icon: Icons.storefront_outlined,
        trailing: IconButton(
          tooltip: 'Refresh published listings',
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ),
      if (_loading) const BuyerProgressStrip(label: 'Updating listings…'),
      if (_error != null)
        BuyerStateNotice(
          icon: Icons.error_outline_rounded,
          tone: BuyerNoticeTone.error,
          title: 'Listings could not be loaded',
          body: _error,
        ),
      if (!_loading && _error == null && _items.isEmpty)
        const BuyerStateNotice(
          icon: Icons.storefront_outlined,
          title: 'No published listings available.',
          body: 'Published items and services will appear here.',
          tone: BuyerNoticeTone.neutral,
        ),
      for (final item in _items)
        HocalistEntrance(
          key: ValueKey('listing-entrance-${item.id}'),
          child: _PublicListingCard(
            key: ValueKey('public-listing-${item.id}'),
            item: item,
          ),
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
  const _PublicListingCard({required this.item, super.key});
  final PublicStoreListing item;
  @override
  State<_PublicListingCard> createState() => _PublicListingCardState();
}

class _PublicListingCardState extends State<_PublicListingCard> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HocalistPalette.border(context, BuyerUiTokens.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: Material(
              color: HocalistPalette.surface(context, Colors.transparent),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            BuyerUiTokens.softSurface,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.storefront_outlined,
                          size: 20,
                          color: HocalistPalette.text(
                            context,
                            BuyerUiTokens.action,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: HocalistPalette.text(
                                  context,
                                  BuyerUiTokens.text,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${item.priceLabel} · ${item.categoryLabel}',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: HocalistPalette.text(
                                  context,
                                  BuyerUiTokens.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: expanded ? .25 : 0,
                        duration: HocalistMotion.duration(context),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: HocalistPalette.text(
                            context,
                            BuyerUiTokens.action,
                          ),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          HocalistExpand(
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: BuyerUiTokens.border, height: 16),
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: HocalistPalette.text(
                                context,
                                BuyerUiTokens.text,
                              ),
                            ),
                          ),
                        if (item.serviceArea.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Service area: ${item.serviceArea}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: HocalistPalette.text(
                                  context,
                                  BuyerUiTokens.muted,
                                ),
                              ),
                            ),
                          ),
                        if (item.availability.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Availability: ${item.availability}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: HocalistPalette.text(
                                  context,
                                  BuyerUiTokens.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
