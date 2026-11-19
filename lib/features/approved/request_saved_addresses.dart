import 'package:flutter/material.dart';
import '../../data/phase2/accounts/saved_places_backend.dart';
import '../../domain/phase2/common.dart';
import 'saved_place_list.dart';
import '../../theme/buyer_ui_foundation.dart';
import 'place_capture_sheet.dart';

String savedAddressKey(PostalAddress address) => [
  address.line1, address.line2, address.city, address.state,
  address.postalCode, address.country,
].map((part) => (part ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')).join('|');

Future<void> rememberRequestAddress(
  SavedPlacesRepository repository,
  PlaceCaptureResult place,
) async {
  final address = place.postalAddress;
  if (address == null || (address.line1?.trim().isEmpty ?? true)) return;
  final existing = await repository.load();
  if (existing.any((saved) => saved.place.postalAddress != null &&
      savedAddressKey(saved.place.postalAddress!) == savedAddressKey(address))) return;
  await repository.save(place, address.line1!.trim());
}

Future<PlaceCaptureResult?> chooseRequestSavedAddress(
  BuildContext context, List<SavedPlace> places,
) => showModalBottomSheet<PlaceCaptureResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => BuyerModalSheet(
    title: 'Choose from saved places',
    subtitle: 'Select an address to fill in your request.',
    icon: Icons.bookmark_border_rounded,
    onClose: () => Navigator.pop(context),
    child: SavedPlaceList(children: [
      for (final saved in places) SavedPlaceRow(
        title: saved.name.isEmpty ? saved.place.label : saved.name,
        address: saved.place.address,
        onTap: () => Navigator.pop(context, saved.place),
      ),
    ]),
  ),
);
