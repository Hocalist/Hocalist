import 'dart:convert';
import '../../domain/phase2/category_answers.dart';
import 'category_question_editor.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';
import '../../components/notification_indicator.dart';

import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/requests.dart';
import '../../theme/accessibility_visuals.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/input_foundation.dart';
import 'approved_replica_metrics.dart';
import 'buyer_bottom_navigation.dart';

const _approvedBlue = BuyerUiTokens.requestAction;
const _approvedNavy = BuyerUiTokens.requestText;
const _approvedMuted = BuyerUiTokens.muted;
const _approvedBorder = BuyerUiTokens.border;
const _approvedLavender = BuyerUiTokens.softSurface;
const _approvedSurface = BuyerUiTokens.surface;

/// Supported country choices for the request location step. United States is
/// first and default; the list is local until the admin-managed catalogue
/// supplies production values.
@immutable
class ApprovedCountryOption {
  const ApprovedCountryOption(this.code, this.label);

  final String code;
  final String label;
}

const approvedRequestCountries = <ApprovedCountryOption>[
  ApprovedCountryOption('US', 'United States'),
  ApprovedCountryOption('CA', 'Canada'),
  ApprovedCountryOption('MX', 'Mexico'),
  ApprovedCountryOption('GB', 'United Kingdom'),
  ApprovedCountryOption('IE', 'Ireland'),
  ApprovedCountryOption('AU', 'Australia'),
  ApprovedCountryOption('NZ', 'New Zealand'),
  ApprovedCountryOption('IN', 'India'),
  ApprovedCountryOption('NG', 'Nigeria'),
  ApprovedCountryOption('GH', 'Ghana'),
  ApprovedCountryOption('KE', 'Kenya'),
  ApprovedCountryOption('ZA', 'South Africa'),
  ApprovedCountryOption('DE', 'Germany'),
  ApprovedCountryOption('FR', 'France'),
  ApprovedCountryOption('ES', 'Spain'),
  ApprovedCountryOption('IT', 'Italy'),
  ApprovedCountryOption('NL', 'Netherlands'),
  ApprovedCountryOption('BR', 'Brazil'),
  ApprovedCountryOption('JP', 'Japan'),
  ApprovedCountryOption('PH', 'Philippines'),
];

const _assetRoot = 'assets/post_request';
const _productIcon = '$_assetRoot/kind-product.png';
const _serviceIcon = '$_assetRoot/kind-service.png';
const _titleIcon = '$_assetRoot/field-title-tag.png';
const _descriptionIcon = '$_assetRoot/field-description.png';
const _conditionIcon = '$_assetRoot/panel-condition.png';
const _serviceTypeIcon = '$_assetRoot/panel-service-type.png';
const _budgetIcon = '$_assetRoot/panel-budget.png';
const _quantityIcon = '$_assetRoot/panel-quantity.png';
const _categoryIcon = '$_assetRoot/panel-category.png';
const _higherOffersIcon = '$_assetRoot/panel-higher-offers.png';
const _newIcon = '$_assetRoot/choice-new.png';
const _usedIcon = '$_assetRoot/choice-used.png';
const _oneTimeIcon = '$_assetRoot/choice-one-time.png';
const _ongoingIcon = '$_assetRoot/choice-ongoing.png';
const _minimumIcon = '$_assetRoot/price-min.png';
const _maximumIcon = '$_assetRoot/price-max.png';
const _categoryGridIcon = '$_assetRoot/category-grid.png';
const _categoryDownIcon = '$_assetRoot/category-down.png';
const _selectedRadioIcon = '$_assetRoot/location-radio-selected.png';
const _buyerModeIcon = '$_assetRoot/header-buyer-down.png';
const _notificationIcon = '$_assetRoot/header-notification.png';

ApprovedReplicaMetrics _replicaMetrics(BuildContext context) {
  return ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        brightness: Theme.of(context).brightness,
        availableWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
      );
}

double _requestFontSize(
  ApprovedReplicaMetrics metrics,
  double referencePixels,
) {
  final scaled = metrics.fontSize(referencePixels);
  if (metrics.screenshotLocked) return scaled;
  return scaled < 10.5 ? 10.5 : scaled;
}

double _requestDimension(
  ApprovedReplicaMetrics metrics,
  double referencePixels, {
  required double floor,
}) {
  final scaled = metrics.geometry(referencePixels);
  if (metrics.screenshotLocked) return scaled;
  return scaled < floor ? floor : scaled;
}

double _requestControlFontSize(
  ApprovedReplicaMetrics metrics,
  double referencePixels, {
  required double floor,
}) {
  final scaled = metrics.fontSize(referencePixels);
  return scaled < floor ? floor : scaled;
}

double _requestControlHeight(
  ApprovedReplicaMetrics metrics, [
  double referencePixels = 30.47,
]) {
  final scaled = metrics.geometry(referencePixels);
  if (metrics.screenshotLocked && metrics.availableWidth < 390 && scaled < 28) {
    return 28;
  }
  return scaled;
}

enum ApprovedRequestKind { product, service }

enum _ApprovedRequestStep { details, location }

/// Submits one complete request draft and returns a user-safe outcome.
typedef RequestDraftSubmitter =
    Future<RequestSubmissionResult> Function(
      RequestDraft draft,
      String operationKey,
    );

/// Screenshot-approved buyer request editor with the existing UI-only contract.
class ApprovedRequestFlowPage extends StatefulWidget {
  const ApprovedRequestFlowPage({
    required this.accent,
    required this.requestTitle,
    required this.budget,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onBack,
    required this.onNotifications,
    required this.onSubmit,
    this.initialKind = ApprovedRequestKind.product,
    this.includeAppChrome = false,
    this.onHome,
    this.onHocatrends,
    this.onOffers,
    this.onChats,
    this.onMore,
    this.onSubmitDraft,
    this.onCreated,
    this.categories = const <CatalogueCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.initialDescription = '',
    this.homeAddress,
    this.onChooseLocation,
    this.questionLoader = loadCategoryQuestions,
    super.key,
  });

  final CategoryQuestionLoader questionLoader;
  final Color accent;
  final String requestTitle;
  final String budget;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onSubmit;
  final ApprovedRequestKind initialKind;
  final bool includeAppChrome;
  final VoidCallback? onHome;
  final VoidCallback? onHocatrends;
  final VoidCallback? onOffers;
  final VoidCallback? onChats;
  final VoidCallback? onMore;

  /// Real request submission. Null keeps the local prototype flow.
  final RequestDraftSubmitter? onSubmitDraft;

  /// Called with the server-created request after an acknowledged create.
  final ValueChanged<MarketplaceRequest>? onCreated;

  /// Server-provided catalogue categories for the real selector.
  final List<CatalogueCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final VoidCallback? onRefreshCategories;

  /// Existing description when editing; the create form starts empty.
  final String initialDescription;

  /// Buyer home address shown on the location step. Null uses the approved
  /// prototype display value.
  final PostalAddress? homeAddress;
  final Future<RequestLocation?> Function(BuildContext context)?
  onChooseLocation;

  bool get usesRealSubmission => onSubmitDraft != null;

  @override
  State<ApprovedRequestFlowPage> createState() =>
      _ApprovedRequestFlowPageState();
}

class _ApprovedRequestFlowPageState extends State<ApprovedRequestFlowPage> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription);
  late ApprovedRequestKind _kind;
  _ApprovedRequestStep _step = _ApprovedRequestStep.details;
  int _quantity = 1;
  bool _acceptHigherOffers = true;
  bool _useHomeAddress = true;
  String _condition = 'New';
  String _serviceType = 'Single';
  String _minimum = '';
  String _maximum = '';
  String? _categoryId;
  List<CategoryAnswer> _categoryAnswers = const [];
  final _questionKey = GlobalKey<CategoryQuestionEditorState>();
  String? _addressLine1;
  String? _addressLine2;
  String? _city;
  String? _state;
  String? _postalCode;
  String? _country;
  RequestLocation? _mapLocation;
  bool _choosingLocation = false;

  bool _submitting = false;
  String? _submitError;
  bool _outcomeUncertain = false;
  RequestDraft? _pendingDraft;
  String? _pendingOperationKey;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _useHomeAddress =
        !widget.usesRealSubmission ||
        (widget.homeAddress != null && widget.homeAddress!.isNotEmpty);
    final homeCountry = widget.homeAddress?.country?.trim().toUpperCase();
    _country =
        homeCountry != null && RegExp(r'^[A-Z]{2}$').hasMatch(homeCountry)
        ? homeCountry
        : 'US';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showStep(_ApprovedRequestStep step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  String get _homeAddressLine2 {
    final home = widget.homeAddress;
    if (home == null) {
      return widget.usesRealSubmission
          ? 'Add an address in your profile or choose a location below.'
          : 'Miami, FL 33101, USA';
    }
    final parts = <String>[
      if (!isBlank(home.city)) home.city!.trim(),
      if (!isBlank(home.state)) home.state!.trim(),
      if (!isBlank(home.postalCode)) home.postalCode!.trim(),
    ];
    final country = home.country?.trim();
    final line = parts.join(', ');
    if (country != null && country.isNotEmpty) {
      return line.isEmpty ? country : '$line, $country';
    }
    return line;
  }

  /// Display label for the persisted ISO two-letter country code.
  String get _countryLabel {
    final code = _country;
    if (code == null || code.isEmpty) return 'United States';
    for (final option in approvedRequestCountries) {
      if (option.code == code) return option.label;
    }
    return code;
  }

  String? get _categoryLabel {
    final id = _categoryId;
    if (id == null) return null;
    for (final option in widget.categories) {
      if (option.id == id) return option.label;
    }
    return id;
  }

  ValueChanged<String> _updateAddress(void Function(String value) assign) {
    return (value) {
      setState(() {
        assign(value);
        _mapLocation = null;
        if (value.trim().isNotEmpty) _useHomeAddress = false;
        _submitError = null;
      });
    };
  }

  int? _parseMinorUnits(String value) {
    final trimmed = value.trim().replaceAll(',', '');
    if (trimmed.isEmpty) return null;
    final amount = double.tryParse(trimmed);
    if (amount == null || amount <= 0) return null;
    return (amount * 100).round();
  }

  RequestDraft _buildDraft() {
    final minimum = _parseMinorUnits(_minimum);
    final maximum = _parseMinorUnits(_maximum);
    final budget = minimum == null && maximum == null
        ? MoneyRange.empty
        : MoneyRange(
            minimum: minimum == null
                ? null
                : Money(minorUnits: minimum, currencyCode: 'USD'),
            maximum: maximum == null
                ? null
                : Money(minorUnits: maximum, currencyCode: 'USD'),
          );
    var location = const RequestLocation.homeAddress();
    if (!_useHomeAddress) {
      final address = PostalAddress(
        line1: _addressLine1,
        line2: _addressLine2,
        city: _city,
        state: _state,
        postalCode: _postalCode,
        country: _country,
      );
      if (address.isNotEmpty) {
        location = RequestLocation.custom(address: address);
      }
      if (_mapLocation != null) location = _mapLocation!;
    }
    final isProduct = _kind == ApprovedRequestKind.product;
    return RequestDraft(
      kind: isProduct ? RequestKind.product : RequestKind.service,
      title: widget.requestTitle.trim(),
      description: _descriptionController.text.trim(),
      condition: isProduct
          ? (_condition == 'New'
                ? ProductCondition.newItem
                : ProductCondition.used)
          : null,
      serviceType: isProduct
          ? null
          : (_serviceType == 'Single'
                ? ServiceType.oneTime
                : ServiceType.ongoing),
      quantity: isProduct ? _quantity : 1,
      budget: budget,
      acceptsHigherOffers: _acceptHigherOffers,
      categoryId: _categoryId,
      categoryAnswers: _categoryAnswers,
      location: location,
    );
  }

  bool _sameDraft(RequestDraft left, RequestDraft right) =>
      left.kind == right.kind &&
      left.title == right.title &&
      left.description == right.description &&
      left.condition == right.condition &&
      left.serviceType == right.serviceType &&
      left.quantity == right.quantity &&
      left.budget == right.budget &&
      left.acceptsHigherOffers == right.acceptsHigherOffers &&
      left.categoryId == right.categoryId &&
      jsonEncode(categoryAnswerInput(left.categoryAnswers)) ==
          jsonEncode(categoryAnswerInput(right.categoryAnswers)) &&
      left.location == right.location;

  String? _detailsValidationMessage() {
    if (widget.requestTitle.trim().isEmpty) return 'Add a clear request title.';
    if (widget.usesRealSubmission &&
        (_categoryId == null ||
            !widget.categories.any(
              (c) =>
                  c.id == _categoryId &&
                  c.isActive &&
                  (_kind == ApprovedRequestKind.product
                      ? c.supportsProduct
                      : c.supportsService),
            ))) {
      return 'Choose an active category before continuing.';
    }
    final questionError = _questionKey.currentState?.validationMessage();
    if (questionError != null) return questionError;
    final minimum = _parseMinorUnits(_minimum);
    final maximum = _parseMinorUnits(_maximum);
    if (minimum != null && maximum != null && maximum < minimum) {
      return 'The maximum budget must be at least the minimum.';
    }
    final issues = _buildDraft().validationIssues();
    return issues.isEmpty ? null : issues.first.message;
  }

  void _continueToLocation() {
    final error = widget.usesRealSubmission
        ? _detailsValidationMessage()
        : null;
    setState(() => _submitError = error);
    if (error == null) _showStep(_ApprovedRequestStep.location);
  }

  String? _localValidationMessage() {
    final detailsError = _detailsValidationMessage();
    if (detailsError != null) return detailsError;
    if (widget.usesRealSubmission &&
        _useHomeAddress &&
        (widget.homeAddress == null || widget.homeAddress!.isEmpty)) {
      return 'Choose a location or add your home address in your profile.';
    }
    if (widget.requestTitle.trim().isEmpty) {
      return 'Add a clear request title.';
    }
    final minimum = _parseMinorUnits(_minimum);
    final maximum = _parseMinorUnits(_maximum);
    if (minimum != null && maximum != null && maximum < minimum) {
      return 'The maximum budget must be at least the minimum.';
    }
    if (!_useHomeAddress) {
      if (_mapLocation != null) return null;
      final country = _country?.trim();
      if (country != null &&
          country.isNotEmpty &&
          !RegExp(r'^[A-Za-z]{2}$').hasMatch(country)) {
        return 'Enter a two-letter country code (for example US).';
      }
      final address = PostalAddress(
        line1: _addressLine1,
        line2: _addressLine2,
        city: _city,
        state: _state,
        postalCode: _postalCode,
        country: _country,
      );
      if ((address.line1?.trim().isEmpty ?? true) &&
          (address.city?.trim().isEmpty ?? true)) {
        return 'Choose a location or enter an address.';
      }
    }
    return null;
  }

  Future<void> _submitRealRequest() async {
    final submitter = widget.onSubmitDraft;
    if (submitter == null) return;
    final localError = _localValidationMessage();
    if (localError != null) {
      setState(() {
        _submitError = localError;
        final detailsInvalid = _detailsValidationMessage() != null;
        _showStep(
          detailsInvalid
              ? _ApprovedRequestStep.details
              : _ApprovedRequestStep.location,
        );
      });
      return;
    }
    final draft = _buildDraft();
    final issues = draft.validationIssues();
    if (issues.isNotEmpty) {
      setState(() {
        _submitError = issues.first.message;
        _showStep(_ApprovedRequestStep.details);
      });
      return;
    }

    // An attempt whose outcome is unknown keeps its exact payload and
    // operation key: retry reconciles that intent. A changed payload must
    // discard the unresolved intent first instead of reusing its key.
    if (_outcomeUncertain) {
      if (!_sameDraft(draft, _pendingDraft!)) {
        setState(
          () => _submitError =
              'An earlier request may already have been posted. Retry to '
              'confirm it, or discard it before changing the details.',
        );
        return;
      }
    } else {
      _pendingDraft = draft;
      _pendingOperationKey = LocalMarketplaceRepository.newStoreOperationKey(
        'request-create',
      );
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final result = await submitter(_pendingDraft!, _pendingOperationKey!);
    if (!mounted) return;
    if (result.isSuccess) {
      final created = result.request!;
      _pendingDraft = null;
      _pendingOperationKey = null;
      _outcomeUncertain = false;
      setState(() => _submitting = false);
      widget.onCreated?.call(created);
      return;
    }
    setState(() {
      _submitting = false;
      _submitError = result.error;
      _outcomeUncertain = result.outcomeUncertain;
      if (!result.outcomeUncertain) {
        _pendingDraft = null;
        _pendingOperationKey = null;
      }
    });
  }

  Future<void> _chooseLocation() async {
    if (_choosingLocation || _submitting || _outcomeUncertain) return;
    final choose = widget.onChooseLocation;
    if (choose == null) return;
    setState(() => _choosingLocation = true);
    try {
      final location = await choose(context);
      if (!mounted || location == null) return;
      setState(() {
        _mapLocation = location;
        final address = location.address;
        _addressLine1 = address?.line1;
        _addressLine2 = address?.line2;
        _city = address?.city;
        _state = address?.state;
        _postalCode = address?.postalCode;
        _country = address?.country;
        _useHomeAddress = false;
        _submitError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _submitError =
              'Location could not be selected. Enter an address below.',
        );
      }
    } finally {
      if (mounted) setState(() => _choosingLocation = false);
    }
  }

  /// Abandons a request whose outcome could not be confirmed so the buyer can
  /// review the form and start a new intent.
  void _discardUncertain() {
    setState(() {
      _outcomeUncertain = false;
      _pendingDraft = null;
      _pendingOperationKey = null;
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: viewport.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return ApprovedReplicaScope(
          metrics: metrics,
          child: Builder(
            builder: (context) {
              final body = PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) widget.onBack();
                },
                child: _buildBody(context),
              );
              if (!widget.includeAppChrome) return body;
              return ApprovedBuyerRequestShell(
                scrollController: _scrollController,
                onBack: widget.onBack,
                onNotifications: widget.onNotifications,
                onHome: widget.onHome,
                onHocatrends: widget.onHocatrends,
                onOffers: widget.onOffers,
                onChats: widget.onChats,
                onMore: widget.onMore,
                child: body,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final isLocation = _step == _ApprovedRequestStep.location;
    final metrics = _replicaMetrics(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: metrics.innerContentMaxWidth(referenceHorizontalInset: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLocation) SizedBox(height: metrics.geometry(16)),
            _ApprovedPageTitle(
              title: 'Post a new request',
              onBack: widget.includeAppChrome ? null : widget.onBack,
              textAlign: !isLocation ? TextAlign.start : TextAlign.center,
            ),
            if (!isLocation) ...[
              SizedBox(height: metrics.geometry(2)),
              Text(
                'Let sellers know what you need.',
                style: _bodyStyle(context).copyWith(
                  color: HocalistPalette.text(context, _approvedMuted),
                ),
              ),
            ],
            SizedBox(
              height: _requestDimension(
                metrics,
                isLocation ? 24 : 8,
                floor: isLocation ? 20 : 10,
              ),
            ),
            if (!isLocation) ...[
              _ApprovedKindPicker(
                selected: _kind,
                onChanged: (value) => setState(() {
                  if (_kind != value) {
                    _categoryId = null;
                    _categoryAnswers = const [];
                  }
                  _kind = value;
                }),
              ),
              SizedBox(height: _requestDimension(metrics, 21, floor: 18)),
            ],
            _ApprovedStepProgress(currentStep: _step),
            SizedBox(
              height: _requestDimension(
                metrics,
                isLocation ? 38 : 28,
                floor: isLocation ? 28 : 20,
              ),
            ),
            AnimatedSwitcher(
              duration: HocalistMotion.duration(context, 160),
              child: isLocation
                  ? ApprovedLocationRequestStep(
                      key: const ValueKey('approved-location-step'),
                      isProduct: _kind == ApprovedRequestKind.product,
                      useHomeAddress: _useHomeAddress,
                      onUseHomeAddressChanged: (value) {
                        setState(() => _useHomeAddress = value);
                      },
                      onBack: () {
                        _showStep(_ApprovedRequestStep.details);
                      },
                      onSubmit: widget.usesRealSubmission
                          ? _submitRealRequest
                          : widget.onSubmit,
                      submitBusy: _submitting,
                      submitError: _submitError,
                      submitUncertain: _outcomeUncertain,
                      onDiscardUncertain: _discardUncertain,
                      onChooseLocation:
                          widget.onChooseLocation == null ||
                              _choosingLocation ||
                              _submitting ||
                              _outcomeUncertain
                          ? null
                          : _chooseLocation,
                      selectedMapAddress: !_useHomeAddress
                          ? _mapLocation?.address?.line1
                          : null,
                      homeAddressLine1:
                          widget.homeAddress?.line1 ??
                          (widget.usesRealSubmission
                              ? 'No saved home address'
                              : '123 Main Street'),
                      homeAddressLine2: _homeAddressLine2,
                      countryLabel: _countryLabel,
                      customAddress: PostalAddress(
                        line1: _addressLine1,
                        line2: _addressLine2,
                        city: _city,
                        state: _state,
                        postalCode: _postalCode,
                        country: _country,
                      ),
                      onAddressLine1Changed: _updateAddress(
                        (value) => _addressLine1 = value,
                      ),
                      onAddressLine2Changed: _updateAddress(
                        (value) => _addressLine2 = value,
                      ),
                      onCityChanged: _updateAddress((value) => _city = value),
                      onStateChanged: _updateAddress((value) => _state = value),
                      onPostalCodeChanged: _updateAddress(
                        (value) => _postalCode = value,
                      ),
                      onCountryChanged: _updateAddress(
                        (value) => _country = value,
                      ),
                    )
                  : _kind == ApprovedRequestKind.product
                  ? ApprovedProductRequestStep(
                      key: const ValueKey('approved-product-step'),
                      requestTitle: widget.requestTitle,
                      quantity: _quantity,
                      condition: _condition,
                      minimum: _minimum,
                      maximum: _maximum,
                      acceptHigherOffers: _acceptHigherOffers,
                      onTitleChanged: widget.onTitleChanged,
                      onBudgetChanged: widget.onBudgetChanged,
                      onConditionChanged: (value) {
                        setState(() => _condition = value);
                      },
                      onMinimumChanged: (value) {
                        setState(() => _minimum = value);
                      },
                      onMaximumChanged: (value) {
                        setState(() => _maximum = value);
                      },
                      onQuantityChanged: (value) {
                        setState(() => _quantity = value.clamp(1, 99));
                      },
                      onAcceptHigherOffersChanged: (value) {
                        setState(() => _acceptHigherOffers = value);
                      },
                      onBack: widget.onBack,
                      onContinue: _continueToLocation,
                      descriptionController: _descriptionController,
                      categoryId: _categoryId,
                      categoryLabel: _categoryLabel,
                      categories: widget.categories,
                      categoriesLoading: widget.categoriesLoading,
                      categoriesError: widget.categoriesError,
                      onRefreshCategories: widget.onRefreshCategories,
                      onCategorySelected: widget.usesRealSubmission
                          ? (value) {
                              setState(() {
                                _categoryId = value;
                                _categoryAnswers = const [];
                                _submitError = null;
                              });
                            }
                          : null,
                      categoryQuestions:
                          widget.usesRealSubmission && _categoryId != null
                          ? CategoryQuestionEditor(
                              key: _questionKey,
                              loader: widget.questionLoader,
                              categoryId: _categoryId!,
                              answers: _categoryAnswers,
                              onChanged: (answers) =>
                                  setState(() => _categoryAnswers = answers),
                            )
                          : null,
                      error: _submitError,
                    )
                  : ApprovedServiceRequestStep(
                      key: const ValueKey('approved-service-step'),
                      requestTitle: widget.requestTitle,
                      serviceType: _serviceType,
                      minimum: _minimum,
                      maximum: _maximum,
                      acceptHigherOffers: _acceptHigherOffers,
                      onTitleChanged: widget.onTitleChanged,
                      onBudgetChanged: widget.onBudgetChanged,
                      onServiceTypeChanged: (value) {
                        setState(() => _serviceType = value);
                      },
                      onMinimumChanged: (value) {
                        setState(() => _minimum = value);
                      },
                      onMaximumChanged: (value) {
                        setState(() => _maximum = value);
                      },
                      onAcceptHigherOffersChanged: (value) {
                        setState(() => _acceptHigherOffers = value);
                      },
                      onBack: widget.onBack,
                      onContinue: _continueToLocation,
                      descriptionController: _descriptionController,
                      categoryId: _categoryId,
                      categoryLabel: _categoryLabel,
                      categories: widget.categories,
                      categoriesLoading: widget.categoriesLoading,
                      categoriesError: widget.categoriesError,
                      onRefreshCategories: widget.onRefreshCategories,
                      onCategorySelected: widget.usesRealSubmission
                          ? (value) {
                              setState(() {
                                _categoryId = value;
                                _categoryAnswers = const [];
                                _submitError = null;
                              });
                            }
                          : null,
                      categoryQuestions:
                          widget.usesRealSubmission && _categoryId != null
                          ? CategoryQuestionEditor(
                              key: _questionKey,
                              loader: widget.questionLoader,
                              categoryId: _categoryId!,
                              answers: _categoryAnswers,
                              onChanged: (answers) =>
                                  setState(() => _categoryAnswers = answers),
                            )
                          : null,
                      error: _submitError,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApprovedProductRequestStep extends StatelessWidget {
  const ApprovedProductRequestStep({
    required this.requestTitle,
    required this.quantity,
    required this.condition,
    required this.minimum,
    required this.maximum,
    required this.acceptHigherOffers,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onConditionChanged,
    required this.onMinimumChanged,
    required this.onMaximumChanged,
    required this.onQuantityChanged,
    required this.onAcceptHigherOffersChanged,
    required this.onBack,
    required this.onContinue,
    this.descriptionController,
    this.categoryQuestions,
    this.categoryId,
    this.categoryLabel,
    this.categories = const <CatalogueCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.onCategorySelected,
    this.error,
    super.key,
  });

  final String requestTitle;
  final int quantity;
  final String condition;
  final String minimum;
  final String maximum;
  final bool acceptHigherOffers;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final ValueChanged<String> onConditionChanged;
  final ValueChanged<String> onMinimumChanged;
  final ValueChanged<String> onMaximumChanged;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<bool> onAcceptHigherOffersChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final TextEditingController? descriptionController;
  final Widget? categoryQuestions;
  final String? categoryId;
  final String? categoryLabel;
  final List<CatalogueCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final VoidCallback? onRefreshCategories;
  final ValueChanged<String>? onCategorySelected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailsStep(
      kind: ApprovedRequestKind.product,
      requestTitle: requestTitle,
      quantity: quantity,
      selectedChoice: condition,
      minimum: minimum,
      maximum: maximum,
      acceptHigherOffers: acceptHigherOffers,
      onTitleChanged: onTitleChanged,
      onBudgetChanged: onBudgetChanged,
      onChoiceChanged: onConditionChanged,
      onMinimumChanged: onMinimumChanged,
      onMaximumChanged: onMaximumChanged,
      onQuantityChanged: onQuantityChanged,
      onAcceptHigherOffersChanged: onAcceptHigherOffersChanged,
      onBack: onBack,
      onContinue: onContinue,
      descriptionController: descriptionController,
      categoryQuestions: categoryQuestions,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      categories: categories,
      categoriesLoading: categoriesLoading,
      categoriesError: categoriesError,
      onRefreshCategories: onRefreshCategories,
      onCategorySelected: onCategorySelected,
      error: error,
    );
  }
}

class ApprovedServiceRequestStep extends StatelessWidget {
  const ApprovedServiceRequestStep({
    required this.requestTitle,
    required this.serviceType,
    required this.minimum,
    required this.maximum,
    required this.acceptHigherOffers,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onServiceTypeChanged,
    required this.onMinimumChanged,
    required this.onMaximumChanged,
    required this.onAcceptHigherOffersChanged,
    required this.onBack,
    required this.onContinue,
    this.descriptionController,
    this.categoryQuestions,
    this.categoryId,
    this.categoryLabel,
    this.categories = const <CatalogueCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.onCategorySelected,
    this.error,
    super.key,
  });

  final String requestTitle;
  final String serviceType;
  final String minimum;
  final String maximum;
  final bool acceptHigherOffers;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final ValueChanged<String> onServiceTypeChanged;
  final ValueChanged<String> onMinimumChanged;
  final ValueChanged<String> onMaximumChanged;
  final ValueChanged<bool> onAcceptHigherOffersChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final TextEditingController? descriptionController;
  final Widget? categoryQuestions;
  final String? categoryId;
  final String? categoryLabel;
  final List<CatalogueCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final VoidCallback? onRefreshCategories;
  final ValueChanged<String>? onCategorySelected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailsStep(
      kind: ApprovedRequestKind.service,
      requestTitle: requestTitle,
      quantity: 1,
      selectedChoice: serviceType,
      minimum: minimum,
      maximum: maximum,
      acceptHigherOffers: acceptHigherOffers,
      onTitleChanged: onTitleChanged,
      onBudgetChanged: onBudgetChanged,
      onChoiceChanged: onServiceTypeChanged,
      onMinimumChanged: onMinimumChanged,
      onMaximumChanged: onMaximumChanged,
      onQuantityChanged: (_) {},
      onAcceptHigherOffersChanged: onAcceptHigherOffersChanged,
      onBack: onBack,
      onContinue: onContinue,
      descriptionController: descriptionController,
      categoryQuestions: categoryQuestions,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      categories: categories,
      categoriesLoading: categoriesLoading,
      categoriesError: categoriesError,
      onRefreshCategories: onRefreshCategories,
      onCategorySelected: onCategorySelected,
      error: error,
    );
  }
}

class _ApprovedDetailsStep extends StatelessWidget {
  const _ApprovedDetailsStep({
    required this.kind,
    required this.requestTitle,
    required this.quantity,
    required this.selectedChoice,
    required this.minimum,
    required this.maximum,
    required this.acceptHigherOffers,
    required this.onTitleChanged,
    required this.onBudgetChanged,
    required this.onChoiceChanged,
    required this.onMinimumChanged,
    required this.onMaximumChanged,
    required this.onQuantityChanged,
    required this.onAcceptHigherOffersChanged,
    required this.onBack,
    required this.onContinue,
    this.descriptionController,
    this.categoryQuestions,
    this.categoryId,
    this.categoryLabel,
    this.categories = const <CatalogueCategoryOption>[],
    this.categoriesLoading = false,
    this.categoriesError,
    this.onRefreshCategories,
    this.onCategorySelected,
    this.error,
  });

  final ApprovedRequestKind kind;
  final String requestTitle;
  final int quantity;
  final String selectedChoice;
  final String minimum;
  final String maximum;
  final bool acceptHigherOffers;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBudgetChanged;
  final ValueChanged<String> onChoiceChanged;
  final ValueChanged<String> onMinimumChanged;
  final ValueChanged<String> onMaximumChanged;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<bool> onAcceptHigherOffersChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final TextEditingController? descriptionController;
  final Widget? categoryQuestions;
  final String? categoryId;
  final String? categoryLabel;
  final List<CatalogueCategoryOption> categories;
  final bool categoriesLoading;
  final String? categoriesError;
  final VoidCallback? onRefreshCategories;
  final ValueChanged<String>? onCategorySelected;

  /// User-safe submission error shown above the action row.
  final String? error;

  bool get isProduct => kind == ApprovedRequestKind.product;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      children: [
        Text(
          isProduct
              ? 'Tell us more about the product you need'
              : 'Tell us more about the service you need',
          textAlign: TextAlign.center,
          maxLines: metrics.screenshotLocked && !metrics.isNarrow ? 1 : null,
          softWrap: !metrics.screenshotLocked || metrics.isNarrow,
          style: _titleStyle(context, 18),
        ),
        SizedBox(height: metrics.geometry(4.875)),
        Text(
          'The more details you provide, the better\nmatches you will receive.',
          textAlign: TextAlign.center,
          style: _bodyStyle(context).copyWith(
            color: HocalistPalette.text(context, _approvedNavy),
            fontSize: _requestFontSize(metrics, 11.5),
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        SizedBox(height: metrics.geometry(12)),
        _ApprovedFieldCard(
          title: isProduct
              ? 'What are you looking for?'
              : 'What service do you need?',
          helper: 'Give your request a clear title.',
          iconAsset: _titleIcon,
          initialValue: requestTitle,
          hint: isProduct
              ? 'e.g., iPad Air 5th Gen, 64GB, Space Gray'
              : 'e.g., House Cleaning, Car Detailing, Logo Design',
          onChanged: onTitleChanged,
        ),
        SizedBox(height: metrics.geometry(10)),
        _ApprovedFieldCard(
          title: isProduct ? 'Describe the product' : 'Describe the service',
          helper:
              'Include key details so sellers can give you accurate offers.',
          iconAsset: _descriptionIcon,
          hint: isProduct
              ? 'Describe what you need, preferred brand, model, size, color, condition, features, etc.'
              : 'Describe what you need, preferred outcome, specific requirements, etc.',
          controller: descriptionController,
          maxLines: 3,
          counterText: '0/500',
        ),
        const SizedBox.shrink(),
        _ApprovedResponsiveGrid(
          preserveColumnsAtNormalScale: true,
          referenceSpacing: 4,
          referenceRunSpacing: 6,
          children: [
            _ApprovedChoicePanel(
              iconAsset: isProduct ? _conditionIcon : _serviceTypeIcon,
              title: isProduct ? 'Condition' : 'Service Type',
              options: isProduct
                  ? const [
                      _ApprovedChoice(_newIcon, 'New'),
                      _ApprovedChoice(_usedIcon, 'Used'),
                    ]
                  : const [
                      _ApprovedChoice(_oneTimeIcon, 'Single'),
                      _ApprovedChoice(_ongoingIcon, 'Ongoing'),
                    ],
              selected: selectedChoice,
              onSelected: onChoiceChanged,
            ),
            _ApprovedBudgetPanel(
              minimum: minimum,
              maximum: maximum,
              onMinimumChanged: onMinimumChanged,
              onMaximumChanged: onMaximumChanged,
              onBudgetChanged: onBudgetChanged,
            ),
            isProduct
                ? _ApprovedQuantityPanel(
                    quantity: quantity,
                    onChanged: onQuantityChanged,
                  )
                : _ApprovedCategoryPanel(
                    options: categories,
                    selectedId: categoryId,
                    selectedLabel: categoryLabel,
                    onSelected: onCategorySelected,
                    loading: categoriesLoading,
                    error: categoriesError,
                    onRetry: onRefreshCategories,
                    supportsProduct: false,
                  ),
            _ApprovedHigherOffersPanel(
              value: acceptHigherOffers,
              onChanged: onAcceptHigherOffersChanged,
            ),
          ],
        ),
        if (isProduct && onCategorySelected != null)
          _ApprovedCategoryPanel(
            options: categories,
            selectedId: categoryId,
            selectedLabel: categoryLabel,
            onSelected: onCategorySelected,
            loading: categoriesLoading,
            error: categoriesError,
            onRetry: onRefreshCategories,
            supportsProduct: true,
          ),
        ?categoryQuestions,
        SizedBox(height: metrics.geometry(2)),
        if (error != null) ...[
          Text(
            error!,
            key: const Key('approvedRequestSubmitError'),
            style: _bodyStyle(context).copyWith(
              color: HocalistPalette.text(context, const Color(0xFFD32F2F)),
              fontSize: _requestFontSize(metrics, 11),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: metrics.geometry(6)),
        ],
        _ApprovedActionRow(
          backLabel: 'Back',
          forwardLabel: 'Continue',
          onBack: onBack,
          onForward: onContinue,
        ),
      ],
    );
  }
}

class ApprovedLocationRequestStep extends StatelessWidget {
  const ApprovedLocationRequestStep({
    required this.useHomeAddress,
    required this.onUseHomeAddressChanged,
    required this.onBack,
    required this.onSubmit,
    this.isProduct = false,
    this.homeAddressLine1 = '123 Main Street',
    this.homeAddressLine2 = 'Miami, FL 33101, USA',
    this.countryLabel = 'United States',
    this.submitBusy = false,
    this.submitError,
    this.submitUncertain = false,
    this.onDiscardUncertain,
    this.onAddressLine1Changed,
    this.onAddressLine2Changed,
    this.onCityChanged,
    this.onStateChanged,
    this.onPostalCodeChanged,
    this.onCountryChanged,
    this.onChooseLocation,
    this.selectedMapAddress,
    this.customAddress,
    super.key,
  });

  final bool useHomeAddress;
  final ValueChanged<bool> onUseHomeAddressChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final bool isProduct;
  final String homeAddressLine1;
  final String homeAddressLine2;
  final String countryLabel;

  /// True while a real submission is in flight.
  final bool submitBusy;

  /// User-safe submission error shown above the actions.
  final String? submitError;

  /// True when the last submission's outcome is unknown and must be
  /// reconciled or discarded before changing anything.
  final bool submitUncertain;
  final VoidCallback? onDiscardUncertain;

  /// Custom-address capture for real submission. Prototype callers omit them.
  final ValueChanged<String>? onAddressLine1Changed;
  final ValueChanged<String>? onAddressLine2Changed;
  final ValueChanged<String>? onCityChanged;
  final ValueChanged<String>? onStateChanged;
  final ValueChanged<String>? onPostalCodeChanged;
  final ValueChanged<String>? onCountryChanged;
  final VoidCallback? onChooseLocation;
  final String? selectedMapAddress;
  final PostalAddress? customAddress;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      children: [
        Text(
          isProduct
              ? 'Where are you looking for this product?'
              : 'Where do you need this service?',
          textAlign: TextAlign.center,
          style: _titleStyle(context, 16),
        ),
        SizedBox(height: metrics.geometry(6)),
        Text(
          'Sellers will be able to only see your\nlocation once you close the deal.',
          textAlign: TextAlign.center,
          style: _bodyStyle(context).copyWith(
            color: HocalistPalette.text(context, _approvedMuted),
            fontSize: _requestFontSize(metrics, 10),
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        SizedBox(height: metrics.geometry(27)),
        _ApprovedSurface(
          referenceHeight: 130,
          referenceVerticalPadding: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Use my home address', style: _sectionStyle(context)),
              SizedBox(height: metrics.geometry(3)),
              Text(
                'This is your default address in settings.',
                style: _smallStyle(context),
              ),
              SizedBox(height: metrics.geometry(6)),
              InkWell(
                onTap: () => onUseHomeAddressChanged(true),
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
                child: Container(
                  padding: metrics.geometryInsets(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  ),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      const Color(0xfffaf9ff),
                    ),
                    borderRadius: BorderRadius.circular(metrics.geometry(9)),
                    border: Border.all(
                      color: HocalistPalette.border(
                        context,
                        useHomeAddress ? _approvedBlue : _approvedBorder,
                      ),
                      width: metrics.geometry(useHomeAddress ? 1.5 : 1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (useHomeAddress)
                            _ApprovedAssetIcon(
                              asset: _selectedRadioIcon,
                              size: metrics.geometry(22),
                            )
                          else
                            Container(
                              key: const ValueKey(
                                'approved-location-radio-unselected',
                              ),
                              width: metrics.geometry(22),
                              height: metrics.geometry(22),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: HocalistPalette.border(
                                    context,
                                    _approvedMuted,
                                  ),
                                  width: metrics.geometry(1.5),
                                ),
                              ),
                            ),
                          SizedBox(width: metrics.geometry(7)),
                          Container(
                            width: metrics.geometry(32),
                            height: metrics.geometry(32),
                            decoration: BoxDecoration(
                              color: HocalistPalette.surface(
                                context,
                                _approvedLavender,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: BuyerGlyphIcon(
                              icon: Icons.home_outlined,
                              slotSize: _requestDimension(
                                metrics,
                                17,
                                floor: 16,
                              ),
                              color: HocalistPalette.text(
                                context,
                                _approvedBlue,
                              ),
                            ),
                          ),
                          SizedBox(width: metrics.geometry(8)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  homeAddressLine1,
                                  style: _bodyStyle(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  homeAddressLine2,
                                  style: _smallStyle(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          if (!metrics.accessibilityReflow)
                            _ApprovedRecommendedBadge(metrics: metrics),
                        ],
                      ),
                      if (metrics.accessibilityReflow) ...[
                        SizedBox(height: metrics.geometry(8)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _ApprovedRecommendedBadge(metrics: metrics),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.geometry(10)),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.geometry(18)),
              child: Text('OR', style: _smallStyle(context)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        SizedBox(height: metrics.geometry(10)),
        if (onChooseLocation != null || selectedMapAddress != null) ...[
          if (onChooseLocation != null)
            OutlinedButton(
              key: const Key('requestChooseMapLocation'),
              onPressed: onChooseLocation,
              child: const Text('Choose location on map'),
            ),
          if (selectedMapAddress != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Selected: $selectedMapAddress\nEditing an address field below replaces this selection.',
                style: _smallStyle(context),
              ),
            ),
        ],
        _ApprovedSurface(
          referenceVerticalPadding: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter a different address', style: _sectionStyle(context)),
              SizedBox(height: metrics.geometry(3)),
              Text(
                'Fill in the address where you need the service.',
                style: _smallStyle(context),
              ),
              SizedBox(height: metrics.geometry(6)),
              _ApprovedAddressField(
                label: 'Street address',
                value: customAddress?.line1,
                hint: '123 Main St',
                onChanged: onAddressLine1Changed,
              ),
              SizedBox(height: metrics.geometry(5)),
              _ApprovedAddressField(
                label: 'Apartment, suite, etc. (optional)',
                value: customAddress?.line2,
                hint: 'Apt 4B, Suite 200, etc.',
                onChanged: onAddressLine2Changed,
              ),
              SizedBox(height: metrics.geometry(5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ApprovedAddressField(
                      label: 'City',
                      value: customAddress?.city,
                      hint: 'Enter city',
                      onChanged: onCityChanged,
                    ),
                  ),
                  SizedBox(width: metrics.geometry(12)),
                  Expanded(
                    child: _ApprovedAddressField(
                      label: 'State',
                      value: customAddress?.state,
                      hint: 'Select state',
                      dropdown: true,
                      onChanged: onStateChanged,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ApprovedAddressField(
                      label: 'ZIP code',
                      value: customAddress?.postalCode,
                      hint: 'Enter ZIP code',
                      onChanged: onPostalCodeChanged,
                    ),
                  ),
                  SizedBox(width: metrics.geometry(12)),
                  Expanded(
                    child: _ApprovedAddressField(
                      label: 'Country',
                      hint: 'Select country',
                      value: countryLabel,
                      dropdown: true,
                      countryOptions: true,
                      onChanged: onCountryChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.geometry(12)),
        _ApprovedLocationActions(
          onBack: onBack,
          onSubmit: onSubmit,
          busy: submitBusy,
          error: submitError,
          uncertain: submitUncertain,
          onDiscard: onDiscardUncertain,
        ),
      ],
    );
  }
}

class _ApprovedRecommendedBadge extends StatelessWidget {
  const _ApprovedRecommendedBadge({required this.metrics});

  final ApprovedReplicaMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: metrics.geometryInsets(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _approvedLavender),
        borderRadius: BorderRadius.circular(metrics.geometry(999)),
      ),
      child: Text(
        'Recommended',
        style: _smallStyle(context).copyWith(
          color: HocalistPalette.text(context, _approvedBlue),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ApprovedBuyerRequestDetailsPage extends StatefulWidget {
  const ApprovedBuyerRequestDetailsPage({
    required this.accent,
    required this.requestTitle,
    required this.budget,
    required this.onBack,
    required this.onNotifications,
    required this.onOffers,
    this.onSaveRequest,
    this.includeAppChrome = false,
    this.locationLabel = 'Chicago, IL',
    this.onHome,
    this.onHocatrends,
    this.onChats,
    this.onMore,
    this.request,
    this.onUpdateRequest,
    this.onCloseRequest,
    this.onChooseLocation,
    this.onUpdated,
    this.bookmarkAction,
    this.questionLoader = loadCategoryQuestions,
    super.key,
  });

  final CategoryQuestionLoader questionLoader;
  final Color accent;
  final String requestTitle;
  final String budget;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onOffers;
  final VoidCallback? onSaveRequest;
  final bool includeAppChrome;
  final String locationLabel;
  final VoidCallback? onHome;
  final VoidCallback? onHocatrends;
  final VoidCallback? onChats;
  final VoidCallback? onMore;

  /// The authoritative request when a real backend is attached.
  final MarketplaceRequest? request;

  /// Real update/close commands. Null keeps the prototype preview flow.
  final RequestDraftSubmitter? onUpdateRequest;
  final Future<RequestSubmissionResult> Function(String operationKey)?
  onCloseRequest;

  /// Real place picker for a revisioned location update. Null keeps the
  /// location tile informational.
  final Future<RequestLocation?> Function(BuildContext context)?
  onChooseLocation;
  final ValueChanged<MarketplaceRequest>? onUpdated;
  final Widget? bookmarkAction;

  bool get usesRealRequest => request != null && onUpdateRequest != null;

  @override
  State<ApprovedBuyerRequestDetailsPage> createState() =>
      _ApprovedBuyerRequestDetailsPageState();
}

class _ApprovedBuyerRequestDetailsPageState
    extends State<ApprovedBuyerRequestDetailsPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _isNew = true;
  ServiceType _serviceType = ServiceType.oneTime;
  bool _acceptHigherOffers = true;
  int _quantity = 1;
  bool _saving = false;
  String? _saveError;
  bool _outcomeUncertain = false;
  RequestDraft? _pendingDraft;
  String? _pendingOperationKey;
  RequestLocation? _editedLocation;
  bool _choosingLocation = false;
  List<CategoryAnswer> _categoryAnswers = const [];
  final _questionKey = GlobalKey<CategoryQuestionEditorState>();

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    final draft = request?.draft;
    _titleController = TextEditingController(
      text: draft?.title ?? widget.requestTitle,
    );
    _descriptionController = TextEditingController(
      text:
          draft?.description ??
          'Looking for an iPad Air 5th generation or newer.\n'
              'Prefer 64GB or higher, in excellent condition.\n'
              'Must include original charger and box.\n'
              "Color doesn't matter.",
    );
    if (draft != null) {
      _categoryAnswers = draft.categoryAnswers;
      _isNew = draft.condition != ProductCondition.used;
      _serviceType = draft.serviceType ?? ServiceType.oneTime;
      _acceptHigherOffers = draft.acceptsHigherOffers;
      _quantity = draft.quantity;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String get _displayTitle =>
      widget.request?.draft.title ?? widget.requestTitle;

  String _formatMinorUnits(int minorUnits) {
    final amount = minorUnits / 100;
    return amount.truncateToDouble() == amount
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _displayBudget(String fallback) {
    final draft = widget.request?.draft;
    if (draft == null) return fallback;
    final range = draft.budget;
    if (range.isEmpty) return 'Any budget';
    final minimum = range.minimum;
    final maximum = range.maximum;
    if (minimum != null && maximum != null) {
      return '\$${_formatMinorUnits(minimum.minorUnits)} – '
          '\$${_formatMinorUnits(maximum.minorUnits)}';
    }
    if (minimum != null) {
      return 'From \$${_formatMinorUnits(minimum.minorUnits)}';
    }
    return 'Up to \$${_formatMinorUnits(maximum!.minorUnits)}';
  }

  String get _budgetMinimumLabel {
    final request = widget.request;
    if (request == null) return r'$350';
    final minimum = request.draft.budget.minimum;
    return minimum == null
        ? r'$0'
        : '\$${_formatMinorUnits(minimum.minorUnits)}';
  }

  String get _budgetMaximumLabel {
    final request = widget.request;
    if (request == null) return r'$480';
    final maximum = request.draft.budget.maximum;
    return maximum == null
        ? r'$0'
        : '\$${_formatMinorUnits(maximum.minorUnits)}';
  }

  String _displayLocation(String fallback) {
    final edited = _editedLocation;
    if (edited != null) {
      if (edited.useHomeAddress) return 'Home address';
      final address = edited.address;
      final parts = <String>[
        if (!isBlank(address?.city)) address!.city!.trim(),
        if (!isBlank(address?.state)) address!.state!.trim(),
      ];
      return parts.isEmpty ? 'Custom address' : parts.join(', ');
    }
    final draft = widget.request?.draft;
    if (draft == null) return fallback;
    if (draft.location.useHomeAddress) return 'Home address';
    final address = draft.location.address;
    final parts = <String>[
      if (!isBlank(address?.city)) address!.city!.trim(),
      if (!isBlank(address?.state)) address!.state!.trim(),
    ];
    return parts.isEmpty ? 'Custom address' : parts.join(', ');
  }

  Future<void> _chooseLocation() async {
    if (_choosingLocation || _saving || _outcomeUncertain) return;
    final choose = widget.onChooseLocation;
    if (choose == null) return;
    setState(() => _choosingLocation = true);
    try {
      final location = await choose(context);
      if (!mounted || location == null) return;
      setState(() {
        _editedLocation = location;
        _saveError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Location could not be selected. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _choosingLocation = false);
    }
  }

  RequestDraft _editedDraft() {
    final current = widget.request!.draft;
    return current.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      condition: current.kind == RequestKind.product
          ? (_isNew ? ProductCondition.newItem : ProductCondition.used)
          : null,
      serviceType: current.kind == RequestKind.service ? _serviceType : null,
      quantity: current.kind == RequestKind.product ? _quantity : 1,
      acceptsHigherOffers: _acceptHigherOffers,
      location: _editedLocation ?? current.location,
      categoryAnswers: _categoryAnswers,
    );
  }

  bool _sameDraft(RequestDraft left, RequestDraft right) =>
      left.kind == right.kind &&
      left.title == right.title &&
      left.description == right.description &&
      left.condition == right.condition &&
      left.serviceType == right.serviceType &&
      left.quantity == right.quantity &&
      left.budget == right.budget &&
      left.acceptsHigherOffers == right.acceptsHigherOffers &&
      left.categoryId == right.categoryId &&
      jsonEncode(categoryAnswerInput(left.categoryAnswers)) ==
          jsonEncode(categoryAnswerInput(right.categoryAnswers)) &&
      left.location == right.location;

  void _discardUncertain() {
    setState(() {
      _outcomeUncertain = false;
      _pendingDraft = null;
      _pendingOperationKey = null;
      _saveError = null;
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedRequestDecisionSheet(
        key: const ValueKey('approved-delete-request-sheet'),
        asset: 'assets/post_request/info.png',
        title: widget.onCloseRequest != null
            ? 'Close this request?'
            : 'Delete this request?',
        message: widget.onCloseRequest != null
            ? 'Closing stops new offers from sellers and removes the request '
                  'from your active list. Existing conversations are kept.'
            : 'Prototype preview only: nothing is removed and sellers are '
                  'not affected.',
        primaryLabel: widget.onCloseRequest != null
            ? 'Close request'
            : 'Preview delete',
        destructive: true,
        onCancel: () => Navigator.pop(sheetContext, false),
        onPrimary: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed != true || !mounted) return;
    final close = widget.onCloseRequest;
    if (close == null) {
      _message('Delete preview only - no request was removed.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final result = await close(
      LocalMarketplaceRepository.newStoreOperationKey('request-close'),
    );
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() => _saving = false);
      widget.onUpdated?.call(result.request!);
      _message('Request closed. Sellers can no longer send offers.');
      return;
    }
    setState(() {
      _saving = false;
      _saveError = result.error;
    });
  }

  Future<void> _confirmSave() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedRequestDecisionSheet(
        key: const ValueKey('approved-update-request-sheet'),
        asset: 'assets/post_request/info.png',
        title: 'Update your request?',
        message:
            'Updating changes the terms sellers see for this request. They '
            'may continue with the updated request or withdraw, and your '
            'estimated rewards may change.',
        primaryLabel: 'Update request',
        onCancel: () => Navigator.pop(sheetContext, false),
        onPrimary: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed != true || !mounted) return;
    final update = widget.onUpdateRequest;
    if (update == null) {
      widget.onSaveRequest?.call();
      _message('Request updated.');
      return;
    }
    final questionError = _questionKey.currentState?.validationMessage();
    if (questionError != null) {
      setState(() => _saveError = questionError);
      return;
    }
    final draft = _editedDraft();
    final issues = draft.validationIssues();
    if (issues.isNotEmpty) {
      setState(() => _saveError = issues.first.message);
      return;
    }
    if (_outcomeUncertain) {
      if (!_sameDraft(draft, _pendingDraft!)) {
        setState(
          () => _saveError =
              'An earlier update may already have been saved. Retry to '
              'confirm it, or discard it before changing the details.',
        );
        return;
      }
    } else {
      _pendingDraft = draft;
      _pendingOperationKey = LocalMarketplaceRepository.newStoreOperationKey(
        'request-update',
      );
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final result = await update(_pendingDraft!, _pendingOperationKey!);
    if (!mounted) return;
    if (result.isSuccess) {
      _pendingDraft = null;
      _pendingOperationKey = null;
      _outcomeUncertain = false;
      setState(() => _saving = false);
      widget.onUpdated?.call(result.request!);
      _message('Request updated.');
      return;
    }
    setState(() {
      _saving = false;
      _saveError = result.error;
      _outcomeUncertain = result.outcomeUncertain;
      if (!result.outcomeUncertain) {
        _pendingDraft = null;
        _pendingOperationKey = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: viewport.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return ApprovedReplicaScope(
          metrics: metrics,
          child: Builder(
            builder: (context) {
              final body = PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) widget.onBack();
                },
                child: _buildBody(context),
              );
              if (!widget.includeAppChrome) return body;
              return ApprovedBuyerRequestShell(
                onBack: widget.onBack,
                onNotifications: widget.onNotifications,
                onHome: widget.onHome,
                onHocatrends: widget.onHocatrends,
                onOffers: widget.onOffers,
                onChats: widget.onChats,
                onMore: widget.onMore,
                child: body,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: metrics.innerContentMaxWidth(referenceHorizontalInset: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedPageTitle(
              title: 'Request details',
              referenceFontSize: 18,
              onBack: widget.includeAppChrome ? null : widget.onBack,
            ),
            SizedBox(height: metrics.geometry(4)),
            Text(
              'Review and edit your request information.',
              style: _bodyStyle(
                context,
              ).copyWith(color: HocalistPalette.text(context, _approvedNavy)),
            ),
            SizedBox(height: metrics.geometry(13)),
            _ApprovedRequestSummary(
              requestTitle: _displayTitle,
              budget: _displayBudget(widget.budget),
              location: _displayLocation(widget.locationLabel),
              onDelete: _confirmDelete,
              isReal: widget.usesRealRequest,
              status: widget.request?.status,
            ),
            SizedBox(height: metrics.geometry(14)),
            Text('Edit your request', style: _titleStyle(context, 16)),
            SizedBox(height: metrics.geometry(4)),
            _ApprovedEditPanel(
              referenceHeight: 93,
              iconAsset: _titleIcon,
              title: 'What are you looking for?',
              helper: 'Give your request a clear title.',
              onEdit: () => _message('Edit the request title below.'),
              child: TextField(
                key: const Key('request-title-field'),
                controller: _titleController,
                style: _bodyStyle(context),
                decoration: _inputDecoration(context, compact: true),
              ),
            ),
            SizedBox(height: metrics.geometry(8)),
            _ApprovedEditPanel(
              referenceHeight: 136,
              iconAsset: _descriptionIcon,
              title: widget.request?.draft.kind == RequestKind.service
                  ? 'Describe the service'
                  : 'Describe the product',
              helper:
                  'Include key details so sellers can give you accurate offers.',
              trailing: '${_descriptionController.text.length}/500',
              onEdit: () => _message('Edit the description below.'),
              child: TextField(
                key: const Key('request-description-field'),
                controller: _descriptionController,
                maxLength: 500,
                minLines: 4,
                maxLines: 4,
                style: _bodyStyle(context),
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(
                  context,
                  compact: true,
                ).copyWith(counterText: ''),
              ),
            ),
            if (widget.usesRealRequest &&
                widget.request!.draft.categoryId != null)
              CategoryQuestionEditor(
                key: _questionKey,
                loader: widget.questionLoader,
                categoryId: widget.request!.draft.categoryId!,
                answers: _categoryAnswers,
                onChanged: (answers) =>
                    setState(() => _categoryAnswers = answers),
              ),
            SizedBox(height: metrics.geometry(10)),
            _ApprovedResponsiveGrid(
              preserveColumnsAtNormalScale: true,
              referenceSpacing: 4,
              referenceRunSpacing: 4,
              children: [
                _ApprovedDetailChoicePanel(
                  referenceHeight: 86,
                  iconAsset: widget.request?.draft.kind == RequestKind.service
                      ? _serviceTypeIcon
                      : _conditionIcon,
                  title: widget.request?.draft.kind == RequestKind.service
                      ? 'Service Type'
                      : 'Condition',
                  helper: 'Select your preference',
                  onEdit: () => _message(
                    widget.request?.draft.kind == RequestKind.service
                        ? 'Choose Single or Ongoing below.'
                        : 'Choose New or Used below.',
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ApprovedTextChoice(
                          label:
                              widget.request?.draft.kind == RequestKind.service
                              ? 'Single'
                              : 'New',
                          selected:
                              widget.request?.draft.kind == RequestKind.service
                              ? _serviceType == ServiceType.oneTime
                              : _isNew,
                          onTap: () => setState(() {
                            _isNew = true;
                            _serviceType = ServiceType.oneTime;
                          }),
                        ),
                      ),
                      SizedBox(width: metrics.geometry(8)),
                      Expanded(
                        child: _ApprovedTextChoice(
                          label:
                              widget.request?.draft.kind == RequestKind.service
                              ? 'Ongoing'
                              : 'Used',
                          selected:
                              widget.request?.draft.kind == RequestKind.service
                              ? _serviceType == ServiceType.ongoing
                              : !_isNew,
                          onTap: () => setState(() {
                            _isNew = false;
                            _serviceType = ServiceType.ongoing;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                _ApprovedDetailBudgetPanel(
                  referenceHeight: 86,
                  onEdit: () => _message('Edit the budget range below.'),
                  minimumLabel: _budgetMinimumLabel,
                  maximumLabel: _budgetMaximumLabel,
                ),
                if (widget.request?.draft.kind != RequestKind.service)
                  _ApprovedDetailQuantityPanel(
                    referenceHeight: 97,
                    quantity: _quantity,
                    onChanged: (value) => setState(() => _quantity = value),
                  ),
                _ApprovedDetailChoicePanel(
                  referenceHeight: 97,
                  iconAsset: _higherOffersIcon,
                  title: 'Willing to receive higher offers?',
                  helper: 'Allow sellers to offer above your budget.',
                  child: Row(
                    children: [
                      Expanded(
                        child: _ApprovedTextChoice(
                          label: 'No, stay on budget',
                          selected: !_acceptHigherOffers,
                          onTap: () {
                            setState(() => _acceptHigherOffers = false);
                          },
                        ),
                      ),
                      SizedBox(width: metrics.geometry(8)),
                      Expanded(
                        child: _ApprovedTextChoice(
                          label: "Yes, I'm open",
                          selected: _acceptHigherOffers,
                          onTap: () {
                            setState(() => _acceptHigherOffers = true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.geometry(8)),
            _ApprovedResponsiveGrid(
              preserveColumnsAtNormalScale: true,
              referenceSpacing: 4,
              referenceRunSpacing: 4,
              children: [
                _ApprovedLocationSummary(
                  referenceHeight: 69,
                  location: _displayLocation(widget.locationLabel),
                  onTap: widget.usesRealRequest
                      ? (widget.onChooseLocation == null
                            ? () => _message(
                                'Location editing is unavailable for this request.',
                              )
                            : () => _chooseLocation())
                      : () => _message('Location editor preview opened.'),
                ),
                if (widget.usesRealRequest)
                  _ApprovedRealOffersPanel(onOffers: widget.onOffers)
                else
                  _ApprovedRewardsPanel(
                    referenceHeight: 69,
                    onOffers: widget.onOffers,
                  ),
              ],
            ),
            if (_saveError != null) ...[
              SizedBox(height: metrics.geometry(5)),
              Text(
                _saveError!,
                key: const Key('requestSaveError'),
                style: _bodyStyle(context).copyWith(
                  color: HocalistPalette.text(context, const Color(0xFFD32F2F)),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_outcomeUncertain) ...[
                SizedBox(height: metrics.geometry(4)),
                TextButton(
                  key: const Key('requestDiscardAttempt'),
                  onPressed: _saving ? null : _discardUncertain,
                  child: const Text('Discard this attempt'),
                ),
              ],
            ],
            SizedBox(height: metrics.geometry(5)),
            if (widget.bookmarkAction != null) widget.bookmarkAction!,
            _ApprovedSavePanel(onSave: _confirmSave, busy: _saving),
          ],
        ),
      ),
    );
  }
}

class ApprovedBuyerRequestShell extends StatelessWidget {
  const ApprovedBuyerRequestShell({
    required this.child,
    required this.onBack,
    required this.onNotifications,
    this.scrollController,
    this.onHome,
    this.onHocatrends,
    this.onOffers,
    this.onChats,
    this.onMore,
    super.key,
  });

  final Widget child;
  final ScrollController? scrollController;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback? onHome;
  final VoidCallback? onHocatrends;
  final VoidCallback? onOffers;
  final VoidCallback? onChats;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final canvasWidth = metrics.contentMaxWidth;
    return Scaffold(
      backgroundColor: HocalistPalette.surface(context, Colors.white),
      body: SafeArea(
        child: Column(
          children: [
            Center(
              child: SizedBox(
                width: canvasWidth,
                child: Padding(
                  padding: metrics.geometryInsets(
                    const EdgeInsets.fromLTRB(14, 2, 12, 0),
                  ),
                  child: _ApprovedGlobalHeader(
                    onBack: onBack,
                    onNotifications: onNotifications,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                key: const Key('approved-request-scroll'),
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  Center(
                    child: SizedBox(
                      width: canvasWidth,
                      child: Padding(
                        padding: metrics.geometryInsets(
                          const EdgeInsets.fromLTRB(24, 0, 24, 0),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: HocalistPalette.surface(context, Colors.white),
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            width: canvasWidth,
            child: BuyerBottomNavigation(
              selected: ApprovedBuyerNavSelection.home,
              accentColor: _approvedBlue,
              callbacks: ApprovedBuyerNavigation(
                onHome: onHome ?? () {},
                onHocatrends: onHocatrends ?? () {},
                onOffers: onOffers ?? () {},
                onChats: onChats ?? () {},
                onMore: onMore ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedGlobalHeader extends StatelessWidget {
  const _ApprovedGlobalHeader({
    required this.onBack,
    required this.onNotifications,
  });

  final VoidCallback onBack;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: metrics.geometry(58.5),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  constraints: BoxConstraints.tightFor(
                    width: metrics.geometry(41.5),
                    height: metrics.geometry(41.5),
                  ),
                  padding: EdgeInsets.zero,
                  icon: BuyerGlyphIcon(
                    icon: Icons.arrow_back,
                    slotSize: metrics.geometry(25.6),
                    color: HocalistPalette.text(context, _approvedNavy),
                  ),
                ),
              ),
              Positioned(
                left: metrics.geometry(43),
                right: constraints.maxWidth * .48,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/brand/hocalist-wordmark.png',
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xfff3f3ff)
                        : null,
                    width: metrics.artSize(88),
                    height: metrics.artSize(54),
                    fit: BoxFit.contain,
                    semanticLabel: 'Hocalist Reverse Marketplace',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: metrics.geometry(36.56),
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.geometry(7.31),
                      ),
                      decoration: BoxDecoration(
                        color: HocalistPalette.surface(
                          context,
                          _approvedLavender,
                        ),
                        borderRadius: BorderRadius.circular(
                          metrics.geometry(999),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ApprovedAssetIcon(
                            asset: _buyerModeIcon,
                            size: metrics.geometry(18.28),
                          ),
                          SizedBox(width: metrics.geometry(3.66)),
                          Text(
                            metrics.accessibilityReflow ||
                                    metrics.availableWidth < 390 ||
                                    MediaQuery.textScalerOf(context).scale(12) >
                                        13.2
                                ? 'Buyer'
                                : 'Buyer mode',
                            maxLines: 1,
                            softWrap: false,
                            style: _smallStyle(context).copyWith(
                              color: HocalistPalette.text(
                                context,
                                _approvedBlue,
                              ),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.geometry(2.44)),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: onNotifications,
                      constraints: BoxConstraints.tightFor(
                        width: metrics.geometry(39),
                        height: metrics.geometry(39),
                      ),
                      padding: EdgeInsets.zero,
                      icon: NotificationArtwork(
                        child: _ApprovedAssetIcon(
                          asset: _notificationIcon,
                          size: metrics.geometry(28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ApprovedKindPicker extends StatelessWidget {
  const _ApprovedKindPicker({required this.selected, required this.onChanged});

  final ApprovedRequestKind selected;
  final ValueChanged<ApprovedRequestKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final product = _ApprovedKindCard(
          selected: selected == ApprovedRequestKind.product,
          iconAsset: _productIcon,
          title: 'Product',
          subtitle: 'I want to buy a product',
          onTap: () => onChanged(ApprovedRequestKind.product),
        );
        final service = _ApprovedKindCard(
          selected: selected == ApprovedRequestKind.service,
          iconAsset: _serviceIcon,
          title: 'Service',
          subtitle: 'I need a service',
          onTap: () => onChanged(ApprovedRequestKind.service),
        );
        if (metrics.accessibilityReflow) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.geometry(11)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                product,
                SizedBox(height: metrics.geometry(7)),
                service,
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.geometry(11)),
          child: Row(
            children: [
              Expanded(child: product),
              SizedBox(width: metrics.geometry(7)),
              Expanded(child: service),
            ],
          ),
        );
      },
    );
  }
}

class _ApprovedKindCard extends StatelessWidget {
  const _ApprovedKindCard({
    required this.selected,
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(
            context,
            selected ? const Color(0xfff8f7ff) : Colors.white,
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
            child: AnimatedContainer(
              duration: HocalistMotion.duration(context, 180),
              constraints: BoxConstraints(
                minHeight: _requestDimension(metrics, 62, floor: 58),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: _requestDimension(metrics, 8, floor: 7),
                vertical: _requestDimension(metrics, 8, floor: 7),
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(metrics.geometry(8)),
                border: Border.all(
                  color: HocalistPalette.border(
                    context,
                    selected ? _approvedBlue : _approvedBorder,
                  ),
                  width: metrics.geometry(selected ? 1.5 : 1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ApprovedAssetIcon(
                        asset: iconAsset,
                        size: _requestDimension(
                          metrics,
                          BuyerIconTokens.control + 2,
                          floor: 22,
                        ),
                      ),
                      SizedBox(width: metrics.geometry(4.875)),
                      Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        style: _sectionStyle(
                          context,
                        ).copyWith(fontSize: _requestFontSize(metrics, 12)),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.geometry(2.44)),
                  Text(
                    subtitle,
                    maxLines: metrics.screenshotLocked ? 1 : null,
                    softWrap: !metrics.screenshotLocked,
                    textAlign: TextAlign.center,
                    style: _smallStyle(context).copyWith(
                      color: HocalistPalette.text(
                        context,
                        selected ? _approvedBlue : _approvedNavy,
                      ),
                      fontSize: _requestFontSize(metrics, 11),
                      fontWeight: FontWeight.w800,
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

class _ApprovedStepProgress extends StatelessWidget {
  const _ApprovedStepProgress({required this.currentStep});

  final _ApprovedRequestStep currentStep;

  @override
  Widget build(BuildContext context) {
    final location = currentStep == _ApprovedRequestStep.location;
    final metrics = _replicaMetrics(context);
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final insetProgress = ((scale - 1) / .3).clamp(0.0, 1.0);
    return Padding(
      padding: metrics.accessibilityReflow
          ? EdgeInsets.symmetric(horizontal: metrics.geometry(8))
          : metrics.geometryInsets(
              EdgeInsets.only(
                left: 75.56 + (28 - 75.56) * insetProgress,
                right: 104.81 + (28 - 104.81) * insetProgress,
              ),
            ),
      child: Row(
        children: [
          const _ApprovedStepDot(
            key: ValueKey('approved-request-step-1'),
            number: '1',
            label: 'Details',
            active: true,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: metrics.geometry(13.4)),
              child: Container(
                key: const ValueKey('approved-request-step-connector'),
                height: metrics.geometry(2.44),
                color: HocalistPalette.surface(context, _approvedBlue),
              ),
            ),
          ),
          _ApprovedStepDot(
            key: const ValueKey('approved-request-step-2'),
            number: '2',
            label: 'Location',
            active: location,
          ),
        ],
      ),
    );
  }
}

class _ApprovedStepDot extends StatelessWidget {
  const _ApprovedStepDot({
    required this.number,
    required this.label,
    required this.active,
    super.key,
  });

  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      children: [
        Container(
          width: _requestDimension(metrics, 28, floor: 26),
          height: _requestDimension(metrics, 28, floor: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HocalistPalette.surface(
              context,
              active ? _approvedBlue : const Color(0xffe7e8ee),
            ),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: _bodyStyle(context).copyWith(
              color: HocalistPalette.text(
                context,
                active ? Colors.white : _approvedNavy,
              ),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: metrics.geometry(2.44)),
        Text(
          label,
          style: _smallStyle(context).copyWith(
            color: HocalistPalette.text(
              context,
              active ? _approvedBlue : _approvedNavy,
            ),
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ApprovedFieldCard extends StatelessWidget {
  const _ApprovedFieldCard({
    required this.title,
    required this.helper,
    required this.iconAsset,
    required this.hint,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.maxLines = 1,
    this.counterText,
  });

  final String title;
  final String helper;
  final String iconAsset;
  final String hint;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final String? counterText;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final multiline = maxLines > 1;
    final effectiveLines = maxLines;
    final lockedInputHeight = _requestDimension(metrics, 76, floor: 74);
    final input = TextFormField(
      initialValue: controller == null ? initialValue : null,
      controller: controller,
      onChanged: onChanged,
      minLines: effectiveLines,
      maxLines: effectiveLines,
      textAlignVertical: multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: _requestInputStyle(context),
      decoration: _inputDecoration(context).copyWith(
        hintText: hint,
        hintMaxLines: effectiveLines,
        hintStyle: _requestHintStyle(context),
        contentPadding: multiline
            ? EdgeInsets.symmetric(
                horizontal: _requestDimension(
                  metrics,
                  HocalistInputTokens.horizontalPadding,
                  floor: 12,
                ),
                vertical: _requestDimension(
                  metrics,
                  HocalistInputTokens.compactVerticalPadding,
                  floor: 9,
                ),
              )
            : null,
        prefixIconConstraints: BoxConstraints(
          minWidth: _requestDimension(metrics, 32, floor: 30),
          minHeight: multiline ? lockedInputHeight : 44,
        ),
        prefixIcon: Container(
          width: _requestDimension(metrics, 32, floor: 30),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: HocalistPalette.border(context, const Color(0xffedf0f8)),
                width: metrics.geometry(1),
              ),
            ),
          ),
          child: _ApprovedAssetIcon(
            asset: iconAsset,
            size: _requestDimension(metrics, 17, floor: 15),
          ),
        ),
      ),
    );
    return _ApprovedSurface(
      referenceHeight: multiline ? 130 : 94,
      referenceVerticalPadding: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: _sectionStyle(context)),
          SizedBox(height: metrics.geometry(multiline ? 2 : 1.22)),
          Text(
            helper,
            style: _smallStyle(context).copyWith(
              color: HocalistPalette.text(context, _approvedNavy),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: metrics.geometry(multiline ? 4 : 2)),
          if (metrics.screenshotLocked && multiline)
            SizedBox(
              height: lockedInputHeight,
              child: Stack(
                children: [
                  Positioned.fill(child: input),
                  if (counterText != null)
                    Positioned(
                      right: metrics.geometry(9),
                      bottom: metrics.geometry(7),
                      child: IgnorePointer(
                        child: Text(
                          counterText!,
                          style: _smallStyle(context).copyWith(
                            color: HocalistPalette.text(context, _approvedNavy),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            input,
        ],
      ),
    );
  }
}

class _ApprovedResponsiveGrid extends StatelessWidget {
  const _ApprovedResponsiveGrid({
    required this.children,
    this.referenceRunSpacing = 9.75,
    this.referenceSpacing = 8.53,
    this.preserveColumnsAtNormalScale = false,
  });

  final List<Widget> children;
  final double referenceRunSpacing;
  final double referenceSpacing;
  final bool preserveColumnsAtNormalScale;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            metrics.screenshotLocked &&
            (preserveColumnsAtNormalScale || !metrics.isNarrow);
        final spacing = metrics.geometry(referenceSpacing);
        final scaledRunSpacing = metrics.geometry(referenceRunSpacing);
        final runSpacing =
            metrics.screenshotLocked &&
                metrics.availableWidth < 390 &&
                scaledRunSpacing < 4
            ? 4.0
            : scaledRunSpacing;
        final width = columns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        if (columns && preserveColumnsAtNormalScale) {
          final rows = <Widget>[];
          for (var index = 0; index < children.length; index += 2) {
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: children[index]),
                    if (index + 1 < children.length) ...[
                      SizedBox(width: spacing),
                      Expanded(child: children[index + 1]),
                    ],
                  ],
                ),
              ),
            );
            if (index + 2 < children.length) {
              rows.add(SizedBox(height: runSpacing));
            }
          }
          return Column(children: rows);
        }
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      },
    );
  }
}

class _ApprovedChoice {
  const _ApprovedChoice(this.asset, this.label);
  final String asset;
  final String label;
}

class _ApprovedChoicePanel extends StatelessWidget {
  const _ApprovedChoicePanel({
    required this.iconAsset,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String iconAsset;
  final String title;
  final List<_ApprovedChoice> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 82,
      referenceVerticalPadding: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ApprovedPanelTitle(iconAsset: iconAsset, title: title),
          SizedBox(height: metrics.geometry(6)),
          Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                if (index > 0) SizedBox(width: metrics.geometry(4.875)),
                Expanded(
                  child: _ApprovedIconChoice(
                    option: options[index],
                    selected: selected == options[index].label,
                    onTap: () => onSelected(options[index].label),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedIconChoice extends StatelessWidget {
  const _ApprovedIconChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ApprovedChoice option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final compactLabel = option.label.length >= 7;
    final controlHeight = _requestDimension(metrics, 40, floor: 36);
    return SizedBox(
      height: controlHeight,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.symmetric(
            horizontal: _requestDimension(
              metrics,
              compactLabel ? 3 : 6,
              floor: compactLabel ? 2.5 : 5,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(
            color: HocalistPalette.border(
              context,
              selected ? _approvedBlue : _approvedBorder,
            ),
            width: metrics.geometry(selected ? 1.5 : 1),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ApprovedAssetIcon(
              asset: option.asset,
              size: _requestDimension(
                metrics,
                compactLabel ? 14 : 17,
                floor: compactLabel ? 13 : 15.5,
              ),
            ),
            SizedBox(width: metrics.geometry(compactLabel ? 1.2 : 2.44)),
            Flexible(
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: _smallStyle(context).copyWith(
                  color: HocalistPalette.text(context, _approvedNavy),
                  fontSize: _requestControlFontSize(
                    metrics,
                    compactLabel ? 9.4 : 10.5,
                    floor: compactLabel ? 7.8 : 8.5,
                  ),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedBudgetPanel extends StatefulWidget {
  const _ApprovedBudgetPanel({
    required this.minimum,
    required this.maximum,
    required this.onMinimumChanged,
    required this.onMaximumChanged,
    required this.onBudgetChanged,
  });

  final String minimum;
  final String maximum;
  final ValueChanged<String> onMinimumChanged;
  final ValueChanged<String> onMaximumChanged;
  final ValueChanged<String> onBudgetChanged;

  @override
  State<_ApprovedBudgetPanel> createState() => _ApprovedBudgetPanelState();
}

class _ApprovedBudgetPanelState extends State<_ApprovedBudgetPanel> {
  late final TextEditingController _minimumController;
  late final TextEditingController _maximumController;

  @override
  void initState() {
    super.initState();
    _minimumController = TextEditingController(text: widget.minimum);
    _maximumController = TextEditingController(text: widget.maximum);
  }

  @override
  void dispose() {
    _minimumController.dispose();
    _maximumController.dispose();
    super.dispose();
  }

  void _notify() {
    final minimum = _minimumController.text.trim();
    final maximum = _maximumController.text.trim();
    widget.onBudgetChanged(
      minimum.isEmpty && maximum.isEmpty
          ? ''
          : '\$${minimum.isEmpty ? '0' : minimum} - '
                '\$${maximum.isEmpty ? '0' : maximum}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 82,
      referenceVerticalPadding: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _ApprovedPanelTitle(iconAsset: _budgetIcon, title: 'Budget'),
          SizedBox(height: metrics.geometry(6)),
          Row(
            children: [
              Expanded(
                child: _ApprovedPriceField(
                  controller: _minimumController,
                  iconAsset: _minimumIcon,
                  label: 'Min',
                  onChanged: (value) {
                    widget.onMinimumChanged(value);
                    _notify();
                  },
                ),
              ),
              SizedBox(width: metrics.geometry(4.875)),
              Expanded(
                child: _ApprovedPriceField(
                  controller: _maximumController,
                  iconAsset: _maximumIcon,
                  label: 'Max',
                  onChanged: (value) {
                    widget.onMaximumChanged(value);
                    _notify();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedPriceField extends StatelessWidget {
  const _ApprovedPriceField({
    required this.controller,
    required this.iconAsset,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String iconAsset;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final narrowLocked = metrics.screenshotLocked && metrics.isNarrow;
    final controlHeight = _requestDimension(metrics, 40, floor: 36);
    return TextField(
      key: ValueKey('approved-request-budget-${label.toLowerCase()}'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      style: _smallStyle(context).copyWith(
        color: HocalistPalette.text(context, _approvedNavy),
        fontWeight: FontWeight.w800,
      ),
      decoration: _inputDecoration(context).copyWith(
        constraints: BoxConstraints.tightFor(height: controlHeight),
        hintText: label,
        hintStyle: _requestHintStyle(
          context,
        ).copyWith(fontSize: _requestFontSize(metrics, 12)),
        contentPadding: EdgeInsets.symmetric(
          horizontal: narrowLocked
              ? metrics.geometry(2)
              : _requestDimension(metrics, 6, floor: 5),
          vertical: _requestDimension(metrics, 10, floor: 9),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: narrowLocked
              ? metrics.geometry(20)
              : _requestDimension(metrics, 30, floor: 28),
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.only(
            left: narrowLocked
                ? metrics.geometry(2)
                : _requestDimension(metrics, 5, floor: 4),
          ),
          child: _ApprovedAssetIcon(
            asset: iconAsset,
            size: narrowLocked
                ? metrics.geometry(13.5)
                : _requestDimension(metrics, 16, floor: 14.5),
          ),
        ),
      ),
    );
  }
}

class _ApprovedQuantityPanel extends StatelessWidget {
  const _ApprovedQuantityPanel({
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 94,
      referenceVerticalPadding: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ApprovedPanelTitle(
            iconAsset: _quantityIcon,
            title: 'Quantity',
          ),
          SizedBox(height: metrics.geometry(8)),
          Container(
            height: _requestControlHeight(metrics),
            decoration: BoxDecoration(
              border: Border.all(
                color: HocalistPalette.border(context, _approvedBorder),
                width: metrics.geometry(1),
              ),
              borderRadius: BorderRadius.circular(metrics.geometry(8)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Decrease quantity',
                  onPressed: quantity > 1
                      ? () => onChanged(quantity - 1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: _requestControlHeight(metrics),
                    height: _requestControlHeight(metrics),
                  ),
                  icon: BuyerGlyphIcon(
                    icon: Icons.remove,
                    slotSize: metrics.geometry(12.19),
                    glyphSize: metrics.geometry(12.19),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$quantity',
                      style: _bodyStyle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Increase quantity',
                  onPressed: () => onChanged(quantity + 1),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: _requestControlHeight(metrics),
                    height: _requestControlHeight(metrics),
                  ),
                  icon: BuyerGlyphIcon(
                    icon: Icons.add,
                    slotSize: metrics.geometry(12.19),
                    glyphSize: metrics.geometry(12.19),
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

class _ApprovedCategoryPanel extends StatefulWidget {
  const _ApprovedCategoryPanel({
    this.options = const <CatalogueCategoryOption>[],
    this.selectedId,
    this.selectedLabel,
    this.onSelected,
    this.loading = false,
    this.error,
    this.onRetry,
    this.supportsProduct,
  });

  /// Server-provided categories. Empty keeps the prototype free-text picker.
  final List<CatalogueCategoryOption> options;
  final String? selectedId;
  final String? selectedLabel;

  /// Non-null enables real-mode selection by catalogue id.
  final ValueChanged<String>? onSelected;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  /// Scope filter for the current request kind; null shows every category.
  final bool? supportsProduct;

  @override
  State<_ApprovedCategoryPanel> createState() => _ApprovedCategoryPanelState();
}

class _ApprovedCategoryPanelState extends State<_ApprovedCategoryPanel> {
  String? _prototypeCategory;

  List<CatalogueCategoryOption> get _eligible {
    final supportsProduct = widget.supportsProduct;
    if (supportsProduct == null) return widget.options;
    return widget.options
        .where(
          (option) =>
              supportsProduct ? option.supportsProduct : option.supportsService,
        )
        .toList(growable: false);
  }

  Future<void> _chooseCategory() async {
    final onSelected = widget.onSelected;
    if (onSelected == null) {
      final selected = await showModalBottomSheet<String>(
        context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x990B1231),
        builder: (sheetContext) => _ApprovedEditableSelectionSheet(
          title: 'Choose a category',
          subtitle:
              'Enter the closest category now. Suggested categories will come from the backend later.',
          icon: Icons.grid_view_outlined,
          fieldKey: const Key('approved-request-category-input'),
          label: 'Category',
          hint: 'Enter a category',
          actionLabel: 'Use category',
          initialValue: _prototypeCategory,
        ),
      );
      if (selected != null && mounted) {
        setState(() => _prototypeCategory = selected);
      }
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => _ApprovedCategorySheet(
        options: _eligible,
        selectedId: widget.selectedId,
        onSelected: (id) => Navigator.pop(sheetContext, id),
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final selected = widget.selectedId != null
        ? (widget.selectedLabel ?? widget.selectedId!)
        : _prototypeCategory;
    return _ApprovedSurface(
      referenceHeight: 105,
      referenceVerticalPadding: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ApprovedPanelTitle(
            iconAsset: _categoryIcon,
            title: 'Category',
            optional: widget.onSelected == null,
          ),
          SizedBox(height: metrics.geometry(4)),
          Text('This avoids mismatch.', style: _smallStyle(context)),
          SizedBox(height: metrics.geometry(8)),
          InkWell(
            key: const Key('approved-request-category-select'),
            onTap: widget.onSelected != null && widget.loading
                ? null
                : _chooseCategory,
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
            child: Container(
              height: metrics.geometry(30.47),
              padding: EdgeInsets.symmetric(horizontal: metrics.geometry(6.1)),
              decoration: BoxDecoration(
                border: Border.all(
                  color: HocalistPalette.border(context, _approvedBorder),
                  width: metrics.geometry(1),
                ),
                borderRadius: BorderRadius.circular(metrics.geometry(8)),
              ),
              child: Row(
                children: [
                  _ApprovedAssetIcon(
                    asset: _categoryGridIcon,
                    size: metrics.geometry(12.19),
                  ),
                  SizedBox(width: metrics.geometry(4.875)),
                  Expanded(
                    child: Text(
                      selected ?? 'Select a category',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: selected == null
                          ? _requestHintStyle(context)
                          : _requestInputStyle(context),
                    ),
                  ),
                  _ApprovedAssetIcon(
                    asset: _categoryDownIcon,
                    size: metrics.geometry(10.97),
                  ),
                ],
              ),
            ),
          ),
          if (widget.loading) ...[
            SizedBox(height: metrics.geometry(4)),
            Text('Loading categories…', style: _smallStyle(context)),
          ] else if (widget.error != null) ...[
            SizedBox(height: metrics.geometry(4)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.error!,
                    key: const Key('approvedRequestCategoryError'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _smallStyle(context).copyWith(
                      color: HocalistPalette.text(
                        context,
                        const Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('approvedRequestCategoryRetry'),
                  onPressed: widget.onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.geometry(6),
                    ),
                    foregroundColor: HocalistPalette.text(
                      context,
                      _approvedBlue,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Real-mode category picker sheet: active server categories by id.
class _ApprovedCategorySheet extends StatelessWidget {
  const _ApprovedCategorySheet({
    required this.options,
    required this.selectedId,
    required this.onSelected,
    required this.onClose,
  });

  final List<CatalogueCategoryOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final active = options.where((option) => option.isActive).toList();
    return BuyerModalSheet(
      title: 'Choose a category',
      subtitle: 'Categories come from the Hocalist catalogue.',
      icon: Icons.grid_view_outlined,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active.isEmpty)
            Padding(
              key: const Key('approvedRequestCategoryEmpty'),
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No categories are available yet. An administrator must publish '
                'the catalogue before categories can be chosen.',
                textAlign: TextAlign.center,
                style: _bodyStyle(context),
              ),
            )
          else
            for (final option in active)
              InkWell(
                key: ValueKey('approvedRequestCategory-${option.id}'),
                onTap: () => onSelected(option.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(option.label, style: _bodyStyle(context)),
                      ),
                      if (option.id == selectedId)
                        Icon(
                          Icons.check,
                          color: HocalistPalette.text(context, _approvedBlue),
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ApprovedHigherOffersPanel extends StatelessWidget {
  const _ApprovedHigherOffersPanel({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 94,
      referenceVerticalPadding: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ApprovedPanelTitle(
            iconAsset: _higherOffersIcon,
            title: 'Willing to receive higher offers?',
          ),
          SizedBox(height: metrics.geometry(8)),
          Row(
            children: [
              Expanded(
                child: _ApprovedTextChoice(
                  label: 'No',
                  selected: !value,
                  onTap: () => onChanged(false),
                ),
              ),
              SizedBox(width: metrics.geometry(8.53)),
              Expanded(
                child: _ApprovedTextChoice(
                  label: 'Yes',
                  selected: value,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedPanelTitle extends StatelessWidget {
  const _ApprovedPanelTitle({
    required this.iconAsset,
    required this.title,
    this.optional = false,
  });

  final String iconAsset;
  final String title;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ApprovedAssetIcon(
          asset: iconAsset,
          size: _requestDimension(metrics, BuyerIconTokens.inline, floor: 17),
        ),
        SizedBox(width: metrics.geometry(3.66)),
        Expanded(
          child: metrics.screenshotLocked
              ? Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          softWrap: false,
                          style: _sectionStyle(context).copyWith(
                            fontSize: _requestControlFontSize(
                              metrics,
                              10.5,
                              floor: 8.25,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (optional) ...[
                      SizedBox(width: metrics.geometry(2.44)),
                      Text(
                        '(optional)',
                        maxLines: 1,
                        softWrap: false,
                        style: _smallStyle(context).copyWith(
                          color: HocalistPalette.text(context, _approvedNavy),
                          fontSize: _requestControlFontSize(
                            metrics,
                            9.5,
                            floor: 8,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : Wrap(
                  spacing: metrics.geometry(4),
                  runSpacing: metrics.geometry(2),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: _sectionStyle(context)),
                    if (optional)
                      Text(
                        '(optional)',
                        style: _smallStyle(context).copyWith(
                          color: HocalistPalette.text(context, _approvedNavy),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ApprovedTextChoice extends StatelessWidget {
  const _ApprovedTextChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final controlHeight = _requestControlHeight(metrics);
    return SizedBox(
      height: controlHeight,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.symmetric(horizontal: metrics.geometry(6)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: HocalistPalette.text(context, _approvedNavy),
          side: BorderSide(
            color: HocalistPalette.border(
              context,
              selected ? _approvedBlue : _approvedBorder,
            ),
            width: metrics.geometry(selected ? 1.5 : 1),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: _smallStyle(context).copyWith(
              color: HocalistPalette.text(
                context,
                selected ? _approvedBlue : _approvedNavy,
              ),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              fontSize: _requestControlFontSize(metrics, 9.25, floor: 7),
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedActionRow extends StatelessWidget {
  const _ApprovedActionRow({
    required this.backLabel,
    required this.forwardLabel,
    required this.onBack,
    required this.onForward,
  });

  final String backLabel;
  final String forwardLabel;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = metrics.accessibilityReflow;
        final actionHeight = _requestDimension(metrics, 34, floor: 40);
        final back = SizedBox(
          height: metrics.screenshotLocked ? actionHeight : null,
          child: OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, actionHeight),
              tapTargetSize: metrics.screenshotLocked
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
              side: BorderSide(
                color: HocalistPalette.border(context, _approvedBlue),
                width: metrics.geometry(1.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(8)),
              ),
            ),
            child: Text(
              backLabel,
              maxLines: 1,
              softWrap: false,
              style: _bodyStyle(context).copyWith(
                fontSize: _requestControlFontSize(metrics, 11.5, floor: 10.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        final forward = _ApprovedPrimaryButton(
          label: forwardLabel,
          onPressed: onForward,
        );
        if (stacked) {
          return Column(
            children: [
              forward,
              SizedBox(height: metrics.geometry(8)),
              back,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: back),
            SizedBox(width: metrics.geometry(8.53)),
            Expanded(child: forward),
          ],
        );
      },
    );
  }
}

class _ApprovedPrimaryButton extends StatelessWidget {
  const _ApprovedPrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final metrics = _replicaMetrics(context);
    final actionHeight = _requestDimension(metrics, 42, floor: 40);
    return SizedBox(
      width: double.infinity,
      height: metrics.screenshotLocked ? actionHeight : null,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: Size(0, actionHeight),
          padding: EdgeInsets.symmetric(horizontal: metrics.geometry(10)),
          tapTargetSize: metrics.screenshotLocked
              ? MaterialTapTargetSize.shrinkWrap
              : null,
          backgroundColor: HocalistPalette.surface(
            context,
            accessibility.backgroundOr(_approvedBlue),
          ),
          foregroundColor: HocalistPalette.text(
            context,
            accessibility.foregroundOr(Colors.white),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              accessibility.radiusOr(metrics.geometry(8)),
            ),
          ),
        ),
        icon: BuyerGlyphIcon(
          icon: Icons.send_outlined,
          slotSize: _requestDimension(
            metrics,
            BuyerIconTokens.inline,
            floor: 16,
          ),
        ),
        label: Text(
          busy ? 'Posting…' : label,
          maxLines: 1,
          softWrap: false,
          style: _bodyStyle(context).copyWith(
            color: HocalistPalette.text(context, Colors.white),
            fontSize: _requestControlFontSize(metrics, 11.5, floor: 10.5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ApprovedLocationActions extends StatelessWidget {
  const _ApprovedLocationActions({
    required this.onBack,
    required this.onSubmit,
    this.busy = false,
    this.error,
    this.uncertain = false,
    this.onDiscard,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final bool busy;
  final String? error;
  final bool uncertain;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Text(
            error!,
            key: const Key('approvedRequestSubmitError'),
            style: _bodyStyle(context).copyWith(
              color: HocalistPalette.text(context, const Color(0xFFD32F2F)),
              fontSize: _requestFontSize(metrics, 11),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: metrics.geometry(6)),
        ],
        _ApprovedPrimaryButton(
          key: const Key('approvedRequestPostButton'),
          label: uncertain ? 'Retry' : 'Post request',
          onPressed: busy ? () {} : onSubmit,
          busy: busy,
        ),
        if (uncertain && !busy && onDiscard != null) ...[
          SizedBox(height: metrics.geometry(4.875)),
          OutlinedButton(
            key: const Key('approvedRequestDiscard'),
            onPressed: onDiscard,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, _requestDimension(metrics, 38, floor: 36)),
              foregroundColor: HocalistPalette.text(context, _approvedBlue),
              side: BorderSide(
                color: HocalistPalette.border(context, _approvedBorder),
              ),
            ),
            child: const Text('Discard this attempt'),
          ),
        ],
        SizedBox(height: metrics.geometry(4.875)),
        TextButton(
          onPressed: onBack,
          style: TextButton.styleFrom(
            minimumSize: Size(0, _requestDimension(metrics, 32, floor: 32)),
            foregroundColor: HocalistPalette.text(context, _approvedBlue),
            tapTargetSize: metrics.screenshotLocked
                ? MaterialTapTargetSize.shrinkWrap
                : null,
            padding: EdgeInsets.symmetric(vertical: metrics.geometry(4)),
          ),
          child: Text(
            'Back',
            maxLines: 1,
            softWrap: false,
            style: _bodyStyle(context).copyWith(
              color: HocalistPalette.text(context, _approvedBlue),
              fontSize: _requestControlFontSize(metrics, 13, floor: 10.5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovedAddressField extends StatefulWidget {
  const _ApprovedAddressField({
    required this.label,
    required this.hint,
    this.value,
    this.dropdown = false,
    this.countryOptions = false,
    this.onChanged,
  });

  final String label;
  final String hint;
  final String? value;
  final bool dropdown;
  final bool countryOptions;
  final ValueChanged<String>? onChanged;

  @override
  State<_ApprovedAddressField> createState() => _ApprovedAddressFieldState();
}

class _ApprovedAddressFieldState extends State<_ApprovedAddressField> {
  late String? _selectedValue = widget.value;
  late final TextEditingController _fieldController = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _ApprovedAddressField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _selectedValue = widget.value;
      _fieldController.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  Future<void> _chooseValue() async {
    if (widget.countryOptions) {
      final choice = await _chooseCountry();
      if (choice == null || !mounted) return;
      _fieldController.text = choice.label;
      setState(() => _selectedValue = choice.code);
      widget.onChanged?.call(choice.code);
      return;
    }
    final selected = await _chooseEditableValue();
    if (selected != null && mounted) {
      _fieldController.text = selected;
      setState(() => _selectedValue = selected);
      widget.onChanged?.call(selected);
    }
  }

  Future<String?> _chooseEditableValue() {
    return showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => _ApprovedEditableSelectionSheet(
        title: 'Choose ${widget.label.toLowerCase()}',
        subtitle:
            'Enter your ${widget.label.toLowerCase()}. Available choices will be managed by the backend later.',
        icon: Icons.location_on_outlined,
        fieldKey: ValueKey(
          'approved-request-${widget.label.toLowerCase()}-picker-input',
        ),
        label: widget.label,
        hint: widget.hint,
        actionLabel: 'Use ${widget.label.toLowerCase()}',
        initialValue: _selectedValue,
      ),
    );
  }

  Future<ApprovedCountryOption?> _chooseCountry() {
    return showModalBottomSheet<ApprovedCountryOption>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => BuyerModalSheet(
        key: const Key('approved-request-country-sheet'),
        title: 'Choose country',
        subtitle:
            'United States is selected by default. Other supported countries '
            'remain available.',
        icon: Icons.public,
        onClose: () => Navigator.pop(sheetContext),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in approvedRequestCountries) ...[
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: ValueKey('approved-country-${option.code}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: option.code == 'US'
                      ? const Icon(Icons.star, color: _approvedBlue, size: 20)
                      : const Icon(
                          Icons.public,
                          color: _approvedMuted,
                          size: 20,
                        ),
                  title: Text(option.label),
                  subtitle: Text(option.code),
                  trailing: option.code == _selectedValue
                      ? const Icon(Icons.check_circle, color: _approvedBlue)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              ),
              if (option != approvedRequestCountries.last)
                const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final narrowLocked =
        metrics.screenshotLocked && metrics.availableWidth < 390;
    final fieldHeight = _requestDimension(metrics, 44, floor: 40);
    final fieldFontSize = _requestControlFontSize(metrics, 10.5, floor: 8.5);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      borderSide: BorderSide(
        color: HocalistPalette.border(context, _approvedBorder),
        width: metrics.geometry(1),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: _smallStyle(context).copyWith(
            color: HocalistPalette.text(context, _approvedNavy),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: metrics.geometry(3)),
        SizedBox(
          height: fieldHeight,
          child: TextFormField(
            key: ValueKey(
              'approved-request-address-${widget.label.toLowerCase().replaceAll(' ', '-')}',
            ),
            controller: _fieldController,
            readOnly: widget.dropdown,
            onTap: widget.dropdown ? _chooseValue : null,
            onChanged: widget.dropdown ? null : widget.onChanged,
            style: _requestInputStyle(
              context,
            ).copyWith(fontSize: fieldFontSize),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: false,
              filled: true,
              fillColor: HocalistPalette.surface(context, Colors.white),
              hintText: widget.hint,
              hintStyle: _requestHintStyle(
                context,
              ).copyWith(fontSize: fieldFontSize),
              contentPadding: EdgeInsets.symmetric(
                horizontal: _requestDimension(
                  metrics,
                  HocalistInputTokens.horizontalPadding,
                  floor: 12,
                ),
                vertical: narrowLocked
                    ? HocalistInputTokens.compactVerticalPadding
                    : HocalistInputTokens.verticalPadding,
              ),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder.copyWith(
                borderSide: BorderSide(
                  color: HocalistPalette.border(context, _approvedBlue),
                  width: metrics.geometry(1.5),
                ),
              ),
              suffixIcon: widget.dropdown
                  ? Padding(
                      padding: EdgeInsets.only(right: metrics.geometry(5)),
                      child: BuyerGlyphIcon(
                        icon: Icons.keyboard_arrow_down,
                        slotSize: metrics.geometry(16),
                        glyphSize: metrics.geometry(16),
                        color: HocalistPalette.text(context, _approvedMuted),
                      ),
                    )
                  : null,
              suffixIconConstraints: widget.dropdown
                  ? BoxConstraints(
                      minWidth: metrics.geometry(24),
                      minHeight: metrics.geometry(24),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovedEditableSelectionSheet extends StatefulWidget {
  const _ApprovedEditableSelectionSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.actionLabel,
    this.initialValue,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Key fieldKey;
  final String label;
  final String hint;
  final String actionLabel;
  final String? initialValue;

  @override
  State<_ApprovedEditableSelectionSheet> createState() =>
      _ApprovedEditableSelectionSheetState();
}

class _ApprovedEditableSelectionSheetState
    extends State<_ApprovedEditableSelectionSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BuyerModalSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: widget.fieldKey,
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 14),
          BuyerPrimaryButton(
            label: widget.actionLabel,
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
          ),
        ],
      ),
    );
  }
}

class _ApprovedRequestSummary extends StatelessWidget {
  const _ApprovedRequestSummary({
    required this.requestTitle,
    required this.budget,
    required this.location,
    required this.onDelete,
    this.isReal = false,
    this.status,
  });

  final String requestTitle;
  final String budget;
  final String location;
  final VoidCallback onDelete;
  final bool isReal;
  final RequestStatus? status;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 110,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final image = Image.asset(
            'assets/buyer_request_detail/ipad-air-approved.png',
            width: metrics.geometry(62),
            height: metrics.geometry(77),
            fit: BoxFit.contain,
            semanticLabel: 'iPad Air request product',
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                requestTitle,
                maxLines: metrics.screenshotLocked ? 1 : null,
                softWrap: !metrics.screenshotLocked,
                style: _titleStyle(context, 13),
              ),
              SizedBox(height: metrics.geometry(6.1)),
              Row(
                children: [
                  Expanded(
                    child: _ApprovedSummaryFact(
                      label: 'Budget range',
                      value: budget,
                    ),
                  ),
                  Container(
                    width: metrics.geometry(1),
                    height: metrics.geometry(29.25),
                    color: HocalistPalette.surface(context, _approvedBorder),
                  ),
                  SizedBox(width: metrics.geometry(4.875)),
                  Expanded(
                    child: _ApprovedSummaryFact(
                      label: 'Location',
                      value: location,
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                ],
              ),
            ],
          );
          final actions = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.geometry(6.1),
                  vertical: metrics.geometry(3.66),
                ),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    const Color(0xffe8f8ed),
                  ),
                  borderRadius: BorderRadius.circular(metrics.geometry(999)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BuyerGlyphIcon(
                      icon: Icons.circle,
                      slotSize: metrics.geometry(6.1),
                      glyphSize: metrics.geometry(6.1),
                      color: HocalistPalette.text(
                        context,
                        const Color(0xff0ca64a),
                      ),
                    ),
                    SizedBox(width: metrics.geometry(2.44)),
                    Text(
                      switch (status) {
                        RequestStatus.closed => 'Closed',
                        RequestStatus.expired => 'Expired',
                        RequestStatus.cancelled => 'Cancelled',
                        RequestStatus.draft => 'Draft',
                        _ => 'Active',
                      },
                      style: TextStyle(
                        color: HocalistPalette.text(
                          context,
                          const Color(0xff07933e),
                        ),
                        fontSize: _requestFontSize(metrics, 9.5),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.geometry(3.66)),
              OutlinedButton.icon(
                key: const Key('delete-request'),
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: HocalistPalette.text(context, Colors.red),
                  side: BorderSide(
                    color: HocalistPalette.border(context, _approvedBorder),
                    width: metrics.geometry(1),
                  ),
                  minimumSize: Size(0, metrics.geometry(36.56)),
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.geometry(4.875),
                  ),
                  tapTargetSize: metrics.screenshotLocked
                      ? MaterialTapTargetSize.shrinkWrap
                      : null,
                ),
                icon: BuyerGlyphIcon(
                  icon: Icons.delete_outline,
                  slotSize: metrics.geometry(14.625),
                  glyphSize: metrics.geometry(14.625),
                ),
                label: Text(
                  isReal ? 'Close' : 'Delete',
                  style: TextStyle(fontSize: _requestFontSize(metrics, 10.5)),
                ),
              ),
            ],
          );
          if (metrics.screenshotLocked) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isReal) ...[
                  image,
                  SizedBox(width: metrics.geometry(7.31)),
                ],
                Expanded(child: details),
                SizedBox(width: metrics.geometry(4.875)),
                actions,
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isReal) ...[
                    image,
                    SizedBox(width: metrics.geometry(12)),
                  ],
                  Expanded(child: details),
                ],
              ),
              SizedBox(height: metrics.geometry(12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: actions.children,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedSummaryFact extends StatelessWidget {
  const _ApprovedSummaryFact({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _smallStyle(context)),
        SizedBox(height: metrics.geometry(3)),
        Row(
          children: [
            if (icon != null) ...[
              BuyerGlyphIcon(
                icon: icon!,
                slotSize: metrics.geometry(18),
                glyphSize: metrics.geometry(18),
                color: HocalistPalette.text(context, _approvedBlue),
              ),
              SizedBox(width: metrics.geometry(4)),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                style: _bodyStyle(context).copyWith(
                  color: HocalistPalette.text(context, _approvedBlue),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ApprovedEditPanel extends StatelessWidget {
  const _ApprovedEditPanel({
    required this.referenceHeight,
    required this.iconAsset,
    required this.title,
    required this.helper,
    required this.onEdit,
    required this.child,
    this.trailing,
  });

  final double referenceHeight;
  final String iconAsset;
  final String title;
  final String helper;
  final VoidCallback onEdit;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: referenceHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ApprovedIconCircle(asset: iconAsset),
          SizedBox(width: metrics.geometry(3.66)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: _sectionStyle(context))),
                    if (trailing != null)
                      Text(trailing!, style: _smallStyle(context)),
                    SizedBox(width: metrics.geometry(3.66)),
                    _ApprovedEditButton(
                      onPressed: onEdit,
                      tooltip: 'Edit $title',
                    ),
                  ],
                ),
                SizedBox(height: metrics.geometry(1)),
                Text(helper, style: _smallStyle(context)),
                SizedBox(height: metrics.geometry(2)),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedDetailChoicePanel extends StatelessWidget {
  const _ApprovedDetailChoicePanel({
    this.referenceHeight,
    required this.iconAsset,
    required this.title,
    required this.helper,
    required this.child,
    this.onEdit,
  });

  final double? referenceHeight;
  final String iconAsset;
  final String title;
  final String helper;
  final Widget child;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: referenceHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ApprovedIconCircle(asset: iconAsset),
              SizedBox(width: metrics.geometry(3.66)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: metrics.screenshotLocked ? 2 : null,
                      softWrap: true,
                      style: _sectionStyle(
                        context,
                      ).copyWith(fontSize: _requestFontSize(metrics, 9)),
                    ),
                    SizedBox(height: metrics.geometry(1.22)),
                    Text(helper, style: _smallStyle(context)),
                  ],
                ),
              ),
              if (onEdit != null)
                _ApprovedEditButton(onPressed: onEdit!, tooltip: 'Edit $title'),
            ],
          ),
          SizedBox(height: metrics.geometry(2.44)),
          child,
        ],
      ),
    );
  }
}

class _ApprovedDetailBudgetPanel extends StatelessWidget {
  const _ApprovedDetailBudgetPanel({
    required this.referenceHeight,
    required this.onEdit,
    this.minimumLabel = r'$350',
    this.maximumLabel = r'$480',
  });
  final double referenceHeight;
  final VoidCallback onEdit;
  final String minimumLabel;
  final String maximumLabel;

  @override
  Widget build(BuildContext context) {
    return _ApprovedDetailChoicePanel(
      referenceHeight: referenceHeight,
      iconAsset: _budgetIcon,
      title: 'Budget (optional)',
      helper: 'Set your budget range',
      onEdit: onEdit,
      child: Row(
        children: [
          Expanded(child: _ApprovedValueBox(value: minimumLabel)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _replicaMetrics(context).geometry(7),
            ),
            child: const Text('-'),
          ),
          Expanded(child: _ApprovedValueBox(value: maximumLabel)),
        ],
      ),
    );
  }
}

class _ApprovedDetailQuantityPanel extends StatelessWidget {
  const _ApprovedDetailQuantityPanel({
    required this.referenceHeight,
    required this.quantity,
    required this.onChanged,
  });
  final double referenceHeight;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedDetailChoicePanel(
      referenceHeight: referenceHeight,
      iconAsset: _quantityIcon,
      title: 'Quantity',
      helper: 'How many do you need?',
      child: Container(
        height: _requestControlHeight(metrics),
        decoration: BoxDecoration(
          border: Border.all(
            color: HocalistPalette.border(context, _approvedBorder),
            width: metrics.geometry(1),
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Decrease quantity',
              onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
              constraints: metrics.screenshotLocked
                  ? BoxConstraints.tightFor(
                      width: _requestControlHeight(metrics),
                      height: _requestControlHeight(metrics),
                    )
                  : null,
              padding: metrics.screenshotLocked ? EdgeInsets.zero : null,
              icon: BuyerGlyphIcon(
                icon: Icons.remove,
                slotSize: metrics.geometry(12.19),
                glyphSize: metrics.geometry(12.19),
              ),
            ),
            Expanded(
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: _bodyStyle(
                  context,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Increase quantity',
              onPressed: () => onChanged(quantity + 1),
              constraints: metrics.screenshotLocked
                  ? BoxConstraints.tightFor(
                      width: _requestControlHeight(metrics),
                      height: _requestControlHeight(metrics),
                    )
                  : null,
              padding: metrics.screenshotLocked ? EdgeInsets.zero : null,
              icon: BuyerGlyphIcon(
                icon: Icons.add,
                slotSize: metrics.geometry(12.19),
                glyphSize: metrics.geometry(12.19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedValueBox extends StatelessWidget {
  const _ApprovedValueBox({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      height: _requestControlHeight(metrics),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          color: HocalistPalette.border(context, _approvedBorder),
          width: metrics.geometry(1),
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
      ),
      child: Text(
        value,
        style: _bodyStyle(context).copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ApprovedLocationSummary extends StatelessWidget {
  const _ApprovedLocationSummary({
    required this.referenceHeight,
    required this.location,
    required this.onTap,
  });
  final double referenceHeight;
  final String location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: referenceHeight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: metrics.geometry(2.44)),
          child: Row(
            children: [
              BuyerGlyphIcon(
                icon: Icons.location_on_outlined,
                slotSize: metrics.geometry(21.94),
                glyphSize: metrics.geometry(21.94),
                color: HocalistPalette.text(context, _approvedNavy),
              ),
              SizedBox(width: metrics.geometry(3.66)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit location', style: _sectionStyle(context)),
                    SizedBox(height: metrics.geometry(1.22)),
                    Text('Change your location', style: _smallStyle(context)),
                    Text(
                      location,
                      style: _bodyStyle(context).copyWith(
                        color: HocalistPalette.text(context, _approvedBlue),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              BuyerGlyphIcon(
                icon: Icons.chevron_right,
                slotSize: metrics.geometry(17.06),
                glyphSize: metrics.geometry(17.06),
                color: HocalistPalette.text(context, _approvedNavy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovedRealOffersPanel extends StatelessWidget {
  const _ApprovedRealOffersPanel({required this.onOffers});

  final VoidCallback onOffers;

  @override
  Widget build(BuildContext context) {
    return _ApprovedSurface(
      referenceHeight: 69,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Seller offers', style: _sectionStyle(context)),
          TextButton(
            key: const Key('realRequestReviewOffers'),
            onPressed: onOffers,
            child: const Text('Review offers'),
          ),
        ],
      ),
    );
  }
}

class _ApprovedRewardsPanel extends StatelessWidget {
  const _ApprovedRewardsPanel({
    required this.referenceHeight,
    required this.onOffers,
  });
  final double referenceHeight;
  final VoidCallback onOffers;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: referenceHeight,
      child: Row(
        children: [
          Container(
            width: metrics.geometry(21.94),
            height: metrics.geometry(21.94),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Color(0xffffb21c)),
              shape: BoxShape.circle,
            ),
            child: BuyerGlyphIcon(
              icon: Icons.star,
              slotSize: metrics.geometry(13.4),
              glyphSize: metrics.geometry(13.4),
              color: HocalistPalette.text(context, Colors.white),
            ),
          ),
          SizedBox(width: metrics.geometry(3.66)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current estimated rewards',
                  maxLines: metrics.screenshotLocked ? 2 : null,
                  softWrap: true,
                  style: _sectionStyle(
                    context,
                  ).copyWith(fontSize: _requestFontSize(metrics, 8.5)),
                ),
                SizedBox(height: metrics.geometry(1.22)),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: metrics.geometry(8.53),
                  runSpacing: metrics.geometry(3.66),
                  children: [
                    Text(
                      '\$6.40',
                      style: TextStyle(
                        color: HocalistPalette.text(
                          context,
                          const Color(0xff0ca64a),
                        ),
                        fontSize: _requestFontSize(metrics, 14),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    InkWell(
                      onTap: onOffers,
                      borderRadius: BorderRadius.circular(metrics.geometry(12)),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.geometry(4.875),
                          vertical: metrics.geometry(1.22),
                        ),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            const Color(0xffe3f7e9),
                          ),
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(12),
                          ),
                        ),
                        child: Text(
                          '32 offers',
                          style: TextStyle(
                            color: HocalistPalette.text(
                              context,
                              const Color(0xff0c9845),
                            ),
                            fontSize: _requestFontSize(metrics, 8.5),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'This is an estimate based on current offers.',
                  maxLines: metrics.screenshotLocked
                      ? metrics.isNarrow
                            ? 3
                            : 2
                      : null,
                  softWrap: true,
                  style: _smallStyle(context).copyWith(
                    fontSize: _requestFontSize(metrics, 8),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          BuyerGlyphIcon(
            icon: Icons.info_outline,
            slotSize: metrics.geometry(12.19),
            glyphSize: metrics.geometry(12.19),
            color: HocalistPalette.text(context, _approvedBlue),
          ),
        ],
      ),
    );
  }
}

class _ApprovedSavePanel extends StatelessWidget {
  const _ApprovedSavePanel({required this.onSave, this.busy = false});
  final VoidCallback onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = metrics.accessibilityReflow;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Save changes', style: _sectionStyle(context)),
              SizedBox(height: metrics.geometry(2)),
              Text(
                'Updating your request may refresh offers and estimated rewards.',
                style: _smallStyle(context),
              ),
            ],
          );
          final button = FilledButton.icon(
            key: const Key('save-request-changes'),
            onPressed: busy ? null : onSave,
            style: FilledButton.styleFrom(
              minimumSize: Size(0, metrics.geometry(30.47)),
              tapTargetSize: metrics.screenshotLocked
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
              padding: EdgeInsets.symmetric(
                horizontal: metrics.geometry(8.53),
                vertical: metrics.geometry(2.44),
              ),
              backgroundColor: HocalistPalette.surface(
                context,
                accessibility.backgroundOr(_approvedBlue),
              ),
              foregroundColor: HocalistPalette.text(
                context,
                accessibility.foregroundOr(Colors.white),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  accessibility.radiusOr(metrics.geometry(8)),
                ),
              ),
            ),
            icon: BuyerGlyphIcon(
              icon: Icons.save_outlined,
              slotSize: metrics.geometry(12.19),
              glyphSize: metrics.geometry(12.19),
            ),
            label: Text(
              'Save changes',
              maxLines: 1,
              softWrap: false,
              style: metrics.screenshotLocked
                  ? _bodyStyle(context).copyWith(
                      color: HocalistPalette.text(
                        context,
                        accessibility.foregroundOr(Colors.white),
                      ),
                      fontSize: _requestControlFontSize(
                        metrics,
                        11.5,
                        floor: 9.5,
                      ),
                      fontWeight: FontWeight.w700,
                    )
                  : null,
            ),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                SizedBox(height: metrics.geometry(10)),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              SizedBox(width: metrics.geometry(8)),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedRequestDecisionSheet extends StatelessWidget {
  const _ApprovedRequestDecisionSheet({
    required this.asset,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onCancel,
    required this.onPrimary,
    this.destructive = false,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onCancel;
  final VoidCallback onPrimary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: media.size.width,
      textScaler: media.textScaler,
    );
    final actionColor = destructive ? const Color(0xffc62828) : _approvedBlue;
    return ApprovedReplicaScope(
      metrics: metrics,
      child: BuyerModalSheet(
        title: title,
        subtitle: message,
        headerArtwork: BuyerAssetIcon(asset: asset, slotSize: 20),
        iconColor: HocalistPalette.text(context, actionColor),
        iconSurface: destructive
            ? const Color(0xffffeeee)
            : BuyerUiTokens.softSurface,
        onClose: onCancel,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cancel = BuyerSecondaryButton(
              key: const ValueKey('approved-request-sheet-cancel'),
              label: 'Cancel',
              color: _approvedNavy,
              onPressed: onCancel,
            );
            final primary = BuyerPrimaryButton(
              key: const ValueKey('approved-request-sheet-primary'),
              label: primaryLabel,
              colors: [actionColor, actionColor],
              onPressed: onPrimary,
            );
            final stackActions =
                constraints.maxWidth < metrics.geometry(286) ||
                metrics.textScale >= 1.6;
            if (stackActions) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primary,
                  SizedBox(height: metrics.geometry(10)),
                  cancel,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: cancel),
                SizedBox(width: metrics.geometry(12)),
                Expanded(child: primary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ApprovedSurface extends StatelessWidget {
  const _ApprovedSurface({
    required this.child,
    this.referenceHeight,
    this.referenceVerticalPadding = 6.1,
  });
  final Widget child;
  final double? referenceHeight;
  final double referenceVerticalPadding;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final scaledVerticalPadding = metrics.geometry(referenceVerticalPadding);
    final verticalPadding =
        metrics.screenshotLocked &&
            metrics.availableWidth < 390 &&
            scaledVerticalPadding < 6
        ? 6.0
        : scaledVerticalPadding;
    return Container(
      constraints:
          metrics.screenshotLocked &&
              !metrics.isNarrow &&
              referenceHeight != null
          ? BoxConstraints(minHeight: metrics.geometry(referenceHeight!))
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(8),
        vertical: metrics.screenshotLocked
            ? verticalPadding
            : _requestDimension(metrics, referenceVerticalPadding, floor: 6),
      ),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _approvedSurface),
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xfff2f3f8)),
          width: metrics.geometry(1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0a10145b),
            blurRadius: metrics.geometry(18),
            offset: Offset(0, metrics.geometry(6)),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ApprovedIconCircle extends StatelessWidget {
  const _ApprovedIconCircle({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedAssetIcon(
      asset: asset,
      size: _requestDimension(metrics, BuyerIconTokens.control, floor: 20),
    );
  }
}

class _ApprovedEditButton extends StatelessWidget {
  const _ApprovedEditButton({required this.onPressed, required this.tooltip});
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints.tightFor(
        width: metrics.geometry(24.375),
        height: metrics.geometry(24.375),
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: HocalistPalette.text(context, _approvedBlue),
        backgroundColor: HocalistPalette.surface(context, _approvedLavender),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(7)),
        ),
      ),
      icon: BuyerGlyphIcon(
        icon: Icons.edit,
        slotSize: metrics.geometry(10.97),
        glyphSize: metrics.geometry(10.97),
      ),
    );
  }
}

class _ApprovedAssetIcon extends StatelessWidget {
  const _ApprovedAssetIcon({required this.asset, required this.size});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (asset == _descriptionIcon) {
      return BuyerGlyphIcon(
        icon: Icons.description_outlined,
        slotSize: size,
        glyphSize: size,
        color: HocalistPalette.text(context, _approvedBlue),
      );
    }
    return BuyerAssetIcon(
      asset: asset,
      slotSize: size,
      color: Theme.of(context).brightness == Brightness.dark
          ? HocalistPalette.text(context, _approvedBlue)
          : null,
    );
  }
}

class _ApprovedPageTitle extends StatelessWidget {
  const _ApprovedPageTitle({
    required this.title,
    this.onBack,
    this.referenceFontSize = 18,
    this.textAlign = TextAlign.start,
  });
  final String title;
  final VoidCallback? onBack;
  final double referenceFontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final titleStyle = BuyerTypography.style(
      context,
      metrics,
      BuyerTextRole.pageTitle,
      color: _approvedNavy,
    ).copyWith(fontSize: _requestFontSize(metrics, referenceFontSize));
    if (onBack == null) {
      return Text(title, textAlign: textAlign, style: titleStyle);
    }
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          constraints: BoxConstraints.tightFor(
            width: metrics.geometry(34.125),
            height: metrics.geometry(34.125),
          ),
          padding: EdgeInsets.zero,
          icon: BuyerGlyphIcon(
            icon: Icons.arrow_back,
            slotSize: metrics.geometry(20.72),
            glyphSize: metrics.geometry(20.72),
            color: HocalistPalette.text(context, _approvedNavy),
          ),
        ),
        SizedBox(width: metrics.geometry(2.44)),
        Expanded(
          child: Text(title, textAlign: textAlign, style: titleStyle),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration(BuildContext context, {bool compact = false}) {
  final metrics = _replicaMetrics(context);
  return InputDecoration(
    isDense: false,
    filled: true,
    fillColor: HocalistPalette.surface(context, Colors.white),
    constraints: metrics.screenshotLocked
        ? BoxConstraints(
            minHeight: compact
                ? _requestDimension(
                    metrics,
                    HocalistInputTokens.compactMinimumHeight,
                    floor: 40,
                  )
                : _requestDimension(
                    metrics,
                    HocalistInputTokens.minimumHeight,
                    floor: 44,
                  ),
          )
        : null,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compact
          ? _requestDimension(
              metrics,
              HocalistInputTokens.compactHorizontalPadding,
              floor: 10,
            )
          : _requestDimension(
              metrics,
              HocalistInputTokens.horizontalPadding,
              floor: 12,
            ),
      vertical: compact
          ? _requestDimension(
              metrics,
              HocalistInputTokens.compactVerticalPadding,
              floor: 9,
            )
          : _requestDimension(
              metrics,
              HocalistInputTokens.verticalPadding,
              floor: 10,
            ),
    ),
    hintStyle: _requestHintStyle(context),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      borderSide: BorderSide(
        color: HocalistPalette.border(context, _approvedBorder),
        width: metrics.geometry(1),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      borderSide: BorderSide(
        color: HocalistPalette.border(context, _approvedBlue),
        width: metrics.geometry(1.5),
      ),
    ),
  );
}

TextStyle _titleStyle(BuildContext context, double size) {
  final metrics = _replicaMetrics(context);
  final approvedSize = switch (size) {
    >= 18 => 14.625,
    >= 16 => 12.19,
    >= 13 => 10.36,
    _ => size,
  };
  return (Theme.of(context).textTheme.headlineSmall ?? const TextStyle())
      .copyWith(
        color: HocalistPalette.text(context, _approvedNavy),
        fontSize: _requestFontSize(metrics, approvedSize),
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: 0,
      );
}

TextStyle _sectionStyle(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
      .copyWith(
        color: HocalistPalette.text(context, _approvedNavy),
        fontSize: _requestFontSize(metrics, 10.5),
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: 0,
      );
}

TextStyle _bodyStyle(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: HocalistPalette.text(context, _approvedNavy),
    fontSize: _requestFontSize(metrics, 11.5),
    fontWeight: FontWeight.w400,
    height: 1.22,
    letterSpacing: 0,
  );
}

TextStyle _requestInputStyle(BuildContext context) {
  return _bodyStyle(context).copyWith(
    color: HocalistPalette.text(context, _approvedNavy),
    fontWeight: FontWeight.w600,
  );
}

TextStyle _requestHintStyle(BuildContext context) {
  return _bodyStyle(context).copyWith(
    color: HocalistPalette.text(
      context,
      _approvedMuted.withValues(alpha: 0.82),
    ),
    fontWeight: FontWeight.w500,
  );
}

TextStyle _smallStyle(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
    color: HocalistPalette.text(context, _approvedMuted),
    fontSize: _requestFontSize(metrics, 10.5),
    fontWeight: FontWeight.w400,
    height: 1.18,
    letterSpacing: 0,
  );
}
