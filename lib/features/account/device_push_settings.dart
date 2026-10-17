import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import '../../data/phase2/providers/hocalist_push_service.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'push_service_scope.dart';

/// Account topic preferences and this device's OS permission are separate.
class DevicePushSettings extends StatefulWidget {
  const DevicePushSettings({this.service, super.key});
  final HocalistPushService? service;
  @override
  State<DevicePushSettings> createState() => _DevicePushSettingsState();
}

class _DevicePushSettingsState extends State<DevicePushSettings>
    with WidgetsBindingObserver {
  HocalistPushService? _service;
  bool _busy = false;
  bool? _enabled;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = widget.service ?? PushServiceScope.read(context);
    if (_service == service) return;
    _service = service;
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _service?.isEnabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not check device notifications. Try again.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _change(bool enable) async {
    if (_busy || _service == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service!.start();
      if (enable) {
        await _service!.enable();
      } else {
        await _service!.disableConsent();
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not update device notifications. Check your connection and notification permission in phone settings, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null || !_service!.supported) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final statusLabel = _enabled == null
        ? 'Checking…'
        : _enabled!
        ? 'On for this phone'
        : 'Off for this phone';
    final statusBody = _enabled == null
        ? 'Check or enable device notifications.'
        : _enabled!
        ? 'Permission enabled on this phone.'
        : 'Device notifications are off.';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.spacing(12)),
      child: Container(
        padding: metrics.geometryInsets(const EdgeInsets.all(14)),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, BuyerUiTokens.surface),
          borderRadius: BorderRadius.circular(metrics.geometry(16)),
          border: Border.all(
            color: HocalistPalette.border(context, BuyerUiTokens.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: metrics.artSize(34),
                  height: metrics.artSize(34),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      BuyerUiTokens.softSurface,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: BuyerGlyphIcon(
                      icon: _enabled == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      slotSize: metrics.artSize(18),
                      glyphSize: metrics.artSize(18),
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: metrics.spacing(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications on this phone',
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.cardTitle,
                        ).copyWith(fontSize: metrics.fontSize(13.5)),
                      ),
                      SizedBox(height: metrics.spacing(3)),
                      Text(
                        statusBody,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.secondaryBody,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.spacing(8)),
                Flexible(
                  child: BuyerStatusChip(
                    label: statusLabel,
                    icon: _enabled == true
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    tone: _enabled == true
                        ? BuyerNoticeTone.success
                        : BuyerNoticeTone.neutral,
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(8)),
            Text(
              'Your in-app inbox remains available. Push delivery also depends '
              'on service availability.',
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.secondaryBody,
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: metrics.spacing(10)),
              BuyerStateNotice(
                key: const Key('devicePushError'),
                icon: Icons.error_outline_rounded,
                tone: BuyerNoticeTone.error,
                title: 'Device notifications were not updated',
                body: _error,
              ),
            ],
            if (_busy) ...[
              SizedBox(height: metrics.spacing(10)),
              const BuyerProgressStrip(label: 'Updating device permission…'),
            ],
            SizedBox(height: metrics.spacing(10)),
            BuyerPrimaryButton(
              label: _busy
                  ? 'Updating…'
                  : _enabled == true
                  ? 'Turn off on this phone'
                  : 'Enable on this phone',
              onPressed: _busy ? null : () => _change(_enabled != true),
            ),
            SizedBox(height: metrics.spacing(8)),
            BuyerSecondaryButton(
              label: 'Refresh device status',
              onPressed: _busy ? null : _load,
            ),
          ],
        ),
      ),
    );
  }
}
