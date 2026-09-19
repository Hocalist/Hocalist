part of '../../main.dart';

class AccessibilityPage extends StatefulWidget {
  const AccessibilityPage({
    required this.appliedPreferences,
    required this.onApply,
    required this.onBack,
    super.key,
  });

  final AccessibilityPreferences appliedPreferences;
  final ValueChanged<AccessibilityPreferences> onApply;
  final VoidCallback onBack;

  @override
  State<AccessibilityPage> createState() => _AccessibilityPageState();
}

class _AccessibilityPageState extends State<AccessibilityPage> {
  static const _primary = Color(0xff4011ff);
  static const _highContrast = Color(0xff2b11aa);
  static const _ink = Color(0xff070b38);
  static const _muted = Color(0xff22264e);
  static const _lavender = Color(0xfff8f7fd);
  static const _greenSurface = Color(0xfff1faf5);
  static const _green = Color(0xff079447);
  static const _outline = Color(0xffd9d8dd);

  late AccessibilityPreferences draft;

  bool get hasChanges => draft != widget.appliedPreferences;

  @override
  void initState() {
    super.initState();
    draft = widget.appliedPreferences;
  }

  @override
  void didUpdateWidget(covariant AccessibilityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appliedPreferences != widget.appliedPreferences &&
        !hasChanges) {
      draft = widget.appliedPreferences;
    }
  }

  Future<void> _requestBack() async {
    if (!hasChanges) {
      widget.onBack();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard accessibility changes?'),
        content: const Text(
          'Your preview choices have not been applied to Hocalist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) widget.onBack();
  }

  void _setTextSize(AppTextSize value) {
    setState(() => draft = draft.copyWith(textSize: value));
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${value.label} text selected',
      TextDirection.ltr,
    );
  }

  void _setFont(AccessibilityFontStyle value) {
    setState(() => draft = draft.copyWith(fontStyle: value));
  }

  void _setButton(AccessibilityButtonStyle value) {
    setState(() => draft = draft.copyWith(buttonStyle: value));
  }

  Future<void> _showPreview() async {
    final currentScale = MediaQuery.textScalerOf(context).scale(1);
    final appliedScale = widget.appliedPreferences.textSize.scale;
    final systemScale = currentScale > appliedScale ? currentScale : 1.0;
    final previewScale = math.max(systemScale, draft.textSize.scale);
    final applied = await showDialog<bool>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(previewScale)),
          child: Theme(
            data: HocalistTheme.lightFor(draft),
            child: Dialog.fullscreen(
              child: SafeArea(
                child: Scaffold(
                  backgroundColor: Colors.white,
                  body: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Close preview',
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            icon: const Icon(Icons.close),
                          ),
                          const Expanded(
                            child: Text(
                              'Preview',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'This is how Hocalist will look',
                        style: Theme.of(dialogContext).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Review titles, descriptions, controls, and buttons before applying your selection.',
                        style: Theme.of(dialogContext).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      const TextField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Example field',
                          hintText: 'Your content remains easy to read',
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Example request card',
                              style: Theme.of(
                                dialogContext,
                              ).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Important descriptions can wrap without hiding the next action.',
                              style: Theme.of(
                                dialogContext,
                              ).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Apply changes',
                        icon: Icons.check_circle_outline,
                        color: _primary,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: 'Cancel',
                        color: _primary,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (applied == true && mounted) {
      widget.onApply(draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _AccessibilityReplicaMetrics.resolve(
          availableWidth: constraints.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return _AccessibilityReplicaScope(
          metrics: metrics,
          child: ColoredBox(
            color: Colors.white,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
                child: ListView(
                  key: const Key('accessibility-page-scroll'),
                  padding: metrics.insets(
                    const EdgeInsets.fromLTRB(18, 5, 18, 16),
                  ),
                  children: [
                    _AccessibilityHeader(onBack: _requestBack),
                    SizedBox(height: metrics.size(5)),
                    _IntroPanel(compact: metrics.accessibilityReflow),
                    SizedBox(height: metrics.size(23)),
                    const _SectionHeading(
                      title: '1. Choose your text size',
                      instruction:
                          'Select the size that is easiest for you to read.',
                    ),
                    SizedBox(height: metrics.size(7)),
                    _ResponsiveOptionGrid(
                      normalColumns: 4,
                      spacing: metrics.size(6),
                      children: AppTextSize.values.map((size) {
                        final sampleSize = switch (size) {
                          AppTextSize.small => 24.0,
                          AppTextSize.medium => 26.0,
                          AppTextSize.large => 28.0,
                          AppTextSize.extraLarge => 30.0,
                        };
                        return _OptionCard(
                          key: Key('text-size-${size.name}'),
                          selected: draft.textSize == size,
                          semanticLabel: '${size.label} text size',
                          minHeight: metrics.size(63),
                          onTap: () => _setTextSize(size),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Aa',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  color: _ink,
                                  fontFamily: draft.fontFamily,
                                  fontSize: metrics.font(sampleSize * 0.9),
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: metrics.size(7)),
                              Text(
                                size.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: draft.textSize == size
                                      ? _primary
                                      : _ink,
                                  fontSize: metrics.font(10.5),
                                  height: 1.08,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: metrics.size(12)),
                    _TextPreviewPanel(preferences: draft),
                    SizedBox(height: metrics.size(20)),
                    const _SectionHeading(
                      title: '2. Choose your font style',
                      instruction:
                          'Pick the font that is clearest and most comfortable for you.',
                    ),
                    SizedBox(height: metrics.size(7)),
                    _ResponsiveOptionGrid(
                      normalColumns: 3,
                      spacing: metrics.size(6),
                      children: AccessibilityFontStyle.values.map((style) {
                        final label = switch (style) {
                          AccessibilityFontStyle.standard => 'Default',
                          AccessibilityFontStyle.friendly => 'Friendly',
                          AccessibilityFontStyle.highContrast =>
                            'High Contrast',
                        };
                        final family = AccessibilityPreferences.defaults
                            .copyWith(fontStyle: style)
                            .fontFamily;
                        return _OptionCard(
                          key: Key('font-style-${style.name}'),
                          selected: draft.fontStyle == style,
                          semanticLabel: '$label font style',
                          minHeight: metrics.size(61),
                          onTap: () => _setFont(style),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                style == AccessibilityFontStyle.highContrast
                                    ? 'HOCALIST'
                                    : 'Hocalist',
                                textScaler: TextScaler.noScaling,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _ink,
                                  fontFamily: family,
                                  fontSize:
                                      style ==
                                          AccessibilityFontStyle.highContrast
                                      ? metrics.font(13.5)
                                      : metrics.font(15.5),
                                  height: 1,
                                  fontWeight:
                                      style ==
                                          AccessibilityFontStyle.highContrast
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: metrics.size(8)),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: draft.fontStyle == style
                                      ? _primary
                                      : _ink,
                                  fontSize: metrics.font(10.5),
                                  height: 1.08,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: metrics.size(20)),
                    const _SectionHeading(
                      title: '3. Choose your button style',
                      instruction:
                          'Pick the button design that is easiest for you to see and tap.',
                    ),
                    SizedBox(height: metrics.size(7)),
                    _ResponsiveOptionGrid(
                      normalColumns: 2,
                      spacing: metrics.size(6),
                      children: [
                        _ButtonStyleOption(
                          style: AccessibilityButtonStyle.rounded,
                          selected:
                              draft.buttonStyle ==
                              AccessibilityButtonStyle.rounded,
                          onTap: () =>
                              _setButton(AccessibilityButtonStyle.rounded),
                        ),
                        _ButtonStyleOption(
                          style: AccessibilityButtonStyle.highContrast,
                          selected:
                              draft.buttonStyle ==
                              AccessibilityButtonStyle.highContrast,
                          onTap: () =>
                              _setButton(AccessibilityButtonStyle.highContrast),
                        ),
                      ],
                    ),
                    SizedBox(height: metrics.size(16)),
                    _FullPreviewPanel(
                      compact: metrics.accessibilityReflow,
                      onPreview: _showPreview,
                    ),
                    SizedBox(height: metrics.size(7)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccessibilityHeader extends StatelessWidget {
  const _AccessibilityHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = textScale <= 1.15
        ? metrics.size(68)
        : (68 + (textScale - 1) * 150).clamp(92.0, 160.0);
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Accessibility',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _AccessibilityPageState._ink,
                    fontSize: metrics.font(20),
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: metrics.size(5)),
                Text(
                  'Customize Hocalist to fit your needs',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _AccessibilityPageState._ink,
                    fontSize: metrics.font(10.5),
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: metrics.size(-13),
            top: (height - metrics.size(44)) / 2,
            child: IconButton(
              key: const Key('accessibility-back'),
              tooltip: 'Back',
              onPressed: onBack,
              constraints: BoxConstraints.tightFor(
                width: metrics.size(44),
                height: metrics.size(44),
              ),
              icon: Image.asset(
                'assets/accessibility/icons/back-chevron.png',
                width: metrics.size(17),
                height: metrics.size(25),
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    final icon = Container(
      width: metrics.size(49),
      height: metrics.size(49),
      decoration: const BoxDecoration(
        color: Color(0xffeeeaff),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/accessibility/icons/accessibility-person.png',
        width: metrics.size(30),
        height: metrics.size(36),
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Make Hocalist easier to read and use',
          style: TextStyle(
            color: _AccessibilityPageState._ink,
            fontSize: metrics.font(13.5),
            height: 1.12,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: metrics.size(6)),
        Text(
          'Choose the text size, fonts, and button style that work best for you. You can change these anytime.',
          style: TextStyle(
            color: _AccessibilityPageState._muted,
            fontSize: metrics.font(10.5),
            height: 1.24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return Container(
      key: const Key('accessibility-intro-panel'),
      constraints: BoxConstraints(minHeight: metrics.size(78)),
      padding: metrics.insets(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      decoration: BoxDecoration(
        color: _AccessibilityPageState._lavender,
        borderRadius: BorderRadius.circular(metrics.size(8)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                SizedBox(height: metrics.size(10)),
                copy,
              ],
            )
          : Row(
              children: [
                icon,
                SizedBox(width: metrics.size(12)),
                Expanded(child: copy),
              ],
            ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.instruction});

  final String title;
  final String instruction;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _AccessibilityPageState._ink,
            fontSize: metrics.font(12),
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: metrics.size(5)),
        Text(
          instruction,
          style: TextStyle(
            color: _AccessibilityPageState._muted,
            fontSize: metrics.font(10.5),
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResponsiveOptionGrid extends StatelessWidget {
  const _ResponsiveOptionGrid({
    required this.children,
    required this.normalColumns,
    required this.spacing,
  });

  final List<Widget> children;
  final int normalColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = !metrics.accessibilityReflow
            ? normalColumns
            : normalColumns == 4
            ? 2
            : 1;
        columns = columns.clamp(1, children.length);
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.semanticLabel,
    required this.minHeight,
    required this.onTap,
    required this.child,
    super.key,
  });

  final bool selected;
  final String semanticLabel;
  final double minHeight;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.size(8)),
          side: BorderSide(
            color: selected
                ? _AccessibilityPageState._primary
                : _AccessibilityPageState._outline,
            width: metrics.size(selected ? 1.5 : 1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Stack(
              children: [
                Padding(
                  padding: metrics.insets(
                    const EdgeInsets.fromLTRB(5, 8, 5, 7),
                  ),
                  child: SizedBox(width: double.infinity, child: child),
                ),
                if (selected)
                  Positioned(
                    top: metrics.size(3),
                    right: metrics.size(3),
                    child: Image.asset(
                      'assets/accessibility/icons/selection-check.png',
                      width: metrics.size(16),
                      height: metrics.size(16),
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
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

class _TextPreviewPanel extends StatelessWidget {
  const _TextPreviewPanel({required this.preferences});

  final AccessibilityPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    final scale = switch (preferences.textSize) {
      AppTextSize.small => 0.82,
      AppTextSize.medium => 0.9,
      AppTextSize.large => 1.0,
      AppTextSize.extraLarge => 1.14,
    };
    return MediaQuery.withNoTextScaling(
      child: Container(
        key: const Key('accessibility-text-preview-panel'),
        constraints: BoxConstraints(minHeight: metrics.size(104)),
        padding: metrics.insets(const EdgeInsets.fromLTRB(14, 13, 14, 12)),
        decoration: BoxDecoration(
          color: _AccessibilityPageState._lavender,
          borderRadius: BorderRadius.circular(metrics.size(8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/accessibility/icons/preview-eye-primary.png',
                  width: metrics.size(15),
                  height: metrics.size(12),
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                SizedBox(width: metrics.size(6)),
                Text(
                  'Preview',
                  style: TextStyle(
                    color: _AccessibilityPageState._primary,
                    fontFamily: preferences.fontFamily,
                    fontSize: metrics.font(10.5) * scale,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.size(11)),
            Text(
              'This is how text will look',
              style: TextStyle(
                color: _AccessibilityPageState._ink,
                fontFamily: preferences.fontFamily,
                fontSize: metrics.font(17) * scale,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: metrics.size(7)),
            Text(
              'You can preview how titles, descriptions, and buttons will appear throughout the app.',
              style: TextStyle(
                color: _AccessibilityPageState._muted,
                fontFamily: preferences.fontFamily,
                fontSize: metrics.font(11.5) * scale,
                height: 1.22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonStyleOption extends StatelessWidget {
  const _ButtonStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AccessibilityButtonStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    final rounded = style == AccessibilityButtonStyle.rounded;
    final referenceWidth = metrics.size(rounded ? 135.0 : 131.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = math.min(
          referenceWidth,
          math.max(metrics.size(88), constraints.maxWidth - metrics.size(36)),
        );
        return _OptionCard(
          key: Key('button-style-${style.name}'),
          selected: selected,
          semanticLabel: rounded
              ? 'Rounded button style'
              : 'High Contrast button style',
          minHeight: metrics.size(73),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(top: metrics.size(5)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  key: Key('button-preview-${style.name}'),
                  width: previewWidth,
                  height: metrics.size(29),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rounded
                        ? null
                        : _AccessibilityPageState._highContrast,
                    gradient: rounded
                        ? const LinearGradient(
                            colors: [Color(0xff5215ff), Color(0xff2f00ed)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(
                      metrics.size(rounded ? 15 : 3),
                    ),
                  ),
                  child: Text(
                    rounded ? 'Continue' : 'CONTINUE',
                    key: Key('button-preview-label-${style.name}'),
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: HocalistTheme.appFontFamily,
                      fontSize: metrics.font(10.5),
                      height: 1,
                      fontWeight: rounded ? FontWeight.w600 : FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                SizedBox(height: metrics.size(8)),
                Text(
                  rounded ? 'Rounded (Default)' : 'High Contrast',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? _AccessibilityPageState._primary
                        : _AccessibilityPageState._ink,
                    fontFamily: HocalistTheme.appFontFamily,
                    fontSize: metrics.font(10),
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FullPreviewPanel extends StatelessWidget {
  const _FullPreviewPanel({required this.compact, required this.onPreview});

  final bool compact;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final metrics = _AccessibilityReplicaScope.of(context);
    final icon = Image.asset(
      'assets/accessibility/icons/preview-check-success.png',
      width: metrics.size(40),
      height: metrics.size(44),
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Preview your selection',
          style: TextStyle(
            color: _AccessibilityPageState._ink,
            fontSize: metrics.font(12),
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: metrics.size(6)),
        Text(
          'See how Hocalist will look with your current settings.',
          style: TextStyle(
            color: _AccessibilityPageState._muted,
            fontSize: metrics.font(10.5),
            height: 1.28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final button = OutlinedButton.icon(
      key: const Key('show-accessibility-preview'),
      onPressed: onPreview,
      style: OutlinedButton.styleFrom(
        foregroundColor: _AccessibilityPageState._green,
        side: const BorderSide(color: _AccessibilityPageState._green),
        minimumSize: Size(metrics.size(110), metrics.size(44)),
        padding: metrics.insets(
          const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.size(7)),
        ),
      ),
      icon: Image.asset(
        'assets/accessibility/icons/preview-eye-success.png',
        width: metrics.size(17),
        height: metrics.size(13),
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
      label: Text(
        'Show Preview',
        style: TextStyle(
          fontSize: metrics.font(10.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Container(
      key: const Key('accessibility-full-preview-panel'),
      constraints: BoxConstraints(minHeight: metrics.size(74)),
      padding: metrics.insets(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      decoration: BoxDecoration(
        color: _AccessibilityPageState._greenSurface,
        borderRadius: BorderRadius.circular(metrics.size(8)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    SizedBox(width: metrics.size(11)),
                    Expanded(child: copy),
                  ],
                ),
                SizedBox(height: metrics.size(11)),
                SizedBox(width: double.infinity, child: button),
              ],
            )
          : Row(
              children: [
                icon,
                SizedBox(width: metrics.size(11)),
                Expanded(child: copy),
                SizedBox(width: metrics.size(11)),
                button,
              ],
            ),
    );
  }
}

@immutable
class _AccessibilityReplicaMetrics {
  const _AccessibilityReplicaMetrics({
    required this.geometryScale,
    required this.contentMaxWidth,
    required this.accessibilityReflow,
  });

  static const double referenceWidth = 390;
  static const double reflowMaxWidth = 426.5;

  factory _AccessibilityReplicaMetrics.resolve({
    required double availableWidth,
    required TextScaler textScaler,
  }) {
    final sharedMetrics = ApprovedReplicaMetrics.resolve(
      availableWidth: availableWidth,
      textScaler: textScaler,
    );
    final accessibilityReflow = sharedMetrics.accessibilityReflow;
    final contentMaxWidth = math.min(
      availableWidth,
      accessibilityReflow ? reflowMaxWidth : referenceWidth,
    );
    return _AccessibilityReplicaMetrics(
      geometryScale: math.min(1, availableWidth / referenceWidth),
      contentMaxWidth: contentMaxWidth,
      accessibilityReflow: accessibilityReflow,
    );
  }

  final double geometryScale;
  final double contentMaxWidth;
  final bool accessibilityReflow;

  double size(double value) => value * geometryScale;

  double font(double value) => value * geometryScale;

  EdgeInsets insets(EdgeInsets value) => EdgeInsets.fromLTRB(
    size(value.left),
    size(value.top),
    size(value.right),
    size(value.bottom),
  );
}

class _AccessibilityReplicaScope extends InheritedWidget {
  const _AccessibilityReplicaScope({
    required this.metrics,
    required super.child,
  });

  final _AccessibilityReplicaMetrics metrics;

  static _AccessibilityReplicaMetrics of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AccessibilityReplicaScope>();
    assert(scope != null, 'Accessibility replica metrics are missing.');
    return scope!.metrics;
  }

  @override
  bool updateShouldNotify(_AccessibilityReplicaScope oldWidget) {
    return metrics.geometryScale != oldWidget.metrics.geometryScale ||
        metrics.contentMaxWidth != oldWidget.metrics.contentMaxWidth ||
        metrics.accessibilityReflow != oldWidget.metrics.accessibilityReflow;
  }
}
