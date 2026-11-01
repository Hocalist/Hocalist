import '../../data/phase2/maps/places_contract.dart' show PlaceSuggestion;
import 'package:hocalist/components/hocalist_loading_indicator.dart';
import '../../domain/phase2/category_answers.dart';
import '../approved/category_question_editor.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../components/pull_refresh.dart';
import '../../components/hocalist_paged_list.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../data/phase2/commercial/entitlement_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
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
import '../media/request_photo_gallery.dart';

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
    this.timezoneId,
  });

  final String name;
  final String address;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final String? timezoneId;
}

typedef SellerOfferPlacePicker =
    Future<SellerOfferPlace?> Function(BuildContext context);

@immutable
class SellerOfferPresentation {
  const SellerOfferPresentation.approvedPrototype()
    : planLabel = 'Your Pro Plan',
      initialBid = r'$1.90',
      winningBid = r'$4.75',
      remainingWinningBid = null,
      rateHint = null,
      higherOffersAllowed = false,
      defaultPrice = '550';

  const SellerOfferPresentation.real({
    this.initialBid = 'Not available',
    this.winningBid = 'Not available',
    this.planLabel = 'HocaCredit deposit batches',
    this.remainingWinningBid,
    this.rateHint,
  }) : higherOffersAllowed = false,
       defaultPrice = '';

  factory SellerOfferPresentation.fromWallet(
    CreditWalletView wallet,
    String? requestId, {
    DateTime? requestExpiresAt,
    DateTime? now,
    PlanCode? plan,
  }) {
    String hc(int minor) => '${(minor / 100).toStringAsFixed(2)} HC';
    final planName = switch (plan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro Seller',
      PlanCode.elite => 'Elite Seller',
      null => null,
    };
    SellerOfferPresentation rates(
      int initial,
      int winning,
      String source,
      String hint,
    ) => SellerOfferPresentation.real(
      planLabel: planName == null ? source : '$planName · $source',
      initialBid: hc(initial),
      winningBid: hc(winning),
      remainingWinningBid: hc(winning - initial),
      rateHint: hint,
    );
    for (final target in wallet.targets) {
      if (target.requestId == requestId &&
          (target.status == CreditTargetStatus.reserved ||
              target.status == CreditTargetStatus.initialCharged)) {
        return rates(
          target.initialMinor,
          target.winningMinor,
          'Saved deal rates',
          'This offer keeps the rates reserved for this deal.',
        );
      }
    }
    final terms = wallet.paygo;
    final remaining = requestExpiresAt?.difference(
      now ?? DateTime.now().toUtc(),
    );
    final late =
        terms != null &&
        remaining != null &&
        remaining > Duration.zero &&
        remaining <= Duration(hours: terms.lateWindowHours);
    final batches =
        wallet.batches.where((batch) => batch.fundingKind != 'paygo').toList()
          ..sort((a, b) {
            final time = a.createdAt.compareTo(b.createdAt);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    for (final batch in batches) {
      final available = batch.fundingKind == 'standard'
          ? batches
                .where(
                  (other) =>
                      other.fundingKind == 'standard' &&
                      other.initialFeeMinor == batch.initialFeeMinor &&
                      other.winningTotalMinor == batch.winningTotalMinor &&
                      other.rateVersion == batch.rateVersion,
                )
                .fold<int>(0, (sum, other) => sum + other.availableMinor)
          : batch.availableMinor;
      if (available >=
          (late ? terms.lateTotalMinor : batch.winningTotalMinor)) {
        return rates(
          late ? terms.lateTotalMinor : batch.initialFeeMinor,
          late ? terms.lateTotalMinor : batch.winningTotalMinor,
          'Wallet rates',
          late
              ? 'The final-hours rate applies to this request.'
              : 'Your deposit keeps the rates saved when it was added.',
        );
      }
    }
    if (terms != null && terms.enabled && terms.authorised) {
      return rates(
        late ? terms.lateTotalMinor : terms.initialMinor,
        late ? terms.lateTotalMinor : terms.winningMinor,
        'Pay as you go',
        late
            ? 'The final-hours rate applies to this request.'
            : 'Your saved card uses your current plan’s standard rates.',
      );
    }
    if (terms != null) {
      return rates(
        late ? terms.lateTotalMinor : terms.initialMinor,
        late ? terms.lateTotalMinor : terms.winningMinor,
        'Standard rates',
        'Add credits before sending. These are your plan’s standard rates.',
      );
    }
    return const SellerOfferPresentation.real(
      initialBid: 'Add credits',
      winningBid: 'Add credits',
    );
  }

  final String planLabel;
  final String initialBid;
  final String winningBid;
  final String? remainingWinningBid;
  final String? rateHint;
  final bool higherOffersAllowed;
  final String defaultPrice;
}

class ApprovedSellerLeadsPage extends StatefulWidget {
  const ApprovedSellerLeadsPage({
    super.key,
    this.onChooseSpecificLocation,
    this.automaticTimezone = false,
    this.resolveBusinessPlace,
    this.readBusinessAddress,
    this.onAddBusinessAddress,
    this.onOpenLocationSettings,
    this.onSearchLocations,
    this.onSelectSearchLocation,
    this.onLoadSearchLocation,
    this.onOfferSubmitted,
    this.sellerName = 'Northside Tech',
    this.offerPresentation = const SellerOfferPresentation.approvedPrototype(),
    this.leads,
    this.focusedLead,
    this.leadsLoading = false,
    this.leadsError,
    this.onRefreshLeads,
    this.categories = const <StoreCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.offerTimezones = const <String>[],
    this.onSubmitOffer,
    this.offeredRequestIds = const <String>{},
    this.onValidateLead,
    this.uploadImage,
    this.leadPaging,
    this.discoveryOrigin,
    this.discoveryOriginLoading = false,
    this.onSaveDiscoveryOrigin,
    this.onDiscoveryOriginSaved,
  });

  final SellerOfferPlacePicker? onChooseSpecificLocation;
  final bool automaticTimezone;
  final SellerOfferPlacePicker? resolveBusinessPlace;
  final String? Function()? readBusinessAddress;
  final Future<void> Function()? onAddBusinessAddress;
  final VoidCallback? onOpenLocationSettings;
  final Future<List<PlaceSuggestion>> Function(String)? onSearchLocations;
  final Future<SellerDiscoveryOriginInput> Function(PlaceSuggestion)? onSelectSearchLocation;
  final Future<SellerDiscoveryOrigin> Function()? onLoadSearchLocation;
  final Set<String> offeredRequestIds;
  final Future<SellerLeadView?> Function(SellerLeadView)? onValidateLead;
  final ValueChanged<LocalOfferRecord>? onOfferSubmitted;
  final String sellerName;
  final SellerOfferPresentation offerPresentation;

  /// Real buyer requests. Null keeps the approved prototype list.
  final List<SellerLeadView>? leads;
  final SellerLeadView? focusedLead;

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
  final _focusedLeadKey = GlobalKey();
  bool _focusActive = true;
  bool _focusPending = true;
  String _category = 'All';
  String _location = 'All';
  String _budget = 'All';
  SellerDiscoveryOrigin? _localDiscoveryOrigin;
  bool _clearingSearchArea = false;
  String? _clearSearchAreaKey;
  SellerDiscoveryOrigin? get _activeOrigin => _localDiscoveryOrigin ?? widget.discoveryOrigin;
  bool get _hasSearchArea => _activeOrigin?.areaLabel?.isNotEmpty == true || _activeOrigin?.coordinatesPresent == true;
  String get _defaultSort => widget.usesRealLeads ? 'Newest first' : 'Best match';

  Future<void> _removeSearchArea({bool clearAll = false}) async {
    if (_clearingSearchArea) return;
    final save = widget.onSaveDiscoveryOrigin;
    if (save == null) return;
    setState(() => _clearingSearchArea = true);
    _clearSearchAreaKey ??= 'discovery-origin-clear-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final saved = await save(const SellerDiscoveryOriginInput(), _clearSearchAreaKey!);
      if (!mounted) return;
      _clearSearchAreaKey = null;
      _localDiscoveryOrigin = saved;
      widget.onDiscoveryOriginSaved?.call(saved);
      _applyFilterChange(() {
        _location = 'All';
        if (clearAll) { _resetFilters(); }
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not confirm removing the search area. Please retry.'),
      ));
    } finally {
      if (mounted) setState(() => _clearingSearchArea = false);
    }
  }

  void _resetFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _query = '';
    _category = 'All';
    _location = 'All';
    _budget = 'All';
    _sort = _defaultSort;
  }

  Widget _activeFilterChips() {
    Widget chip(String id, String label, VoidCallback remove) => InputChip(
      key: Key('sellerActiveFilter-$id'), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onDeleted: _clearingSearchArea ? null : remove,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteButtonTooltipMessage: 'Remove $label',
      backgroundColor: HocalistPalette.surface(context, SellerUiColors.lavender),
      labelStyle: TextStyle(fontSize: 12, color: HocalistPalette.text(context, SellerUiColors.ink)),
      side: BorderSide(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder)),
    );
    return Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(
      spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_query.trim().isNotEmpty) chip('search', 'Search: ${_query.trim()}', () => _applyFilterChange(() {
          _searchDebounce?.cancel(); _searchController.clear(); _query = '';
        })),
        if (_categoryFilterVisible && _category != 'All') chip('category', _categoryOptions.where((option) => option.id == _category).firstOrNull?.label ?? _category, () => _applyFilterChange(() => _category = 'All')),
        if (_location != 'All') chip('location', _location, () => _applyFilterChange(() => _location = 'All')),
        if (_hasSearchArea) chip('area', '${_activeOrigin?.areaLabel ?? 'Search area'} · within ${_activeOrigin?.radiusMiles ?? 25} mi', () => unawaited(_removeSearchArea())),
        if (_budget != 'All') chip('budget', _budget, () => _applyFilterChange(() => _budget = 'All')),
        if (_sort != _defaultSort) chip('sort', _sort, () => _applyFilterChange(() => _sort = _defaultSort)),
        TextButton(key: const Key('sellerClearAllFilters'), onPressed: _clearingSearchArea ? null : () {
          if (_hasSearchArea) { unawaited(_removeSearchArea(clearAll: true)); }
          else { _applyFilterChange(_resetFilters); }
        }, child: Text(_clearingSearchArea ? 'Clearing…' : 'Clear all')),
      ],
    ));
  }

  String _sort = 'Best match';

  List<SellerLeadView> _pagedLeads = const [];
  String? _pagedCursor;
  bool _pagedLoading = false;
  bool _pagedLoadingMore = false;
  String? _pagedError;
  int _pagedToken = 0;
  Timer? _searchDebounce;
  bool _openingOffer = false;
  final Set<String> _justOfferedRequestIds = {};
  bool _hasOffer(SellerLeadView lead) =>
      lead.requestId != null &&
      (widget.offeredRequestIds.contains(lead.requestId) ||
          _justOfferedRequestIds.contains(lead.requestId));
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
  void didUpdateWidget(covariant ApprovedSellerLeadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedLead != widget.focusedLead) {
      _resetFilters();
      _focusActive = true;
      _focusPending = true;
    }
    if (oldWidget.discoveryOrigin?.revision != widget.discoveryOrigin?.revision) {
      _localDiscoveryOrigin = null;
      if (_pagedMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_reloadPagedLeads());
        });
      }
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
      budgetMinimumMinor: _budgetMinimum(_budget),
      budgetMaximumMinor: _budgetMaximum(_budget),
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
    _focusActive = false;
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
      _budget != 'All' || _hasSearchArea || _sort != _defaultSort;

  List<SellerLeadView> get _visibleLeads {
    if (_pagedMode) return _prioritizeFocusedLead(_pagedLeads);
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
    return _prioritizeFocusedLead(filtered);
  }

  List<SellerLeadView> _prioritizeFocusedLead(List<SellerLeadView> rows) {
    final focused = widget.focusedLead;
    if (focused == null || !_focusActive) return rows;
    final current = rows
        .where((row) => row.requestId == focused.requestId)
        .firstOrNull;
    return [
      current ?? focused,
      ...rows.where((row) => row.requestId != focused.requestId),
    ];
  }

  /// Budget bands compare numeric bounds when the label is parseable, so real
  /// request budgets filter correctly instead of only matching prototype text.
  bool _matchesBudgetFilter(String budget) {
    if (_budget == 'All') return true;
    final numbers = RegExp(
      r'\d+(?:\.\d+)?',
    ).allMatches(budget.replaceAll(',', '')).map((match) => double.parse(match.group(0)!)).toList();
    if (numbers.isEmpty) return true;
    final highest = numbers.reduce(
      (left, right) => left > right ? left : right,
    );
    final minimum = _budgetMinimum(_budget);
    final maximum = _budgetMaximum(_budget);
    return (minimum == null || highest * 100 >= minimum) &&
        (maximum == null || highest * 100 <= maximum);
  }

  /// Applies one filter change and re-queries the server in paged mode.
  void _applyFilterChange(VoidCallback update) {
    _focusActive = false;
    setState(update);
    if (_pagedMode) unawaited(_reloadPagedLeads());
  }

  Future<void> _openLocation() async {
    if (widget.onSaveDiscoveryOrigin != null) {
      await _openDiscoveryArea();
      return;
    }
    var area = _location == 'All' ? '' : _location;
    final fieldKey = GlobalKey<FormFieldState<String>>();
    final result = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.location_on_outlined, title: 'Location',
        subtitle: 'Search requests by city or area.',
        onClose: () => Navigator.pop(sheetContext),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(key: fieldKey, initialValue: area,
            decoration: sellerInputDecoration(sheetContext, labelText: 'City or area', hintText: 'Enter a city or area'),
            onChanged: (value) => area = value.trim()),
          const SizedBox(height: 16),
          SellerPrimaryButton(label: 'Apply location', onPressed: () => Navigator.pop(sheetContext, area)),
          TextButton(onPressed: () { area = ''; fieldKey.currentState?.didChange(''); }, child: const Text('Clear')),
        ]),
      ),
    );
    if (mounted && result != null) _applyFilterChange(() => _location = result.isEmpty ? 'All' : result);
  }

  bool _openingLocation = false;
  Future<void> _openDiscoveryArea() async {
    if (_openingLocation) return;
    final save = widget.onSaveDiscoveryOrigin;
    if (save == null) return;
    if (widget.onLoadSearchLocation != null) {
      _openingLocation = true;
      try {
        final origin = await widget.onLoadSearchLocation!();
        if (!mounted) return;
        setState(() => _localDiscoveryOrigin = origin);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load your location. Please try again.')));
        return;
      } finally { _openingLocation = false; }
    }
    final saved = await showModalBottomSheet<SellerDiscoveryOrigin>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => SellerDiscoveryOriginSheet(
        initial: _activeOrigin,
        onSearchLocations: widget.onSearchLocations,
        onSelectLocation: widget.onSelectSearchLocation,
        onSave: save,
        onAddLocation: () {
          Navigator.of(sheetContext).pop();
          widget.onOpenLocationSettings?.call();
        },
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _localDiscoveryOrigin = saved);
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
    final filterMetrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    var category = _category;
    var location = _location;
    final locationFieldKey=GlobalKey<FormFieldState<String>>();
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
                      : 'Categories are currently unavailable. You can still search by location or budget.',
                  key: const Key('sellerLeadsCategoryUnavailable'),
                  style: sellerText(
                    filterMetrics,
                    11,
                    color: SellerUiColors.body,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                key:locationFieldKey,
                initialValue:location=='All'?'':location,
                maxLength:120,
                textCapitalization:TextCapitalization.words,
                decoration:sellerInputDecoration(context,hintText:'Enter a city or area').copyWith(labelText:'City or area',helperText:'Leave blank to show all locations.',counterText:''),
                onChanged:(value)=>location=value.trim().isEmpty?'All':value.trim(),
              ),
              const SizedBox(height: 10),
              HocalistSelectMenu<String>(
                role: HocalistControlRole.seller,
                value: budget,
                options: _leadBudgetOptions,
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
                        locationFieldKey.currentState?.didChange('');
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
    if (_openingOffer || _hasOffer(lead)) return;
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
              'This request could not be confirmed as available. Please try again.';
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
        automaticTimezone: widget.automaticTimezone,
        resolveBusinessPlace: widget.resolveBusinessPlace,
        readBusinessAddress: widget.readBusinessAddress,
        onAddBusinessAddress: widget.onAddBusinessAddress,
        timezones: widget.offerTimezones,
        onSubmitOffer: widget.onSubmitOffer,
        uploadImage: widget.uploadImage,
      ),
    );
    _openingOffer = false;
    if (!mounted || submitted == null) return;
    if (lead.requestId != null) {
      setState(() => _justOfferedRequestIds.add(lead.requestId!));
    }
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
    if (_focusPending && _focusActive && widget.focusedLead != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _focusedLeadKey.currentContext;
        if (!mounted || target == null) return;
        _focusPending = false;
        Scrollable.ensureVisible(target, alignment: 0.05);
      });
    }
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
                  SizedBox(height: metrics.spacing(10)),
                  _SearchField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onClear: () {
                      _searchController.clear();
                      setState(() { _query = ''; _focusActive = false; });
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
                    onChooseLocation:()=>unawaited(_openLocation()),
                    onBudget: (value) =>
                        _applyFilterChange(() => _budget = value),
                    onSort: (value) => _applyFilterChange(() => _sort = value),
                  ),
                  if (_hasActiveFilter) _activeFilterChips(),
                  SizedBox(height: metrics.spacing(11)),
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
                      child: HocalistLoadingIndicator(
                        key: const Key('sellerLeadsLoading'),
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
                    HocalistPagedList<SellerLeadView>(
                      items: _visibleLeads,
                      resetKey: [
                        widget.focusedLead?.requestId ?? '',
                        _query,
                        _category,
                        _location,
                        _budget,
                        _sort,
                      ].join('|'),
                      hasMore: _pagedMode && _pagedCursor != null,
                      loadedCount: _pagedLeads.length,
                      loadMore: _pagedMode ? _loadMorePagedLeads : null,
                      itemBuilder: (context, lead) => Padding(
                        key: _focusActive && widget.focusedLead != null && identical(lead, _visibleLeads.first) ? _focusedLeadKey : null,
                        padding: EdgeInsets.only(bottom: metrics.spacing(12)),
                        child: _LeadCard(
                          key: Key('sellerLeadCard${lead.initials}'),
                          lead: lead,
                          alreadyOffered: _hasOffer(lead),
                          onPrepareOffer: _hasOffer(lead)
                              ? null
                              : () => _openOffer(lead),
                          onLowOffer:
                              _hasOffer(lead) ||
                                  lead.presetPrice(high: false) == null
                              ? null
                              : () => _openOffer(lead, highPreset: false),
                          onHighOffer:
                              _hasOffer(lead) ||
                                  lead.presetPrice(high: true) == null
                              ? null
                              : () => _openOffer(lead, highPreset: true),
                        ),
                      ),
                    ),
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
        const _TargetingNotice(),
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
          tooltip: 'Lead filters',
          onPressed: onFilter,
          icon: Icon(
            filtersActive
                ? Icons.filter_alt_off_outlined
                : Icons.filter_alt_outlined,
          ),
          color: HocalistPalette.text(context, SellerUiColors.primaryBright),
        ),
      ],
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
        prefixIcon: Icon(
          Icons.search,
          color: HocalistPalette.text(context, SellerUiColors.body),
        ),
        contentPadding: EdgeInsets.symmetric(vertical: metrics.geometry(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(11)),
          borderSide: BorderSide(
            color: HocalistPalette.border(
              context,
              SellerUiColors.lavenderBorder,
            ),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(11)),
          borderSide: BorderSide(
            color: HocalistPalette.border(
              context,
              SellerUiColors.primaryBright,
            ),
          ),
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
    required this.onChooseLocation,
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
  final VoidCallback onChooseLocation;
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
            values: const ['All', 'Choose location…'],
            onChanged: (value)=>value=='All'?onLocation('All'):onChooseLocation(),
          ),
          SizedBox(width: metrics.geometry(8)),
          _SellerLeadFilterMenu(
            icon: Icons.paid_outlined,
            label: budget == 'All' ? 'Budget' : budget,
            value: budget,
            values: _leadBudgetOptions,
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
      color: HocalistPalette.surface(context, SellerUiColors.white),
      surfaceTintColor: HocalistPalette.surface(context, SellerUiColors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        side: BorderSide(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
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
                          color: HocalistPalette.text(
                            context,
                            SellerUiColors.primaryBright,
                          ),
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
          color: HocalistPalette.surface(
            context,
            value == values.first
                ? Colors.transparent
                : SellerUiColors.lavender,
          ),
          border: Border.all(
            color: HocalistPalette.border(
              context,
              value == values.first
                  ? SellerUiColors.line
                  : SellerUiColors.primaryBright,
            ),
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: metrics.artSize(18),
              color: HocalistPalette.text(context, SellerUiColors.body),
            ),
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
        color: HocalistPalette.surface(context, SellerUiColors.white),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            filtered ? Icons.search_off_outlined : Icons.inbox_outlined,
            size: metrics.artSize(34),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
                      'Check back shortly.',
            textAlign: TextAlign.center,
            style: sellerText(metrics, 11.5, color: SellerUiColors.muted),
          ),
          if (!filtered && onRefresh != null) ...[
            SizedBox(height: metrics.spacing(8)),
            PullRefreshAction(
              key: const Key('sellerLeadsEmptyRefresh'),
              onRefresh: onRefresh,
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
  Widget build(BuildContext context) => IconButton(
    key: const Key('sellerLeadFeeInfo'),
    tooltip: 'How fees work',
    icon: const Icon(Icons.info_outline_rounded),
    color: HocalistPalette.text(context, SellerUiColors.primaryBright),
    onPressed: () => showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SellerModalSheet(
        icon: Icons.info_outline_rounded, title: 'How fees work',
        subtitle: 'Sending an offer does not charge the initial fee.',
        onClose: () => Navigator.pop(sheetContext),
        child: const Text(
          'The total fee uses credits from one top-up. For Free and Pro, the initial fee is charged when the buyer replies. '
          'Elite fees stay pending until a purchase confirmed with a PIN or the seven-day deadline, with eligible fees waived if no purchase happens. '
          'A confirmed purchase charges only the remaining difference. Each buyer you send an offer to uses one weekly slot.',
        ),
      ),
    ),
  );
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.onPrepareOffer,
    this.alreadyOffered = false,
    this.onLowOffer,
    this.onHighOffer,
    super.key,
  });

  final SellerLeadView lead;
  final VoidCallback? onPrepareOffer;
  final bool alreadyOffered;
  final VoidCallback? onLowOffer, onHighOffer;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          padding: EdgeInsets.all(metrics.spacing(11)),
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, SellerUiColors.white),
            border: Border.all(
              color: HocalistPalette.border(context, SellerUiColors.line),
            ),
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
                    backgroundColor: HocalistPalette.surface(
                      context,
                      lead.avatarColor,
                    ),
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
                          lead.locationSummary,
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
                        color: HocalistPalette.surface(
                          context,
                          SellerUiColors.greenSurface,
                        ),
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
                        color: HocalistPalette.surface(
                          context,
                          SellerUiColors.lavender,
                        ),
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
              CategoryAnswersView(answers: lead.categoryAnswers),
              RequestPhotoGallery(ids: lead.requestImages),
              SizedBox(height: metrics.spacing(8)),
              Row(
                children: [
                  Icon(
                    Icons.sell_outlined,
                    size: metrics.artSize(17),
                    color: HocalistPalette.text(context, SellerUiColors.body),
                  ),
                  SizedBox(width: metrics.geometry(6)),
                  Text(
                    'Budget range',
                    style: sellerText(metrics, 10, color: SellerUiColors.body),
                  ),
                  SizedBox(width: metrics.geometry(6)),
                  Expanded(
                    child: Text(
                      lead.budget,
                      textAlign: TextAlign.end,
                      style: sellerText(
                        metrics,
                        16,
                        weight: FontWeight.w800,
                        color: SellerUiColors.green,
                      ),
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
                      label: alreadyOffered ? 'Offer sent' : 'Prepare offer',
                      compact: true,
                      fontSize: 12,
                      onPressed: onPrepareOffer,
                      leading: Icon(
                        Icons.description_outlined,
                        key: Key('sellerPrepareOfferIcon${lead.initials}'),
                        color: HocalistPalette.text(context, Colors.white),
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
          color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
        side: BorderSide(
          color: HocalistPalette.border(context, SellerUiColors.primaryBright),
        ),
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
    this.automaticTimezone = false,
    this.resolveBusinessPlace,
    this.readBusinessAddress,
    this.onAddBusinessAddress,
    this.timezones = const <String>[],
    this.onSubmitOffer,
    this.uploadImage,
  });

  final SellerLeadView lead;
  final String sellerName;
  final SellerOfferPresentation presentation;
  final String? initialPrice;
  final SellerOfferPlacePicker? onChooseSpecificLocation;
  final bool automaticTimezone;
  final SellerOfferPlacePicker? resolveBusinessPlace;
  final String? Function()? readBusinessAddress;
  final Future<void> Function()? onAddBusinessAddress;
  final List<String> timezones;
  final SellerOfferSubmitter? onSubmitOffer;
  final ImageUpload? uploadImage;

  @override
  State<_SendOfferSheet> createState() => _SendOfferSheetState();
}

class _SendOfferSheetState extends State<_SendOfferSheet> {
  bool get _realMode => widget.onSubmitOffer != null;
  SellerOfferPresentation get _presentation =>
      _realMode ? _livePresentation : widget.presentation;
  SellerOfferPresentation _livePresentation =
      const SellerOfferPresentation.real(
        initialBid: 'Loading…',
        winningBid: 'Loading…',
      );

  Future<void> _loadFeePresentation() async {
    try {
      final backend = createConfiguredCommercialWalletBackend();
      if (backend == null) throw StateError('Credit read unavailable');
      final entitlementBackend = createConfiguredEntitlementBackend();
      final identity = entitlementBackend?.identity;
      final user = identity?.call();
      Future<SellerEntitlementView?> readPlan() async {
        try {
          return await entitlementBackend?.loadEntitlement();
        } catch (_) {
          return null;
        }
      }

      final reads = await Future.wait<Object?>([
        backend.loadCreditWallet(),
        readPlan(),
      ]);
      final wallet = reads[0] as CreditWalletView;
      final entitlement = reads[1] as SellerEntitlementView?;
      if (!mounted ||
          (identity != null && (user == null || identity() != user))) {
        return;
      }
      setState(
        () => _livePresentation = SellerOfferPresentation.fromWallet(
          wallet,
          widget.lead.requestId,
          requestExpiresAt: widget.lead.acceptanceExpiresAt,
          plan: entitlement?.effectivePlan,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _livePresentation = const SellerOfferPresentation.real(),
        );
      }
    }
  }

  late final TextEditingController _priceController;
  late final TextEditingController _messageController;
  late _MeetupChoice _meetupChoice =
      _realMode &&
          widget.readBusinessAddress != null &&
          widget.readBusinessAddress!() == null
      ? _MeetupChoice.specific
      : _MeetupChoice.business;
  SellerOfferPlace? _specificLocation;
  SellerOfferPlace? _businessPlace;
  bool _resolvingBusiness = false;
  DateTime _meetingDate = DateTime(2025, 5, 22);
  TimeOfDay _meetingTime = const TimeOfDay(hour: 15, minute: 0);
  String? _priceError;
  String? _submitError;
  bool _submitting = false;
  bool _closing = false;

  bool get _ownsCurrentRoute =>
      mounted && !_closing && ModalRoute.of(context)?.isCurrent == true;

  void _close([LocalOfferRecord? result]) {
    if (!_ownsCurrentRoute) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(result);
  }

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
    if (_realMode) {
      _meetingDate = DateTime.now();
      unawaited(_loadFeePresentation());
      if (widget.automaticTimezone && _meetupChoice == _MeetupChoice.business) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resolveBusiness();
        });
      }
    }
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

  Future<void> _resolveBusiness() async {
    final resolve = widget.resolveBusinessPlace;
    if (resolve == null || _resolvingBusiness) return;
    setState(() => _resolvingBusiness = true);
    try {
      final place = await resolve(context);
      if (!mounted || _meetupChoice != _MeetupChoice.business) return;
      setState(() {
        _businessPlace = place;
        _submitError = place == null
            ? 'Confirm a meeting location using Choose a specific location below.'
            : null;
        _timezoneId = place?.timezoneId;
        _occurrence = null;
      });
    } catch (_) {
      if (mounted && _meetupChoice == _MeetupChoice.business) {
        setState(() {
          _timezoneId = null;
          _submitError =
              'We could not confirm this address. Search for a specific meeting location.';
        });
      }
    } finally {
      if (mounted) setState(() => _resolvingBusiness = false);
    }
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
        _timezoneId = place.timezoneId;
        _occurrence = null;
        if (!_outcomeUncertain) _submitError = null;
      });
      return;
    }

    final place = await picker(context);
    if (!mounted || place == null) return;
    setState(() {
      _specificLocation = place;
      _meetupChoice = _MeetupChoice.specific;
      _timezoneId = place.timezoneId;
      _occurrence = null;
      if (!_outcomeUncertain) _submitError = null;
    });
  }

  Future<void> _pickSchedule(SellerSchedulePickerMode mode) async {
    final selection = await showSellerSchedulePicker(
      context: context,
      mode: mode,
      initialDate: _meetingDate,
      initialTime: _meetingTime,
      earliestDate: _realMode ? DateTime.now() : null,
    );
    if (!mounted || selection == null) return;
    setState(() {
      _meetingDate = selection.date;
      _meetingTime = selection.time;
      if (!_outcomeUncertain) _submitError = null;
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
    if (!_ownsCurrentRoute ||
        _submitting ||
        _imagePending ||
        _resolvingBusiness) {
      return;
    }
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
    _close(_displayRecord(price));
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
    if (_meetupChoice == _MeetupChoice.business &&
        widget.readBusinessAddress != null &&
        widget.readBusinessAddress!() == null) {
      setState(
        () => _submitError =
            'Add your business address or choose another meeting location.',
      );
      return;
    }
    if (_timezoneId == null) {
      setState(
        () => _submitError = widget.automaticTimezone
            ? 'Confirm the meeting location to determine its timezone.'
            : 'Choose the meeting timezone.',
      );
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
    if (!_ownsCurrentRoute) return;
    if (result.isSuccess) {
      _pendingTerms = null;
      _pendingOperationKey = null;
      _outcomeUncertain = false;
      _close(_displayRecord(price));
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
      label: _businessPlace?.name ?? '${widget.sellerName} business location',
      address: _businessPlace?.address,
      placeId: _businessPlace?.placeId,
      latitude: _businessPlace?.latitude,
      longitude: _businessPlace?.longitude,
    ),
    _MeetupChoice.buyer => MeetingPlace(
      choice: MeetupPlaceChoice.buyerLocation,
      label: widget.lead.city,
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
      brightness: Theme.of(context).brightness,
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
        color: HocalistPalette.surface(context, SellerUiColors.white),
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
                  color: HocalistPalette.surface(
                    context,
                    const Color(0xFFC6C1DD),
                  ),
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
                    metrics.spacing(16) +
                        media.viewInsets.bottom +
                        media.viewPadding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: metrics.artSize(25),
                            backgroundColor: HocalistPalette.surface(
                              context,
                              widget.lead.avatarColor,
                            ),
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
                                  widget.lead.locationSummary,
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
                            onPressed: () => _close(),
                            icon: const Icon(Icons.close),
                            color: HocalistPalette.text(
                              context,
                              SellerUiColors.ink,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: metrics.spacing(8)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _OfferPlanChip(label: _presentation.planLabel),
                      ),
                      SizedBox(height: metrics.spacing(8)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Send your offer',
                            key: const Key('sellerSendOfferHeading'),
                            textAlign: TextAlign.center,
                            style: sellerText(
                              metrics,
                              20,
                              weight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: metrics.spacing(8)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _OfferBidCard(
                              initialBid: _presentation.initialBid,
                              winningBid: _presentation.winningBid,
                              remainingWinningBid:
                                  _presentation.remainingWinningBid,
                              compact: true,
                            ),
                          ),
                          if (_presentation.rateHint case final hint?) ...[
                            SizedBox(height: metrics.spacing(6)),
                            Text(
                              hint,
                              textAlign: TextAlign.right,
                              style: sellerText(
                                metrics,
                                11,
                                color: SellerUiColors.muted,
                              ),
                            ),
                          ],
                        ],
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
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: HocalistPalette.border(
                                      context,
                                      SellerUiColors.line,
                                    ),
                                  ),
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
                              subtitle:
                                  widget.readBusinessAddress?.call() ??
                                  (_realMode
                                      ? 'Add your business address to use this location'
                                      : 'Meet at my business location'),
                              onTap: () async {
                                if (_meetupChoice == _MeetupChoice.business) {
                                  setState(
                                    () =>
                                        _meetupChoice = _MeetupChoice.specific,
                                  );
                                  _timezoneId = _specificLocation?.timezoneId;
                                  return;
                                }
                                if (_realMode &&
                                    widget.readBusinessAddress?.call() ==
                                        null) {
                                  await widget.onAddBusinessAddress?.call();
                                  if (!mounted) return;
                                  if (widget.readBusinessAddress?.call() ==
                                      null) {
                                    return;
                                  }
                                }
                                setState(() {
                                  _meetupChoice = _MeetupChoice.business;
                                  _timezoneId = null;
                                });
                                if (widget.automaticTimezone) {
                                  await _resolveBusiness();
                                }
                              },
                            ),
                            _OfferChoice(
                              key: const Key('sellerMeetupBuyer'),
                              selected: _meetupChoice == _MeetupChoice.buyer,
                              icon: Icons.location_on_outlined,
                              title: 'Buyer’s location',
                              subtitle: _meetupChoice == _MeetupChoice.buyer
                                  ? '${widget.lead.city}. Exact address shared after selection.'
                                  : 'I’ll travel to the buyer',
                              onTap: () => setState(() {
                                _meetupChoice = _MeetupChoice.buyer;
                                _timezoneId = widget.lead.buyerLocationTimezone;
                                _occurrence = null;
                                if (!_outcomeUncertain) _submitError = null;
                              }),
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
                                  onTap: () => _pickSchedule(SellerSchedulePickerMode.date),
                                ),
                              ),
                              SizedBox(width: metrics.geometry(8)),
                              Expanded(
                                child: _OfferPicker(
                                  key: const Key('sellerOfferTime'),
                                  icon: Icons.schedule_outlined,
                                  label: 'Time',
                                  value: _formattedTime,
                                  onTap: () => _pickSchedule(SellerSchedulePickerMode.time),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onSubmitOffer != null) ...[
                        SizedBox(height: metrics.spacing(10)),
                        if (widget.automaticTimezone)
                          Padding(
                            padding: EdgeInsets.only(left: metrics.geometry(40)),
                            child: SellerStateNotice(
                            icon: Icons.schedule_outlined,
                            title: _resolvingBusiness
                                ? 'Checking location…'
                                : _timezoneId == null
                                ? (_meetupChoice == _MeetupChoice.buyer
                                    ? 'Choose a meeting location'
                                    : 'Select a meeting location')
                                : 'Meeting timezone: $_timezoneId',
                            body: _timezoneId == null && _meetupChoice == _MeetupChoice.buyer
                                ? 'We could not confirm the buyer’s location. Search for a specific place to meet.'
                                : 'Meeting times use the local time at your selected location.',
                            ),
                          )
                        else
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
                            color: HocalistPalette.surface(
                              context,
                              SellerUiColors.lavender,
                            ),
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
                                    ? 'Sending holds the total fee from one eligible credit top-up. Free and Pro pay the initial fee when the buyer replies. Elite fees stay pending until a purchase is confirmed with a PIN or the seven-day deadline. Eligible fees are waived if no purchase happens.'
                                    : 'Free and Pro initial fees apply after the buyer replies. Elite fees stay pending until a purchase confirmed with a PIN or the seven-day deadline; eligible no-purchase fees are waived.',
                              ),
                              _OfferHowItWorksRow(
                                icon: Icons.emoji_events_outlined,
                                text: _realMode
                                    ? 'If the buyer confirms purchasing from you with their Hocalist PIN, only the unpaid part of your total fee is charged.'
                                    : 'If the buyer confirms the purchase with their Hocalist PIN, you’ll only pay the remaining balance needed to complete your winning bid.',
                              ),
                              _OfferHowItWorksRow(
                                icon: Icons.refresh,
                                text: _realMode
                                    ? 'Your credit top-up keeps its original rates. Held credits are released according to the meeting and expiry rules. There is no automatic \$1 charge.'
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
                              color: HocalistPalette.text(
                                context,
                                Colors.white,
                              ),
                              size: metrics.artSize(compactAction ? 17 : 19),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: metrics.spacing(12)),
                      OutlinedButton.icon(
                        key: const Key('sellerSendOfferCancel'),
                        onPressed: _submitting ? null : () => _close(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(metrics.geometry(44)),
                          foregroundColor: HocalistPalette.text(
                            context,
                            SellerUiColors.red,
                          ),
                          side: BorderSide(
                            color: HocalistPalette.border(
                              context,
                              SellerUiColors.red,
                            ),
                          ),
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
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: EdgeInsets.all(metrics.spacing(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.lavenderBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: metrics.artSize(20),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
              color: HocalistPalette.surface(context, SellerUiColors.lavender),
              borderRadius: BorderRadius.circular(metrics.geometry(10)),
              border: Border.all(
                color: HocalistPalette.border(context, SellerUiColors.line),
              ),
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
                          color: HocalistPalette.surface(
                            context,
                            SellerUiColors.white,
                          ),
                          border: Border.all(
                            color: HocalistPalette.border(
                              context,
                              SellerUiColors.line,
                            ),
                          ),
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
                          color: HocalistPalette.text(
                            context,
                            SellerUiColors.red,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: HocalistPalette.surface(
                              context,
                              Colors.white,
                            ),
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
                foregroundColor: HocalistPalette.text(
                  context,
                  SellerUiColors.primaryBright,
                ),
                side: BorderSide(
                  color: HocalistPalette.border(
                    context,
                    SellerUiColors.primaryBright,
                  ),
                ),
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
      brightness: Theme.of(context).brightness,
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
                  color: HocalistPalette.text(
                    context,
                    SellerUiColors.primaryBright,
                  ),
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
                  color: HocalistPalette.text(context, SellerUiColors.body),
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
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  SellerUiColors.primaryBright,
                ),
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
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Material(
      color: HocalistPalette.surface(context, SellerUiColors.white),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
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
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    SellerUiColors.lavender,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  size: metrics.artSize(18),
                  color: HocalistPalette.text(
                    context,
                    SellerUiColors.primaryBright,
                  ),
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
                color: HocalistPalette.text(
                  context,
                  SellerUiColors.primaryBright,
                ),
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
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: metrics.artSize(17),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
          ),
          SizedBox(width: metrics.geometry(6)),
          Flexible(
            child: Text(
              label,
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
    );
  }
}

class _OfferBidCard extends StatelessWidget {
  const _OfferBidCard({
    required this.initialBid,
    required this.winningBid,
    this.remainingWinningBid,
    this.compact = false,
  });

  final String initialBid;
  final String winningBid;
  final String? remainingWinningBid;
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
            color: HocalistPalette.surface(context, const Color(0xFFFFE2A0)),
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
                '${remainingWinningBid == null ? 'Winning Bid' : 'Winning total'} $winningBid',
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
        Icon(
          icon,
          size: metrics.artSize(16),
          color: HocalistPalette.text(context, color),
        ),
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
            color: HocalistPalette.border(
              context,
              selected ? SellerUiColors.primaryBright : SellerUiColors.line,
            ),
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
                  color: HocalistPalette.text(
                    context,
                    SellerUiColors.primaryBright,
                  ),
                ),
                SizedBox(width: metrics.geometry(7)),
                Icon(
                  icon,
                  color: HocalistPalette.text(context, SellerUiColors.body),
                ),
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
            color: HocalistPalette.border(
              context,
              selected ? SellerUiColors.primaryBright : SellerUiColors.line,
            ),
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
                  color: HocalistPalette.text(context, SellerUiColors.body),
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
                  color: HocalistPalette.text(context, SellerUiColors.ink),
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
          border: Border.all(
            color: HocalistPalette.border(context, SellerUiColors.line),
          ),
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
                  color: HocalistPalette.text(context, SellerUiColors.body),
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
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
    this.categoryAnswers = const [],
    this.requestId,
    this.requestRevision = 0,
    this.categoryId,
    this.matchReasons = const [],
    this.realMode = false,
    this.acceptsHigherOffers = false,
    this.minimumMinor,
    this.maximumMinor,
    this.buyerLocationTimezone,
    this.requestImages = const [],
    this.acceptanceExpiresAt,
  });

  final DateTime? acceptanceExpiresAt;

  /// Builds the approved lead card from a real seller lead projection.
  factory SellerLeadView.fromProjection(
    SellerLeadProjection projection, {
    List<String> matchReasons = const [],
    bool realMode = true,
  }) {
    final distance = projection.distanceMiles;
    return SellerLeadView(
      requestId: projection.requestId,
      acceptanceExpiresAt: projection.acceptanceExpiresAt,
      requestRevision: projection.requestRevision,
      categoryId: projection.categoryId,
      categoryAnswers: projection.categoryAnswers,
      name: projection.buyerDisplayName,
      initials: _initialsFor(projection.buyerDisplayName),
      city: projection.areaLabel?.trim().isNotEmpty == true
          ? projection.areaLabel!.trim() : 'Location unavailable',
      buyerLocationTimezone: projection.locationTimezone,
      requestImages: projection.imageMediaIds,
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
      lastPurchase: projection.lastCompletedItemLabel ?? (projection.verifiedPurchaseCount == 0 ? 'No purchases yet' : 'Not available'),
      meeting: projection.preferredMeetupLabel ?? 'Not specified',
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
  String get locationSummary => distance.trim().isEmpty
      ? city : '$city  •  $distance';

  final int? minimumMinor, maximumMinor;
  final String? buyerLocationTimezone;
  final List<String> requestImages;
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
  final List<CategoryAnswer> categoryAnswers;

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
        color: HocalistPalette.surface(context, SellerUiColors.redSurface),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(
          color: HocalistPalette.border(
            context,
            SellerUiColors.red.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: metrics.artSize(18),
            color: HocalistPalette.text(context, SellerUiColors.red),
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
                foregroundColor: HocalistPalette.text(
                  context,
                  SellerUiColors.primary,
                ),
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
          color: HocalistPalette.surface(context, SellerUiColors.amberSurface),
          borderRadius: BorderRadius.circular(metrics.geometry(9)),
        ),
        child: Text(
          'Meeting timezones are unavailable right now. Please try again.',
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
        SellerSecondaryButton(
          key: const Key('sellerOfferTimezone'),
          label: labelFor(value ?? ''),
          onPressed: () async {
            var query = '';
            final selected = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: HocalistPalette.surface(
                context,
                Colors.transparent,
              ),
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
        color: HocalistPalette.surface(context, SellerUiColors.amberSurface),
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
        foregroundColor: HocalistPalette.text(
          context,
          selected ? SellerUiColors.primaryBright : SellerUiColors.body,
        ),
        side: BorderSide(
          color: HocalistPalette.border(
            context,
            selected ? SellerUiColors.primaryBright : SellerUiColors.line,
          ),
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

const _leadBudgetOptions = ['All', r'Under $100', r'Under $250', r'Under $500', r'Under $1,000', r'$500+', r'$1,000+', r'$5,000+'];
int? _budgetAmount(String label) => int.tryParse(label.replaceAll(RegExp(r'[^0-9]'), ''));
int? _budgetMinimum(String label) => label.endsWith('+') ? (_budgetAmount(label)! * 100) : null;
int? _budgetMaximum(String label) => label.startsWith('Under ') ? (_budgetAmount(label)! * 100 - 1) : null;

