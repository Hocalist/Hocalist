import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../data/local_marketplace_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

class SavedItemButton extends StatefulWidget {
  const SavedItemButton({
    required this.read,
    required this.setSaved,
    super.key,
  });
  final Future<bool> Function() read;
  final Future<void> Function(bool, String) setSaved;
  @override
  State<SavedItemButton> createState() => _SavedItemButtonState();
}

class _SavedItemButtonState extends State<SavedItemButton> {
  bool? _saved;
  bool _busy = false;
  String? _error;
  bool? _pending;
  String? _key;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.read();
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check saved status.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change() async {
    if (_busy) return;
    if (_saved == null) return _read();
    _pending ??= !_saved!;
    _key ??= LocalMarketplaceRepository.newStoreOperationKey('saved-state');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.setSaved(_pending!, _key!);
      if (!mounted) return;
      // Reconcile the latest state, including another device's later change.
      final saved = await widget.read();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _pending = null;
        _key = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Change not confirmed. Retry to check safely.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved == true;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          BuyerStateNotice(
            key: const Key('savedItemError'),
            icon: Icons.sync_problem_rounded,
            tone: BuyerNoticeTone.warning,
            title: 'Saved change not confirmed',
            body: _error,
          ),
          SizedBox(height: metrics.spacing(8)),
        ],
        if (_busy) ...[
          const BuyerProgressStrip(label: 'Checking saved status…'),
          SizedBox(height: metrics.spacing(8)),
        ],
        OutlinedButton.icon(
          key: const Key('buyerSavedRequestButton'),
          onPressed: _busy ? null : _change,
          style: OutlinedButton.styleFrom(
            foregroundColor: HocalistPalette.text(
              context,
              BuyerUiTokens.action,
            ),
            backgroundColor: HocalistPalette.surface(
              context,
              saved ? BuyerUiTokens.activeSurface : BuyerUiTokens.surface,
            ),
            minimumSize: Size.fromHeight(metrics.geometry(44)),
            padding: EdgeInsets.symmetric(horizontal: metrics.geometry(12)),
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                saved ? BuyerUiTokens.action : BuyerUiTokens.border,
              ),
              width: saved ? 1.5 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
            ),
            textStyle:
                (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
                    .copyWith(
                      fontSize: metrics.fontSize(13),
                      fontWeight: FontWeight.w600,
                    ),
          ),
          icon: Icon(
            saved ? Icons.bookmark : Icons.bookmark_border,
            size: metrics.artSize(20),
          ),
          label: Text(
            _busy
                ? 'Checking saved status…'
                : _error != null
                ? 'Retry saved action'
                : saved
                ? 'Remove from saved'
                : 'Save request',
          ),
        ),
      ],
    );
  }
}
