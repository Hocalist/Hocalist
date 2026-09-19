import 'package:flutter/material.dart';

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
    super.key,
  });

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

  @override
  State<ApprovedRequestFlowPage> createState() =>
      _ApprovedRequestFlowPageState();
}

class _ApprovedRequestFlowPageState extends State<ApprovedRequestFlowPage> {
  final ScrollController _scrollController = ScrollController();
  late ApprovedRequestKind _kind;
  _ApprovedRequestStep _step = _ApprovedRequestStep.details;
  int _quantity = 1;
  bool _acceptHigherOffers = true;
  bool _useHomeAddress = true;
  String _condition = 'New';
  String _serviceType = 'Single';
  String _minimum = '';
  String _maximum = '';

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showStep(_ApprovedRequestStep step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
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
                style: _bodyStyle(context).copyWith(color: _approvedMuted),
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
                onChanged: (value) => setState(() => _kind = value),
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
              duration: const Duration(milliseconds: 160),
              child: isLocation
                  ? ApprovedLocationRequestStep(
                      key: const ValueKey('approved-location-step'),
                      useHomeAddress: _useHomeAddress,
                      onUseHomeAddressChanged: (value) {
                        setState(() => _useHomeAddress = value);
                      },
                      onBack: () {
                        _showStep(_ApprovedRequestStep.details);
                      },
                      onSubmit: widget.onSubmit,
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
                      onContinue: () {
                        _showStep(_ApprovedRequestStep.location);
                      },
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
                      onContinue: () {
                        _showStep(_ApprovedRequestStep.location);
                      },
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
            color: _approvedNavy,
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
                : const _ApprovedCategoryPanel(),
            _ApprovedHigherOffersPanel(
              value: acceptHigherOffers,
              onChanged: onAcceptHigherOffersChanged,
            ),
          ],
        ),
        SizedBox(height: metrics.geometry(2)),
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
    this.homeAddressLine1 = '123 Main Street',
    this.homeAddressLine2 = 'Miami, FL 33101, USA',
    this.countryLabel = 'United States',
    super.key,
  });

  final bool useHomeAddress;
  final ValueChanged<bool> onUseHomeAddressChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final String homeAddressLine1;
  final String homeAddressLine2;
  final String countryLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      children: [
        Text(
          'Where do you need this service?',
          textAlign: TextAlign.center,
          style: _titleStyle(context, 16),
        ),
        SizedBox(height: metrics.geometry(6)),
        Text(
          'Sellers will be able to only see your\nlocation once you close the deal.',
          textAlign: TextAlign.center,
          style: _bodyStyle(context).copyWith(
            color: _approvedMuted,
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
                    color: const Color(0xfffaf9ff),
                    borderRadius: BorderRadius.circular(metrics.geometry(9)),
                    border: Border.all(
                      color: useHomeAddress ? _approvedBlue : _approvedBorder,
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
                                  color: _approvedMuted,
                                  width: metrics.geometry(1.5),
                                ),
                              ),
                            ),
                          SizedBox(width: metrics.geometry(7)),
                          Container(
                            width: metrics.geometry(32),
                            height: metrics.geometry(32),
                            decoration: const BoxDecoration(
                              color: _approvedLavender,
                              shape: BoxShape.circle,
                            ),
                            child: BuyerGlyphIcon(
                              icon: Icons.home_outlined,
                              slotSize: _requestDimension(
                                metrics,
                                17,
                                floor: 16,
                              ),
                              color: _approvedBlue,
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
              const _ApprovedAddressField(
                label: 'Street address',
                hint: '123 Main St',
              ),
              SizedBox(height: metrics.geometry(5)),
              const _ApprovedAddressField(
                label: 'Apartment, suite, etc. (optional)',
                hint: 'Apt 4B, Suite 200, etc.',
              ),
              SizedBox(height: metrics.geometry(5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: _ApprovedAddressField(
                      label: 'City',
                      hint: 'Enter city',
                    ),
                  ),
                  SizedBox(width: metrics.geometry(12)),
                  const Expanded(
                    child: _ApprovedAddressField(
                      label: 'State',
                      hint: 'Select state',
                      dropdown: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: _ApprovedAddressField(
                      label: 'ZIP code',
                      hint: 'Enter ZIP code',
                    ),
                  ),
                  SizedBox(width: metrics.geometry(12)),
                  Expanded(
                    child: _ApprovedAddressField(
                      label: 'Country',
                      hint: 'Select country',
                      value: countryLabel,
                      dropdown: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.geometry(12)),
        _ApprovedLocationActions(onBack: onBack, onSubmit: onSubmit),
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
        color: _approvedLavender,
        borderRadius: BorderRadius.circular(metrics.geometry(999)),
      ),
      child: Text(
        'Recommended',
        style: _smallStyle(
          context,
        ).copyWith(color: _approvedBlue, fontWeight: FontWeight.w800),
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
    super.key,
  });

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

  @override
  State<ApprovedBuyerRequestDetailsPage> createState() =>
      _ApprovedBuyerRequestDetailsPageState();
}

class _ApprovedBuyerRequestDetailsPageState
    extends State<ApprovedBuyerRequestDetailsPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _isNew = true;
  bool _acceptHigherOffers = true;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.requestTitle);
    _descriptionController = TextEditingController(
      text:
          'Looking for an iPad Air 5th generation or newer.\n'
          'Prefer 64GB or higher, in excellent condition.\n'
          'Must include original charger and box.\n'
          "Color doesn't matter.",
    );
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

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedRequestDecisionSheet(
        key: const ValueKey('approved-delete-request-sheet'),
        asset: 'assets/post_request/info.png',
        title: 'Delete this request?',
        message:
            'This removes the request from your active list and stops new offers from sellers.',
        primaryLabel: 'Delete request',
        destructive: true,
        onCancel: () => Navigator.pop(sheetContext, false),
        onPrimary: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed == true && mounted) {
      _message('Delete preview only - no request was removed.');
    }
  }

  Future<void> _confirmSave() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedRequestDecisionSheet(
        key: const ValueKey('approved-update-request-sheet'),
        asset: 'assets/post_request/info.png',
        title: 'Update your request?',
        message:
            'Your active sellers will be notified. They may continue with the updated request or withdraw, and your estimated rewards may change.',
        primaryLabel: 'Update request',
        onCancel: () => Navigator.pop(sheetContext, false),
        onPrimary: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed == true && mounted) {
      widget.onSaveRequest?.call();
      _message('Request updated. Active sellers were notified.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final metrics = ApprovedReplicaMetrics.resolve(
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
              style: _bodyStyle(context).copyWith(color: _approvedNavy),
            ),
            SizedBox(height: metrics.geometry(13)),
            _ApprovedRequestSummary(
              requestTitle: widget.requestTitle,
              budget: widget.budget,
              location: widget.locationLabel,
              onDelete: _confirmDelete,
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
              title: 'Describe the product',
              helper:
                  'Include key details so sellers can give you accurate offers.',
              trailing: '${_descriptionController.text.length}/500',
              onEdit: () => _message('Edit the product description below.'),
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
            SizedBox(height: metrics.geometry(10)),
            _ApprovedResponsiveGrid(
              preserveColumnsAtNormalScale: true,
              referenceSpacing: 4,
              referenceRunSpacing: 4,
              children: [
                _ApprovedDetailChoicePanel(
                  referenceHeight: 86,
                  iconAsset: _conditionIcon,
                  title: 'Condition',
                  helper: 'Select your preference',
                  onEdit: () => _message('Choose New or Used below.'),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ApprovedTextChoice(
                          label: 'New',
                          selected: _isNew,
                          onTap: () => setState(() => _isNew = true),
                        ),
                      ),
                      SizedBox(width: metrics.geometry(8)),
                      Expanded(
                        child: _ApprovedTextChoice(
                          label: 'Used',
                          selected: !_isNew,
                          onTap: () => setState(() => _isNew = false),
                        ),
                      ),
                    ],
                  ),
                ),
                _ApprovedDetailBudgetPanel(
                  referenceHeight: 86,
                  onEdit: () => _message('Edit the budget range below.'),
                ),
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
                  location: widget.locationLabel,
                  onTap: () => _message('Location editor preview opened.'),
                ),
                _ApprovedRewardsPanel(
                  referenceHeight: 69,
                  onOffers: widget.onOffers,
                ),
              ],
            ),
            SizedBox(height: metrics.geometry(5)),
            _ApprovedSavePanel(onSave: _confirmSave),
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
      backgroundColor: Colors.white,
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
        color: Colors.white,
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
                    color: _approvedNavy,
                  ),
                ),
              ),
              Image.asset(
                'assets/brand/hocalist-wordmark.png',
                width: metrics.geometry(95),
                height: metrics.geometry(53.625),
                fit: BoxFit.contain,
                semanticLabel: 'Hocalist Reverse Marketplace',
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
                        color: _approvedLavender,
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
                            metrics.accessibilityReflow || metrics.isNarrow
                                ? 'Buyer'
                                : 'Buyer mode',
                            maxLines: 1,
                            softWrap: false,
                            style: _smallStyle(context).copyWith(
                              color: _approvedBlue,
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
                      icon: _ApprovedAssetIcon(
                        asset: _notificationIcon,
                        size: metrics.geometry(28),
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
    return Material(
      color: selected ? const Color(0xfff8f7ff) : Colors.white,
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        child: Container(
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
              color: selected ? _approvedBlue : _approvedBorder,
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
                  color: selected ? _approvedBlue : _approvedNavy,
                  fontSize: _requestFontSize(metrics, 11),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    return Padding(
      padding: metrics.accessibilityReflow
          ? EdgeInsets.symmetric(horizontal: metrics.geometry(28))
          : metrics.geometryInsets(
              const EdgeInsets.only(left: 75.56, right: 104.81),
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
                color: _approvedBlue,
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
            color: active ? _approvedBlue : const Color(0xffe7e8ee),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: _bodyStyle(context).copyWith(
              color: active ? Colors.white : _approvedNavy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: metrics.geometry(2.44)),
        Text(
          label,
          style: _smallStyle(context).copyWith(
            color: active ? _approvedBlue : _approvedNavy,
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
    this.onChanged,
    this.maxLines = 1,
    this.counterText,
  });

  final String title;
  final String helper;
  final String iconAsset;
  final String hint;
  final String? initialValue;
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
      initialValue: initialValue,
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
                color: const Color(0xffedf0f8),
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
            style: _smallStyle(
              context,
            ).copyWith(color: _approvedNavy, fontWeight: FontWeight.w700),
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
                            color: _approvedNavy,
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
            color: selected ? _approvedBlue : _approvedBorder,
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
                  color: _approvedNavy,
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
      style: _smallStyle(
        context,
      ).copyWith(color: _approvedNavy, fontWeight: FontWeight.w800),
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
                color: _approvedBorder,
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
  const _ApprovedCategoryPanel();

  @override
  State<_ApprovedCategoryPanel> createState() => _ApprovedCategoryPanelState();
}

class _ApprovedCategoryPanelState extends State<_ApprovedCategoryPanel> {
  String? _category;

  Future<void> _chooseCategory() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
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
        initialValue: _category,
      ),
    );
    if (selected != null && mounted) setState(() => _category = selected);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return _ApprovedSurface(
      referenceHeight: 105,
      referenceVerticalPadding: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ApprovedPanelTitle(
            iconAsset: _categoryIcon,
            title: 'Category',
            optional: true,
          ),
          SizedBox(height: metrics.geometry(4)),
          Text('This avoids mismatch.', style: _smallStyle(context)),
          SizedBox(height: metrics.geometry(8)),
          InkWell(
            key: const Key('approved-request-category-select'),
            onTap: _chooseCategory,
            borderRadius: BorderRadius.circular(metrics.geometry(8)),
            child: Container(
              height: metrics.geometry(30.47),
              padding: EdgeInsets.symmetric(horizontal: metrics.geometry(6.1)),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _approvedBorder,
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
                      _category ?? 'Select a category',
                      style: _category == null
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
                          color: _approvedNavy,
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
                        style: _smallStyle(
                          context,
                        ).copyWith(color: _approvedNavy),
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
          foregroundColor: _approvedNavy,
          side: BorderSide(
            color: selected ? _approvedBlue : _approvedBorder,
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
              color: selected ? _approvedBlue : _approvedNavy,
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
                color: _approvedBlue,
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
  const _ApprovedPrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

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
          backgroundColor: accessibility.backgroundOr(_approvedBlue),
          foregroundColor: accessibility.foregroundOr(Colors.white),
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
          label,
          maxLines: 1,
          softWrap: false,
          style: _bodyStyle(context).copyWith(
            color: Colors.white,
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
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ApprovedPrimaryButton(label: 'Post request', onPressed: onSubmit),
        SizedBox(height: metrics.geometry(4.875)),
        TextButton(
          onPressed: onBack,
          style: TextButton.styleFrom(
            minimumSize: Size(0, _requestDimension(metrics, 32, floor: 32)),
            foregroundColor: _approvedBlue,
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
              color: _approvedBlue,
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
  });

  final String label;
  final String hint;
  final String? value;
  final bool dropdown;

  @override
  State<_ApprovedAddressField> createState() => _ApprovedAddressFieldState();
}

class _ApprovedAddressFieldState extends State<_ApprovedAddressField> {
  late String? _selectedValue = widget.value;
  late final TextEditingController _fieldController = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  Future<void> _chooseValue() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
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
    if (selected != null && mounted) {
      _fieldController.text = selected;
      setState(() => _selectedValue = selected);
    }
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
        color: _approvedBorder,
        width: metrics.geometry(1),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: _smallStyle(
            context,
          ).copyWith(color: _approvedNavy, fontWeight: FontWeight.w600),
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
            style: _requestInputStyle(
              context,
            ).copyWith(fontSize: fieldFontSize),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: false,
              filled: true,
              fillColor: Colors.white,
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
                  color: _approvedBlue,
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
                        color: _approvedMuted,
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
  });

  final String requestTitle;
  final String budget;
  final String location;
  final VoidCallback onDelete;

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
                    color: _approvedBorder,
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
                  color: const Color(0xffe8f8ed),
                  borderRadius: BorderRadius.circular(metrics.geometry(999)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BuyerGlyphIcon(
                      icon: Icons.circle,
                      slotSize: metrics.geometry(6.1),
                      glyphSize: metrics.geometry(6.1),
                      color: const Color(0xff0ca64a),
                    ),
                    SizedBox(width: metrics.geometry(2.44)),
                    Text(
                      'Active',
                      style: TextStyle(
                        color: const Color(0xff07933e),
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
                  foregroundColor: Colors.red,
                  side: BorderSide(
                    color: _approvedBorder,
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
                  'Delete',
                  style: TextStyle(fontSize: _requestFontSize(metrics, 10.5)),
                ),
              ),
            ],
          );
          if (metrics.screenshotLocked) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                image,
                SizedBox(width: metrics.geometry(7.31)),
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
                  image,
                  SizedBox(width: metrics.geometry(12)),
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
                color: _approvedBlue,
              ),
              SizedBox(width: metrics.geometry(4)),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                style: _bodyStyle(
                  context,
                ).copyWith(color: _approvedBlue, fontWeight: FontWeight.w800),
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
  });
  final double referenceHeight;
  final VoidCallback onEdit;

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
          const Expanded(child: _ApprovedValueBox(value: '\$350')),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _replicaMetrics(context).geometry(7),
            ),
            child: const Text('-'),
          ),
          const Expanded(child: _ApprovedValueBox(value: '\$480')),
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
            color: _approvedBorder,
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
        border: Border.all(color: _approvedBorder, width: metrics.geometry(1)),
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
                color: _approvedNavy,
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
                        color: _approvedBlue,
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
                color: _approvedNavy,
              ),
            ],
          ),
        ),
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
            decoration: const BoxDecoration(
              color: Color(0xffffb21c),
              shape: BoxShape.circle,
            ),
            child: BuyerGlyphIcon(
              icon: Icons.star,
              slotSize: metrics.geometry(13.4),
              glyphSize: metrics.geometry(13.4),
              color: Colors.white,
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
                        color: const Color(0xff0ca64a),
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
                          color: const Color(0xffe3f7e9),
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(12),
                          ),
                        ),
                        child: Text(
                          '32 offers',
                          style: TextStyle(
                            color: const Color(0xff0c9845),
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
            color: _approvedBlue,
          ),
        ],
      ),
    );
  }
}

class _ApprovedSavePanel extends StatelessWidget {
  const _ApprovedSavePanel({required this.onSave});
  final VoidCallback onSave;

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
            onPressed: onSave,
            style: FilledButton.styleFrom(
              minimumSize: Size(0, metrics.geometry(30.47)),
              tapTargetSize: metrics.screenshotLocked
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
              padding: EdgeInsets.symmetric(
                horizontal: metrics.geometry(8.53),
                vertical: metrics.geometry(2.44),
              ),
              backgroundColor: accessibility.backgroundOr(_approvedBlue),
              foregroundColor: accessibility.foregroundOr(Colors.white),
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
                      color: accessibility.foregroundOr(Colors.white),
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
        iconColor: actionColor,
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
        color: _approvedSurface,
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        border: Border.all(
          color: const Color(0xfff2f3f8),
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
        foregroundColor: _approvedBlue,
        backgroundColor: _approvedLavender,
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
        color: _approvedBlue,
      );
    }
    return BuyerAssetIcon(asset: asset, slotSize: size);
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
            color: _approvedNavy,
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
    fillColor: Colors.white,
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
        color: _approvedBorder,
        width: metrics.geometry(1),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(8)),
      borderSide: BorderSide(
        color: _approvedBlue,
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
        color: _approvedNavy,
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
        color: _approvedNavy,
        fontSize: _requestFontSize(metrics, 10.5),
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: 0,
      );
}

TextStyle _bodyStyle(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: _approvedNavy,
    fontSize: _requestFontSize(metrics, 11.5),
    fontWeight: FontWeight.w400,
    height: 1.22,
    letterSpacing: 0,
  );
}

TextStyle _requestInputStyle(BuildContext context) {
  return _bodyStyle(
    context,
  ).copyWith(color: _approvedNavy, fontWeight: FontWeight.w600);
}

TextStyle _requestHintStyle(BuildContext context) {
  return _bodyStyle(context).copyWith(
    color: _approvedMuted.withValues(alpha: 0.82),
    fontWeight: FontWeight.w500,
  );
}

TextStyle _smallStyle(BuildContext context) {
  final metrics = _replicaMetrics(context);
  return (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
    color: _approvedMuted,
    fontSize: _requestFontSize(metrics, 10.5),
    fontWeight: FontWeight.w400,
    height: 1.18,
    letterSpacing: 0,
  );
}
