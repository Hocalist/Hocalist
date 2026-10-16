import '../../components/hocalist_motion.dart';
import 'package:flutter/material.dart';
import '../../domain/phase2/discovery.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../theme/buyer_ui_foundation.dart';

/// Only displays the consent-filtered public projection, never account contacts.
class BuyerPublicProfilePage extends StatefulWidget {
  const BuyerPublicProfilePage({
    required this.onBack,
    required this.load,
    super.key,
  });
  final VoidCallback onBack;
  final Future<PublicBuyerProfile> Function() load;
  @override
  State<BuyerPublicProfilePage> createState() => _BuyerPublicProfilePageState();
}

class _BuyerPublicProfilePageState extends State<BuyerPublicProfilePage> {
  PublicBuyerProfile? profile;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.load();
      if (mounted) setState(() => profile = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The buyer profile could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BuyerNestedHeader(
        title: 'Buyer profile',
        subtitle: 'Details shared by this buyer',
        onBack: widget.onBack,
      ),
      const SizedBox(height: 16),
      HocalistStateTransition(
        stateKey: (loading, error, profile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading)
              const SellerStateNotice(
                icon: Icons.person_outline,
                title: 'Loading buyer profile…',
              )
            else if (error != null)
              SellerStateNotice(
                icon: Icons.cloud_off_outlined,
                title: error!,
                actionLabel: 'Retry',
                onAction: refresh,
              )
            else if (profile?.available != true)
              const SellerStateNotice(
                icon: Icons.lock_outline,
                title: 'This profile is private',
                body:
                    'The buyer has not shared a public profile. You can continue your conversation.',
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SellerUiColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 40,
                      color: SellerUiColors.primaryBright,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile!.displayName ?? 'Buyer',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (profile!.areaLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          profile!.areaLabel!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SellerMetricTile(
                      label: 'Confirmed purchases',
                      value: '${profile!.verifiedPurchaseCount}',
                    ),
                    if (profile!.memberSince != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Member since ${profile!.memberSince!.year}',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
