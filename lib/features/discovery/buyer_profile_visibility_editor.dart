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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.backend.loadConsent();
      if (!mounted) return;
      setState(() {
        _adopt(value);
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
              'Save was not confirmed. Retry the same visibility change or reload to check its result.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_loading && !_saving && _base != null && _pending == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BuyerUiTokens.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BuyerSectionHeading(title: 'Public profile visibility'),
            const Text(
              'Your profile is private unless you choose to share it. Contact details and exact addresses are never included.',
            ),
            if (_loading)
              const BuyerProgressStrip(label: 'Loading visibility…'),
            SwitchListTile.adaptive(
              title: const Text('Share my buyer profile'),
              value: _public,
              onChanged: enabled ? (v) => setState(() => _public = v) : null,
            ),
            for (final field in <(String, bool, ValueChanged<bool>)>[
              ('Display name', _name, (v) => setState(() => _name = v)),
              ('Approximate area', _area, (v) => setState(() => _area = v)),
              (
                'Request categories',
                _categories,
                (v) => setState(() => _categories = v),
              ),
            ])
              CheckboxListTile(
                title: Text(field.$1),
                value: field.$2,
                onChanged: enabled && _public
                    ? (v) => field.$3(v ?? false)
                    : null,
              ),
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
      ),
    );
  }
}
