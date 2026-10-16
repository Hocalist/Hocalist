import '../../components/hocalist_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_marketplace_repository.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../data/phase2/media/image_gateway.dart';
import '../media/private_image_picker.dart';
import '../media/private_remote_image.dart';

enum _StoreKindFilter { all, products, services }

enum _StoreStatusFilter { all, active, draft, paused }

class ApprovedSellerStorePage extends StatefulWidget {
  const ApprovedSellerStorePage({
    required this.repository,
    required this.onStoreSettings,
    this.sellerName,
    this.sellerProfileId,
    super.key,
  });

  final LocalMarketplaceRepository repository;
  final VoidCallback onStoreSettings;

  /// Authoritative seller display name for the real public preview.
  final String? sellerName;
  final String? sellerProfileId;

  @override
  State<ApprovedSellerStorePage> createState() =>
      _ApprovedSellerStorePageState();
}

class _ApprovedSellerStorePageState extends State<ApprovedSellerStorePage> {
  final TextEditingController _searchController = TextEditingController();
  _StoreKindFilter _kindFilter = _StoreKindFilter.all;
  _StoreStatusFilter _statusFilter = _StoreStatusFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LocalStoreListing> _visibleListings(List<LocalStoreListing> listings) {
    final query = _query.trim().toLowerCase();
    return listings
        .where((listing) {
          final kindMatches = switch (_kindFilter) {
            _StoreKindFilter.all => true,
            _StoreKindFilter.products =>
              listing.kind == LocalListingKind.product,
            _StoreKindFilter.services =>
              listing.kind == LocalListingKind.service,
          };
          final statusMatches = switch (_statusFilter) {
            _StoreStatusFilter.all => true,
            _StoreStatusFilter.active =>
              listing.status == LocalListingStatus.active,
            _StoreStatusFilter.draft =>
              listing.status == LocalListingStatus.draft,
            _StoreStatusFilter.paused =>
              listing.status == LocalListingStatus.paused,
          };
          final queryMatches =
              query.isEmpty ||
              listing.title.toLowerCase().contains(query) ||
              listing.category.toLowerCase().contains(query) ||
              listing.description.toLowerCase().contains(query);
          return kindMatches && statusMatches && queryMatches;
        })
        .toList(growable: false);
  }

  Future<void> _openListingEditor([LocalStoreListing? listing]) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddStoreListingSheet(
        initialListing: listing,
        storeBacked: widget.repository.isStoreBacked,
        categories: widget.repository.storeCategories,
        onReconcile: () => widget.repository.refreshStore(),
        onSave: (saved, {required operationKey, required isRetry}) async {
          try {
            final result = await widget.repository.saveStoreListing(
              saved,
              operationKey: operationKey,
            );
            if (!mounted) return const _StoreEditorOutcome();
            final warning = widget.repository.storeError;
            _showMessage(
              warning ?? _savedMessage(result, isNew: listing == null),
            );
            return const _StoreEditorOutcome();
          } on StoreBackendException catch (error) {
            return _StoreEditorOutcome(
              error: error.message,
              ambiguous: error.ambiguous,
            );
          }
        },
      ),
    );
  }

  String _savedMessage(LocalStoreListing saved, {required bool isNew}) {
    if (saved.status == LocalListingStatus.active) {
      return saved.pendingReview
          ? 'Submitted for review. It appears in discovery after approval.'
          : isNew
          ? 'Listing published to your store.'
          : 'Listing changes saved.';
    }
    if (saved.status == LocalListingStatus.draft) {
      return 'Draft saved to your store.';
    }
    return 'Listing saved and paused.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showStoreMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.storefront_outlined,
        title: 'Store options',
        subtitle: 'Preview or update how buyers see your business.',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          children: [
            _StoreSheetAction(
              key: const Key('sellerStorePreviewAction'),
              icon: Icons.visibility_outlined,
              title: 'Preview public store',
              subtitle: 'See your currently published listings.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showPublicStorePreview();
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              key: const Key('sellerStoreSettingsAction'),
              icon: Icons.tune_rounded,
              title: 'Store settings',
              subtitle: 'Update your store profile and service details.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onStoreSettings();
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              key: const Key('sellerStoreShareAction'),
              icon: Icons.ios_share_outlined,
              title: 'Share store',
              subtitle:
                  widget.sellerProfileId != null &&
                      widget.repository.storeListings.any(
                        (l) => l.isPubliclyVisible,
                      )
                  ? 'Copy a link to your published Store. Drafts stay private.'
                  : 'Publish an approved listing before sharing your Store.',
              enabled:
                  widget.sellerProfileId != null &&
                  widget.repository.storeListings.any(
                    (l) => l.isPubliclyVisible,
                  ),
              onTap: () async {
                final id = widget.sellerProfileId;
                if (id == null) return;
                await Clipboard.setData(
                  ClipboardData(text: 'https://www.hocalist.com/store/$id'),
                );
                if (!sheetContext.mounted || !mounted) return;
                Navigator.of(sheetContext).pop();
                _showMessage(
                  'Store link copied. Only approved published listings are shared.',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPublicStorePreview() async {
    final active = widget.repository.storeListings
        .where(
          (listing) =>
              listing.status == LocalListingStatus.active &&
              !listing.pendingReview,
        )
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.visibility_outlined,
        title: 'Public store preview',
        subtitle: 'This is the catalogue buyers will see in discovery.',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.repository.isStoreBacked)
              const _StoreIdentityCard()
            else if ((widget.sellerName ?? '').trim().isNotEmpty)
              _StoreIdentityCard(
                name: widget.sellerName!.trim(),
                realMode: true,
              ),
            const SizedBox(height: 12),
            if (active.isEmpty)
              const _StoreEmptyState(
                title: 'Nothing published yet',
                body: 'Publish a listing before sharing your public store.',
              )
            else
              for (final listing in active) ...[
                _PublicListingPreview(listing: listing),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    var selected = _statusFilter;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SellerModalSheet(
          icon: Icons.filter_alt_outlined,
          title: 'Filter listings',
          subtitle:
              'Choose which listing status appears in your store manager.',
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in _StoreStatusFilter.values) ...[
                _StoreRadioOption(
                  label: _statusLabel(option),
                  selected: selected == option,
                  onTap: () => setSheetState(() => selected = option),
                ),
                if (option != _StoreStatusFilter.values.last)
                  const SizedBox(height: 8),
              ],
              const SizedBox(height: 14),
              SellerPrimaryButton(
                label: 'Apply filter',
                onPressed: () {
                  setState(() => _statusFilter = selected);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showListingActions(LocalStoreListing listing) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: listing.kind == LocalListingKind.product
            ? Icons.inventory_2_outlined
            : Icons.design_services_outlined,
        title: listing.title,
        subtitle:
            'Manage this ${_kindLabel(listing.kind).toLowerCase()} listing.',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          children: [
            _StoreSheetAction(
              key: const Key('sellerStoreEditListing'),
              icon: Icons.edit_outlined,
              title: 'Edit listing',
              subtitle: 'Update details, images, pricing, or availability.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openListingEditor(listing);
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              icon: Icons.visibility_outlined,
              title: 'Preview listing',
              subtitle: 'Review the buyer-facing listing card.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showListingPreview(listing);
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              key: const Key('sellerStoreToggleListing'),
              icon: listing.status == LocalListingStatus.active
                  ? Icons.pause_circle_outline
                  : Icons.publish_outlined,
              title: listing.status == LocalListingStatus.active
                  ? 'Pause listing'
                  : 'Publish listing',
              subtitle: listing.pendingReview
                  ? 'It is not visible to buyers while it awaits review.'
                  : listing.status == LocalListingStatus.active
                  ? 'Hide it from buyer discovery without deleting it.'
                  : widget.repository.isStoreBacked
                  ? 'Make it available for discovery after approval.'
                  : 'Make it visible to buyers in discovery.',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final publishing = listing.status != LocalListingStatus.active;
                try {
                  final updated = await widget.repository
                      .updateStoreListingStatus(
                        listing.id,
                        publishing
                            ? LocalListingStatus.active
                            : LocalListingStatus.paused,
                      );
                  if (!mounted) return;
                  _showMessage(
                    publishing
                        ? updated.pendingReview
                              ? 'Submitted for review. It appears in discovery after approval.'
                              : 'Listing published.'
                        : 'Listing paused.',
                  );
                } on StoreBackendException catch (error) {
                  if (!mounted) return;
                  _showMessage(error.message);
                }
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              icon: Icons.copy_outlined,
              title: 'Duplicate',
              subtitle: 'Create a draft copy to edit separately.',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  final copy = await widget.repository.duplicateStoreListing(
                    listing.id,
                  );
                  if (!mounted) return;
                  _showMessage(
                    copy == null
                        ? 'Listing could not be copied.'
                        : 'Draft copy created.',
                  );
                } on StoreBackendException catch (error) {
                  if (!mounted) return;
                  _showMessage(error.message);
                }
              },
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              icon: Icons.delete_outline_rounded,
              title: widget.repository.isStoreBacked
                  ? 'Archive listing'
                  : 'Delete listing',
              subtitle: widget.repository.isStoreBacked
                  ? 'Hide it from your Store. Its record is kept.'
                  : 'Remove it from your store manager.',
              color: SellerUiColors.red,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(listing);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showListingPreview(LocalStoreListing listing) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.visibility_outlined,
        title: 'Listing preview',
        subtitle: 'Review the buyer-facing details before publishing.',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: _PublicListingPreview(listing: listing, expanded: true),
      ),
    );
  }

  Future<void> _confirmDelete(LocalStoreListing listing) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.delete_outline_rounded,
        title: widget.repository.isStoreBacked
            ? 'Archive this listing?'
            : 'Delete this listing?',
        subtitle: widget.repository.isStoreBacked
            ? 'This hides ${listing.title} from your Store and buyer discovery. Its record is kept.'
            : 'This removes ${listing.title} from the local store manager.',
        accentColor: SellerUiColors.red,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cancel = SellerSecondaryButton(
              label: 'Keep listing',
              onPressed: () => Navigator.of(sheetContext).pop(),
            );
            final remove = SellerPrimaryButton(
              label: widget.repository.isStoreBacked
                  ? 'Archive listing'
                  : 'Delete listing',
              colors: const [SellerUiColors.red, Color(0xffcf1621)],
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await widget.repository.deleteStoreListing(listing.id);
                  if (!mounted) return;
                  _showMessage(
                    widget.repository.isStoreBacked
                        ? 'Listing archived.'
                        : 'Listing deleted.',
                  );
                } on StoreBackendException catch (error) {
                  if (!mounted) return;
                  _showMessage(error.message);
                }
              },
            );
            if (constraints.maxWidth < 330) {
              return Column(
                children: [cancel, const SizedBox(height: 8), remove],
              );
            }
            return Row(
              children: [
                Expanded(child: cancel),
                const SizedBox(width: 10),
                Expanded(child: remove),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SellerResponsivePage(
      builder: (context, metrics) => SizedBox.expand(
        child: AnimatedBuilder(
          animation: widget.repository,
          builder: (context, _) {
            final listings = _visibleListings(widget.repository.storeListings);
            final activeCount = widget.repository.storeListings
                .where(
                  (listing) =>
                      listing.status == LocalListingStatus.active &&
                      !listing.pendingReview,
                )
                .length;
            // Backed Store creation needs an admin-managed active category.
            // Prototype mode keeps the approved free-text category flow.
            final catalogueReady =
                !widget.repository.isStoreBacked ||
                widget.repository.storeCategories.any(
                  (category) => category.isActive,
                );
            return SingleChildScrollView(
              key: const Key('sellerStoreScroll'),
              padding: EdgeInsets.fromLTRB(
                metrics.pageHorizontalPadding(14),
                metrics.spacing(14),
                metrics.pageHorizontalPadding(14),
                metrics.spacing(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Store',
                              style: sellerText(
                                metrics,
                                21,
                                weight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: metrics.spacing(3)),
                            Text(
                              'Manage the products and services buyers can discover.',
                              style: sellerText(
                                metrics,
                                11.25,
                                color: SellerUiColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: metrics.spacing(8)),
                      IconButton(
                        key: const Key('sellerStoreMenu'),
                        tooltip: 'Store options',
                        onPressed: _showStoreMenu,
                        icon: const Icon(Icons.more_vert_rounded),
                        color: SellerUiColors.ink,
                        style: IconButton.styleFrom(
                          backgroundColor: SellerUiColors.lavender,
                          minimumSize: Size.square(metrics.artSize(40)),
                        ),
                      ),
                    ],
                  ),
                  if (widget.repository.storeLoading) ...[
                    SizedBox(height: metrics.spacing(10)),
                    const SellerProgressStrip(
                      key: Key('sellerStoreLoading'),
                      label: 'Loading your listings…',
                    ),
                  ],
                  if (widget.repository.storeError != null) ...[
                    SizedBox(height: metrics.spacing(10)),
                    _StoreErrorNotice(
                      message: widget.repository.storeError!,
                      onRetry: widget.repository.refreshStore,
                    ),
                  ],
                  SizedBox(height: metrics.spacing(12)),
                  _StoreSummaryCard(
                    activeCount: activeCount,
                    totalCount: widget.repository.storeListings.length,
                  ),
                  SizedBox(height: metrics.spacing(12)),
                  _AddListingCard(
                    onTap: _openListingEditor,
                    enabled: catalogueReady,
                    disabledNote:
                        'Adding listings is unavailable until an administrator '
                        'configures at least one active Store category.',
                  ),
                  SizedBox(height: metrics.spacing(14)),
                  _StoreKindFilters(
                    selected: _kindFilter,
                    onSelected: (value) => setState(() => _kindFilter = value),
                  ),
                  SizedBox(height: metrics.spacing(10)),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('sellerStoreSearch'),
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          style: sellerInputText(metrics),
                          decoration: _storeInputDecoration(
                            metrics,
                            hintText: 'Search your listings',
                            prefixIcon: Icons.search_rounded,
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.spacing(8)),
                      SizedBox.square(
                        dimension: 48,
                        child: OutlinedButton(
                          key: const Key('sellerStoreFilter'),
                          onPressed: _showFilters,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: SellerUiColors.primaryBright,
                            side: const BorderSide(
                              color: SellerUiColors.lavenderBorder,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                metrics.geometry(11),
                              ),
                            ),
                          ),
                          child: Badge(
                            isLabelVisible:
                                _statusFilter != _StoreStatusFilter.all,
                            smallSize: metrics.geometry(7),
                            child: Icon(
                              Icons.filter_alt_outlined,
                              size: metrics.artSize(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.spacing(13)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _statusFilter == _StoreStatusFilter.all
                              ? 'Your listings'
                              : '${_statusLabel(_statusFilter)} listings',
                          style: sellerText(
                            metrics,
                            14,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${listings.length}',
                        style: sellerText(
                          metrics,
                          11,
                          weight: FontWeight.w800,
                          color: SellerUiColors.muted,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.spacing(8)),
                  if (listings.isEmpty)
                    _StoreEmptyState(
                      title: widget.repository.storeListings.isEmpty
                          ? 'No listings yet'
                          : 'No listings found',
                      body: widget.repository.storeListings.isEmpty
                          ? 'Add your first product or service. It stays '
                                'private until you publish it.'
                          : _query.isEmpty
                          ? 'Change the filter to see other listings.'
                          : 'Try another search term or clear your filters.',
                    )
                  else
                    for (final listing in listings) ...[
                      _StoreListingCard(
                        listing: listing,
                        onTap: () => _showListingActions(listing),
                      ),
                      SizedBox(height: metrics.spacing(9)),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoreSummaryCard extends StatelessWidget {
  const _StoreSummaryCard({
    required this.activeCount,
    required this.totalCount,
  });

  final int activeCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final hasPublished = activeCount > 0;
    final (badgeLabel, badgeForeground, badgeBackground) = hasPublished
        ? ('Store active', SellerUiColors.green, SellerUiColors.greenSurface)
        : totalCount == 0
        ? ('No listings yet', SellerUiColors.muted, SellerUiColors.lavender)
        : ('Not published', SellerUiColors.amber, SellerUiColors.amberSurface);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          padding: EdgeInsets.all(metrics.geometry(12)),
          decoration: BoxDecoration(
            color: SellerUiColors.lavender,
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
          ),
          child: Row(
            children: [
              Container(
                width: metrics.artSize(42),
                height: metrics.artSize(42),
                decoration: const BoxDecoration(
                  color: SellerUiColors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  size: metrics.artSize(23),
                  color: SellerUiColors.primaryBright,
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$activeCount published',
                      style: sellerText(metrics, 12.5, weight: FontWeight.w800),
                    ),
                    SizedBox(height: metrics.spacing(2)),
                    Text(
                      '$totalCount total listings · Offline item payment',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sellerText(
                        metrics,
                        10.25,
                        color: SellerUiColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _StoreStatusBadge(
                label: badgeLabel,
                foreground: badgeForeground,
                background: badgeBackground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddListingCard extends StatelessWidget {
  const _AddListingCard({
    required this.onTap,
    this.enabled = true,
    this.disabledNote,
  });

  final VoidCallback onTap;
  final bool enabled;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final accent = enabled
        ? SellerUiColors.primaryBright
        : SellerUiColors.muted;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(12),
        vertical: metrics.geometry(10),
      ),
      child: Row(
        children: [
          Container(
            width: metrics.artSize(38),
            height: metrics.artSize(38),
            decoration: const BoxDecoration(
              color: SellerUiColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_rounded,
              size: metrics.artSize(24),
              color: accent,
            ),
          ),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add a product or service',
                  style: sellerText(
                    metrics,
                    12.5,
                    weight: FontWeight.w800,
                    color: enabled
                        ? SellerUiColors.primary
                        : SellerUiColors.muted,
                  ),
                ),
                SizedBox(height: metrics.spacing(2)),
                Text(
                  enabled
                      ? 'Create a listing buyers can discover.'
                      : (disabledNote ??
                            'Adding listings is unavailable until the catalogue '
                                'is configured.'),
                  maxLines: 3,
                  style: sellerText(metrics, 10, color: SellerUiColors.muted),
                ),
              ],
            ),
          ),
          Icon(
            enabled ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
            color: accent,
            size: metrics.artSize(22),
          ),
        ],
      ),
    );
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: enabled ? SellerUiColors.white : const Color(0xfff6f6fb),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: enabled
                  ? SellerUiColors.primaryBright
                  : SellerUiColors.line,
            ),
            borderRadius: BorderRadius.circular(metrics.geometry(12)),
          ),
          child: enabled
              ? InkWell(
                  key: const Key('sellerStoreAddListing'),
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(metrics.geometry(12)),
                  child: content,
                )
              : Padding(
                  key: const Key('sellerStoreAddListingDisabled'),
                  padding: EdgeInsets.zero,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _StoreKindFilters extends StatelessWidget {
  const _StoreKindFilters({required this.selected, required this.onSelected});

  final _StoreKindFilter selected;
  final ValueChanged<_StoreKindFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      children: [
        for (final filter in _StoreKindFilter.values) ...[
          Expanded(
            child: _StoreFilterChip(
              label: switch (filter) {
                _StoreKindFilter.all => 'All',
                _StoreKindFilter.products => 'Products',
                _StoreKindFilter.services => 'Services',
              },
              selected: selected == filter,
              onTap: () => onSelected(filter),
            ),
          ),
          if (filter != _StoreKindFilter.values.last)
            SizedBox(width: metrics.spacing(6)),
        ],
      ],
    );
  }
}

class _StoreFilterChip extends StatelessWidget {
  const _StoreFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Material(
      color: selected ? SellerUiColors.primaryBright : SellerUiColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        side: BorderSide(
          color: selected
              ? SellerUiColors.primaryBright
              : SellerUiColors.lavenderBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: metrics.geometry(8)),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sellerText(
              metrics,
              10.5,
              weight: FontWeight.w800,
              color: selected ? SellerUiColors.white : SellerUiColors.body,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreListingCard extends StatelessWidget {
  const _StoreListingCard({required this.listing, required this.onTap});

  final LocalStoreListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistExpand(
      child: HocalistEntrance(
        child: HocalistPressFeedback(
          child: Material(
            color: SellerUiColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
              side: const BorderSide(color: SellerUiColors.line),
            ),
            child: InkWell(
              key: Key('sellerStoreListing-${listing.id}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
              child: Padding(
                padding: EdgeInsets.all(metrics.geometry(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ListingImage(listing: listing, size: metrics.artSize(72)),
                    SizedBox(width: metrics.spacing(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  listing.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: sellerText(
                                    metrics,
                                    12.5,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(width: metrics.spacing(5)),
                              Icon(
                                Icons.more_vert_rounded,
                                size: metrics.artSize(19),
                                color: SellerUiColors.body,
                              ),
                            ],
                          ),
                          SizedBox(height: metrics.spacing(3)),
                          Text(
                            '${_kindLabel(listing.kind)} · ${listing.category}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sellerText(
                              metrics,
                              9.75,
                              color: SellerUiColors.muted,
                            ),
                          ),
                          SizedBox(height: metrics.spacing(6)),
                          Wrap(
                            spacing: metrics.spacing(6),
                            runSpacing: metrics.spacing(4),
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                listing.priceLabel,
                                style: sellerText(
                                  metrics,
                                  13,
                                  weight: FontWeight.w900,
                                  color: SellerUiColors.primaryBright,
                                ),
                              ),
                              _listingStatusBadge(listing),
                            ],
                          ),
                          SizedBox(height: metrics.spacing(5)),
                          Text(
                            listing.availability,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sellerText(
                              metrics,
                              9.5,
                              color: SellerUiColors.body,
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
      ),
    );
  }
}

class _ListingImage extends StatelessWidget {
  const _ListingImage({required this.listing, required this.size});

  final LocalStoreListing listing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(size * .16),
      ),
      clipBehavior: Clip.antiAlias,
      child: listing.imageMediaIds.isNotEmpty
          ? PrivateRemoteImage(id: listing.imageMediaIds.first, size: size)
          : listing.imageAsset == null
          ? Icon(
              listing.kind == LocalListingKind.product
                  ? Icons.inventory_2_outlined
                  : Icons.design_services_outlined,
              size: size * .38,
              color: SellerUiColors.primaryBright,
            )
          : Image.asset(
              listing.imageAsset!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.image_outlined,
                size: size * .38,
                color: SellerUiColors.primaryBright,
              ),
            ),
    );
  }
}

class _StoreEmptyState extends StatelessWidget {
  const _StoreEmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: EdgeInsets.all(metrics.geometry(18)),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(metrics.geometry(13)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: metrics.artSize(30),
            color: SellerUiColors.primaryBright,
          ),
          SizedBox(height: metrics.spacing(8)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: sellerText(metrics, 13, weight: FontWeight.w800),
          ),
          SizedBox(height: metrics.spacing(3)),
          Text(
            body,
            textAlign: TextAlign.center,
            style: sellerText(
              metrics,
              10.5,
              color: SellerUiColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreIdentityCard extends StatelessWidget {
  const _StoreIdentityCard({this.name, this.realMode = false});

  final String? name;
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final displayName = realMode
        ? (name == null || name!.trim().isEmpty ? 'Your store' : name!.trim())
        : 'Northside Tech';
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          padding: EdgeInsets.all(metrics.geometry(12)),
          decoration: BoxDecoration(
            color: SellerUiColors.lavender,
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
          ),
          child: Row(
            children: [
              if (realMode)
                Container(
                  width: metrics.artSize(44),
                  height: metrics.artSize(44),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: SellerUiColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: sellerText(
                      metrics,
                      14,
                      weight: FontWeight.w800,
                      color: SellerUiColors.primaryBright,
                    ),
                  ),
                )
              else
                CircleAvatar(
                  radius: metrics.artSize(22),
                  backgroundImage: const AssetImage(SellerAssets.homeAvatar),
                ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: sellerText(metrics, 13, weight: FontWeight.w900),
                    ),
                    SizedBox(height: metrics.spacing(2)),
                    Text(
                      realMode
                          ? 'Public store preview'
                          : 'Verified seller · Yonkers, NY',
                      style: sellerText(
                        metrics,
                        10,
                        color: SellerUiColors.muted,
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

class _PublicListingPreview extends StatelessWidget {
  const _PublicListingPreview({required this.listing, this.expanded = false});

  final LocalStoreListing listing;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Container(
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        borderRadius: BorderRadius.circular(metrics.geometry(13)),
        border: Border.all(color: SellerUiColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ListingImage(listing: listing, size: metrics.artSize(68)),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  style: sellerText(metrics, 12.5, weight: FontWeight.w900),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  listing.priceLabel,
                  style: sellerText(
                    metrics,
                    13,
                    weight: FontWeight.w900,
                    color: SellerUiColors.primaryBright,
                  ),
                ),
                SizedBox(height: metrics.spacing(4)),
                Text(
                  listing.description,
                  maxLines: expanded ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: sellerText(
                    metrics,
                    10,
                    color: SellerUiColors.body,
                    height: 1.3,
                  ),
                ),
                if (expanded) ...[
                  SizedBox(height: metrics.spacing(5)),
                  Text(
                    '${listing.serviceArea} · ${listing.availability}',
                    style: sellerText(
                      metrics,
                      9.5,
                      color: SellerUiColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreSheetAction extends StatelessWidget {
  const _StoreSheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = SellerUiColors.ink,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final effectiveColor = enabled ? color : SellerUiColors.muted;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(11),
        vertical: metrics.geometry(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: effectiveColor, size: metrics.artSize(20)),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: sellerText(
                    metrics,
                    12,
                    weight: FontWeight.w800,
                    color: effectiveColor,
                  ),
                ),
                SizedBox(height: metrics.spacing(2)),
                Text(
                  subtitle,
                  style: sellerText(
                    metrics,
                    9.75,
                    color: effectiveColor == SellerUiColors.red
                        ? SellerUiColors.red
                        : SellerUiColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.spacing(6)),
          Icon(
            enabled ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
            color: effectiveColor,
            size: metrics.artSize(20),
          ),
        ],
      ),
    );
    return Material(
      color: enabled ? const Color(0xfff8f8ff) : const Color(0xfff4f4f9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: const BorderSide(color: SellerUiColors.line),
      ),
      child: enabled
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(metrics.geometry(12)),
              child: content,
            )
          : content,
    );
  }
}

class _StoreRadioOption extends StatelessWidget {
  const _StoreRadioOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Material(
      color: selected ? SellerUiColors.lavender : const Color(0xfff8f8ff),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: BorderSide(
          color: selected ? SellerUiColors.primaryBright : SellerUiColors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.geometry(12),
            vertical: metrics.geometry(11),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: sellerText(metrics, 11.5, weight: FontWeight.w700),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: metrics.artSize(20),
                color: selected
                    ? SellerUiColors.primaryBright
                    : SellerUiColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _StoreEditorSave =
    Future<_StoreEditorOutcome> Function(
      LocalStoreListing listing, {
      required String operationKey,
      required bool isRetry,
    });

/// Outcome of one editor save attempt. [ambiguous] means the write may have
/// committed and must be retried with the same key and payload.
class _StoreEditorOutcome {
  const _StoreEditorOutcome({this.error, this.ambiguous = false});

  final String? error;
  final bool ambiguous;
}

class _AddStoreListingSheet extends StatefulWidget {
  const _AddStoreListingSheet({
    required this.initialListing,
    required this.onSave,
    this.storeBacked = false,
    this.categories = const <StoreCategoryOption>[],
    this.onReconcile,
  });

  final LocalStoreListing? initialListing;
  final _StoreEditorSave onSave;
  final bool storeBacked;
  final List<StoreCategoryOption> categories;
  final VoidCallback? onReconcile;

  @override
  State<_AddStoreListingSheet> createState() => _AddStoreListingSheetState();
}

enum _ListingEditorStage { chooseType, details, preview }

class _AddStoreListingSheetState extends State<_AddStoreListingSheet> {
  late _ListingEditorStage _stage;
  LocalListingKind? _kind;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _areaController;
  late final TextEditingController _availabilityController;
  int _imageCount = 0;
  final _existingImageIds = <String>[];
  List<String> _newImageIds = [];
  String? _error;
  String? _saveError;
  bool _saving = false;
  bool _imagePending = false;
  bool _ambiguous = false;
  LocalStoreListing? _pendingListing;
  String? _operationKey;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialListing;
    _stage = initial == null
        ? _ListingEditorStage.chooseType
        : _ListingEditorStage.details;
    _kind = initial?.kind;
    _titleController = TextEditingController(text: initial?.title);
    _descriptionController = TextEditingController(text: initial?.description);
    _categoryController = TextEditingController(text: initial?.category);
    _priceController = TextEditingController(text: initial?.priceLabel);
    _areaController = TextEditingController(text: initial?.serviceArea);
    _availabilityController = TextEditingController(
      text: initial?.availability,
    );
    _imageCount = initial?.imageCount ?? 0;
    _existingImageIds.addAll(initial?.imageMediaIds ?? const []);
    _categoryId = initial?.categoryId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _areaController.dispose();
    _availabilityController.dispose();
    super.dispose();
  }

  LocalStoreListing _buildListing(LocalListingStatus status) {
    final initial = widget.initialListing;
    return LocalStoreListing(
      id: initial?.id ?? '',
      kind: _kind!,
      title: _titleController.text.trim(),
      priceLabel: _priceController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _categoryLabel ?? _categoryController.text.trim(),
      categoryId: _categoryId,
      revision: initial?.revision ?? 0,
      pendingReview: initial?.pendingReview ?? false,
      serviceArea: _areaController.text.trim(),
      availability: _availabilityController.text.trim(),
      status: status,
      imageAsset: initial?.imageAsset,
      imageCount: widget.storeBacked
          ? _existingImageIds.length + _newImageIds.length
          : _imageCount,
      imageMediaIds: List.unmodifiable([..._existingImageIds, ..._newImageIds]),
    );
  }

  List<StoreCategoryOption> get _activeCategories {
    final kind = _kind;
    final scope = kind == LocalListingKind.product
        ? 'product'
        : kind == LocalListingKind.service
        ? 'service'
        : null;
    return widget.categories
        .where(
          (category) =>
              category.isActive &&
              (scope == null ||
                  category.scope == 'both' ||
                  category.scope == scope),
        )
        .toList(growable: false);
  }

  String? get _categoryLabel {
    final id = _categoryId;
    if (id == null) return null;
    for (final category in widget.categories) {
      if (category.id == id) return category.label;
    }
    return widget.initialListing?.category;
  }

  bool _validateDetails() {
    final active = _activeCategories;
    final categoryMissing = widget.storeBacked
        ? _categoryId == null || !active.any((entry) => entry.id == _categoryId)
        : _categoryController.text.trim().isEmpty;
    if (_titleController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty ||
        categoryMissing) {
      setState(() {
        _error = widget.storeBacked
            ? 'Add a title and price, and choose an active category.'
            : 'Add a title, category, and price before continuing.';
      });
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  /// Saves through the repository and only reports success after the
  /// authoritative result. On an ambiguous outcome the sheet keeps the same
  /// operation key and payload for a safe retry.
  Future<void> _submit(LocalListingStatus status) async {
    if (_saving || _imagePending) return;
    if (_ambiguous) {
      final pending = _pendingListing;
      if (pending == null) return;
      setState(() {
        _saving = true;
        _saveError = null;
      });
      final outcome = await widget.onSave(
        pending,
        operationKey: _operationKey!,
        isRetry: true,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (outcome.error != null) {
          _saveError = outcome.error;
          _ambiguous = outcome.ambiguous;
        } else {
          _ambiguous = false;
          _pendingListing = null;
        }
      });
      if (outcome.error == null) Navigator.of(context).pop();
      return;
    }
    if (!_validateDetails()) return;
    final listing = _buildListing(status);
    _operationKey ??= LocalMarketplaceRepository.newStoreOperationKey(
      'store-save',
    );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final outcome = await widget.onSave(
      listing,
      operationKey: _operationKey!,
      isRetry: false,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (outcome.error != null) {
        _saveError = outcome.error;
        if (outcome.ambiguous) {
          _ambiguous = true;
          _pendingListing = listing;
        }
      }
    });
    if (outcome.error == null) Navigator.of(context).pop();
  }

  void _discardPending() {
    setState(() {
      _ambiguous = false;
      _pendingListing = null;
      _saveError = null;
      _operationKey = null;
    });
    widget.onReconcile?.call();
  }

  /// Save failure and ambiguous-retry feedback, shared by both editor stages so
  /// a failure from the preview step is never silent.
  List<Widget> _saveFeedback(ApprovedReplicaMetrics metrics) {
    return [
      if (_saveError != null) ...[
        SizedBox(height: metrics.spacing(8)),
        Text(
          _saveError!,
          key: const Key('sellerStoreSaveError'),
          style: sellerText(
            metrics,
            10,
            weight: FontWeight.w700,
            color: SellerUiColors.red,
          ),
        ),
      ],
      if (_ambiguous) ...[
        SizedBox(height: metrics.spacing(8)),
        _StorePendingNotice(
          onRetry: () =>
              _submit(_pendingListing?.status ?? LocalListingStatus.draft),
          onDiscard: _discardPending,
        ),
      ],
    ];
  }

  Future<void> _pickImages() async {
    final count = await showModalBottomSheet<int>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.add_a_photo_outlined,
        title: 'Add listing images',
        subtitle: 'Choose how you want to add photos to this listing.',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          children: [
            _StoreSheetAction(
              key: const Key('sellerStoreTakePhoto'),
              icon: Icons.photo_camera_outlined,
              title: 'Take a photo',
              subtitle: 'Camera access connects with the mobile platform.',
              onTap: () => Navigator.of(sheetContext).pop(1),
            ),
            const SizedBox(height: 8),
            _StoreSheetAction(
              key: const Key('sellerStoreChooseLibrary'),
              icon: Icons.photo_library_outlined,
              title: 'Choose from library',
              subtitle: 'Select clear photos of the product or service.',
              onTap: () => Navigator.of(sheetContext).pop(3),
            ),
          ],
        ),
      ),
    );
    if (count != null && mounted) {
      setState(() => _imageCount = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SellerModalSheet(
      icon: _kind == LocalListingKind.service
          ? Icons.design_services_outlined
          : Icons.inventory_2_outlined,
      title: widget.initialListing == null ? 'Add listing' : 'Edit listing',
      subtitle: switch (_stage) {
        _ListingEditorStage.chooseType =>
          'Choose what you want buyers to discover.',
        _ListingEditorStage.details =>
          'Add clear details, pricing, images, and availability.',
        _ListingEditorStage.preview =>
          'Review the buyer-facing listing before saving it.',
      },
      onClose: () => Navigator.of(context).pop(),
      child: switch (_stage) {
        _ListingEditorStage.chooseType => _buildTypeChooser(),
        _ListingEditorStage.details => _buildDetails(),
        _ListingEditorStage.preview => _buildPreview(),
      },
    );
  }

  Widget _buildTypeChooser() {
    return Column(
      children: [
        _ListingTypeCard(
          key: const Key('sellerStoreChooseProduct'),
          icon: Icons.inventory_2_outlined,
          title: 'Product',
          body: 'List an item with its condition, price, and availability.',
          onTap: () => setState(() {
            _kind = LocalListingKind.product;
            _stage = _ListingEditorStage.details;
          }),
        ),
        const SizedBox(height: 10),
        _ListingTypeCard(
          key: const Key('sellerStoreChooseService'),
          icon: Icons.design_services_outlined,
          title: 'Service',
          body: 'List a service with its coverage area, pricing, and schedule.',
          onTap: () => setState(() {
            _kind = LocalListingKind.service;
            _stage = _ListingEditorStage.details;
          }),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StoreFormField(
          fieldKey: const Key('sellerStoreTitleField'),
          label: '${_kindLabel(_kind!)} title',
          hintText: _kind == LocalListingKind.product
              ? 'What product are you offering?'
              : 'What service do you provide?',
          controller: _titleController,
        ),
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          label: 'Description',
          hintText: 'Share the important details buyers should know.',
          controller: _descriptionController,
          minLines: 3,
          maxLines: 5,
        ),
        SizedBox(height: metrics.spacing(10)),
        if (widget.storeBacked)
          _StoreCategoryPicker(
            categories: _activeCategories,
            value:
                _categoryId != null &&
                    _activeCategories.any((entry) => entry.id == _categoryId)
                ? _categoryId
                : null,
            currentLabel: _categoryLabel,
            onSelected: (id) => setState(() => _categoryId = id),
          )
        else
          _StoreFormField(
            label: 'Category',
            hintText: 'Enter the closest category',
            controller: _categoryController,
            fieldKey: const Key('sellerStoreCategoryField'),
          ),
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          fieldKey: const Key('sellerStorePriceField'),
          label: 'Pricing',
          hintText: r'Example: $650, From $50, or Quote required',
          controller: _priceController,
        ),
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          label: _kind == LocalListingKind.product
              ? 'Pickup or service area'
              : 'Service area',
          hintText: 'Where is this available?',
          controller: _areaController,
        ),
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          label: 'Availability',
          hintText: 'Example: Available today or Weekdays',
          controller: _availabilityController,
        ),
        SizedBox(height: metrics.spacing(10)),
        if (widget.storeBacked) ...[
          Wrap(
            spacing: 8,
            children: _existingImageIds
                .map(
                  (id) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrivateRemoteImage(id: id),
                      SizedBox(
                        width: 120,
                        child: SellerSecondaryButton(
                          compact: true,
                          label: 'Remove',
                          onPressed: _saving || _imagePending || _ambiguous
                              ? null
                              : () => setState(
                                  () => _existingImageIds.remove(id),
                                ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
          if (configuredImageUpload('store') case final upload?)
            PrivateImagePicker(
              upload: upload,
              maxImages: 10 - _existingImageIds.length,
              onPendingChanged: (value) =>
                  setState(() => _imagePending = value),
              enabled: !_saving && !_ambiguous,
              onChanged: (ids) => setState(() => _newImageIds = ids),
            ),
        ] else
          OutlinedButton.icon(
            key: const Key('sellerStoreAddImages'),
            onPressed: _pickImages,
            icon: Icon(
              _imageCount == 0
                  ? Icons.add_a_photo_outlined
                  : Icons.check_circle_outline_rounded,
              size: metrics.artSize(19),
            ),
            label: Text(
              _imageCount == 0
                  ? 'Add listing images'
                  : '$_imageCount ${_imageCount == 1 ? 'image' : 'images'} added',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: Size.fromHeight(metrics.geometry(44)),
              foregroundColor: SellerUiColors.primaryBright,
              side: const BorderSide(color: SellerUiColors.lavenderBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(13)),
              ),
              textStyle:
                  (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
                      .copyWith(
                        fontSize: metrics.fontSize(12.5),
                        fontWeight: FontWeight.w600,
                      ),
            ),
          ),
        if (_error != null) ...[
          SizedBox(height: metrics.spacing(8)),
          Text(
            _error!,
            key: const Key('sellerStoreEditorError'),
            style: sellerText(
              metrics,
              10,
              weight: FontWeight.w700,
              color: SellerUiColors.red,
            ),
          ),
        ],
        ..._saveFeedback(metrics),
        SizedBox(height: metrics.spacing(14)),
        LayoutBuilder(
          builder: (context, constraints) {
            final draft = SellerSecondaryButton(
              label: _saving ? 'Saving…' : 'Save draft',
              onPressed: _saving || _imagePending || _ambiguous
                  ? null
                  : () => _submit(LocalListingStatus.draft),
            );
            final preview = SellerPrimaryButton(
              label: 'Preview listing',
              onPressed: _saving || _imagePending || _ambiguous
                  ? null
                  : () {
                      if (!_validateDetails()) return;
                      setState(() => _stage = _ListingEditorStage.preview);
                    },
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preview, const SizedBox(height: 8), draft],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final listing = _buildListing(
      widget.initialListing?.status == LocalListingStatus.paused
          ? LocalListingStatus.paused
          : LocalListingStatus.active,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PublicListingPreview(listing: listing, expanded: true),
        SizedBox(height: metrics.spacing(10)),
        Container(
          padding: EdgeInsets.all(metrics.geometry(10)),
          decoration: BoxDecoration(
            color: SellerUiColors.amberSurface,
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: metrics.artSize(18),
                color: SellerUiColors.amber,
              ),
              SizedBox(width: metrics.spacing(8)),
              Expanded(
                child: Text(
                  widget.storeBacked
                      ? 'Hocalist helps buyers discover and contact sellers. Item payment remains offline, and new or edited listings are reviewed before appearing in discovery.'
                      : 'Hocalist helps buyers discover and contact sellers. Item payment remains offline.',
                  style: sellerText(
                    metrics,
                    10,
                    color: SellerUiColors.body,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._saveFeedback(metrics),
        SizedBox(height: metrics.spacing(14)),
        SellerPrimaryButton(
          key: const Key('sellerStorePublishListing'),
          label: _saving
              ? 'Saving…'
              : _ambiguous
              ? 'Retry save'
              : widget.initialListing == null
              ? 'Publish listing'
              : 'Save changes',
          onPressed: _saving || _imagePending
              ? null
              : () => _submit(listing.status),
        ),
        SizedBox(height: metrics.spacing(8)),
        SellerSecondaryButton(
          label: 'Back to edit',
          onPressed: () => setState(() => _stage = _ListingEditorStage.details),
        ),
      ],
    );
  }
}

class _ListingTypeCard extends StatelessWidget {
  const _ListingTypeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: const Color(0xfff8f8ff),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
            side: const BorderSide(color: SellerUiColors.lavenderBorder),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
            child: Padding(
              padding: EdgeInsets.all(metrics.geometry(13)),
              child: Row(
                children: [
                  Container(
                    width: metrics.artSize(42),
                    height: metrics.artSize(42),
                    decoration: const BoxDecoration(
                      color: SellerUiColors.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: metrics.artSize(22),
                      color: SellerUiColors.primaryBright,
                    ),
                  ),
                  SizedBox(width: metrics.spacing(11)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: sellerText(
                            metrics,
                            13,
                            weight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: metrics.spacing(3)),
                        Text(
                          body,
                          style: sellerText(
                            metrics,
                            10,
                            color: SellerUiColors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: metrics.artSize(21),
                    color: SellerUiColors.primaryBright,
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

class _StoreFormField extends StatelessWidget {
  const _StoreFormField({
    required this.label,
    required this.hintText,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
    this.fieldKey,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final Key? fieldKey;

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
            9.75,
            weight: FontWeight.w800,
            color: SellerUiColors.muted,
            letterSpacing: .6,
          ),
        ),
        SizedBox(height: metrics.spacing(4)),
        TextField(
          key: fieldKey,
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          style: sellerInputText(metrics, size: 12),
          decoration: _storeInputDecoration(metrics, hintText: hintText),
        ),
      ],
    );
  }
}

InputDecoration _storeInputDecoration(
  ApprovedReplicaMetrics metrics, {
  required String hintText,
  IconData? prefixIcon,
}) {
  final radius = metrics.geometry(11);
  return InputDecoration(
    hintText: hintText,
    hintStyle: sellerInputPlaceholder(metrics, size: 11.5),
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: metrics.artSize(19)),
    prefixIconColor: SellerUiColors.body,
    filled: true,
    fillColor: const Color(0xfff9f9ff),
    isDense: true,
    constraints: const BoxConstraints(minHeight: 48),
    contentPadding: EdgeInsets.symmetric(
      horizontal: metrics.geometry(11),
      vertical: metrics.geometry(12),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: SellerUiColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: SellerUiColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(
        color: SellerUiColors.primaryBright,
        width: 1.4,
      ),
    ),
  );
}

_StoreStatusBadge _listingStatusBadge(LocalStoreListing listing) {
  if (listing.pendingSync) {
    return const _StoreStatusBadge(
      label: 'Saving…',
      foreground: SellerUiColors.primary,
      background: SellerUiColors.lavender,
    );
  }
  if (listing.status == LocalListingStatus.active && listing.pendingReview) {
    return const _StoreStatusBadge(
      label: 'In review',
      foreground: SellerUiColors.amber,
      background: SellerUiColors.amberSurface,
    );
  }
  return switch (listing.status) {
    LocalListingStatus.active => const _StoreStatusBadge(
      label: 'Active',
      foreground: SellerUiColors.green,
      background: SellerUiColors.greenSurface,
    ),
    LocalListingStatus.draft => const _StoreStatusBadge(
      label: 'Draft',
      foreground: SellerUiColors.body,
      background: SellerUiColors.lavender,
    ),
    LocalListingStatus.paused => const _StoreStatusBadge(
      label: 'Paused',
      foreground: SellerUiColors.amber,
      background: SellerUiColors.amberSurface,
    ),
  };
}

class _StoreStatusBadge extends StatelessWidget {
  const _StoreStatusBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

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
        horizontal: metrics.geometry(7),
        vertical: metrics.geometry(3),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: sellerText(
          metrics,
          8.75,
          weight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

String _kindLabel(LocalListingKind kind) => switch (kind) {
  LocalListingKind.product => 'Product',
  LocalListingKind.service => 'Service',
};

String _statusLabel(_StoreStatusFilter status) => switch (status) {
  _StoreStatusFilter.all => 'All',
  _StoreStatusFilter.active => 'Active',
  _StoreStatusFilter.draft => 'Draft',
  _StoreStatusFilter.paused => 'Paused',
};

class _StoreErrorNotice extends StatelessWidget {
  const _StoreErrorNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SellerStateNotice(
      key: const Key('sellerStoreError'),
      icon: Icons.error_outline_rounded,
      tone: SellerNoticeTone.error,
      title: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}

class _StoreCategoryPicker extends StatelessWidget {
  const _StoreCategoryPicker({
    required this.categories,
    required this.value,
    required this.currentLabel,
    required this.onSelected,
  });

  final List<StoreCategoryOption> categories;
  final String? value;
  final String? currentLabel;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    if (categories.isEmpty) {
      return Container(
        key: const Key('sellerStoreNoCategories'),
        padding: EdgeInsets.all(metrics.geometry(10)),
        decoration: BoxDecoration(
          color: SellerUiColors.amberSurface,
          borderRadius: BorderRadius.circular(metrics.geometry(11)),
        ),
        child: Text(
          'No active categories are available yet. An administrator manages the catalogue.',
          style: sellerText(
            metrics,
            10,
            color: SellerUiColors.body,
            height: 1.35,
          ),
        ),
      );
    }
    String labelFor(String id) {
      if (id.isEmpty) return 'Choose a category';
      for (final category in categories) {
        if (category.id == id) return category.label;
      }
      return id;
    }

    final retiredNotice =
        value == null && currentLabel != null && currentLabel!.isNotEmpty
        ? 'The current category ($currentLabel) is no longer offered. '
              'Choose an active category to save changes.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: sellerText(
            metrics,
            10.5,
            weight: FontWeight.w800,
            color: SellerUiColors.body,
          ),
        ),
        SizedBox(height: metrics.spacing(5)),
        HocalistSelectMenu<String>(
          key: const Key('sellerStoreCategoryPicker'),
          role: HocalistControlRole.seller,
          value: value ?? '',
          options: <String>['', ...categories.map((category) => category.id)],
          labelBuilder: labelFor,
          selectedLabelBuilder: labelFor,
          onSelected: (id) => onSelected(id.isEmpty ? null : id),
          leading: Icons.grid_view_outlined,
          expanded: true,
        ),
        if (retiredNotice != null) ...[
          SizedBox(height: metrics.spacing(5)),
          Text(
            retiredNotice,
            key: const Key('sellerStoreRetiredCategory'),
            style: sellerText(
              metrics,
              9.5,
              color: SellerUiColors.amber,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _StorePendingNotice extends StatelessWidget {
  const _StorePendingNotice({required this.onRetry, required this.onDiscard});

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Container(
      key: const Key('sellerStorePendingNotice'),
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: SellerUiColors.amberSurface,
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        border: Border.all(color: SellerUiColors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We could not confirm the previous save. Retry to check it safely, '
            'or discard it and refresh.',
            style: sellerText(
              metrics,
              10,
              color: SellerUiColors.body,
              height: 1.35,
            ),
          ),
          SizedBox(height: metrics.spacing(4)),
          Row(
            children: [
              Expanded(
                child: SellerSecondaryButton(
                  key: const Key('sellerStoreRetrySave'),
                  compact: true,
                  label: 'Retry save',
                  onPressed: onRetry,
                ),
              ),
              SizedBox(width: metrics.spacing(8)),
              Expanded(
                child: SellerSecondaryButton(
                  key: const Key('sellerStoreDiscardPending'),
                  compact: true,
                  label: 'Discard pending change',
                  onPressed: onDiscard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
