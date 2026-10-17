import '../../components/hocalist_account_field.dart';
import 'package:flutter/material.dart';
import '../../domain/phase2/account_contacts.dart';
import '../../domain/phase2/patch.dart';
import '../../data/local_marketplace_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'hocalist_account_controller.dart';

class PrivateContactEditor extends StatefulWidget {
  const PrivateContactEditor({
    required this.readCurrent,
    required this.onSave,
    this.seller = false,
    super.key,
  });
  final bool seller;
  final PrivateContactRecord? Function() readCurrent;
  final Future<void> Function(UpdateContactCommand) onSave;
  @override
  State<PrivateContactEditor> createState() => _PrivateContactEditorState();
}

class _PrivateContactEditorState extends State<PrivateContactEditor> {
  final fields = List.generate(7, (_) => TextEditingController());
  PrivateContactRecord? base;
  UpdateContactCommand? pending;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    base = widget.readCurrent();
    final c = base?.contact;
    final values = [
      c?.phone,
      c?.addressLine1,
      c?.addressLine2,
      c?.city,
      c?.region,
      c?.postalCode,
      c?.countryCode ?? 'US',
    ];
    for (var i = 0; i < fields.length; i++) {
      fields[i].text = values[i] ?? '';
    }
  }

  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  Patch<String> patch(int i) => fields[i].text.trim().isEmpty
      ? const PatchClear()
      : PatchSet(fields[i].text.trim());
  Future<void> save() async {
    if (busy || base == null) return;
    if (pending == null) {
      fields[6].text = fields[6].text.trim().toUpperCase();
      if (fields[6].text.isNotEmpty &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(fields[6].text)) {
        setState(
          () => message = 'Use a two-letter country code, for example US.',
        );
        return;
      }
      pending = UpdateContactCommand(
        expectedRevision: base!.stamp.revision,
        phone: patch(0),
        addressLine1: patch(1),
        addressLine2: patch(2),
        city: patch(3),
        region: patch(4),
        postalCode: patch(5),
        countryCode: patch(6),
        idempotencyKey: LocalMarketplaceRepository.newStoreOperationKey(
          'contact',
        ),
      );
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.onSave(pending!);
      if (!mounted) return;
      setState(() {
        pending = null;
        load();
        message = 'Private contact details saved.';
      });
    } on AccountActionException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Save was not confirmed. Retry the same details.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Contact phone',
      'Street address',
      'Apartment or suite',
      'City',
      'State / region',
      'ZIP / postal code',
      'Country code',
    ];
    const limits = [40, 300, 300, 150, 150, 40, 2];
    return HocalistAccountFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BuyerSectionHeading(title: 'Private contact details'),
          Text(
            'Used for your home address. Saving a phone number here does not '
            'verify it for login.',
            style: BuyerTypography.style(
              context,
              ApprovedReplicaScope.maybeOf(context) ??
                  ApprovedReplicaMetrics.resolve(
                    brightness: Theme.of(context).brightness,
                    availableWidth: MediaQuery.sizeOf(context).width,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
              BuyerTextRole.secondaryBody,
            ),
          ),
          if (base == null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: BuyerStateNotice(
                icon: Icons.contact_page_outlined,
                tone: BuyerNoticeTone.warning,
                title: 'Contact details are not loaded',
                body: 'Reload to try again.',
              ),
            ),
          for (var i = 0; i < fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: HocalistAccountField(
                fieldKey: Key('privateContact$i'),
                label: labels[i],
                seller: widget.seller,
                controller: fields[i],
                readOnly: busy || pending != null,
                maxLength: limits[i],
                keyboardType: i == 0 ? TextInputType.phone : TextInputType.text,
              ),
            ),
          if (message != null) ...[
            const SizedBox(height: 12),
            BuyerStateNotice(
              key: const Key('contactMessage'),
              icon: message!.contains('saved') || message!.contains('Loaded')
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              tone: message!.contains('saved') || message!.contains('Loaded')
                  ? BuyerNoticeTone.success
                  : BuyerNoticeTone.warning,
              title: message!,
            ),
          ],
          const SizedBox(height: 12),
          BuyerPrimaryButton(
            onPressed: busy || base == null ? null : save,
            label: busy
                ? 'Saving…'
                : pending != null
                ? 'Retry contact save'
                : 'Save contact details',
          ),
          const SizedBox(height: 8),
          BuyerSecondaryButton(
            label: pending != null
                ? 'Discard retry and reload saved details'
                : 'Reload saved details',
            onPressed: busy
                ? null
                : () {
                    setState(() {
                      pending = null;
                      load();
                      message = 'Loaded the latest saved contact details.';
                    });
                  },
          ),
        ],
      ),
    );
  }
}
