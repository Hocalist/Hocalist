import 'package:flutter/material.dart';

/// Uses the approved gold star artwork with fractional rating fill.
class ProfileRatingStars extends StatelessWidget {
  const ProfileRatingStars({super.key, required this.rating, this.size = 19});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating out of 5 stars',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    Opacity(
                      opacity: .20,
                      child: Image.asset(
                        'assets/approved_trends_notifications/transparent/seller-star.png',
                        width: size,
                        height: size,
                      ),
                    ),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: (rating - i).clamp(0.0, 1.0),
                        child: Image.asset(
                          'assets/approved_trends_notifications/transparent/seller-star.png',
                          width: size,
                          height: size,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
