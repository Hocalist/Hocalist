import 'saved_place_list.dart';
import 'package:flutter/material.dart';
import '../../data/phase2/accounts/saved_places_backend.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/adaptive_palette.dart';
import 'place_capture_sheet.dart';

typedef CaptureSavedPlace =
    Future<PlaceCaptureResult?> Function(PlaceCaptureResult? initial);

Future<bool> savePlaceForNextTime(
  BuildContext context,
  SavedPlacesRepository repository,
  PlaceCaptureResult place,
) async {
  final decision = await showModalBottomSheet<_SaveDecision>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavePlaceConfirmation(place: place, mustSave: true),
  );
  if (decision == null) return false;
  await repository.save(place, decision.name);
  return true;
}

class SavedPlaceChoice {
  const SavedPlaceChoice(this.place, {this.primary = false});
  final PlaceCaptureResult place;
  final bool primary;
}

Future<SavedPlaceChoice?> showSavedPlacesSheet({
  required BuildContext context,
  required SavedPlacesRepository repository,
  required CaptureSavedPlace capture,
  PlaceCaptureResult? primary,
  String primaryLabel = 'Home',
  bool manage = false,
  PlaceCaptureResult? initial,
}) => showModalBottomSheet<SavedPlaceChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => SavedPlacesSheet(
    repository: repository,
    capture: capture,
    primary: primary,
    primaryLabel: primaryLabel,
    manage: manage,
    initial: initial,
  ),
);

class SavedPlacesSheet extends StatefulWidget {
  const SavedPlacesSheet({
    super.key,
    required this.repository,
    required this.capture,
    this.primary,
    this.primaryLabel = 'Home',
    this.manage = false,
    this.initial,
  });
  final SavedPlacesRepository repository;
  final CaptureSavedPlace capture;
  final PlaceCaptureResult? primary;
  final String primaryLabel;
  final bool manage;
  final PlaceCaptureResult? initial;
  @override
  State<SavedPlacesSheet> createState() => _SavedPlacesSheetState();
}

class _SavedPlacesSheetState extends State<SavedPlacesSheet> {
  List<SavedPlace> _places = [];
  SavedPlaceChoice? _selected;
  String? _selectedId;
  bool _busy = true;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loading = true;
      _error = null;
    });
    try {
      final places = await widget.repository.load();
      if (mounted) setState(() => _places = places);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Saved places could not be loaded. Try again, or use a different address.',
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _loading = false;
        });
    }
  }

  Future<void> _capture({SavedPlace? editing}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final place = await widget.capture(editing?.place ?? widget.initial);
      if (!mounted || place == null) return;
      if (widget.manage) {
        final label = editing?.name ?? place.label.trim();
        final name = label.length > 60 ? label.substring(0, 60) : label;
        await widget.repository.save(place, name, id: editing?.id);
        if (!mounted) return;
        await _load();
        return;
      }
      final decision = await showModalBottomSheet<_SaveDecision>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SavePlaceConfirmation(
          place: place,
          name: editing?.name,
          mustSave: widget.manage || editing != null,
        ),
      );
      if (!mounted || decision == null) return;
      if (decision.save) {
        await widget.repository.save(place, decision.name, id: editing?.id);
        if (!mounted) return;
      }
      if (widget.manage) {
        await _load();
      } else {
        Navigator.pop(context, SavedPlaceChoice(place));
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'This place could not be saved. Your existing saved places have not been replaced. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(SavedPlace p) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (c) => BuyerModalSheet(
        title: 'Remove saved place?', icon: Icons.delete_outline,
        onClose: () => Navigator.pop(c, false),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(p.name.isEmpty ? p.place.address : p.name),
          const SizedBox(height: 12),
          const Text('Existing requests and meetings will keep their address.'),
          const SizedBox(height: 20),
          BuyerPrimaryButton(onPressed: () => Navigator.pop(c, true), label: 'Remove place'),
          const SizedBox(height: 10),
          BuyerSecondaryButton(onPressed: () => Navigator.pop(c, false), label: 'Keep place'),
        ]),
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.remove(p.id);
      if (mounted) await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'This place could not be removed. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(
    String title,
    String address, {
    required String id,
    required SavedPlaceChoice choice,
    SavedPlace? saved,
  }) {
    final selected = _selectedId == id;
    return SavedPlaceRow(
      title: title, address: address, selected: selected, selectable: !widget.manage,
      onTap: _busy ? null : widget.manage
          ? (saved == null ? null : () => _capture(editing: saved))
          : () => setState(() { _selected = choice; _selectedId = id; }),
      onEdit: widget.manage && saved != null && !_busy ? () => _capture(editing: saved) : null,
      onRemove: widget.manage && saved != null && !_busy ? () => _remove(saved) : null,
    );
  }

  @override
  Widget build(BuildContext context) => BuyerModalSheet(
    title: 'Saved places',
    subtitle: 'Your saved places are private to you.',
    icon: Icons.bookmark_border_rounded,
    onClose: () => Navigator.pop(context),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_loading) const BuyerProgressStrip(label: 'Loading saved places…'),
      if (_error != null) BuyerStateNotice(icon: Icons.cloud_off_outlined,
        title: _error!, actionLabel: 'Try again', onAction: _busy ? null : _load),
      if (_places.isNotEmpty || (widget.primary != null && !widget.manage))
        SavedPlaceList(children: [
      if (widget.primary != null && !widget.manage)
        _card(widget.primaryLabel, widget.primary!.address, id: 'primary',
          choice: SavedPlaceChoice(widget.primary!, primary: true)),
      for (final place in _places)
        _card(place.name.isEmpty ? 'Saved place' : place.name, place.place.address,
          id: place.id, choice: SavedPlaceChoice(place.place), saved: place),
        ]),
      if (!_busy && _error == null && _places.isEmpty && (widget.manage || widget.primary == null))
        const BuyerStateNotice(icon: Icons.bookmark_border_rounded, title: 'No saved places yet',
          body: 'Save a place to choose it quickly next time.'),
      const SizedBox(height: 8),
      BuyerSecondaryButton(onPressed: _busy ? null : () => _capture(),
        label: widget.manage ? 'Add a place' : 'Use a different address'),
      if (!widget.manage) ...[
        const SizedBox(height: 12),
        BuyerPrimaryButton(onPressed: _busy || _selected == null ? null : () => Navigator.pop(context, _selected), label: 'Use this place'),
      ],
    ]),
  );
}

class _SaveDecision {
  const _SaveDecision(this.save, this.name);
  final bool save;
  final String name;
}

class _SavePlaceConfirmation extends StatefulWidget {
  const _SavePlaceConfirmation({
    required this.place,
    required this.mustSave,
    this.name,
  });
  final PlaceCaptureResult place;
  final bool mustSave;
  final String? name;
  @override
  State<_SavePlaceConfirmation> createState() => _SavePlaceConfirmationState();
}

class _SavePlaceConfirmationState extends State<_SavePlaceConfirmation> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name ?? '',
  );
  late bool _save = widget.mustSave;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BuyerModalSheet(
    title: widget.mustSave ? 'Save place' : 'Use this address?',
    icon: Icons.bookmark_add_outlined,
    onClose: () => Navigator.pop(context),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.place.address),
      const SizedBox(height: 16),
      if (!widget.mustSave) CheckboxListTile(contentPadding: EdgeInsets.zero,
        value: _save, onChanged: (v) => setState(() => _save = v ?? false), title: const Text('Save for next time')),
      if (_save) TextField(controller: _name, maxLength: 60,
        decoration: InputDecoration(labelText: 'Name (optional)', hintText: 'Office, pickup spot…',
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 16),
      BuyerPrimaryButton(onPressed: () => Navigator.pop(context, _SaveDecision(_save, _name.text)),
        label: widget.mustSave ? 'Save place' : 'Use this address'),
    ]),
  );
}
