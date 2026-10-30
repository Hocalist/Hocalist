import '../../components/pull_refresh.dart';
import '../../components/hocalist_account_field.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/discovery/discovery_backends.dart';
import '../../domain/phase2/discovery.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../components/hocalist_reload_link.dart';

/// Explicit opt-in. The server remains the authority for per-field visibility.
class BuyerProfileVisibilityEditor extends StatefulWidget {
  const BuyerProfileVisibilityEditor({required this.backend, super.key});
  final BuyerConsentBackend backend;
  @override
  State<BuyerProfileVisibilityEditor> createState() =>
      _BuyerProfileVisibilityEditorState();
}

class _BuyerProfileVisibilityEditorState
    extends State<BuyerProfileVisibilityEditor> {
  BuyerPublicProfileConsent? _base, _pending;
  String? _key, _error;
  bool _loading = true, _saving = false;
  bool _public = false, _name = false, _area = false, _categories = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool preserveChoices = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.backend.loadConsent();
      if (!mounted) return;
      setState(() {
        if (preserveChoices) {
          _base = value;
        } else {
          _adopt(value);
        }
        _pending = null;
        _key = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your profile visibility.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pull() async {
    if (_loading || _saving || _pending != null) return;
    final base = _base;
    final dirty = base != null && (_public != base.isPublic || _name != base.showDisplayName ||
      _area != base.showArea || _categories != base.showCategories);
    await _load(preserveChoices: dirty);
  }

  void _adopt(BuyerPublicProfileConsent value) {
    _base = value;
    _public = value.isPublic;
    _name = value.showDisplayName;
    _area = value.showArea;
    _categories = value.showCategories;
  }

  Future<void> _save() async {
    if (_base == null || _saving) return;
    _pending ??= BuyerPublicProfileConsent(
      isPublic: _public,
      showDisplayName: _name,
      showArea: _area,
      showCategories: _categories,
      revision: _base!.revision,
    );
    _key ??= LocalMarketplaceRepository.newStoreOperationKey(
      'buyer-visibility',
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final value = await widget.backend.setConsent(
        consent: _pending!,
        operationKey: _key!,
      );
      if (!mounted) return;
      setState(() {
        _adopt(value);
        _pending = null;
        _key = null;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Profile visibility saved.')),
      );
    } on StoreBackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (!e.ambiguous) {
          _pending = null;
          _key = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Save was not confirmed. Retry the same change or discard your changes.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PullRefreshAction(onRefresh: _loading || _saving ? null : _pull, child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final enabled = !_loading && !_saving && _base != null && _pending == null;
    return HocalistAccountFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BuyerSectionHeading(title: 'Buyer profile sharing'),
          const SizedBox(height: 8),
          Text(
            'Choose what sellers can see. Your contact details and exact address stay private.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const BuyerProgressStrip(label: 'Loading sharing preferences…'),
          _choice(
            context,
            label: 'Share my buyer profile',
            description: _public
                ? 'Your selected details can be seen by sellers.'
                : 'Your buyer profile is private.',
            selected: _public,
            enabled: enabled,
            onChanged: (value) => setState(() => _public = value),
            primary: true,
          ),
          if (_public) ...[
            const SizedBox(height: 16),
            Text(
              'Details to share',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _choice(
              context,
              label: 'Display name',
              description: 'The name on your buyer profile.',
              selected: _name,
              enabled: enabled,
              onChanged: (v) => setState(() => _name = v),
            ),
            _choice(
              context,
              label: 'Approximate area',
              description: 'Your area, never your exact address.',
              selected: _area,
              enabled: enabled,
              onChanged: (v) => setState(() => _area = v),
            ),
            _choice(
              context,
              label: 'Request categories',
              description: 'The types of products or services you need.',
              selected: _categories,
              enabled: enabled,
              onChanged: (v) => setState(() => _categories = v),
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null)
            BuyerStateNotice(
              icon: Icons.info_outline,
              title: _error!,
              tone: BuyerNoticeTone.warning,
            ),
          BuyerPrimaryButton(
            label: _saving
                ? 'Saving…'
                : _pending == null
                ? 'Save visibility'
                : 'Retry visibility save',
            onPressed: _loading || _saving || _base == null ? null : _save,
          ),
          HocalistReloadLink(
            onPressed: _saving ? null : _load,
            description: 'Reload visibility and discard unsaved choices',
            loading: _loading,
          ),
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required String description,
    required bool selected,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    bool primary = false,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HocalistPalette.surface(
          context,
          selected ? const Color(0xfff2efff) : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: .45)
                : HocalistPalette.border(context, BuyerUiTokens.border),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => onChanged(!selected) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (primary)
                  Switch(value: selected, onChanged: enabled ? onChanged : null)
                else
                  Checkbox(
                    value: selected,
                    onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
