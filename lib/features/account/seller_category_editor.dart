/// Seller profile category editor.
///
/// Uses real active catalogue ids. Retired selected categories stay visible
/// with an explicit replacement notice and are only removed when the seller
/// changes the selection. Saves carry the revision the editor loaded; a stale
/// revision reloads and asks for an explicit retry.
library;

import 'package:flutter/material.dart';

import '../../data/phase2/accounts/profile_categories_backend.dart';
import '../../domain/phase2/account_completion.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';

class SellerCategoryEditor extends StatefulWidget {
  const SellerCategoryEditor({
    required this.load,
    required this.save,
    this.onSaved,
    super.key,
  });

  final Future<SellerCategorySelection> Function() load;
  final Future<SellerCategoryUpdateResult> Function(
    int expectedRevision,
    List<String> categoryIds,
  )
  save;

  /// Called after a confirmed save so a parent summary can reload.
  final VoidCallback? onSaved;

  @override
  State<SellerCategoryEditor> createState() => _SellerCategoryEditorState();
}

class _SellerCategoryEditorState extends State<SellerCategoryEditor> {
  final _filter = TextEditingController();
  SellerCategorySelection? _selection;
  Set<String> _selected = <String>{};
  List<String>? _pendingIds;
  bool _busy = false;
  String? _error;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final run = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selection = await widget.load();
      if (!mounted || run != _generation) return;
      setState(() {
        _selection = selection;
        _selected = selection.selected.map((option) => option.id).toSet();
        _pendingIds = null;
      });
    } catch (_) {
      if (!mounted || run != _generation) return;
      setState(() => _error = 'Seller categories could not be loaded.');
    } finally {
      if (mounted && run == _generation) setState(() => _busy = false);
    }
  }

  List<SellerCategoryOption> get _visibleAvailable {
    final selection = _selection;
    if (selection == null) return const <SellerCategoryOption>[];
    final query = _filter.text.trim().toLowerCase();
    if (query.isEmpty) return selection.available;
    return selection.available
        .where(
          (option) =>
              option.label.toLowerCase().contains(query) ||
              option.id.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _save() async {
    final selection = _selection;
    if (selection == null || _busy) return;
    final ids = _selected.toList(growable: false)..sort();
    _pendingIds ??= ids;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.save(selection.revision, _pendingIds!);
      if (!mounted) return;
      widget.onSaved?.call();
      setState(() {
        _pendingIds = null;
        _message = 'Seller categories saved.';
      });
      await _load();
    } on ProfileCategoriesConflictException {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() {
        _pendingIds = null;
        _message = null;
        _error =
            'Your profile changed on another device. Reload and choose again.';
      });
    } on ProfileCategoriesUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        if (!failure.outcomeUncertain) _pendingIds = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Padding(
      padding: const EdgeInsets.all(14),
      key: const ValueKey('sellerCategoryEditor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SellerSectionHeading(title: 'Seller categories'),
          Text(
            'Choose the catalogue categories buyers can find you in. A '
            'retired category stays visible until you replace it.',
            style: sellerText(
              metrics,
              12,
              color: SellerUiColors.body,
              height: 1.35,
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const SellerProgressStrip(label: 'Saving categories…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            SellerStateNotice(
              key: const ValueKey('sellerCategoryError'),
              icon: Icons.error_outline_rounded,
              tone: SellerNoticeTone.error,
              title: 'Seller categories were not saved',
              body: _error,
              actionKey: const ValueKey('sellerCategoryRetry'),
              actionLabel: _pendingIds == null ? 'Retry' : 'Retry save',
              onAction: _busy ? null : (_pendingIds == null ? _load : _save),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            SellerStateNotice(
              key: const ValueKey('sellerCategoryMessage'),
              icon: Icons.check_circle_rounded,
              tone: SellerNoticeTone.success,
              title: _message!,
            ),
          ],
          if (selection == null && !_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SellerStateNotice(
                icon: Icons.hourglass_empty_rounded,
                tone: SellerNoticeTone.neutral,
                title: 'Seller categories are not loaded yet.',
                body: 'Reload to load the active catalogue.',
              ),
            ),
          if (selection != null) ...[
            if (selection.retiredSelected.isNotEmpty) ...[
              const SizedBox(height: 10),
              SellerStateNotice(
                key: const ValueKey('sellerCategoryRetiredNotice'),
                icon: Icons.history_toggle_off_rounded,
                tone: SellerNoticeTone.warning,
                title: 'Retired categories selected',
                body:
                    '${selection.retiredSelected.map((o) => o.label).join(', ')}. '
                    'Remove or replace these before saving if you no longer offer them.',
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sellerCategoryFilter'),
              controller: _filter,
              enabled: !_busy,
              style: sellerInputText(metrics),
              decoration: sellerInputDecoration(
                context,
                labelText: 'Filter categories',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in selection.selected.where(
                  (option) => option.isRetired,
                ))
                  HocalistFilterChip(
                    key: ValueKey('sellerCategory-retired-${option.id}'),
                    role: HocalistControlRole.seller,
                    label: '${option.label} (retired)',
                    selected: _selected.contains(option.id),
                    onSelected: _busy
                        ? (_) {}
                        : (selected) => setState(() {
                            if (selected) {
                              _selected.add(option.id);
                            } else {
                              _selected.remove(option.id);
                            }
                            _message = null;
                          }),
                  ),
                for (final option in _visibleAvailable)
                  HocalistFilterChip(
                    key: ValueKey('sellerCategory-${option.id}'),
                    role: HocalistControlRole.seller,
                    label: option.label,
                    selected: _selected.contains(option.id),
                    onSelected: _busy
                        ? (_) {}
                        : (selected) => setState(() {
                            if (selected) {
                              _selected.add(option.id);
                            } else {
                              _selected.remove(option.id);
                            }
                            _message = null;
                          }),
                  ),
              ],
            ),
            if (_visibleAvailable.isEmpty && _filter.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SellerStateNotice(
                  key: ValueKey('sellerCategoryFilteredEmpty'),
                  icon: Icons.search_off_rounded,
                  tone: SellerNoticeTone.neutral,
                  title: 'No categories match this filter.',
                ),
              )
            else if (_visibleAvailable.isEmpty && selection.available.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SellerStateNotice(
                  key: ValueKey('sellerCategoryEmpty'),
                  icon: Icons.category_outlined,
                  tone: SellerNoticeTone.neutral,
                  title: 'No active catalogue categories are configured yet.',
                ),
              ),
            const SizedBox(height: 12),
            SellerPrimaryButton(
              key: const ValueKey('sellerCategorySave'),
              onPressed: _busy ? null : _save,
              label: _busy
                  ? 'Saving...'
                  : _pendingIds == null
                  ? 'Save categories'
                  : 'Retry category save',
            ),
            const SizedBox(height: 8),
            SellerSecondaryButton(
              key: const ValueKey('sellerCategoryReload'),
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _pendingIds = null;
                        _message = null;
                      });
                      _load();
                    },
              label: 'Reload saved categories',
            ),
          ],
        ],
      ),
    );
  }
}
