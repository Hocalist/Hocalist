import '../../domain/phase2/category_answers.dart';
import '../approved/category_question_editor.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import '../../components/pull_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_marketplace_repository.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../data/phase2/media/image_gateway.dart';
import '../media/private_image_picker.dart';
import '../media/private_remote_image.dart';
import '../approved/place_capture_sheet.dart';
import '../../data/phase2/maps/places_composition.dart';
import '../../data/phase2/maps/device_location.dart';
import '../../domain/phase2/commercial/commercial.dart';
import 'approved_seller_leads_page.dart' show SellerLeadView;

enum _StoreKindFilter { all, products, services }

enum _StoreStatusFilter { all, active, inReview, notApproved, draft, paused, archived }

_StoreStatusFilter _listingGroup(LocalStoreListing item) {
  if (item.status == LocalListingStatus.archived) return _StoreStatusFilter.archived;
  if (item.rejected) return _StoreStatusFilter.notApproved;
  if (item.status == LocalListingStatus.active && item.pendingReview) return _StoreStatusFilter.inReview;
  return switch (item.status) {
    LocalListingStatus.active => _StoreStatusFilter.active,
    LocalListingStatus.draft => _StoreStatusFilter.draft,
    LocalListingStatus.paused => _StoreStatusFilter.paused,
    LocalListingStatus.archived => _StoreStatusFilter.archived,
  };
}

class ApprovedSellerStorePage extends StatefulWidget {
  const ApprovedSellerStorePage({
    required this.repository,
    required this.onStoreSettings,
    this.sellerName,
    this.sellerProfileId,
    this.loadPublicProfile,
    this.loadEntitlement,
    this.loadMatchingRequests,
    this.onOpenMatchingRequest,
    this.imageUpload,
    this.hocatrendsControl,
    this.questionLoader = loadCategoryQuestions,
    super.key,
  });

  final LocalMarketplaceRepository repository;
  final VoidCallback onStoreSettings;

  /// Authoritative seller display name for the real public preview.
  final String? sellerName;
  final String? sellerProfileId;
  final Future<Map<String, dynamic>> Function()? loadPublicProfile;
  final Future<SellerEntitlementView?> Function()? loadEntitlement;
  final Future<List<SellerLeadView>> Function(LocalStoreListing listing)?
      loadMatchingRequests;
  final ValueChanged<SellerLeadView>? onOpenMatchingRequest;
  final ImageUpload? imageUpload;
  final Widget Function(String listingId)? hocatrendsControl;
  final CategoryQuestionLoader questionLoader;

  @override
  State<ApprovedSellerStorePage> createState() =>
      _ApprovedSellerStorePageState();
}

class _ApprovedSellerStorePageState extends State<ApprovedSellerStorePage> {
  final TextEditingController _searchController = TextEditingController();
  _StoreKindFilter _kindFilter = _StoreKindFilter.all;
  _StoreStatusFilter _statusFilter = _StoreStatusFilter.all;
  String _query = '';
  Future<Map<String, dynamic>>? _publicProfile;
  Future<SellerEntitlementView?>? _entitlement;

  @override
  void initState() {
    super.initState();
    _publicProfile = widget.loadPublicProfile?.call();
    _entitlement = widget.loadEntitlement?.call();
  }

  void _refreshEntitlement() {
    if (widget.loadEntitlement != null) {
      setState(() => _entitlement = widget.loadEntitlement!());
    }
  }

  Future<void> _refreshPresentation() async {
    setState(() => _publicProfile = widget.loadPublicProfile?.call());
    _refreshEntitlement();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LocalStoreListing> _matchingSearchAndKind(List<LocalStoreListing> listings) {
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
          final queryMatches =
              query.isEmpty ||
              listing.title.toLowerCase().contains(query) ||
              listing.category.toLowerCase().contains(query) ||
              listing.description.toLowerCase().contains(query);
          return kindMatches && queryMatches;
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
        imageUpload: widget.imageUpload,
        initialListing: listing,
        storeBacked: widget.repository.isStoreBacked,
        questionLoader: widget.questionLoader,
        categories: widget.repository.storeCategories,
        onReconcile: () => widget.repository.refreshStore(),
        onSave: (saved, {required operationKey, required isRetry}) async {
          try {
            final result = await widget.repository.saveStoreListing(
              saved,
              operationKey: operationKey,
            );
            if (!mounted) return const _StoreEditorOutcome();
            _refreshEntitlement();
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
    if (saved.rejected) {
      return 'Listing saved. It is not approved for publication.';
    }
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
              key: const Key('sellerStoreArchivedAction'),
              icon: Icons.archive_outlined,
              title: 'Archived listings',
              subtitle: 'Restore a saved listing to a private draft.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() { _statusFilter = _StoreStatusFilter.archived; _kindFilter = _StoreKindFilter.all; _query = ''; _searchController.clear(); });
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
                        (l) => l.isPubliclyVisible && !l.pendingSync,
                      )
                  ? 'Copy a link to your published Store. Drafts stay private.'
                  : 'Publish an approved listing before sharing your Store.',
              enabled:
                  widget.sellerProfileId != null &&
                  widget.repository.storeListings.any(
                    (l) => l.isPubliclyVisible && !l.pendingSync,
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
        .where((listing) => listing.isPubliclyVisible && !listing.pendingSync)
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
            _storeIdentity(publicPreview: true),
            const SizedBox(height: 12),
            if (active.isEmpty)
              const _StoreEmptyState(
                title: 'No live listings yet',
                body: 'Approved, published listings will appear here.',
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

  Widget _storeIdentity({bool publicPreview = false}) =>
      FutureBuilder<Map<String, dynamic>>(
        future: _publicProfile,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return _StoreIdentityCard(
            name: _publicText(data, 'display_name') ?? widget.sellerName,
            avatarId: _publicText(data, 'avatar_media_id'),
            area: _publicText(data, 'area_label'),
            phone: publicPreview ? _publicText(data, 'phone') : null,
            email: publicPreview ? _publicText(data, 'email') : null,
            publicPreview: publicPreview,
            onEdit: publicPreview ? null : widget.onStoreSettings,
          );
        },
      );

  String? _publicText(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    if (data?['available'] != true || value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _showFilters() async {
    var status = _statusFilter;
    var kind = _kindFilter;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SellerModalSheet(
          icon: Icons.filter_alt_outlined,
          title: 'Filter listings',
          subtitle: 'Narrow your listings by type and status.',
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Listing type'),
              const SizedBox(height: 8),
              for (final option in _StoreKindFilter.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StoreRadioOption(
                    label: _kindFilterLabel(option),
                    selected: kind == option,
                    onTap: () => setSheetState(() => kind = option),
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Status'),
              const SizedBox(height: 8),
              for (final option in _StoreStatusFilter.values) ...[
                _StoreRadioOption(
                  label: _statusLabel(option),
                  selected: status == option,
                  onTap: () => setSheetState(() => status = option),
                ),
                if (option != _StoreStatusFilter.values.last)
                  const SizedBox(height: 8),
              ],
              const SizedBox(height: 14),
              SellerPrimaryButton(
                label: 'Apply filters',
                onPressed: () {
                  setState(() {
                    _statusFilter = status;
                    _kindFilter = kind;
                  });
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
    if (listing.status == LocalListingStatus.archived) {
      final key = LocalMarketplaceRepository.newStoreOperationKey('store-restore');
      var busy = false;
      String? error;
      await showModalBottomSheet<void>(context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(builder: (context, update) => SellerModalSheet(
          icon: Icons.restore_rounded, title: listing.title,
          subtitle: 'Restore this listing as a private draft. Review it before publishing again.',
          onClose: () { if (!busy) Navigator.of(sheetContext).pop(); },
          child: Column(children: [
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!)),
            SellerPrimaryButton(label: busy ? 'Restoring…' : 'Restore to draft',
              onPressed: busy ? null : () async {
                update(() { busy = true; error = null; });
                try {
                  await widget.repository.updateStoreListingStatus(listing.id, LocalListingStatus.draft, operationKey: key);
                  if (!mounted || !sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  setState(() => _statusFilter = _StoreStatusFilter.draft);
                  _showMessage('Restored to drafts. Review it before publishing.');
                } on StoreBackendException catch (e) {
                  if (sheetContext.mounted) update(() { busy = false; error = e.message; });
                }
              }),
          ]),
        )),
      );
      return;
    }
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
            if (widget.hocatrendsControl case final control?) ...[
              control(listing.id),
              const SizedBox(height: 8),
            ],
            _StoreSheetAction(
              key: const Key('sellerStoreEditListing'),
              icon: Icons.edit_outlined,
              title: listing.rejected ? 'Edit and resubmit' : 'Edit listing',
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
                  : widget.repository.isStoreBacked && listing.pendingReview
                  ? 'Submit for review' : 'Publish listing',
              subtitle: listing.rejected
                  ? 'Not approved. Update the listing before submitting it again.'
                  : listing.pendingReview && listing.status == LocalListingStatus.active
                  ? 'It is not visible to buyers while it awaits review.'
                  : listing.status == LocalListingStatus.active
                  ? 'Hide it from buyer discovery without deleting it.'
                  : widget.repository.isStoreBacked
                  ? 'Make it available for discovery after approval.'
                  : 'Make it visible to buyers in discovery.',
              enabled: !listing.rejected &&
                  !(listing.pendingReview && listing.status == LocalListingStatus.active),
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
                  _refreshEntitlement();
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

  Future<void> _showMatchingRequests(LocalStoreListing listing) async {
    final category = listing.categoryId;
    final load = widget.loadMatchingRequests;
    final open = widget.onOpenMatchingRequest;
    if (category == null || load == null || open == null) return;
    final results = load(listing);
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => SellerModalSheet(
        icon: Icons.manage_search,
        title: 'Matching requests',
        subtitle: 'Requests in ${listing.category} for your ${_kindLabel(listing.kind).toLowerCase()} listing.',
        onClose: () => Navigator.of(sheet).pop(),
        child: FutureBuilder<List<SellerLeadView>>(
          future: results,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SellerProgressStrip(label: 'Finding matching requests…');
            }
            if (snapshot.hasError) {
              return const Text('Matching requests could not be loaded. Close this panel and try again.');
            }
            final leads = snapshot.data ?? const [];
            if (leads.isEmpty) return const Text('No open buyer requests match this category right now.');
            return Column(
              children: [
                for (final lead in leads)
                  _StoreSheetAction(
                    icon: Icons.search,
                    title: lead.request,
                    subtitle: '${lead.city} · ${lead.budget}',
                    onTap: () {
                      Navigator.of(sheet).pop();
                      open(lead);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showListingHocatrends(LocalStoreListing listing) {
    final control = widget.hocatrendsControl;
    if (control == null) return;
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => SellerModalSheet(
        icon: Icons.trending_up,
        title: 'Hocatrends visibility',
        subtitle: listing.title,
        onClose: () => Navigator.of(sheet).pop(),
        child: control(listing.id),
      ),
    );
  }

  Widget? _listingShortcuts(LocalStoreListing listing) {
    if (listing.rejected && listing.status != LocalListingStatus.archived) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This listing is private. Update its details before sending it back for review.'),
          TextButton(
            onPressed: () => _openListingEditor(listing),
            child: const Text('Edit and resubmit'),
          ),
        ],
      );
    }
    if (!listing.isPubliclyVisible || listing.pendingSync ||
        (widget.loadMatchingRequests == null && widget.hocatrendsControl == null)) {
      return null;
    }
    return FutureBuilder<SellerEntitlementView?>(
      future: _entitlement,
      builder: (context, snapshot) {
        final plan = snapshot.data?.effectivePlan;
        if (plan != PlanCode.pro && plan != PlanCode.elite) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          children: [
            if (listing.categoryId != null &&
                widget.loadMatchingRequests != null &&
                widget.onOpenMatchingRequest != null)
              TextButton(
                onPressed: () => _showMatchingRequests(listing),
                child: const Text('Find matching requests'),
              ),
            if (widget.hocatrendsControl != null)
              TextButton(
                onPressed: () => _showListingHocatrends(listing),
                child: const Text('Show in Hocatrends'),
              ),
          ],
        );
      },
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
                  _refreshEntitlement();
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
    return PullRefreshAction(
      onRefresh: _refreshPresentation,
      child: _buildStorePage(),
    );
  }

  Widget _buildStorePage() => SellerResponsivePage(
      builder: (context, metrics) => SizedBox.expand(
        child: AnimatedBuilder(
          animation: widget.repository,
          builder: (context, _) {
            final inventory = [...widget.repository.storeListings, ...widget.repository.archivedStoreListings];
            final matching = _matchingSearchAndKind(inventory);
            final listings = _statusFilter == _StoreStatusFilter.all
                ? matching
                : matching.where((item) => _listingGroup(item) == _statusFilter).toList();
            final activeCount = widget.repository.storeListings
                .where((listing) => listing.isPubliclyVisible && !listing.pendingSync)
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
                        color: HocalistPalette.text(
                          context,
                          SellerUiColors.ink,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: HocalistPalette.surface(
                            context,
                            SellerUiColors.lavender,
                          ),
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
                  _storeIdentity(),
                  SizedBox(height: metrics.spacing(8)),
                  SellerSecondaryButton(
                    key: const Key('sellerStorePublicPreview'),
                    label: 'Preview public store',
                    onPressed: _showPublicStorePreview,
                  ),
                  if (inventory.isNotEmpty) ...[
                    SizedBox(height: metrics.spacing(12)),
                    FutureBuilder<SellerEntitlementView?>(
                      future: _entitlement,
                      builder: (context, snapshot) => _StoreSummaryCard(
                        activeCount: activeCount,
                        totalCount: inventory.length,
                        entitlement: snapshot.data,
                      ),
                    ),
                  ],
                  SizedBox(height: metrics.spacing(12)),
                  _AddListingCard(
                    onTap: _openListingEditor,
                    firstListing: inventory.isEmpty,
                    enabled: catalogueReady,
                    disabledNote:
                        'Adding listings is unavailable until an administrator '
                        'configures at least one active Store category.',
                  ),
                  if (inventory.isNotEmpty || _statusFilter != _StoreStatusFilter.all) ...[
                  SizedBox(height: metrics.spacing(14)),
                  SizedBox(
                    height: 48 + (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, double.infinity),
                    child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TextField(
                          expands: true,
                          inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
                          minLines: null,
                          maxLines: null,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          textAlignVertical: TextAlignVertical.center,
                          key: const Key('sellerStoreSearch'),
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          style: sellerInputText(metrics),
                          decoration: _storeInputDecoration(
                            context,
                            metrics,
                            hintText: 'Search your listings',
                            prefixIcon: Icons.search_rounded,
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.spacing(8)),
                      SizedBox(
                        width: 48,
                        child: OutlinedButton(
                          key: const Key('sellerStoreFilter'),
                          onPressed: _showFilters,
                          style: OutlinedButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(48, 48),
                            padding: EdgeInsets.zero,
                            foregroundColor: HocalistPalette.text(
                              context,
                              SellerUiColors.primaryBright,
                            ),
                            side: BorderSide(
                              color: HocalistPalette.border(
                                context,
                                SellerUiColors.lavenderBorder,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                metrics.geometry(11),
                              ),
                            ),
                          ),
                          child: Badge(
                            isLabelVisible:
                              _statusFilter != _StoreStatusFilter.all ||
                              _kindFilter != _StoreKindFilter.all,
                            smallSize: metrics.geometry(7),
                            child: Icon(
                              Icons.filter_alt_outlined,
                              semanticLabel: 'Filter listings',
                              size: metrics.artSize(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                  SizedBox(height: metrics.spacing(13)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (_statusFilter) {
                            _StoreStatusFilter.all => 'Your listings',
                            _StoreStatusFilter.inReview => 'Listings in review',
                            _StoreStatusFilter.notApproved => 'Listings needing changes',
                            _ => '${_statusLabel(_statusFilter)} listings',
                          },
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
                      title: _statusFilter == _StoreStatusFilter.archived
                          ? 'No archived listings' : 'No listings found',
                      body: _statusFilter == _StoreStatusFilter.archived
                          ? 'Listings you archive will appear here.' : _query.isEmpty
                          ? 'Change the filter to see other listings.'
                          : 'Try another search term or clear your filters.',
                    )
                  else
                    for (final listing in listings) ...[
                      _StoreListingCard(
                        listing: listing,
                        onTap: () => _showListingActions(listing),
                        shortcuts: _listingShortcuts(listing),
                      ),
                      SizedBox(height: metrics.spacing(9)),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
  );
}

class _StoreSummaryCard extends StatelessWidget {
  const _StoreSummaryCard({
    required this.activeCount,
    required this.totalCount,
    this.entitlement,
  });

  final int activeCount;
  final int totalCount;
  final SellerEntitlementView? entitlement;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final usage = entitlement?.storeListing;
    final plan = switch (entitlement?.effectivePlan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro Seller',
      PlanCode.elite => 'Elite Seller',
      null => null,
    };
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
            color: HocalistPalette.surface(context, SellerUiColors.lavender),
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
          ),
          child: Row(
            children: [
              Container(
                width: metrics.artSize(42),
                height: metrics.artSize(42),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, SellerUiColors.white),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  size: metrics.artSize(23),
                  color: HocalistPalette.text(
                    context,
                    SellerUiColors.primaryBright,
                  ),
                ),
              ),
              SizedBox(width: metrics.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usage == null
                          ? '$activeCount published'
                          : '${usage.active} of ${usage.limit} listing slots used',
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
              Flexible(
                child: _StoreStatusBadge(
                  label: plan ?? badgeLabel,
                  foreground: badgeForeground,
                  background: badgeBackground,
                ),
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
    this.firstListing = false,
    this.disabledNote,
  });

  final VoidCallback onTap;
  final bool enabled;
  final bool firstListing;
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
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, SellerUiColors.lavender),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_rounded,
              size: metrics.artSize(24),
              color: HocalistPalette.text(context, accent),
            ),
          ),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstListing ? 'Add your first listing' : 'Add listing',
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
                      ? firstListing
                            ? 'Start with a product or service. You can save it as a private draft.'
                            : 'Add a product or service to your Store.'
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
            color: HocalistPalette.text(context, accent),
            size: metrics.artSize(22),
          ),
        ],
      ),
    );
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(
            context,
            enabled ? SellerUiColors.white : const Color(0xfff6f6fb),
          ),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                enabled ? SellerUiColors.primaryBright : SellerUiColors.line,
              ),
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

class _StoreListingCard extends StatelessWidget {
  const _StoreListingCard({
    required this.listing,
    required this.onTap,
    this.shortcuts,
  });

  final LocalStoreListing listing;
  final VoidCallback onTap;
  final Widget? shortcuts;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final thumbnailWidth = metrics.artSize(72);
    return HocalistExpand(
      child: HocalistEntrance(
        child: HocalistPressFeedback(
          child: Material(
            color: HocalistPalette.surface(context, SellerUiColors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
              side: BorderSide(
                color: HocalistPalette.border(context, SellerUiColors.line),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  key: Key('sellerStoreListing-${listing.id}'),
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(metrics.geometry(13)),
                  child: Padding(
                    padding: EdgeInsets.all(metrics.geometry(10)),
                    child: Stack(
                      children: [
                        PositionedDirectional(
                          start: 0,
                          top: 0,
                          bottom: 0,
                          width: thumbnailWidth,
                          child: ExcludeSemantics(
                            child: IgnorePointer(
                              child: _ListingImage(
                                listing: listing,
                                size: thumbnailWidth,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: thumbnailWidth + metrics.spacing(10),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: thumbnailWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        key: Key(
                                          'sellerStoreTitle-${listing.id}',
                                        ),
                                        onPressed: onTap,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          alignment: Alignment.centerLeft,
                                          minimumSize: const Size(0, 44),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
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
                                    ),
                                    SizedBox(width: metrics.spacing(5)),
                                    IconButton(
                                      key: Key(
                                        'sellerStoreManage-${listing.id}',
                                      ),
                                      tooltip: 'Manage listing',
                                      onPressed: onTap,
                                      constraints: const BoxConstraints(
                                        minWidth: 44,
                                        minHeight: 44,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: metrics.artSize(19),
                                        color: HocalistPalette.text(
                                          context,
                                          SellerUiColors.body,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: metrics.spacing(1)),
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
                                SizedBox(height: metrics.spacing(4)),
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
                                if (listing.availability.trim().isNotEmpty) ...[
                                  SizedBox(height: metrics.spacing(3)),
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
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (shortcuts != null)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.spacing(10),
                    ),
                    child: shortcuts!,
                  ),
              ],
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
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(size * .16),
      ),
      clipBehavior: Clip.antiAlias,
      child: listing.imageMediaIds.isNotEmpty
          ? PrivateRemoteImage(id: listing.imageMediaIds.first, size: size)
          : listing.imageAsset == null
          ? Center(
              child: Icon(
                listing.kind == LocalListingKind.product
                    ? Icons.inventory_2_outlined
                    : Icons.design_services_outlined,
                size: size * .38,
                color: HocalistPalette.text(
                  context,
                  SellerUiColors.primaryBright,
                ),
              ),
            )
          : Image.asset(
              listing.imageAsset!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Icon(
                  Icons.image_outlined,
                  size: size * .38,
                  color: HocalistPalette.text(
                    context,
                    SellerUiColors.primaryBright,
                  ),
                ),
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
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: EdgeInsets.all(metrics.geometry(18)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(13)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: metrics.artSize(30),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
  const _StoreIdentityCard({
    this.name,
    this.avatarId,
    this.area,
    this.phone,
    this.email,
    this.publicPreview = false,
    this.onEdit,
  });

  final String? name, avatarId, area, phone, email;
  final bool publicPreview;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final displayName = name?.trim().isNotEmpty == true ? name!.trim() : 'Seller store';
    final size = metrics.artSize(publicPreview ? 58 : 40);
    final initials = displayName.split(RegExp(r'\s+')).take(2)
        .map((part) => part.characters.first.toUpperCase()).join();
    final header = Container(
      padding: EdgeInsets.all(metrics.spacing(10)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(13)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(metrics.geometry(12)),
              child: avatarId != null
                  ? PrivateRemoteImage(id: avatarId!, size: size)
                  : ColoredBox(
                      color: HocalistPalette.surface(context, SellerUiColors.white),
                      child: Center(
                        child: Text(initials, style: sellerText(
                          metrics, publicPreview ? 19 : 13,
                          color: SellerUiColors.primaryBright, weight: FontWeight.w800,
                        )),
                      ),
                    ),
            ),
          ),
          SizedBox(width: metrics.spacing(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: sellerText(
                  metrics, publicPreview ? 17 : 13, weight: FontWeight.w900,
                )),
                if (area != null || !publicPreview)
                  Text(area ?? 'Store profile', style: sellerText(
                    metrics, 11, color: SellerUiColors.muted,
                  )),
              ],
            ),
          ),
          if (onEdit != null)
            TextButton(
              key: const Key('sellerStoreEditProfile'),
              onPressed: onEdit,
              child: const Text('Edit profile'),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (phone != null || email != null) ...[
          SizedBox(height: metrics.spacing(12)),
          Text('Contact this business', style: sellerText(
            metrics, 13, weight: FontWeight.w800,
          )),
          for (final (label, detail) in [('Phone', phone), ('Email', email)])
            if (detail != null)
              Padding(
                padding: EdgeInsets.only(top: metrics.spacing(5)),
                child: SelectableText('$label: $detail'),
              ),
        ],
      ],
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
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Container(
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.white),
        borderRadius: BorderRadius.circular(metrics.geometry(13)),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
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
                  CategoryAnswersView(answers: listing.categoryAnswers),
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
      brightness: Theme.of(context).brightness,
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
          Icon(
            icon,
            color: HocalistPalette.text(context, effectiveColor),
            size: metrics.artSize(20),
          ),
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
            color: HocalistPalette.text(context, effectiveColor),
            size: metrics.artSize(20),
          ),
        ],
      ),
    );
    return Material(
      color: HocalistPalette.surface(
        context,
        enabled ? const Color(0xfff8f8ff) : const Color(0xfff4f4f9),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: BorderSide(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
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
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Material(
      color: HocalistPalette.surface(
        context,
        selected ? SellerUiColors.lavender : const Color(0xfff8f8ff),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: BorderSide(
          color: HocalistPalette.border(
            context,
            selected ? SellerUiColors.primaryBright : SellerUiColors.line,
          ),
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
                color: HocalistPalette.text(
                  context,
                  selected
                      ? SellerUiColors.primaryBright
                      : SellerUiColors.muted,
                ),
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
    this.imageUpload,
    this.questionLoader = loadCategoryQuestions,
    this.categories = const <StoreCategoryOption>[],
    this.onReconcile,
  });

  final LocalStoreListing? initialListing;
  final _StoreEditorSave onSave;
  final bool storeBacked;
  final ImageUpload? imageUpload;
  final CategoryQuestionLoader questionLoader;
  final List<StoreCategoryOption> categories;
  final VoidCallback? onReconcile;

  @override
  State<_AddStoreListingSheet> createState() => _AddStoreListingSheetState();
}

enum _ListingEditorStage { chooseType, details, preview }

enum _ListingPricing {
  fixed('Fixed price'),
  startingAt('Starting at'),
  hourly('Hourly'),
  quote('Request a quote'),
  custom('Custom price');

  const _ListingPricing(this.label);
  final String label;
}

class _AddStoreListingSheetState extends State<_AddStoreListingSheet> {
  static const _conditions = ['New', 'Like new', 'Good', 'Fair', 'For parts'];
  late _ListingEditorStage _stage;
  LocalListingKind? _kind;
  String? _condition;
  _ListingPricing _pricing = _ListingPricing.fixed;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _areaController;
  PlaceCaptureResult? _selectedArea;
  bool _choosingArea = false;

  Future<void> _chooseArea() async {
    if (_choosingArea || _saving || _ambiguous) return;
    _choosingArea = true;
    FocusScope.of(context).unfocus();
    try {
      final result = await showPlaceCaptureSheet(
        context: context,
        title: 'Choose pickup or service area',
        subtitle: 'Search for a location or use your current location. This location will appear on your listing.',
        confirmLabel: 'Use this location',
        places: createConfiguredPlacesRepository(),
        locationReader: readForegroundLocation,
        initial: _selectedArea ?? (_areaController.text.trim().isEmpty ? null : PlaceCaptureResult(
          label: _areaController.text.trim(), address: _areaController.text.trim(),
          source: PlaceCaptureSource.manual,
        )),
      );
      if (mounted && result != null) {
        setState(() {
          _selectedArea = result;
          _areaController.text = result.address;
        });
      }
    } finally { _choosingArea = false; }
  }
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
  List<CategoryAnswer> _categoryAnswers = const [];
  final _questionKey = GlobalKey<CategoryQuestionEditorState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialListing;
    _stage = initial == null
        ? _ListingEditorStage.chooseType
        : _ListingEditorStage.details;
    _kind = initial?.kind;
    _titleController = TextEditingController(text: initial?.title);
    var description = initial?.description ?? '';
    if (_kind == LocalListingKind.product) {
      final lines = description.split('\n');
      for (final option in _conditions) {
        if (lines.first == 'Condition: $option') {
          _condition = option;
          description = lines.skip(1).join('\n').trimLeft();
          break;
        }
      }
    }
    _descriptionController = TextEditingController(text: description);
    _categoryController = TextEditingController(text: initial?.category);
    final price = initial?.priceLabel.trim() ?? '';
    _pricing = _priceMode(price);
    _priceController = TextEditingController(
      text: switch (_pricing) {
        _ListingPricing.startingAt => price.substring(5).trim(),
        _ListingPricing.hourly => price.substring(0, price.length - 5).trim(),
        _ListingPricing.quote => '',
        _ => price,
      },
    );
    _areaController = TextEditingController(text: initial?.serviceArea);
    _availabilityController = TextEditingController(
      text: initial?.availability,
    );
    _imageCount = initial?.imageCount ?? 0;
    _existingImageIds.addAll(initial?.imageMediaIds ?? const []);
    _categoryId = initial?.categoryId;
    _categoryAnswers = initial?.categoryAnswers ?? const [];
  }

  _ListingPricing _priceMode(String value) {
    if (value.isEmpty || _isAmount(value)) return _ListingPricing.fixed;
    if (value.startsWith('From ') && _isAmount(value.substring(5))) {
      return _ListingPricing.startingAt;
    }
    if (_kind == LocalListingKind.service) {
      if (value == 'Quote required') return _ListingPricing.quote;
      if (value.endsWith('/hour') &&
          _isAmount(value.substring(0, value.length - 5))) {
        return _ListingPricing.hourly;
      }
    }
    return _ListingPricing.custom;
  }

  bool _isAmount(String value) =>
      RegExp(r'^\$?\s*\d+(?:\.\d{1,2})?$').hasMatch(value.trim());

  String get _priceLabel {
    final raw = _priceController.text.trim();
    final amount = raw.startsWith(r'$') ? raw.substring(1).trim() : raw;
    return switch (_pricing) {
      _ListingPricing.fixed => '\$$amount',
      _ListingPricing.startingAt => 'From \$$amount',
      _ListingPricing.hourly => '\$$amount/hour',
      _ListingPricing.quote => 'Quote required',
      _ListingPricing.custom => raw,
    };
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
      priceLabel: _priceLabel,
      description: [
        if (_kind == LocalListingKind.product && _condition != null)
          'Condition: $_condition',
        if (_descriptionController.text.trim().isNotEmpty)
          _descriptionController.text.trim(),
      ].join('\n\n'),
      category: _categoryLabel ?? _categoryController.text.trim(),
      categoryId: _categoryId,
      categoryAnswers: _categoryAnswers,
      revision: initial?.revision ?? 0,
      pendingReview: initial?.pendingReview ?? false,
      rejected: initial?.rejected ?? false,
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
    final validPrice = switch (_pricing) {
      _ListingPricing.quote => true,
      _ListingPricing.custom => _priceController.text.trim().isNotEmpty,
      _ => _isAmount(_priceController.text),
    };
    if (_titleController.text.trim().isEmpty ||
        !validPrice ||
        categoryMissing) {
      setState(() {
        _error = widget.storeBacked
            ? 'Add a title, enter a valid price or choose a quote, and pick an active category.'
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
    final questionError = _questionKey.currentState?.validationMessage(
      requiredAnswers: status == LocalListingStatus.active,
    );
    if (questionError != null) {
      setState(() => _error = questionError);
      return;
    }
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
    final product = _kind == LocalListingKind.product;
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
          label: product ? 'Description' : 'What’s included?',
          hintText: product
              ? 'Mention the model, what’s included, and any wear.'
              : 'Describe the work you’ll do and what the price includes.',
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
            onSelected: (id) => setState(() {
              _categoryId = id;
              _categoryAnswers = const [];
            }),
          )
        else
          _StoreFormField(
            label: 'Category',
            hintText: 'Enter the closest category',
            controller: _categoryController,
            fieldKey: const Key('sellerStoreCategoryField'),
          ),
        SizedBox(height: metrics.spacing(10)),
        if (widget.storeBacked && _categoryId != null)
          CategoryQuestionEditor(
            key: _questionKey,
            loader: widget.questionLoader,
            categoryId: _categoryId!,
            answers: _categoryAnswers,
            onChanged: (answers) => setState(() => _categoryAnswers = answers),
          ),
        if (product) ...[
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _condition,
            decoration: _storeInputDecoration(
              context, metrics, hintText: 'Condition (optional)',
            ).copyWith(labelText: 'Condition'),
            items: [
              for (final condition in _conditions)
                DropdownMenuItem(value: condition, child: Text(condition)),
            ],
            onChanged: _saving || _ambiguous
                ? null : (value) => setState(() => _condition = value),
          ),
          SizedBox(height: metrics.spacing(10)),
        ],
        DropdownButtonFormField<_ListingPricing>(
          key: const Key('sellerStorePricingType'),
          isExpanded: true,
          initialValue: _pricing,
          decoration: _storeInputDecoration(
            context, metrics, hintText: 'Choose how to price this listing',
          ).copyWith(labelText: 'Pricing'),
          items: [
            for (final option in _ListingPricing.values)
              if (option == _ListingPricing.fixed ||
                  option == _ListingPricing.startingAt ||
                  (!product && (option == _ListingPricing.hourly || option == _ListingPricing.quote)) ||
                  (_pricing == _ListingPricing.custom && option == _ListingPricing.custom))
                DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: _saving || _ambiguous ? null : (value) {
            if (value != null) setState(() => _pricing = value);
          },
        ),
        if (_pricing != _ListingPricing.quote) ...[
          SizedBox(height: metrics.spacing(10)),
          _StoreFormField(
            fieldKey: const Key('sellerStorePriceField'),
            label: _pricing == _ListingPricing.hourly ? 'Hourly rate' : 'Price',
            prefixText: _pricing == _ListingPricing.custom ? null : r'$',
            hintText: _pricing == _ListingPricing.custom ? 'Enter your price' : '0.00',
            controller: _priceController,
            keyboardType: _pricing == _ListingPricing.custom
                ? null : const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          label: product ? 'Pickup area' : 'Service area',
          hintText: product ? 'Where can a buyer pick it up?' : 'Where do you work?',
          controller: _areaController,
          fieldKey: const Key('sellerStoreLocationField'),
          onTap: _chooseArea,
        ),
        SizedBox(height: metrics.spacing(10)),
        _StoreFormField(
          label: 'Availability',
          hintText: product ? 'Example: Available this weekend' : 'Example: Weekday mornings',
          controller: _availabilityController,
        ),
        SizedBox(height: metrics.spacing(10)),
        if (widget.storeBacked) ...[
          Wrap(
            spacing: 8,
            children: _existingImageIds
                .map(
                  (id) => Stack(
                    key: ValueKey('saved-store-photo-$id'),
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(12), child: PrivateRemoteImage(id: id)),
                      Positioned(top: 0, right: 0, child: StorePhotoRemoveButton(
                        onPressed: _saving || _imagePending || _ambiguous ? null
                            : () => setState(() => _existingImageIds.remove(id)),
                      )),
                    ],
                  ),
                )
                .toList(),
          ),
          if ((widget.imageUpload ?? configuredImageUpload('store'))
              case final upload?)
            PrivateImagePicker(
              upload: upload,
              existingImageCount: _existingImageIds.length,
              storePhotoControls: true,
              onPendingChanged: (value) =>
                  setState(() => _imagePending = value),
              enabled: !_saving && !_ambiguous,
              onChanged: (ids) => setState(() => _newImageIds = ids),
            )
          else ...[
            const SellerStateNotice(
              icon: Icons.photo_library_outlined,
              tone: SellerNoticeTone.error,
              title: 'Photo tools could not be loaded',
              body:
                  'Retry to restore the photo picker. Your listing details are kept.',
            ),
            SellerSecondaryButton(
              label: 'Retry photo tools',
              onPressed: () => setState(() {}),
            ),
          ],
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
              : widget.storeBacked && listing.status == LocalListingStatus.active
              ? (widget.initialListing?.rejected == true ? 'Resubmit for review' : 'Submit for review')
              : widget.initialListing == null ? 'Publish listing' : 'Save changes',
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
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(context, const Color(0xfff8f8ff)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(13)),
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                SellerUiColors.lavenderBorder,
              ),
            ),
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
                    decoration: BoxDecoration(
                      color: HocalistPalette.surface(
                        context,
                        SellerUiColors.lavender,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: metrics.artSize(22),
                      color: HocalistPalette.text(
                        context,
                        SellerUiColors.primaryBright,
                      ),
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
                    color: HocalistPalette.text(
                      context,
                      SellerUiColors.primaryBright,
                    ),
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
    this.prefixText,
    this.onTap,
    this.keyboardType,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final Key? fieldKey;
  final String? prefixText;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
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
          keyboardType: keyboardType,
          readOnly: onTap != null,
          onTap: onTap,
          minLines: minLines,
          maxLines: maxLines,
          style: sellerInputText(metrics, size: 12),
          decoration: _storeInputDecoration(context, metrics, hintText: hintText).copyWith(
            suffixIcon: onTap == null ? null : const Icon(Icons.location_on_outlined),
            prefixIcon: prefixText == null ? null : Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Text(prefixText!, style: sellerInputText(metrics, size: 12)),
            ),
            prefixIconConstraints: prefixText == null ? null : const BoxConstraints(minWidth: 30),
          ),
        ),
      ],
    );
  }
}

InputDecoration _storeInputDecoration(
  BuildContext context,
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
    prefixIconColor: HocalistPalette.text(context, SellerUiColors.body),
    filled: true,
    fillColor: HocalistPalette.surface(context, const Color(0xfff9f9ff)),
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
  if (listing.rejected && listing.status != LocalListingStatus.archived) {
    return const _StoreStatusBadge(
      label: 'Needs changes',
      foreground: SellerUiColors.amber,
      background: SellerUiColors.amberSurface,
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
      label: 'Live',
      foreground: SellerUiColors.green,
      background: SellerUiColors.greenSurface,
    ),
    LocalListingStatus.draft => const _StoreStatusBadge(
      label: 'Draft',
      foreground: SellerUiColors.body,
      background: SellerUiColors.lavender,
    ),
    LocalListingStatus.archived => const _StoreStatusBadge(label: 'Archived', foreground: SellerUiColors.body, background: SellerUiColors.lavender),
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
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(7),
        vertical: metrics.geometry(3),
      ),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, background),
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

String _kindFilterLabel(_StoreKindFilter kind) => switch (kind) {
  _StoreKindFilter.all => 'All types',
  _StoreKindFilter.products => 'Products',
  _StoreKindFilter.services => 'Services',
};

String _statusLabel(_StoreStatusFilter status) => switch (status) {
  _StoreStatusFilter.all => 'All statuses',
  _StoreStatusFilter.active => 'Live',
  _StoreStatusFilter.draft => 'Draft',
  _StoreStatusFilter.inReview => 'In review',
  _StoreStatusFilter.notApproved => 'Needs changes',
  _StoreStatusFilter.paused => 'Paused',
  _StoreStatusFilter.archived => 'Archived',
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
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    if (categories.isEmpty) {
      return Container(
        key: const Key('sellerStoreNoCategories'),
        padding: EdgeInsets.all(metrics.geometry(10)),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, SellerUiColors.amberSurface),
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
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Container(
      key: const Key('sellerStorePendingNotice'),
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.amberSurface),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        border: Border.all(
          color: HocalistPalette.border(
            context,
            SellerUiColors.amber.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We could not confirm the previous save. Retry to check it safely, '
            'or discard the pending change.',
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
