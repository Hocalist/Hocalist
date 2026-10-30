import 'package:flutter/material.dart';
import 'private_remote_image.dart';

/// Previews use the authenticated gateway and current request access rules.
class RequestPhotoGallery extends StatelessWidget {
  const RequestPhotoGallery({required this.ids, super.key});
  final List<String> ids;

  @override
  Widget build(BuildContext context) => ids.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in ids)
                Semantics(
                  label: 'Request photo',
                  image: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PrivateRemoteImage(id: id),
                  ),
                ),
            ],
          ),
        );
}
