import 'package:flutter/material.dart';
import '../../data/phase2/accounts/profile_presentation_backend.dart';
import '../../data/phase2/accounts/saved_places_backend.dart';
import 'profile_ui.dart';
import '../../components/account_role_components.dart';
import '../../theme/buyer_ui_foundation.dart';

class SellerVisibilityEditor extends StatefulWidget {
  const SellerVisibilityEditor({
    super.key,
    required this.backend,
    required this.savedPlaces,
  });
  final ProfilePresentationBackend backend;
  final SavedPlacesRepository savedPlaces;
  @override
  State<SellerVisibilityEditor> createState() => _SellerVisibilityEditorState();
}

class _SellerVisibilityEditorState extends State<SellerVisibilityEditor> {
  Map<String, dynamic>? values;
  List<SavedPlace> places = [];
  bool busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final v = await widget.backend.visibility();
      final p = await widget.savedPlaces.load();
      final ownedIds = p.map((place) => place.id).toSet();
      v['location_ids'] = (v['location_ids'] as List? ?? [])
          .where(ownedIds.contains)
          .toList();
      if (mounted)
        setState(() {
          values = v;
          places = p;
          message = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => message =
              'Visibility settings could not be loaded. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final v = await widget.backend.visibility(
        Map<String, Object?>.from(values!),
      );
      if (mounted)
        setState(() {
          values = v;
          message = 'Visibility settings saved.';
        });
    } catch (_) {
      if (mounted)
        setState(
          () => message =
              'Your settings could not be saved. Reload to check the latest choices.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _choice(String key, String label, IconData icon, {String? description}) =>
    ProfileSharingChoice(label: label, icon: icon, description: description,
      value: values![key] == true,
      onChanged: busy ? null : (v) => setState(() => values![key] = v));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Choose what buyers can see on your public profile.',
      ),
      const SizedBox(height: 16),
      if (busy) const BuyerProgressStrip(label: 'Updating visibility…'),
      if (values != null) ...[
        ProfileSection('Business information', child: Column(children: [
          _choice('show_about', 'Business description', Icons.storefront_outlined),
          _choice('show_area', 'Service area', Icons.location_on_outlined,
            description: 'Your city and coverage radius.'),
        ])),
        ProfileSection('Contact details', child: Column(children: [
          _choice('show_business_address', 'Business address', Icons.place_outlined,
            description: 'Show your exact business address.'),
          _choice('show_phone', 'Phone number', Icons.phone_outlined),
          _choice('show_email', 'Email address', Icons.mail_outline),
        ])),
      ],
      if (values != null && places.isNotEmpty)
        ProfileSection(
          'Additional public locations',
          child: ProfileCard(
            child: Column(
              children: [
                const Text(
                  'Only select business or meeting locations you want buyers to see. Your other saved places remain private.',
                ),
                for (final place in places)
                  ProfileSharingChoice(
                    checkbox: true,
                    icon: Icons.location_on_outlined,
                    label: place.name.isEmpty ? 'Saved place' : place.name,
                    description: place.place.address,
                    value: (values!['location_ids'] as List? ?? []).contains(
                      place.id,
                    ),
                    onChanged: busy
                        ? null
                        : (selected) => setState(() {
                            final ids = List<String>.from(
                              values!['location_ids'] as List? ?? [],
                            );
                            if (selected == true) {
                              if (!ids.contains(place.id)) ids.add(place.id);
                            } else {
                              ids.remove(place.id);
                            }
                            values!['location_ids'] = ids;
                          }),
                  ),
              ],
            ),
          ),
        ),
      if (message != null) ...[const SizedBox(height: 12),
        AccountStateNotice(seller: true, icon: Icons.info_outline, title: message!)],
      const SizedBox(height: 16),
      if (values != null)
        AccountActionButton(
          seller: true,
          onPressed: busy ? null : save,
          label: busy ? 'Saving…' : 'Save visibility',
        ),
      if (values == null || (message != null && message != 'Visibility settings saved.')) ProfileSecondaryAction(
        seller: true,
        onPressed: busy ? null : load,
        label: 'Reload settings',
      ),
    ],
  );
}
