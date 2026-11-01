import 'package:flutter/material.dart';
import '../../domain/phase2/requests.dart';
import '../../domain/phase2/money.dart';
import '../media/private_remote_image.dart';
import 'profile_ui.dart';

/// Only accepts the request projected for this conversation by the server.
class ProfileRequestCard extends StatefulWidget {
  const ProfileRequestCard({super.key, required this.load});
  final Future<SellerLeadProjection?> Function() load;
  @override
  State<ProfileRequestCard> createState() => _ProfileRequestCardState();
}

class _ProfileRequestCardState extends State<ProfileRequestCard> {
  SellerLeadProjection? request;
  bool loading = true;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      failed = false;
      request = null;
    });
    try {
      final result = await widget.load();
      if (mounted) setState(() => request = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? budget(MoneyRange range) {
    String? amount(Money? m) => m == null || m.currencyCode != 'USD'
        ? null
        : '\$${(m.minorUnits / 100).toStringAsFixed(m.minorUnits % 100 == 0 ? 0 : 2)}';
    final low = amount(range.minimum), high = amount(range.maximum);
    if (low != null && high != null) return '$low – $high';
    return low != null
        ? 'From $low'
        : high != null
        ? 'Up to $high'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    if (!loading && !failed && r == null) return const SizedBox.shrink();
    return ProfileSection(
      'Request in this chat',
      child: ProfileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading)
              const LinearProgressIndicator()
            else if (failed) ...[
              const Text('This request could not be loaded.'),
              ProfileSecondaryAction(
                seller: true,
                label: 'Try again',
                onPressed: reload,
              ),
            ] else if (r != null) ...[
              if (r.imageMediaIds.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 160,
                    child: PrivateRemoteImage(id: r.imageMediaIds.first),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                r.title,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (budget(r.budget) != null) ...[
                const SizedBox(height: 6),
                Text(
                  budget(r.budget)!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(r.description),
              ],
              if (r.areaLabel?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(r.areaLabel!),
              ],
              if (r.preferredMeetupLabel?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                ProfileActionRow(
                  icon: Icons.people_outline,
                  title: 'Meeting preference',
                  subtitle: r.preferredMeetupLabel,
                ),
              ],
              if (r.lastCompletedItemLabel?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                ProfileActionRow(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Last confirmed purchase',
                  subtitle: r.lastCompletedItemLabel,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
