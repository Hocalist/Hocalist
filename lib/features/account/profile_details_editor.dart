import '../../components/hocalist_account_field.dart';
import 'package:flutter/material.dart';
import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/accounts.dart';
import '../../domain/phase2/patch.dart';
import '../../domain/phase2/profiles.dart';
import 'hocalist_account_controller.dart';
import '../../theme/buyer_ui_foundation.dart';

class ProfileDetailsEditor extends StatefulWidget {
  const ProfileDetailsEditor({
    required this.readCurrent,
    required this.onSave,
    this.readDisplayName,
    this.onSaved,
    this.serviceAreaOnly = false,
    this.radiusOnly = false,
    this.areaReadOnly = false,
    this.hideRadius = false,
    super.key,
  });
  final AccountRoleProfile? Function() readCurrent;
  final String Function()? readDisplayName;
  final VoidCallback? onSaved;
  final bool serviceAreaOnly;
  final bool radiusOnly;
  final bool areaReadOnly;
  final bool hideRadius;
  final Future<void> Function(UpdateRoleProfileCommand) onSave;
  @override
  State<ProfileDetailsEditor> createState() => _ProfileDetailsEditorState();
}

class _ProfileDetailsEditorState extends State<ProfileDetailsEditor> {
  final _fields = List.generate(5, (_) => TextEditingController());
  AccountRoleProfile? _base;
  UpdateRoleProfileCommand? _pending;
  bool _busy = false;
  String? _message;
  List<String> _loadedValues = const [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latest = widget.readCurrent();
    final clean =
        _loadedValues.length == _fields.length &&
        List.generate(
          _fields.length,
          (i) => _fields[i].text == _loadedValues[i],
        ).every((same) => same);
    if (!_busy &&
        _pending == null &&
        (latest?.membershipId != _base?.membershipId ||
            (clean && latest?.stamp.revision != _base?.stamp.revision))) {
      _load();
    }
  }

  void _load() {
    _base = widget.readCurrent();
    final p = _base;
    final values = [
      p?.areaLabel,
      p?.profileNote,
      p?.preferredMeetupType,
      p?.serviceRadiusMiles?.toString(),
      p?.pickupAvailability,
    ];
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].text = values[i] ?? '';
    }
    _loadedValues = _fields.map((field) => field.text).toList();
    _pending = null;
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Patch<String> _patch(int index) => _fields[index].text.trim().isEmpty
      ? const PatchClear()
      : PatchSet(_fields[index].text.trim());
  Future<void> _save() async {
    if (_busy || _base == null) return;
    final base = _base!;
    try {
      final radiusText = _fields[3].text.trim();
      final radius = int.tryParse(radiusText);
      if (_pending == null &&
          base.role == HocalistRole.seller &&
          radiusText.isNotEmpty &&
          (radius == null || radius < 0 || radius > accountServiceRadiusMax)) {
        setState(() => _message = 'Enter a valid whole-number service radius.');
        return;
      }
      _pending ??= UpdateRoleProfileCommand(
        profileId: base.membershipId,
        expectedRevision: base.stamp.revision,
        displayName: widget.readDisplayName?.call().trim() ?? base.displayName,
        areaLabel: (widget.radiusOnly || widget.areaReadOnly) ? const PatchKeep() : _patch(0),
        profileNote: widget.serviceAreaOnly ? const PatchKeep() : _patch(1),
        preferredMeetupType: widget.serviceAreaOnly
            ? const PatchKeep()
            : _patch(2),
        serviceRadiusMiles: widget.hideRadius || base.role != HocalistRole.seller
            ? const PatchKeep()
            : radius == null
            ? const PatchClear()
            : PatchSet(radius),
        pickupAvailability:
            !widget.serviceAreaOnly && base.role == HocalistRole.seller
            ? _patch(4)
            : const PatchKeep(),
        idempotencyKey: LocalMarketplaceRepository.newStoreOperationKey(
          'profile-details',
        ),
      );
    } on ArgumentError {
      setState(() => _message = 'Check the profile details and field lengths.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.onSave(_pending!);
      if (!mounted) return;
      setState(() {
        _load();
        _message = widget.serviceAreaOnly
            ? 'Service area saved.'
            : 'Profile details saved.';
      });
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error is AccountActionException
            ? error.message
            : 'Save could not be confirmed. Try again or discard your changes.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = _base?.role == HocalistRole.seller;
    final labels = [
      seller ? (widget.areaReadOnly ? 'Service area (from Business / Store address)' : 'Service area') : 'Your area',
      seller ? 'About your business' : 'About you',
      'Preferred meeting place',
      'Service radius (miles)',
      'Pickup availability',
    ];
    const limits = [
      accountAreaLabelMaxLength,
      accountProfileNoteMaxLength,
      accountPreferredMeetupTypeMaxLength,
      8,
      accountPickupAvailabilityMaxLength,
    ];
    return HocalistAccountFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.serviceAreaOnly)
            const BuyerSectionHeading(title: 'Profile details'),
          if (_base == null)
            const BuyerStateNotice(
              icon: Icons.person_off_outlined,
              tone: BuyerNoticeTone.warning,
              title: 'Profile details are unavailable',
              body: 'Please try again.',
            ),
          if (_base != null)
            for (
              var i = 0;
              i < (_base!.role == HocalistRole.seller ? 5 : 3);
              i++
            )
              if (!(widget.hideRadius && i == 3) && (widget.radiusOnly ? i == 3 : (!widget.serviceAreaOnly || i == 0 || i == 3))) ...[
                HocalistAccountField(
                  fieldKey: Key('profileDetailsField$i'),
                  label: labels[i],
                  seller: _base!.role == HocalistRole.seller,
                  controller: _fields[i],
                  enabled: !_busy && _pending == null,
                  readOnly: i == 0 && widget.areaReadOnly,
                  maxLength: limits[i],
                  maxLines: i == 1 ? 3 : 1,
                  keyboardType: i == 3
                      ? TextInputType.number
                      : TextInputType.text,
                ),
                const SizedBox(height: 8),
              ],
          if (_message != null) ...[
            BuyerStateNotice(
              key: const Key('profileDetailsMessage'),
              icon: _message!.contains('saved')
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              tone: _message!.contains('saved')
                  ? BuyerNoticeTone.success
                  : BuyerNoticeTone.warning,
              title: _message!,
            ),
            const SizedBox(height: 10),
          ],
          BuyerPrimaryButton(
            key: const Key('profileDetailsSave'),
            onPressed: _busy || _base == null ? null : _save,
            label: _busy
                ? 'Saving…'
                : widget.serviceAreaOnly
                ? 'Save service area'
                : _pending == null
                ? widget.readDisplayName == null
                      ? 'Save profile details'
                      : 'Save profile'
                : 'Retry profile save',
          ),
          const SizedBox(height: 8),
          BuyerSecondaryButton(
            label: 'Discard changes',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _load();
                    _message = null;
                  }),
          ),
        ],
      ),
    );
  }
}
