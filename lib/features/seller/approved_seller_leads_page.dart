import '../../components/hocalist_motion.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/discovery/discovery_adapter.dart';
import '../../data/phase2/marketplace/marketplace_leads_backend.dart';
import '../../domain/phase2/discovery.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/offers.dart';
import '../../domain/phase2/requests.dart';
import '../../domain/phase2/schedule.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import '../discovery/seller_discovery_origin_sheet.dart';
import 'seller_schedule_controls.dart';
import '../../data/phase2/media/image_gateway.dart';
import '../media/private_image_picker.dart';

/// Submits one real offer and returns a user-safe outcome.
typedef SellerOfferSubmitter =
    Future<OfferSubmissionResult> Function(
      SellerLeadView lead,
      OfferTerms terms,
      String operationKey,
    );

@immutable
class SellerOfferPlace {
  const SellerOfferPlace({
    required this.name,
    required this.address,
    this.placeId,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String address;
  final String? placeId;
  final double? latitude;
  final double? longitude;
}

typedef SellerOfferPlacePicker =
    Future<SellerOfferPlace?> Function(BuildContext context);

@immutable
class SellerOfferPresentation {
  const SellerOfferPresentation.approvedPrototype()
    : planLabel = 'Your Pro Plan',
      initialBid = r'$1.90',
      winningBid = r'$4.75',
      higherOffersAllowed = false,
      defaultPrice = '550';

  const SellerOfferPresentation.real()
    : planLabel = 'HocaCredit deposit batches',
      initialBid = 'Not available',
      winningBid = 'Not available',
      higherOffersAllowed = false,
      defaultPrice = '';

  final String planLabel;
  final String initialBid;
  final String winningBid;
  final bool higherOffersAllowed;
  final String defaultPrice;
}

class ApprovedSellerLeadsPage extends StatefulWidget {
  const ApprovedSellerLeadsPage({
    super.key,
    this.onChooseSpecificLocation,
    this.onOfferSubmitted,
    this.sellerName = 'Northside Tech',
    this.offerPresentation = const SellerOfferPresentation.approvedPrototype(),
    this.leads,
    this.leadsLoading = false,
    this.leadsError,
    this.onRefreshLeads,
    this.categories = const <StoreCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.offerTimezones = const <String>[],
    this.onSubmitOffer,
    this.onValidateLead,
    this.uploadImage,
    this.leadPaging,
    this.discoveryOrigin,
    this.discoveryOriginLoading = false,
    this.onSaveDiscoveryOrigin,
    this.onDiscoveryOriginSaved,
  });

  final SellerOfferPlacePicker? onChooseSpecificLocation;
  final Future<SellerLeadView?> Function(SellerLeadView)? onValidateLead;
  final ValueChanged<LocalOfferRecord>? onOfferSubmitted;
  final String sellerName;
  final SellerOfferPresentation offerPresentation;

  /// Real buyer requests. Null keeps the approved prototype list.
  final List<SellerLeadView>? leads;

  final bool leadsLoading;

  /// User-safe message when the real leads load failed.
  final String? leadsError;

  final VoidCallback? onRefreshLeads;

  /// Admin-managed catalogue categories for the lead filter. Empty keeps the
  /// prototype fixture options in prototype mode and hides the category filter
  /// in real mode until the catalogue is configured.
  final List<StoreCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final VoidCallback? onRefreshCategories;

  /// Server-provided named IANA zones for real offer scheduling.
  final List<String> offerTimezones;

  /// Real offer submission. Null keeps the local prototype flow.
  final SellerOfferSubmitter? onSubmitOffer;
  final ImageUpload? uploadImage;

  /// Server-paged discovery. When set, filters, sorts and the cursor are
  /// server-authorized and page two is fetched with the returned cursor.
  final MarketplacePagedLeadsBackend? leadPaging;

  /// The seller's current discovery origin, when configured. The Leads screen
  /// shows it and opens the manual area editor that persists it.
  final SellerDiscoveryOrigin? discoveryOrigin;
  final bool discoveryOriginLoading;

  /// Persists a manual discovery area. Receives one client-owned operation key
  /// per intent; retries of the same intent reuse it.
  final Future<SellerDiscoveryOrigin> Function(
    SellerDiscoveryOriginInput input,
    String operationKey,
  )?
  onSaveDiscoveryOrigin;
  final ValueChanged<SellerDiscoveryOrigin>? onDiscoveryOriginSaved;

  bool get usesRealLeads => leads != null;

  bool get usesPagedLeads => leadPaging != null;

  bool get usesRealOffers => onSubmitOffer != null;

  @override
  State<ApprovedSellerLeadsPage> createState() =>
      _ApprovedSellerLeadsPageState();
}

class _ApprovedSellerLeadsPageState extends State<ApprovedSellerLeadsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';
  String _location = 'All';
  String _budget = 'All';
  String _sort = 'Best match';

  List<SellerLeadView> _pagedLeads = const [];
  String? _pagedCursor;
  bool _pagedLoading = false;
  bool _pagedLoadingMore = false;
  String? _pagedError;
  int _pagedToken = 0;
  Timer? _searchDebounce;
  bool _openingOffer = false;
  String? _offerOpenError;

  bool get _pagedMode => widget.leadPaging != null;

  @override
  void initState() {
    super.initState();
    if (widget.usesRealLeads) _sort = 'Newest first';
    if (_pagedMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reloadPagedLeads());
      });
    }
    final refresh = widget.onRefreshCategories;
    if (widget.usesRealLeads && refresh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  DiscoveryLeadFilter _serverFilter() {
    String? category;
    if (_category != 'All' && _categoryOptions.any((o) => o.id == _category)) {
      category = _category;
    }
    return DiscoveryLeadFilter(
      categoryId: category,
      areaLabel: _location == 'All' ? null : _location,
      query: _query.trim().isEmpty ? null : _query.trim(),
      budgetMinimumMinor: _budget == r'$500+' ? 50000 : null,
      budgetMaximumMinor: _budget == r'Under $500' ? 50000 : null,
      sort: switch (_sort) {
        'Best match' || 'Highest match' => DiscoverySort.recommended,
        'Closest' => DiscoverySort.closest,
        'Budget' => DiscoverySort.budget,
        _ => DiscoverySort.newest,
      },
    );
  }

  Future<void> _reloadPagedLeads() async {
    final backend = widget.leadPaging;
    if (backend == null) return;
    final token = ++_pagedToken;
    setState(() {
      _pagedLoading = true;
      _pagedError = null;
    });
    try {
      final page = await backend.loadLeadPage(
        filter: _serverFilter(),
        limit: 20,
      );
      if (!mounted || token != _pagedToken) return;
      setState(() {
        _pagedLeads = _pagedViews(page);
        _pagedCursor = page.nextCursor;
      });
    } on StoreBackendException catch (error) {
      if (!mounted || token != _pagedToken) return;
      setState(() => _pagedError = error.message);
    } finally {
      if (mounted && token == _pagedToken) {
        setState(() => _pagedLoading = false);
      }
    }
  }

  Future<void> _loadMorePagedLeads() async {
    final backend = widget.leadPaging;
    final cursor = _pagedCursor;
    if (backend == null || cursor == null || _pagedLoadingMore) return;
    final token = _pagedToken;
    setState(() {
      _pagedLoadingMore = true;
      _pagedError = null;
    });
    try {
      final page = await backend.loadLeadPage(
        filter: _serverFilter(),
        cursor: cursor,
        limit: 20,
      );
      if (!mounted || token != _pagedToken) return;
      final existing = _pagedLeads.map((lead) => lead.requestId).toSet();
      setState(() {
        _pagedLeads = [
          ..._pagedLeads,
          ..._pagedViews(
            page,
          ).where((lead) => !existing.contains(lead.requestId)),
        ];
        _pagedCursor = page.nextCursor == cursor ? null : page.nextCursor;
      });
    } on StoreBackendException catch (error) {
      if (!mounted || token != _pagedToken) return;
      setState(() => _pagedError = error.message);
    } finally {
      if (mounted && token == _pagedToken) {
        setState(() => _pagedLoadingMore = false);
      }
    }
  }

  /// Maps one page to card views, attaching each item's explainable reasons.
  List<SellerLeadView> _pagedViews(DiscoveryLeadPage page) {
    return [
      for (var index = 0; index < page.items.length; index++)
        SellerLeadView.fromProjection(
          page.items[index],
          matchReasons: index < page.matchReasons.length
              ? page.matchReasons[index]
              : const [],
        ),
    ];
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    if (!_pagedMode) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_reloadPagedLeads()),
    );
  }

  /// Active admin-managed categories available to this role.
  List<StoreCategoryOption> get _categoryOptions => widget.categories
      .where((category) => category.isActive)
      .toList(growable: false);

  bool get _categoryFilterVisible =>
      !widget.usesRealLeads || _categoryOptions.isNotEmpty;

  bool get _hasActiveFilter =>
      _query.trim().isNotEmpty ||
      (_categoryFilterVisible && _category != 'All') ||
      _location != 'All' ||
      _budget != 'All';

  List<SellerLeadView> get _visibleLeads {
    if (_pagedMode) return _pagedLeads;
    final source = widget.leads ?? _prototypeLeads;
    final query = _query.trim().toLowerCase();
    final filtered = source.where((lead) {
      final matchesQuery =
          query.isEmpty ||
          '${lead.name} ${lead.city} ${lead.request} ${lead.description}'
              .toLowerCase()
              .contains(query);
      final matchesLocation =
          _location == 'All' ||
          lead.city.toLowerCase().contains(_location.toLowerCase());
      final matchesBudget = _matchesBudgetFilter(lead.budget);
      final matchesCategory =
          _category == 'All' ||
          (widget.usesRealLeads
              ? lead.categoryId == _category
              : (_category == 'Tablets' &&
                    lead.request.toLowerCase().contains('ipad')));
      return matchesQuery &&
          matchesLocation &&
          matchesBudget &&
          matchesCategory;
    }).toList();
    if (_sort == 'Closest') {
      filtered.sort((a, b) => a.distance.compareTo(b.distance));
    } else if (_sort == 'Highest match') {
      filtered.sort((a, b) => b.match.compareTo(a.match));
    } else if (_sort == 'Most purchases') {
      filtered.sort((a, b) => (b.purchases ?? -1).compareTo(a.purchases ?? -1));
    }
    return filtered;
  }

  /// Budget bands compare numeric bounds when the label is parseable, so real
  /// request budgets filter correctly instead of only matching prototype text.
  bool _matchesBudgetFilter(String budget) {
    if (_budget == 'All') return true;
    final numbers = RegExp(
      r'\d+(?:\.\d+)?',
    ).allMatches(budget).map((match) => double.parse(match.group(0)!)).toList();
    if (numbers.isEmpty) return true;
    final highest = numbers.reduce(
      (left, right) => left > right ? left : right,
    );
    if (_budget == r'Under $500') return highest < 500;
    if (_budget == r'$500+') return highest >= 500;
    return true;
  }

  /// Applies one filter change and re-queries the server in paged mode.
  void _applyFilterChange(VoidCallback update) {
    setState(update);
    if (_pagedMode) unawaited(_reloadPagedLeads());
  }

  Future<void> _openDiscoveryArea() async {
    final save = widget.onSaveDiscoveryOrigin;
    if (save == null) return;
    final saved = await showModalBottomSheet<SellerDiscoveryOrigin>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => SellerDiscoveryOriginSheet(
        initial: widget.discoveryOrigin,
        onSave: save,
      ),
    );
    if (!mounted || saved == null) return;
    widget.onDiscoveryOriginSaved?.call(saved);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: Key('sellerDiscoveryOriginSavedNotice'),
          content: Text('Discovery area saved.'),
        ),
      );
    if (_pagedMode) unawaited(_reloadPagedLeads());
  }

  Future<void> _openFilters() async {
    var category = _category;
    var location = _location;
    var budget = _budget;
    var sort = _sort;
    final categoryOptions = _categoryOptions;
    final realCategories = widget.usesRealLeads && categoryOptions.isNotEmpty;
    final categoryIds = <String>[
      'All',
      if (realCategories)
        ...categoryOptions.map((option) => option.id)
      else if (!widget.usesRealLeads)
        'Tablets',
    ];
    final categoryLabels = <String, String>{
      'All': 'All categories',
      if (realCategories)
        for (final option in categoryOptions) option.id: option.label,
    };
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SellerModalSheet(
          icon: Icons.tune_rounded,
          title: 'Lead filters',
          subtitle: 'Refine the buyer requests shown in Leads.',
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (categoryIds.length > 1) ...[
                HocalistSelectMenu<String>(
                  role: HocalistControlRole.seller,
                  value: categoryIds.contains(category) ? category : 'All',
                  options: categoryIds,
                  labelBuilder: (value) =>
                      categoryLabels[value] ??
                      (value == 'All' ? 'All categories' : value),
                  selectedLabelBuilder: (value) =>
                      categoryLabels[value] ??
                      (value == 'All' ? 'All categories' : value),
                  onSelected: (value) => setSheetState(() => category = value),
                  leading: Icons.grid_view_outlined,
                  expanded: true,
                ),
                const SizedBox(height: 10),
              ] else if (widget.usesRealLeads) ...[
                Text(
                  widget.categoriesLoading
                      ? 'Loading Store categories…'
                      : widget.categoriesError != null
                      ? widget.categoriesError!
                      : 'No active Store categories are configured yet. The category filter is unavailable.',
                  key: const Key('sellerLeadsCategoryUnavailable'),
                  style: sellerText(
                    ApprovedReplicaScope.of(context),
                    11,
                    color: SellerUiColors.body,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              HocalistSelectMenu<String>(
                role: HocalistControlRole.seller,
                value: location,
                options: const [
                  'All',
                  'Yonkers',
                  'New Rochelle',
                  'Mount Vernon',
                ],
                labelBuilder: (value) => value,
                selectedLabelBuilder: (value) =>
                    value == 'All' ? 'All locations' : value,
                onSelected: (value) => setSheetState(() => location = value),
                leading: Icons.location_on_outlined,
                expanded: true,
              ),
              const SizedBox(height: 10),
              HocalistSelectMenu<String>(
                role: HocalistControlRole.seller,
                value: budget,
                options: const ['All', r'Under $500', r'$500+'],
                labelBuilder: (value) => value,
                selectedLabelBuilder: (value) =>
                    value == 'All' ? 'All budgets' : value,
                onSelected: (value) => setSheetState(() => budget = value),
                leading: Icons.paid_outlined,
                expanded: true,
              ),
              const SizedBox(height: 10),
              HocalistSelectMenu<String>(
                role: HocalistControlRole.seller,
                value: sort,
                options: widget.usesRealLeads
                    ? const ['Newest first', 'Best match', 'Closest', 'Budget']
                    : const [
                        'Best match',
                        'Closest',
                        'Highest match',
                        'Most purchases',
                      ],
                labelBuilder: (value) => value,
                onSelected: (value) => setSheetState(() => sort = value),
                leading: Icons.swap_vert_rounded,
                expanded: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SellerSecondaryButton(
                      label: 'Clear',
                      onPressed: () => setSheetState(() {
                        category = 'All';
                        location = 'All';
                        budget = 'All';
                        sort = widget.usesRealLeads
                            ? 'Newest first'
                            : 'Best match';
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SellerPrimaryButton(
                      label: 'Apply filters',
                      onPressed: () {
                        _applyFilterChange(() {
                          _category = category;
                          _location = location;
                          _budget = budget;
                          _sort = sort;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOffer(SellerLeadView lead, {bool? highPreset}) async {
    if (_openingOffer) return;
    _openingOffer = true;
    if (widget.onValidateLead != null) {
      SellerLeadView? refreshed;
      try {
        refreshed = await widget.onValidateLead!(lead);
      } catch (_) {
        // An unavailable read never authorizes opening an outdated offer form.
      }
      if (!mounted) return;
      if (refreshed == null) {
        setState(() {
          _openingOffer = false;
          _offerOpenError =
              'This request could not be confirmed as available. Refresh Leads and try again.';
        });
        if (_pagedMode) unawaited(_reloadPagedLeads());
        widget.onRefreshLeads?.call();
        return;
      }
      lead = refreshed;
    }
    if (mounted) setState(() => _offerOpenError = null);
    final submitted = await showModalBottomSheet<LocalOfferRecord>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (context) => _SendOfferSheet(
        lead: lead,
        initialPrice: highPreset == null
            ? null
            : lead.presetPrice(high: highPreset),
        sellerName: widget.sellerName,
        presentation: widget.offerPresentation,
        onChooseSpecificLocation: widget.onChooseSpecificLocation,
        timezones: widget.offerTimezones,
        onSubmitOffer: widget.onSubmitOffer,
        uploadImage: widget.uploadImage,
      ),
    );
    _openingOffer = false;
    if (!mounted || submitted == null) return;
    // Real offers are persisted by the server; only the prototype keeps a
    // local record.
    if (!widget.usesRealOffers) {
      widget.onOfferSubmitted?.call(submitted);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('sellerOfferSubmittedNotice'),
          content: Text('Offer sent to ${lead.name}. You are still in Leads.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SellerResponsivePage(
      builder: (context, metrics) {
        return CustomScrollView(
          key: const Key('sellerLeadsScroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                metrics.pageHorizontalPadding(14),
                metrics.spacing(12),
                metrics.pageHorizontalPadding(14),
                metrics.spacing(14),
              ),
              sliver: SliverList.list(
                children: [
                  _LeadsHeader(
                    filtersActive: _hasActiveFilter,
                    realMode: widget.usesRealLeads,
                    onFilter: _openFilters,
                  ),
                  if (widget.usesRealLeads &&
                      widget.onSaveDiscoveryOrigin != null) ...[
                    SizedBox(height: metrics.spacing(8)),
                    _DiscoveryAreaBar(
                      origin: widget.discoveryOrigin,
                      loading: widget.discoveryOriginLoading,
                      onTap: () => unawaited(_openDiscoveryArea()),
                    ),
                  ],
                  SizedBox(height: metrics.spacing(10)),
                  _SearchField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onClear: () {
                      _searchController.clear();
                      if (_pagedMode) {
                        _searchDebounce?.cancel();
                        unawaited(_reloadPagedLeads());
                      } else {
                        setState(() => _query = '');
                      }
                    },
                  ),
                  SizedBox(height: metrics.spacing(10)),
                  _FilterRow(
                    realMode: widget.usesRealLeads,
                    categories: _categoryOptions,
                    category: _category,
                    location: _location,
                    budget: _budget,
                    sort: _sort,
                    onCategory: (value) =>
                        _applyFilterChange(() => _category = value),
                    onLocation: (value) =>
                        _applyFilterChange(() => _location = value),
                    onBudget: (value) =>
                        _applyFilterChange(() => _budget = value),
                    onSort: (value) => _applyFilterChange(() => _sort = value),
                  ),
                  SizedBox(height: metrics.spacing(11)),
                  if (widget.usesRealLeads &&
                      _sort == 'Closest' &&
                      widget.discoveryOrigin?.coordinatesPresent != true)
                    SellerStateNotice(
                      key: const Key('sellerClosestOriginNotice'),
                      icon: Icons.location_off_outlined,
                      title: 'Distance sorting needs a discovery location',
                      body:
                          'Distance is unavailable, so these results cannot be ordered by proximity. Set a discovery location or choose another sort.',
                      actionLabel: widget.onSaveDiscoveryOrigin == null
                          ? null
                          : 'Set discovery area',
                      onAction: widget.onSaveDiscoveryOrigin == null
                          ? null
                          : () => unawaited(_openDiscoveryArea()),
                    ),
                  const _TargetingNotice(),
                  if (_offerOpenError != null)
                    SellerStateNotice(
                      key: const Key('sellerLeadUnavailable'),
                      icon: Icons.info_outline,
                      title: 'Request availability',
                      body: _offerOpenError,
                    ),
                  SizedBox(height: metrics.spacing(12)),
                  if ((_pagedMode ? _pagedLoading : widget.leadsLoading)) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        key: const Key('sellerLeadsLoading'),
                        minHeight: 3,
                        color: SellerUiColors.primary,
                        backgroundColor: SellerUiColors.lavender,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(10)),
                  ],
                  if ((_pagedMode ? _pagedError : widget.leadsError)
                      case final error?) ...[
                    _SellerLeadsErrorNotice(
                      message: error,
                      onRetry: _pagedMode
                          ? () => unawaited(_reloadPagedLeads())
                          : widget.onRefreshLeads,
                    ),
                    SizedBox(height: metrics.spacing(10)),
                  ],
                  if (_visibleLeads.isEmpty && !_pagedLoading)
                    _SellerLeadsEmptyState(
                      filtered: _hasActiveFilter,
                      onRefresh: _pagedMode
                          ? () => unawaited(_reloadPagedLeads())
                          : widget.onRefreshLeads,
                    )
                  else
                    for (final lead in _visibleLeads) ...[
                      _LeadCard(
                        key: Key('sellerLeadCard${lead.initials}'),
                        lead: lead,
                        onPrepareOffer: () => _openOffer(lead),
                        onLowOffer: lead.presetPrice(high: false) == null
                            ? null
                            : () => _openOffer(lead, highPreset: false),
                        onHighOffer: lead.presetPrice(high: true) == null
                            ? null
                            : () => _openOffer(lead, highPreset: true),
                      ),
                      SizedBox(height: metrics.spacing(12)),
                    ],
                  if (_pagedMode && _pagedCursor != null && !_pagedLoading) ...[
                    Center(
                      child: SellerSecondaryButton(
                        key: const Key('sellerLeadsLoadMore'),
                        label: _pagedLoadingMore
                            ? 'Loading more…'
                            : 'Load more leads',
                        onPressed: _pagedLoadingMore
                            ? null
                            : () => unawaited(_loadMorePagedLeads()),
                      ),
                    ),
                    SizedBox(height: metrics.spacing(6)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LeadsHeader extends StatelessWidget {
  const _LeadsHeader({
    required this.filtersActive,
    required this.onFilter,
    this.realMode = false,
  });

  final bool filtersActive;
  final VoidCallback onFilter;
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 34),
        Expanded(
          child: Column(
            children: [
              Text(
                'Find Customers',
                style: sellerText(metrics, 25, weight: FontWeight.w800),
              ),
              SizedBox(height: metrics.geometry(3)),
              Text(
                realMode
                    ? 'Buyer requests you can offer on'
                    : 'Curated buyers looking for what you offer',
                textAlign: TextAlign.center,
                style: sellerText(metrics, 13, color: SellerUiColors.body),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('sellerLeadsFilter'),
          tooltip: filtersActive ? 'Clear lead filters' : 'Lead filters',
          onPressed: onFilter,
          icon: Icon(
            filtersActive
                ? Icons.filter_alt_off_outlined
                : Icons.filter_alt_outlined,
          ),
          color: SellerUiColors.primaryBright,
        ),
      ],
    );
  }
}

/// Reachable discovery-area summary and editor entry for the manual fallback.
class _DiscoveryAreaBar extends StatelessWidget {
  const _DiscoveryAreaBar({
    required this.origin,
    required this.loading,
    required this.onTap,
  });

  final SellerDiscoveryOrigin? origin;
  final bool loading;
  final VoidCallback onTap;

  String get _label {
    if (loading) return 'Loading discovery area…';
    final value = origin;
    if (value == null || !value.configured) return 'Set your discovery area';
    final area = value.areaLabel;
    final radius = value.radiusMiles;
    if (area != null && radius != null) {
      return 'Discovery area: $area · within $radius mi';
    }
    if (radius != null) return 'Discovery area: within $radius miles';
    return 'Discovery area: $area';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('sellerDiscoveryAreaBar'),
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.geometry(11),
            vertical: metrics.geometry(9),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FF),
            border: Border.all(color: SellerUiColors.lavenderBorder),
            borderRadius: BorderRadius.circular(metrics.geometry(10)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.explore_outlined,
                size: metrics.artSize(18),
                color: SellerUiColors.primaryBright,
              ),
              SizedBox(width: metrics.geometry(7)),
              Expanded(
                child: Text(
                  _label,
                  maxLines: metrics.accessibilityReflow ? null : 1,
                  overflow: metrics.accessibilityReflow
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: sellerText(
                    metrics,
                    11.5,
                    weight: FontWeight.w700,
                    color: SellerUiColors.ink,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: metrics.geometry(18),
                color: SellerUiColors.body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return TextField(
      key: const Key('sellerLeadsSearch'),
      controller: controller,
      style: sellerInputText(metrics),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by product, service, brand, or keyword...',
        hintStyle: sellerInputPlaceholder(metrics),
        prefixIcon: const Icon(Icons.search, color: SellerUiColors.body),
        contentPadding: EdgeInsets.symmetric(vertical: metrics.geometry(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(11)),
          borderSide: const BorderSide(color: SellerUiColors.lavenderBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(11)),
          borderSide: const BorderSide(color: SellerUiColors.primaryBright),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.category,
    required this.categories,
    required this.location,
    required this.budget,
    required this.sort,
    required this.onCategory,
    required this.onLocation,
    required this.onBudget,
    required this.onSort,
    this.realMode = false,
  });

  final String category;
  final List<StoreCategoryOption> categories;
  final String location;
  final String budget;
  final String sort;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onLocation;
  final ValueChanged<String> onBudget;
  final ValueChanged<String> onSort;
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final defaultSort = realMode ? 'Newest first' : 'Best match';
    final categoryValues = <String>[
      'All',
      if (!realMode) 'Tablets' else ...categories.map((option) => option.id),
    ];
    final categoryLabels = <String, String>{
      'All': 'All categories',
      for (final option in categories) option.id: option.label,
    };
    final showCategory = !realMode || categoryValues.length > 1;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showCategory) ...[
            _SellerLeadFilterMenu(
              icon: Icons.grid_view_outlined,
              label: category == 'All'
                  ? 'Category'
                  : categoryLabels[category] ?? category,
              value: category,
              values: categoryValues,
              labelFor: (value) => categoryLabels[value] ?? value,
              onChanged: onCategory,
            ),
            SizedBox(width: metrics.geometry(8)),
          ],
          _SellerLeadFilterMenu(
            icon: Icons.location_on_outlined,
            label: location == 'All' ? 'Location' : location,
            value: location,
            values: const ['All', 'Yonkers', 'New Rochelle', 'Mount Vernon'],
            onChanged: onLocation,
          ),
          SizedBox(width: metrics.geometry(8)),
          _SellerLeadFilterMenu(
            icon: Icons.paid_outlined,
            label: budget == 'All' ? 'Budget' : budget,
            value: budget,
            values: const ['All', r'Under $500', r'$500+'],
            onChanged: onBudget,
          ),
          SizedBox(width: metrics.geometry(8)),
          _SellerLeadFilterMenu(
            icon: Icons.swap_vert,
            label: sort == defaultSort ? 'Sort' : sort,
            value: sort,
            values: realMode
                ? const ['Newest first', 'Best match', 'Closest', 'Budget']
                : const [
                    'Best match',
                    'Closest',
                    'Highest match',
                    'Most purchases',
                  ],
            onChanged: onSort,
          ),
        ],
      ),
    );
  }
}

class _SellerLeadFilterMenu extends StatelessWidget {
  const _SellerLeadFilterMenu({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelFor,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  /// Optional display label for option ids such as catalogue category ids.
  final String Function(String value)? labelFor;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    String display(String option) => labelFor?.call(option) ?? option;
    return PopupMenuButton<String>(
      initialValue: value,
      position: PopupMenuPosition.under,
      color: SellerUiColors.white,
      surfaceTintColor: SellerUiColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: const BorderSide(color: SellerUiColors.line),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in values)
          PopupMenuItem<String>(
            value: option,
            height: metrics.geometry(44),
            child: Row(
              children: [
                SizedBox(
                  width: metrics.artSize(22),
                  child: option == value
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: metrics.artSize(18),
                          color: SellerUiColors.primaryBright,
                        )
                      : null,
                ),
                SizedBox(width: metrics.geometry(7)),
                Text(
                  display(option),
                  style: sellerText(
                    metrics,
                    12,
                    weight: option == value ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: BoxConstraints(minHeight: metrics.geometry(44)),
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(11)),
        decoration: BoxDecoration(
          color: value == values.first
              ? Colors.transparent
              : SellerUiColors.lavender,
          border: Border.all(
            color: value == values.first
                ? SellerUiColors.line
                : SellerUiColors.primaryBright,
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: metrics.artSize(18), color: SellerUiColors.body),
            SizedBox(width: metrics.geometry(6)),
            Text(
              label,
              style: sellerText(metrics, 12, weight: FontWeight.w700),
            ),
            SizedBox(width: metrics.geometry(5)),
            Icon(Icons.keyboard_arrow_down, size: metrics.artSize(17)),
          ],
        ),
      ),
    );
  }
}

class _SellerLeadsEmptyState extends StatelessWidget {
  const _SellerLeadsEmptyState({this.filtered = false, this.onRefresh});

  /// A filtered zero result and a genuinely empty marketplace need different
  /// explanations.
  final bool filtered;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerLeadsEmptyState'),
      padding: EdgeInsets.all(metrics.spacing(20)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            filtered ? Icons.search_off_outlined : Icons.inbox_outlined,
            size: metrics.artSize(34),
            color: SellerUiColors.primaryBright,
          ),
          SizedBox(height: metrics.spacing(8)),
          Text(
            filtered ? 'No matching leads' : 'No leads available yet',
            style: sellerText(metrics, 15, weight: FontWeight.w800),
          ),
          SizedBox(height: metrics.spacing(4)),
          Text(
            filtered
                ? 'Try another search or clear one of the active filters.'
                : 'New buyer requests appear here as they are posted. '
                      'Check back shortly or refresh.',
            textAlign: TextAlign.center,
            style: sellerText(metrics, 11.5, color: SellerUiColors.muted),
          ),
          if (!filtered && onRefresh != null) ...[
            SizedBox(height: metrics.spacing(8)),
            TextButton(
              key: const Key('sellerLeadsEmptyRefresh'),
              onPressed: onRefresh,
              child: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetingNotice extends StatelessWidget {
  const _TargetingNotice();

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      padding: EdgeInsets.all(metrics.spacing(10)),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: SellerUiColors.primaryBright),
          SizedBox(width: metrics.spacing(8)),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(
                    text: 'No targeting fee is charged yet.\n',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text:
                        'When a buyer accepts your offer, the winning total is reserved '
                        'from one HocaCredit deposit batch. The initial fee is charged '
                        'after both of you message; a confirmed purchase charges only '
                        'the remaining difference. Each targeted customer uses one weekly slot.',
                  ),
                ],
              ),
              style: sellerText(metrics, 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.onPrepareOffer,
    this.onLowOffer,
    this.onHighOffer,
    super.key,
  });

  final SellerLeadView lead;
  final VoidCallback onPrepareOffer;
  final VoidCallback? onLowOffer, onHighOffer;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          padding: EdgeInsets.all(metrics.spacing(11)),
          decoration: BoxDecoration(
            color: SellerUiColors.white,
            border: Border.all(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(metrics.geometry(12)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0B1231),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: metrics.artSize(26),
                    backgroundColor: lead.avatarColor,
                    child: Text(
                      lead.initials,
                      style: sellerText(
                        metrics,
                        20,
                        weight: FontWeight.w800,
                        color: lead.initialColor,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.spacing(9)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.realMode ? lead.name : '${lead.name}  ✓',
                          style: sellerText(
                            metrics,
                            18,
                            weight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(2)),
                        Text(
                          '${lead.city}  •  ${lead.distance}',
                          style: sellerText(
                            metrics,
                            12,
                            color: SellerUiColors.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lead.match > 0)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.geometry(8),
                        vertical: metrics.geometry(5),
                      ),
                      decoration: BoxDecoration(
                        color: SellerUiColors.greenSurface,
                        borderRadius: BorderRadius.circular(
                          metrics.geometry(7),
                        ),
                      ),
                      child: Text(
                        '${lead.match}% Match',
                        style: sellerText(
                          metrics,
                          11,
                          weight: FontWeight.w800,
                          color: SellerUiColors.green,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.geometry(8),
                        vertical: metrics.geometry(5),
                      ),
                      decoration: BoxDecoration(
                        color: SellerUiColors.lavender,
                        borderRadius: BorderRadius.circular(
                          metrics.geometry(7),
                        ),
                      ),
                      child: Text(
                        'New request',
                        style: sellerText(
                          metrics,
                          11,
                          weight: FontWeight.w800,
                          color: SellerUiColors.primaryBright,
                        ),
                      ),
                    ),
                ],
              ),
              if (lead.matchReasons.isNotEmpty) ...[
                SizedBox(height: metrics.geometry(6)),
                Text(
                  lead.matchReasons.join(' • '),
                  key: Key('sellerLeadMatchReasons${lead.initials}'),
                  style: sellerText(
                    metrics,
                    11,
                    color: SellerUiColors.primaryBright,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
              SizedBox(height: metrics.spacing(10)),
              Text(
                lead.request,
                style: sellerText(metrics, 17, weight: FontWeight.w800),
              ),
              Text(
                lead.description,
                style: sellerText(metrics, 12, color: SellerUiColors.body),
              ),
              SizedBox(height: metrics.spacing(8)),
              Row(
                children: [
                  Icon(
                    Icons.sell_outlined,
                    size: metrics.artSize(17),
                    color: SellerUiColors.body,
                  ),
                  SizedBox(width: metrics.geometry(6)),
                  Text(
                    'Budget range',
                    style: sellerText(metrics, 10, color: SellerUiColors.body),
                  ),
                  const Spacer(),
                  Text(
                    lead.budget,
                    style: sellerText(
                      metrics,
                      16,
                      weight: FontWeight.w800,
                      color: SellerUiColors.green,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.spacing(9)),
              const Divider(height: 1, color: SellerUiColors.line),
              SizedBox(height: metrics.spacing(9)),
              Row(
                children: [
                  Expanded(
                    child: _LeadFact(
                      key: Key('sellerVerifiedFact${lead.initials}'),
                      icon: Icons.verified_user_outlined,
                      title: lead.realMode
                          ? 'Confirmed purchases'
                          : '${lead.purchases} verified',
                      value: lead.realMode
                          ? lead.purchases?.toString() ?? 'Not available'
                          : 'Great buyer',
                    ),
                  ),
                  Expanded(
                    child: _LeadFact(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Last purchase',
                      value: lead.lastPurchase,
                    ),
                  ),
                  Expanded(
                    child: _LeadFact(
                      icon: Icons.groups_outlined,
                      title: 'Preferred meet',
                      value: lead.meeting,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.spacing(10)),
              LayoutBuilder(
                builder: (context, constraints) {
                  final actions = <Widget>[
                    _BidButton(
                      label: 'Send Low Bid',
                      icon: Icons.bolt,
                      onTap: onLowOffer,
                    ),
                    _BidButton(
                      label: 'Send High Bid',
                      icon: Icons.rocket_launch_outlined,
                      onTap: onHighOffer,
                    ),
                    SellerPrimaryButton(
                      label: 'Prepare offer',
                      compact: true,
                      fontSize: 12,
                      onPressed: onPrepareOffer,
                      leading: Icon(
                        Icons.description_outlined,
                        key: Key('sellerPrepareOfferIcon${lead.initials}'),
                        color: Colors.white,
                        size: metrics.artSize(17),
                      ),
                    ),
                  ];
                  final stacked =
                      constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(12) > 15.6;
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          actions[i],
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) SizedBox(width: metrics.geometry(7)),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadFact extends StatelessWidget {
  const _LeadFact({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: metrics.artSize(17),
          color: SellerUiColors.primaryBright,
        ),
        SizedBox(width: metrics.geometry(5)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sellerText(metrics, 9, color: SellerUiColors.body),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sellerText(metrics, 10, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BidButton extends StatelessWidget {
  const _BidButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, metrics.geometry(48)),
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(3)),
        side: const BorderSide(color: SellerUiColors.primaryBright),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(9)),
        ),
      ),
      icon: Icon(icon, size: metrics.artSize(16)),
      label: Text(
        label,
        maxLines: 1,
        style: sellerText(
          metrics,
          10,
          weight: FontWeight.w800,
          color: SellerUiColors.primaryBright,
        ),
      ),
    );
  }
}

class _SendOfferSheet extends StatefulWidget {
  const _SendOfferSheet({
    required this.lead,
    required this.sellerName,
    required this.presentation,
    this.initialPrice,
    this.onChooseSpecificLocation,
    this.timezones = const <String>[],
    this.onSubmitOffer,
    this.uploadImage,
  });

  final SellerLeadView lead;
  final String sellerName;
  final SellerOfferPresentation presentation;
  final String? initialPrice;
  final SellerOfferPlacePicker? onChooseSpecificLocation;
  final List<String> timezones;
  final SellerOfferSubmitter? onSubmitOffer;
  final ImageUpload? uploadImage;

  @override
  State<_SendOfferSheet> createState() => _SendOfferSheetState();
}

class _SendOfferSheetState extends State<_SendOfferSheet> {
  bool get _realMode => widget.onSubmitOffer != null;
  SellerOfferPresentation get _presentation =>
      _realMode ? const SellerOfferPresentation.real() : widget.presentation;
  late final TextEditingController _priceController;
  late final TextEditingController _messageController;
  _MeetupChoice _meetupChoice = _MeetupChoice.business;
  SellerOfferPlace? _specificLocation;
  DateTime _meetingDate = DateTime(2025, 5, 22);
  TimeOfDay _meetingTime = const TimeOfDay(hour: 15, minute: 0);
  String? _priceError;
  String? _submitError;
  bool _submitting = false;
  bool _imagePending = false;
  final List<String> _productImages = [];
  String? _timezoneId;
  RepeatedTimeOccurrence? _occurrence;
  bool _ambiguousTime = false;
  bool _outcomeUncertain = false;
  OfferTerms? _pendingTerms;
  String? _pendingOperationKey;

  @override
  void initState() {
    super.initState();
    if (_realMode) _meetingDate = DateTime.now();
    final firstName = widget.lead.name.split(' ').first;
    final product = widget.lead.request
        .replaceFirst('Looking for ', '')
        .replaceFirst('Need ', '');
    _priceController = TextEditingController(
      text: widget.initialPrice ?? _presentation.defaultPrice,
    );
    _messageController = TextEditingController(
      text: _realMode
          ? ''
          : 'Hi $firstName, I have a like-new $product 256GB in space gray. '
                'Includes original charger and box. Let me know if you have any questions!',
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _chooseSpecificLocation() async {
    final picker = widget.onChooseSpecificLocation;
    if (picker == null) {
      final place = await showModalBottomSheet<SellerOfferPlace>(
        context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x990B1231),
        builder: (sheetContext) => SellerModalSheet(
          key: const Key('sellerPlacesConnectionDialog'),
          icon: Icons.location_searching_outlined,
          title: 'Location search',
          subtitle: 'Choose a specific safe meeting location for this offer.',
          onClose: () => Navigator.pop(sheetContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SellerInformationPanel(
                icon: Icons.shield_outlined,
                title: 'Choose a public meetup place',
                body:
                    'These review locations are stored only in this prototype. Live place search connects with the location provider later.',
              ),
              const SizedBox(height: 10),
              for (final option in _prototypeMeetingPlaces) ...[
                _SpecificLocationOption(
                  place: option,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
                if (option != _prototypeMeetingPlaces.last)
                  const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
      if (!mounted || place == null) return;
      setState(() {
        _specificLocation = place;
        _meetupChoice = _MeetupChoice.specific;
      });
      return;
    }

    final place = await picker(context);
    if (!mounted || place == null) return;
    setState(() {
      _specificLocation = place;
      _meetupChoice = _MeetupChoice.specific;
    });
  }

  Future<void> _pickSchedule() async {
    final selection = await showSellerSchedulePicker(
      context: context,
      initialDate: _meetingDate,
      initialTime: _meetingTime,
      earliestDate: _realMode ? DateTime.now() : null,
    );
    if (!mounted || selection == null) return;
    setState(() {
      _meetingDate = selection.date;
      _meetingTime = selection.time;
    });
  }

  Future<void> _addProductImage() async {
    // Real offers do not carry images until the reviewed media pipeline
    // exists, so this action must not fabricate placeholder filenames.
    if (widget.onSubmitOffer != null) return;
    final source = await showModalBottomSheet<_SellerOfferImageSource>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SellerOfferImagePickerSheet(
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (!mounted || source == null) return;
    final label = source == _SellerOfferImageSource.camera
        ? 'iPad-front-camera.jpg'
        : 'iPad-product-library.jpg';
    setState(() {
      if (!_productImages.contains(label)) _productImages.add(label);
    });
  }

  Future<void> _submit() async {
    if (_submitting || _imagePending) return;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      setState(() => _priceError = 'Enter a valid offer price.');
      return;
    }
    final submitter = widget.onSubmitOffer;
    if (submitter != null) {
      await _submitRealOffer(price, submitter);
      return;
    }
    setState(() {
      _priceError = null;
      _submitting = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.pop(context, _displayRecord(price));
  }

  Future<void> _submitRealOffer(
    double price,
    SellerOfferSubmitter submitter,
  ) async {
    if (!_outcomeUncertain &&
        DateUtils.dateOnly(
          _meetingDate,
        ).isBefore(DateUtils.dateOnly(DateTime.now()))) {
      setState(() => _submitError = 'Choose today or a future meeting date.');
      return;
    }
    if (widget.lead.requestId == null) {
      setState(
        () => _submitError = 'This request is not available for offers.',
      );
      return;
    }
    if (_timezoneId == null) {
      setState(() => _submitError = 'Choose the meeting timezone.');
      return;
    }
    if (_meetupChoice == _MeetupChoice.specific && _specificLocation == null) {
      setState(() => _submitError = 'Choose a specific meeting location.');
      return;
    }
    final MeetingPlace place;
    try {
      place = _meetingPlace;
    } on ArgumentError {
      setState(() => _submitError = 'Choose a specific meeting location.');
      return;
    }
    final terms = OfferTerms(
      price: Money(minorUnits: (price * 100).round(), currencyCode: 'USD'),
      message: _messageController.text.trim(),
      schedule: LocalSchedule(
        date: LocalDate(
          year: _meetingDate.year,
          month: _meetingDate.month,
          day: _meetingDate.day,
        ),
        startTime: LocalTime(
          hour: _meetingTime.hour,
          minute: _meetingTime.minute,
        ),
        timezoneId: _timezoneId!,
        occurrence: _occurrence,
      ),
      place: place,
      imageMediaIds: List.unmodifiable(_productImages),
    );

    // An attempt whose outcome is unknown keeps its exact payload and
    // operation key: Retry reconciles that same intent. A changed payload must
    // discard the unresolved intent first instead of silently reusing its key.
    if (_outcomeUncertain) {
      if (terms != _pendingTerms) {
        setState(
          () => _submitError =
              'An earlier offer may already have been sent. Retry to confirm '
              'it, or discard it before changing the details.',
        );
        return;
      }
    } else {
      _pendingTerms = terms;
      _pendingOperationKey = LocalMarketplaceRepository.newStoreOperationKey(
        'offer-submit',
      );
    }

    setState(() {
      _priceError = null;
      _submitError = null;
      _submitting = true;
    });
    final result = await submitter(
      widget.lead,
      _pendingTerms!,
      _pendingOperationKey!,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      _pendingTerms = null;
      _pendingOperationKey = null;
      _outcomeUncertain = false;
      Navigator.pop(context, _displayRecord(price));
      return;
    }
    setState(() {
      _submitting = false;
      _submitError = result.error;
      _outcomeUncertain = result.outcomeUncertain;
      _ambiguousTime = result.ambiguousTime;
      if (!result.outcomeUncertain) {
        // A definitive rejection committed nothing: the next submission is a
        // new intent with a new key. The repeated-time correction also starts
        // cleanly with the occurrence the user picked.
        _pendingTerms = null;
        _pendingOperationKey = null;
        if (result.ambiguousTime) _occurrence = null;
      }
    });
  }

  /// Abandons an offer whose outcome could not be confirmed so the seller can
  /// review the form and start a new intent.
  void _discardUncertain() {
    setState(() {
      _outcomeUncertain = false;
      _pendingTerms = null;
      _pendingOperationKey = null;
      _submitError = null;
    });
  }

  MeetingPlace get _meetingPlace => switch (_meetupChoice) {
    _MeetupChoice.business => MeetingPlace(
      choice: MeetupPlaceChoice.sellerBusiness,
      label: '${widget.sellerName} business location',
    ),
    _MeetupChoice.buyer => MeetingPlace(
      choice: MeetupPlaceChoice.buyerLocation,
    ),
    _MeetupChoice.specific => MeetingPlace(
      choice: MeetupPlaceChoice.specificPlace,
      label: _specificLocation?.name,
      address: _specificLocation?.address,
      placeId: _specificLocation?.placeId,
      latitude: _specificLocation?.latitude,
      longitude: _specificLocation?.longitude,
    ),
  };

  LocalOfferRecord _displayRecord(double price) {
    final requestTitle = widget.lead.request
        .replaceFirst('Looking for ', '')
        .replaceFirst('Need ', '');
    final location = switch (_meetupChoice) {
      _MeetupChoice.business => '${widget.sellerName} business location',
      _MeetupChoice.buyer => '${widget.lead.name} preferred location',
      _MeetupChoice.specific =>
        _specificLocation?.name ??
            _specificLocation?.address ??
            'Public meetup',
    };
    return LocalOfferRecord(
      id: 'offer-${widget.lead.initials.toLowerCase()}',
      requestId: widget.lead.requestId ?? 'request-ipad-air',
      buyerName: widget.lead.name,
      sellerName: widget.sellerName,
      requestTitle: requestTitle,
      price:
          '\$${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}',
      location: location,
      meetingDate: _formattedDate,
      meetingTime: _formattedTime,
      message: _messageController.text.trim(),
      imageNames: List<String>.unmodifiable(_productImages),
      status: LocalOfferStatus.sent,
    );
  }

  String get _formattedDate {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[_meetingDate.weekday - 1]}, '
        '${months[_meetingDate.month - 1]} ${_meetingDate.day}, ${_meetingDate.year}';
  }

  String get _formattedTime {
    final hour = _meetingTime.hourOfPeriod == 0
        ? 12
        : _meetingTime.hourOfPeriod;
    final minute = _meetingTime.minute.toString().padLeft(2, '0');
    final period = _meetingTime.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: media.size.width.clamp(
        320,
        ApprovedReplicaMetrics.supportedViewportMaxWidth,
      ),
      textScaler: media.textScaler,
    );
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Material(
        key: const Key('sellerSendOfferBottomSheet'),
        color: SellerUiColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ApprovedReplicaScope(
          metrics: metrics,
          child: Column(
            children: [
              SizedBox(height: metrics.geometry(10)),
              Container(
                width: metrics.geometry(62),
                height: metrics.geometry(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFC6C1DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('sellerSendOfferScroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    metrics.pageHorizontalPadding(16),
                    metrics.spacing(10),
                    metrics.pageHorizontalPadding(16),
                    metrics.spacing(16) + media.viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: metrics.artSize(25),
                            backgroundColor: widget.lead.avatarColor,
                            child: Text(
                              widget.lead.initials,
                              style: sellerText(
                                metrics,
                                18,
                                weight: FontWeight.w800,
                                color: widget.lead.initialColor,
                              ),
                            ),
                          ),
                          SizedBox(width: metrics.spacing(9)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _realMode
                                      ? widget.lead.name
                                      : '${widget.lead.name}  ✓',
                                  style: sellerText(
                                    metrics,
                                    18,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  widget.lead.request,
                                  style: sellerText(metrics, 12),
                                ),
                                Text(
                                  '${widget.lead.city}  •  ${widget.lead.distance}',
                                  style: sellerText(
                                    metrics,
                                    11,
                                    color: SellerUiColors.body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const Key('sellerSendOfferClose'),
                            tooltip: 'Close offer',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            color: SellerUiColors.ink,
                          ),
                        ],
                      ),
                      SizedBox(height: metrics.spacing(8)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _OfferPlanChip(label: _presentation.planLabel),
                      ),
                      SizedBox(height: metrics.spacing(8)),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compactHeader = constraints.maxWidth < 400;
                          final bidCard = _OfferBidCard(
                            initialBid: _presentation.initialBid,
                            winningBid: _presentation.winningBid,
                            compact: compactHeader,
                          );
                          if (constraints.maxWidth < 300) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  key: const Key('sellerSendOfferHeading'),
                                  'Send your offer',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: sellerText(
                                    metrics,
                                    20,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: metrics.spacing(8)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: bidCard,
                                ),
                              ],
                            );
                          }
                          if (compactHeader) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Center(
                                  child: Text(
                                    key: const Key('sellerSendOfferHeading'),
                                    'Send your offer',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    style: sellerText(
                                      metrics,
                                      20,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: bidCard,
                                ),
                              ],
                            );
                          }
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: Text(
                                  key: const Key('sellerSendOfferHeading'),
                                  'Send your offer',
                                  textAlign: TextAlign.center,
                                  style: sellerText(
                                    metrics,
                                    25,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: bidCard,
                              ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: metrics.spacing(14)),
                      _OfferSection(
                        number: '1',
                        title: 'Your price offer',
                        subtitle: 'Enter the total price you’re offering.',
                        child: TextField(
                          key: const Key('sellerOfferPrice'),
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          style: sellerInputText(metrics, size: 14),
                          onChanged: (_) {
                            if (_priceError != null) {
                              setState(() => _priceError = null);
                            }
                          },
                          decoration: InputDecoration(
                            prefixIcon: Container(
                              key: const Key('sellerOfferCurrencyPrefix'),
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: SellerUiColors.line),
                                ),
                              ),
                              child: Text(
                                r'$',
                                style: sellerText(
                                  metrics,
                                  16,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                            prefixIconConstraints: BoxConstraints(
                              minWidth: metrics.geometry(48),
                              maxWidth: metrics.geometry(48),
                              minHeight: metrics.geometry(52),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: metrics.spacing(12),
                              vertical: metrics.spacing(13),
                            ),
                            errorText: _priceError,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(height: metrics.spacing(10)),
                      Padding(
                        padding: EdgeInsets.only(left: metrics.geometry(40)),
                        child: Wrap(
                          spacing: metrics.spacing(20),
                          runSpacing: metrics.spacing(7),
                          children: [
                            _OfferInlineNotice(
                              icon: Icons.info_outline,
                              text: 'Buyer’s budget: ${widget.lead.budget}',
                              color: SellerUiColors.green,
                            ),
                            if (!(widget.lead.realMode
                                ? widget.lead.acceptsHigherOffers
                                : widget.presentation.higherOffersAllowed))
                              const _OfferInlineNotice(
                                key: Key('sellerHigherOfferWarning'),
                                icon: Icons.info_outline,
                                text: 'Buyer is not open to higher offers.',
                                color: Color(0xFFFF4A19),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 28, color: SellerUiColors.line),
                      _OfferSection(
                        number: '2',
                        title: 'Product images',
                        subtitle: 'Show the exact item included in your offer.',
                        child:
                            widget.onSubmitOffer != null &&
                                widget.uploadImage != null
                            ? PrivateImagePicker(
                                upload: widget.uploadImage!,
                                onPendingChanged: (value) =>
                                    setState(() => _imagePending = value),
                                enabled: !_submitting && !_outcomeUncertain,
                                onChanged: (ids) => setState(() {
                                  _productImages
                                    ..clear()
                                    ..addAll(ids);
                                }),
                              )
                            : _SellerOfferImageSection(
                                images: _productImages,
                                mediaUploadAvailable:
                                    widget.onSubmitOffer == null,
                                onAdd: _addProductImage,
                                onRemove: (image) => setState(
                                  () => _productImages.remove(image),
                                ),
                              ),
                      ),
                      const Divider(height: 28, color: SellerUiColors.line),
                      _OfferSection(
                        number: '3',
                        title: 'Place of meet up',
                        subtitle: 'Where would you like to meet?',
                        child: Column(
                          children: [
                            _OfferChoice(
                              key: const Key('sellerMeetupBusiness'),
                              selected: _meetupChoice == _MeetupChoice.business,
                              icon: Icons.storefront_outlined,
                              title: 'My business / Store',
                              subtitle: 'Meet at my business location',
                              onTap: () => setState(
                                () => _meetupChoice = _MeetupChoice.business,
                              ),
                            ),
                            _OfferChoice(
                              key: const Key('sellerMeetupBuyer'),
                              selected: _meetupChoice == _MeetupChoice.buyer,
                              icon: Icons.location_on_outlined,
                              title: 'Buyer’s location',
                              subtitle: 'I’ll travel to the buyer',
                              onTap: () => setState(
                                () => _meetupChoice = _MeetupChoice.buyer,
                              ),
                            ),
                            _SpecificLocationLauncher(
                              key: const Key('sellerOfferSpecificLocation'),
                              title: 'Choose a specific location',
                              subtitle: _specificLocation?.name ?? '',
                              selected: _meetupChoice == _MeetupChoice.specific,
                              onTap: _chooseSpecificLocation,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 28, color: SellerUiColors.line),
                      _OfferSection(
                        number: '4',
                        title: 'Time you can meet',
                        subtitle: 'Select the date and time you’re available.',
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _OfferPicker(
                                  key: const Key('sellerOfferDate'),
                                  icon: Icons.calendar_today_outlined,
                                  label: 'Date',
                                  value: _formattedDate,
                                  onTap: _pickSchedule,
                                ),
                              ),
                              SizedBox(width: metrics.geometry(8)),
                              Expanded(
                                child: _OfferPicker(
                                  key: const Key('sellerOfferTime'),
                                  icon: Icons.schedule_outlined,
                                  label: 'Time',
                                  value: _formattedTime,
                                  onTap: _pickSchedule,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onSubmitOffer != null) ...[
                        SizedBox(height: metrics.spacing(10)),
                        _OfferTimezoneField(
                          timezones: widget.timezones,
                          value: _timezoneId,
                          onSelected: (zone) => setState(() {
                            _timezoneId = zone;
                            _occurrence = null;
                            _ambiguousTime = false;
                            _submitError = null;
                          }),
                        ),
                        if (_ambiguousTime) ...[
                          SizedBox(height: metrics.spacing(8)),
                          _OfferOccurrenceChooser(
                            timezoneId: _timezoneId ?? '',
                            selected: _occurrence,
                            onSelected: (occurrence) =>
                                setState(() => _occurrence = occurrence),
                          ),
                        ],
                      ],
                      SizedBox(height: metrics.spacing(14)),
                      _OfferSection(
                        number: '5',
                        title: 'How it works',
                        subtitle: '',
                        child: Container(
                          padding: EdgeInsets.all(metrics.spacing(10)),
                          decoration: BoxDecoration(
                            color: SellerUiColors.lavender,
                            borderRadius: BorderRadius.circular(
                              metrics.geometry(9),
                            ),
                          ),
                          child: Column(
                            children: [
                              const _OfferHowItWorksRow(
                                icon: Icons.edit_note_outlined,
                                text: 'Send your offer to the buyer.',
                              ),
                              _OfferHowItWorksRow(
                                icon: Icons.phone_outlined,
                                text: _realMode
                                    ? 'Acceptance reserves the winning fee from one eligible HocaCredit deposit batch. The initial fee is charged once both parties message.'
                                    : 'If the buyer accepts your offer and chooses to share verified contact information, your initial bid is charged and you’ll receive access to their contact details.',
                              ),
                              _OfferHowItWorksRow(
                                icon: Icons.emoji_events_outlined,
                                text: _realMode
                                    ? 'Only the selected purchase seller pays the remaining winning-fee difference when the buyer confirms the purchase with their Hocalist PIN.'
                                    : 'If the buyer confirms the purchase with their Hocalist PIN, you’ll only pay the remaining balance needed to complete your winning bid.',
                              ),
                              _OfferHowItWorksRow(
                                icon: Icons.refresh,
                                text: _realMode
                                    ? 'Deposit batches keep their original rates. Unused reservations are released under the meeting and expiry rules; there is no automatic \$1 fee.'
                                    : 'If the buyer never confirms a purchase with any seller, your initial bid is automatically reduced to just \$1.00.',
                                showBottomGap: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: metrics.spacing(14)),
                      _OfferSection(
                        number: '6',
                        title: 'Add a message (optional)',
                        subtitle:
                            'Introduce yourself or add details about your offer.',
                        child: _OfferMessageField(
                          controller: _messageController,
                        ),
                      ),
                      SizedBox(height: metrics.spacing(10)),
                      if (_submitError != null) ...[
                        Text(
                          _submitError!,
                          key: const Key('sellerOfferSubmitError'),
                          style: sellerText(
                            metrics,
                            11,
                            weight: FontWeight.w700,
                            color: SellerUiColors.red,
                          ),
                        ),
                        SizedBox(height: metrics.spacing(8)),
                      ],
                      if (_outcomeUncertain) ...[
                        Row(
                          children: [
                            Expanded(
                              child: SellerPrimaryButton(
                                key: const Key('sellerOfferRetry'),
                                label: 'Retry',
                                onPressed: _submitting || _imagePending
                                    ? null
                                    : _submit,
                              ),
                            ),
                            SizedBox(width: metrics.geometry(8)),
                            Expanded(
                              child: SellerSecondaryButton(
                                key: const Key('sellerOfferDiscard'),
                                label: 'Discard',
                                onPressed: _submitting
                                    ? null
                                    : _discardUncertain,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: metrics.spacing(8)),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compactAction = constraints.maxWidth < 360;
                          return SellerPrimaryButton(
                            key: const Key('sellerSendOfferSubmit'),
                            label: _submitting ? 'Sending…' : 'Send Offer',
                            onPressed: _submitting || _imagePending
                                ? null
                                : _submit,
                            fontSize: compactAction ? 12 : 14,
                            trailing: Icon(
                              Icons.send_outlined,
                              color: Colors.white,
                              size: metrics.artSize(compactAction ? 17 : 19),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: metrics.spacing(12)),
                      OutlinedButton.icon(
                        key: const Key('sellerSendOfferCancel'),
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(metrics.geometry(44)),
                          foregroundColor: SellerUiColors.red,
                          side: const BorderSide(color: SellerUiColors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              metrics.geometry(12),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerInformationPanel extends StatelessWidget {
  const _SellerInformationPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
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
      padding: EdgeInsets.all(metrics.spacing(12)),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(color: SellerUiColors.lavenderBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: metrics.artSize(20),
            color: SellerUiColors.primaryBright,
          ),
          SizedBox(width: metrics.spacing(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: sellerText(metrics, 12.5, weight: FontWeight.w800),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  body,
                  style: sellerText(
                    metrics,
                    10.75,
                    color: SellerUiColors.body,
                    height: 1.4,
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

enum _SellerOfferImageSource { camera, library }

class _SellerOfferImageSection extends StatelessWidget {
  const _SellerOfferImageSection({
    required this.images,
    required this.onAdd,
    required this.onRemove,
    this.mediaUploadAvailable = true,
  });

  final List<String> images;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  /// False while the media upload pipeline is not connected: the action is
  /// disabled and the copy must not imply photos were attached.
  final bool mediaUploadAvailable;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isEmpty)
          Container(
            key: const Key('sellerOfferImagesEmpty'),
            padding: EdgeInsets.all(metrics.spacing(12)),
            decoration: BoxDecoration(
              color: SellerUiColors.lavender,
              borderRadius: BorderRadius.circular(metrics.geometry(10)),
              border: Border.all(color: SellerUiColors.line),
            ),
            child: Text(
              mediaUploadAvailable
                  ? 'No product images added yet. Add clear photos of the item and any included accessories.'
                  : 'Product photos aren’t connected yet, so this offer is sent without images.',
              style: sellerText(metrics, 11.5, color: SellerUiColors.body),
            ),
          )
        else
          Wrap(
            spacing: metrics.spacing(8),
            runSpacing: metrics.spacing(8),
            children: [
              for (final image in images)
                SizedBox(
                  key: ValueKey('sellerOfferImage-$image'),
                  width: metrics.geometry(112),
                  child: Stack(
                    children: [
                      Container(
                        padding: EdgeInsets.all(metrics.geometry(7)),
                        decoration: BoxDecoration(
                          color: SellerUiColors.white,
                          border: Border.all(color: SellerUiColors.line),
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(10),
                          ),
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/approved_offers_chat/chat-ipad.png',
                              width: metrics.artSize(64),
                              height: metrics.artSize(64),
                              fit: BoxFit.contain,
                            ),
                            SizedBox(height: metrics.spacing(4)),
                            Text(
                              image,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sellerText(
                                metrics,
                                9.5,
                                color: SellerUiColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          key: ValueKey('sellerOfferRemoveImage-$image'),
                          tooltip: 'Remove image',
                          constraints: BoxConstraints.tight(
                            Size(metrics.geometry(32), metrics.geometry(32)),
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () => onRemove(image),
                          icon: Icon(Icons.close, size: metrics.artSize(17)),
                          color: SellerUiColors.red,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        SizedBox(height: metrics.spacing(8)),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 280;
            return OutlinedButton(
              key: const Key('sellerOfferAddImages'),
              onPressed: mediaUploadAvailable ? onAdd : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : metrics.spacing(14),
                ),
                foregroundColor: SellerUiColors.primaryBright,
                side: const BorderSide(color: SellerUiColors.primaryBright),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    compact ? 10 : metrics.geometry(10),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: compact ? 18 : metrics.artSize(20),
                  ),
                  SizedBox(width: compact ? 6 : metrics.spacing(8)),
                  Flexible(
                    child: Text(
                      images.isEmpty
                          ? 'Add product images'
                          : 'Add another image',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sellerText(
                        metrics,
                        14,
                        weight: FontWeight.w800,
                        color: SellerUiColors.primaryBright,
                      ).copyWith(fontSize: compact ? 13 : null),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: metrics.spacing(5)),
        Text(
          mediaUploadAvailable
              ? 'Camera, gallery permissions, and storage upload connect at the backend/platform integration step.'
              : 'Photo upload isn’t connected yet. Send the offer now and add images once media upload ships.',
          key: const Key('sellerOfferImagesNotice'),
          style: sellerText(metrics, 9.5, color: SellerUiColors.muted),
        ),
      ],
    );
  }
}

class _SellerOfferImagePickerSheet extends StatelessWidget {
  const _SellerOfferImagePickerSheet({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 340;
    return SellerModalSheet(
      key: const Key('sellerOfferImagePickerSheet'),
      icon: Icons.add_photo_alternate_outlined,
      title: 'Add product images',
      subtitle: 'Choose how you want to add a photo to this offer.',
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SellerOfferImageSourceTile(
            key: const Key('sellerOfferImageCamera'),
            icon: Icons.photo_camera_outlined,
            label: 'Take a photo',
            compact: compact,
            onTap: () => Navigator.pop(context, _SellerOfferImageSource.camera),
          ),
          _SellerOfferImageSourceTile(
            key: const Key('sellerOfferImageLibrary'),
            icon: Icons.photo_library_outlined,
            label: 'Choose from library',
            compact: compact,
            onTap: () =>
                Navigator.pop(context, _SellerOfferImageSource.library),
          ),
        ],
      ),
    );
  }
}

class _SellerOfferImageSourceTile extends StatelessWidget {
  const _SellerOfferImageSourceTile({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: metrics.geometry(48)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: SellerUiColors.primaryBright,
                  size: compact ? 20 : metrics.artSize(20),
                ),
                SizedBox(width: compact ? 10 : metrics.spacing(10)),
                Expanded(
                  child: Text(
                    label,
                    style: sellerText(
                      metrics,
                      12.5,
                      weight: FontWeight.w700,
                    ).copyWith(fontSize: compact ? 12 : null),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: SellerUiColors.body,
                  size: compact ? 22 : metrics.artSize(22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferSection extends StatelessWidget {
  const _OfferSection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: metrics.geometry(32),
              height: metrics.geometry(32),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: SellerUiColors.primaryBright,
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: sellerText(
                  metrics,
                  14,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: sellerText(metrics, 17, weight: FontWeight.w800),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: sellerText(
                        metrics,
                        11,
                        color: SellerUiColors.body,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(8)),
        Padding(
          padding: EdgeInsets.only(left: metrics.geometry(40)),
          child: child,
        ),
      ],
    );
  }
}

const _prototypeMeetingPlaces = <SellerOfferPlace>[
  SellerOfferPlace(
    name: 'Cross County Mall',
    address: '8000 Mall Walk, Yonkers, NY',
    placeId: 'prototype-cross-county',
  ),
  SellerOfferPlace(
    name: 'Yonkers Public Library',
    address: '1 Larkin Center, Yonkers, NY',
    placeId: 'prototype-yonkers-library',
  ),
  SellerOfferPlace(
    name: 'Hocalist Safe Meet Center',
    address: 'Central Park Ave, Yonkers, NY',
    placeId: 'prototype-safe-meet',
  ),
];

class _SpecificLocationOption extends StatelessWidget {
  const _SpecificLocationOption({required this.place, required this.onTap});

  final SellerOfferPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Material(
      color: SellerUiColors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
      ),
      child: InkWell(
        key: ValueKey('sellerPrototypePlace-${place.placeId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        child: Padding(
          padding: EdgeInsets.all(metrics.spacing(10)),
          child: Row(
            children: [
              Container(
                width: metrics.geometry(34),
                height: metrics.geometry(34),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: SellerUiColors.lavender,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  size: metrics.artSize(18),
                  color: SellerUiColors.primaryBright,
                ),
              ),
              SizedBox(width: metrics.geometry(9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: sellerText(metrics, 12, weight: FontWeight.w800),
                    ),
                    Text(
                      place.address,
                      style: sellerText(
                        metrics,
                        10,
                        color: SellerUiColors.body,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: metrics.artSize(18),
                color: SellerUiColors.primaryBright,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MeetupChoice { business, buyer, specific }

class _OfferPlanChip extends StatelessWidget {
  const _OfferPlanChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerOfferPlanChip'),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(11),
        vertical: metrics.geometry(8),
      ),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: metrics.artSize(17),
            color: SellerUiColors.primaryBright,
          ),
          SizedBox(width: metrics.geometry(6)),
          Text(
            label,
            style: sellerText(
              metrics,
              11,
              weight: FontWeight.w800,
              color: SellerUiColors.primaryBright,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferBidCard extends StatelessWidget {
  const _OfferBidCard({
    required this.initialBid,
    required this.winningBid,
    this.compact = false,
  });

  final String initialBid;
  final String winningBid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          key: const Key('sellerOfferBidCard'),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.geometry(compact ? 8 : 12),
            vertical: metrics.geometry(compact ? 7 : 9),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE2A0),
            borderRadius: BorderRadius.circular(metrics.geometry(9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Initial bid $initialBid',
                style: sellerText(
                  metrics,
                  compact ? 9.5 : 11,
                  weight: FontWeight.w800,
                ),
              ),
              SizedBox(height: metrics.geometry(3)),
              Text(
                'Winning Bid $winningBid',
                style: sellerText(
                  metrics,
                  compact ? 9.5 : 11,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferInlineNotice extends StatelessWidget {
  const _OfferInlineNotice({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: metrics.artSize(16), color: color),
        SizedBox(width: metrics.geometry(6)),
        Flexible(
          child: Text(
            text,
            softWrap: true,
            style: sellerText(
              metrics,
              12,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfferChoice extends StatelessWidget {
  const _OfferChoice({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '$title. $subtitle',
      child: Container(
        margin: EdgeInsets.only(bottom: metrics.geometry(7)),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? SellerUiColors.primaryBright
                : SellerUiColors.line,
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
          child: Padding(
            padding: EdgeInsets.all(metrics.geometry(9)),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: SellerUiColors.primaryBright,
                ),
                SizedBox(width: metrics.geometry(7)),
                Icon(icon, color: SellerUiColors.body),
                SizedBox(width: metrics.geometry(8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: sellerText(metrics, 12, weight: FontWeight.w800),
                      ),
                      Text(
                        subtitle,
                        style: sellerText(
                          metrics,
                          10,
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
    );
  }
}

class _SpecificLocationLauncher extends StatelessWidget {
  const _SpecificLocationLauncher({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Semantics(
      selected: selected,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? SellerUiColors.primaryBright
                : SellerUiColors.line,
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
        ),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(8)),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(metrics.geometry(10)),
            child: Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  color: SellerUiColors.body,
                  size: metrics.artSize(21),
                ),
                SizedBox(width: metrics.geometry(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: sellerText(metrics, 12, weight: FontWeight.w800),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sellerText(
                            metrics,
                            10,
                            color: SellerUiColors.body,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.geometry(8)),
                Icon(
                  Icons.chevron_right,
                  color: SellerUiColors.ink,
                  size: metrics.artSize(22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferPicker extends StatelessWidget {
  const _OfferPicker({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$label. $value',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: SellerUiColors.line),
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
          child: Padding(
            padding: EdgeInsets.all(metrics.geometry(10)),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: metrics.artSize(17),
                  color: SellerUiColors.body,
                ),
                SizedBox(width: metrics.geometry(7)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: sellerText(
                          metrics,
                          9,
                          color: SellerUiColors.body,
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sellerText(metrics, 10, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferMessageField extends StatelessWidget {
  const _OfferMessageField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Stack(
          children: [
            TextField(
              key: const Key('sellerOfferMessage'),
              controller: controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 250,
              style: sellerInputText(metrics, size: 13),
              decoration: InputDecoration(
                hintText: 'Add details about your offer',
                hintStyle: sellerInputPlaceholder(metrics),
                counterText: '',
                contentPadding: EdgeInsets.fromLTRB(
                  metrics.spacing(12),
                  metrics.spacing(11),
                  metrics.spacing(12),
                  metrics.spacing(28),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            Positioned(
              right: metrics.spacing(10),
              bottom: metrics.spacing(7),
              child: IgnorePointer(
                child: Text(
                  '${value.text.characters.length}/250',
                  key: const Key('sellerOfferMessageCounter'),
                  style: sellerText(metrics, 11, color: SellerUiColors.body),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OfferHowItWorksRow extends StatelessWidget {
  const _OfferHowItWorksRow({
    required this.icon,
    required this.text,
    this.showBottomGap = true,
  });

  final IconData icon;
  final String text;
  final bool showBottomGap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: showBottomGap ? metrics.geometry(10) : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: SellerUiColors.primaryBright,
            size: metrics.artSize(18),
          ),
          SizedBox(width: metrics.geometry(9)),
          Expanded(
            child: Text(text, style: sellerText(metrics, 11, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class SellerLeadView {
  const SellerLeadView({
    required this.name,
    required this.initials,
    required this.city,
    required this.distance,
    required this.request,
    required this.description,
    required this.budget,
    required this.match,
    required this.purchases,
    required this.lastPurchase,
    required this.meeting,
    required this.avatarColor,
    required this.initialColor,
    this.requestId,
    this.requestRevision = 0,
    this.categoryId,
    this.matchReasons = const [],
    this.realMode = false,
    this.acceptsHigherOffers = false,
    this.minimumMinor,
    this.maximumMinor,
  });

  /// Builds the approved lead card from a real seller lead projection.
  factory SellerLeadView.fromProjection(
    SellerLeadProjection projection, {
    List<String> matchReasons = const [],
    bool realMode = true,
  }) {
    final distance = projection.distanceMiles;
    return SellerLeadView(
      requestId: projection.requestId,
      requestRevision: projection.requestRevision,
      categoryId: projection.categoryId,
      name: projection.buyerDisplayName,
      initials: _initialsFor(projection.buyerDisplayName),
      city: projection.areaLabel ?? 'Area not shared',
      distance: distance == null
          ? (realMode ? 'Distance unavailable' : '—')
          : '${distance.toStringAsFixed(1)} mi',
      request: projection.title,
      description: projection.description,
      budget: _budgetLabelFor(projection.budget),
      minimumMinor: projection.budget.minimum?.minorUnits,
      maximumMinor: projection.budget.maximum?.minorUnits,
      match: projection.matchPercent ?? 0,
      purchases: projection.verifiedPurchaseCount,
      lastPurchase: projection.lastCompletedItemLabel ?? 'Not shared',
      meeting: projection.preferredMeetupLabel ?? 'Public place',
      avatarColor: const Color(0xFFF0EDFF),
      initialColor: SellerUiColors.primaryBright,
      matchReasons: matchReasons,
      realMode: realMode,
      acceptsHigherOffers: projection.acceptsHigherOffers,
    );
  }

  final String name,
      initials,
      city,
      distance,
      request,
      description,
      budget,
      lastPurchase,
      meeting;
  final int? minimumMinor, maximumMinor;
  String? presetPrice({required bool high}) {
    var minor = high ? maximumMinor : minimumMinor;
    if (!realMode && minor == null) {
      final amounts = RegExp(
        r'\d+(?:\.\d+)?',
      ).allMatches(budget).map((m) => double.parse(m[0]!)).toList();
      if (amounts.isNotEmpty) {
        minor = ((high ? amounts.last : amounts.first) * 100).round();
      }
    }
    if (minor == null) return null;
    return '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  }

  final int match;
  final int? purchases;
  final Color avatarColor, initialColor;

  /// Explainable server match reasons; empty when none apply.
  final List<String> matchReasons;

  /// True when the card is built from a real projection, so prototype trust
  /// marks and rank claims are suppressed.
  final bool realMode;
  final bool acceptsHigherOffers;

  /// Authoritative request id in real mode; null for prototype leads.
  final String? requestId;

  /// Admin-managed catalogue category of the request in real mode.
  final String? categoryId;

  /// Request revision the projection was built from.
  final int requestRevision;
}

String _initialsFor(String displayName) {
  final parts = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final single = parts.first;
    return (single.length >= 2 ? single.substring(0, 2) : single).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String _budgetLabelFor(MoneyRange budget) {
  final minimum = budget.minimum;
  final maximum = budget.maximum;
  if (minimum == null && maximum == null) return 'Budget not set';
  String format(Money money) {
    final major = money.minorUnits ~/ 100;
    final cents = money.minorUnits % 100;
    return cents == 0
        ? '\$$major'
        : '\$$major.${cents.toString().padLeft(2, '0')}';
  }

  if (minimum != null && maximum != null) {
    return '${format(minimum)} – ${format(maximum)}';
  }
  if (minimum != null) return 'From ${format(minimum)}';
  return 'Up to ${format(maximum!)}';
}

const _prototypeLeads = [
  SellerLeadView(
    name: 'Maya Chen',
    initials: 'MC',
    city: 'Yonkers, NY',
    distance: '2.1 mi',
    request: 'Looking for iPad Air (5th gen)',
    description: 'Looking for a 64GB or 256GB. Good condition or like new.',
    budget: r'$350 – $500',
    match: 95,
    purchases: 12,
    lastPurchase: 'MacBook Air',
    meeting: 'Public place',
    avatarColor: Color(0xFFF0EDFF),
    initialColor: SellerUiColors.primaryBright,
  ),
  SellerLeadView(
    name: 'Alicia C.',
    initials: 'AC',
    city: 'New Rochelle, NY',
    distance: '4.7 mi',
    request: 'Need iPad Pro 11-inch',
    description: 'Looking for 128GB or higher. Works perfectly.',
    budget: r'$550 – $750',
    match: 92,
    purchases: 8,
    lastPurchase: 'iPhone 14 Pro',
    meeting: 'Seller business',
    avatarColor: Color(0xFFFFF0DF),
    initialColor: SellerUiColors.amber,
  ),
  SellerLeadView(
    name: 'Robert W.',
    initials: 'RW',
    city: 'Mount Vernon, NY',
    distance: '3.3 mi',
    request: 'iPad 10th Gen',
    description: 'Prefer 64GB. New or gently used is fine.',
    budget: r'$300 – $400',
    match: 89,
    purchases: 6,
    lastPurchase: 'AirPods Pro',
    meeting: 'Your home',
    avatarColor: Color(0xFFE3F7E9),
    initialColor: SellerUiColors.green,
  ),
];

class _SellerLeadsErrorNotice extends StatelessWidget {
  const _SellerLeadsErrorNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerLeadsError'),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(12),
        vertical: metrics.geometry(10),
      ),
      decoration: BoxDecoration(
        color: SellerUiColors.redSurface,
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(color: SellerUiColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: metrics.artSize(18),
            color: SellerUiColors.red,
          ),
          SizedBox(width: metrics.geometry(8)),
          Expanded(
            child: Text(
              message,
              style: sellerText(
                metrics,
                11,
                color: SellerUiColors.ink,
                height: 1.3,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('sellerLeadsRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: SellerUiColors.primary,
                padding: EdgeInsets.symmetric(horizontal: metrics.geometry(8)),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _OfferTimezoneField extends StatelessWidget {
  const _OfferTimezoneField({
    required this.timezones,
    required this.value,
    required this.onSelected,
  });

  final List<String> timezones;
  final String? value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    if (timezones.isEmpty) {
      return Container(
        key: const Key('sellerOfferTimezoneUnavailable'),
        padding: EdgeInsets.all(metrics.geometry(10)),
        decoration: BoxDecoration(
          color: SellerUiColors.amberSurface,
          borderRadius: BorderRadius.circular(metrics.geometry(9)),
        ),
        child: Text(
          'Meeting timezones are unavailable right now. Refresh Leads and try again.',
          style: sellerText(
            metrics,
            10,
            color: SellerUiColors.body,
            height: 1.35,
          ),
        ),
      );
    }
    String labelFor(String zone) =>
        zone.isEmpty ? 'Choose the meeting timezone' : zone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: const Key('sellerOfferTimezone'),
          icon: const Icon(Icons.public_outlined),
          label: Text(labelFor(value ?? '')),
          onPressed: () async {
            var query = '';
            final selected = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              sheetAnimationStyle: HocalistMotion.sheetStyle(context),
              builder: (sheetContext) => StatefulBuilder(
                builder: (context, setSheetState) => SellerModalSheet(
                  icon: Icons.public_outlined,
                  title: 'Meeting timezone',
                  subtitle: 'Search by city, region or timezone name.',
                  onClose: () => Navigator.pop(sheetContext),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('sellerOfferTimezoneSearch'),
                        decoration: sellerInputDecoration(
                          context,
                          hintText: 'Search timezones',
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (text) => setSheetState(
                          () => query = text.trim().toLowerCase().replaceAll(
                            ' ',
                            '_',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * .4,
                        child: ListView(
                          children: [
                            if (!timezones.any(
                              (zone) => zone.toLowerCase().contains(query),
                            ))
                              const SellerStateNotice(
                                icon: Icons.search_off,
                                title: 'No matching timezones',
                              ),
                            for (final zone in timezones.where(
                              (zone) => zone.toLowerCase().contains(query),
                            ))
                              ListTile(
                                title: Text(zone),
                                selected: zone == value,
                                trailing: zone == value
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () => Navigator.pop(sheetContext, zone),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (selected != null && context.mounted) onSelected(selected);
          },
        ),
        if (value != null) ...[
          SizedBox(height: metrics.geometry(5)),
          Text(
            'Times are scheduled in $value. Both parties accept this schedule revision.',
            key: const Key('sellerOfferTimezoneConfirmation'),
            style: sellerText(
              metrics,
              9.5,
              color: SellerUiColors.muted,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _OfferOccurrenceChooser extends StatelessWidget {
  const _OfferOccurrenceChooser({
    required this.timezoneId,
    required this.selected,
    required this.onSelected,
  });

  final String timezoneId;
  final RepeatedTimeOccurrence? selected;
  final ValueChanged<RepeatedTimeOccurrence> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerOfferOccurrenceChooser'),
      padding: EdgeInsets.all(metrics.geometry(10)),
      decoration: BoxDecoration(
        color: SellerUiColors.amberSurface,
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This local time happens twice in $timezoneId. Choose which one applies.',
            style: sellerText(
              metrics,
              10,
              color: SellerUiColors.body,
              height: 1.35,
            ),
          ),
          SizedBox(height: metrics.geometry(6)),
          Row(
            children: [
              Expanded(
                child: _OccurrenceOption(
                  key: const Key('sellerOfferOccurrenceEarlier'),
                  label: 'Earlier occurrence',
                  selected: selected == RepeatedTimeOccurrence.earlier,
                  onTap: () => onSelected(RepeatedTimeOccurrence.earlier),
                ),
              ),
              SizedBox(width: metrics.geometry(8)),
              Expanded(
                child: _OccurrenceOption(
                  key: const Key('sellerOfferOccurrenceLater'),
                  label: 'Later occurrence',
                  selected: selected == RepeatedTimeOccurrence.later,
                  onTap: () => onSelected(RepeatedTimeOccurrence.later),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccurrenceOption extends StatelessWidget {
  const _OccurrenceOption({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(metrics.geometry(38)),
        foregroundColor: selected
            ? SellerUiColors.primaryBright
            : SellerUiColors.body,
        side: BorderSide(
          color: selected ? SellerUiColors.primaryBright : SellerUiColors.line,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(9)),
        ),
      ),
      child: Text(
        label,
        style: sellerText(metrics, 10.5, weight: FontWeight.w800),
      ),
    );
  }
}
