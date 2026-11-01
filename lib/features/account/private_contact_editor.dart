import 'dart:async';
import '../../data/phase2/maps/places_repository.dart';
import '../../data/phase2/maps/places_contract.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/accounts.dart';
import '../../components/hocalist_account_field.dart';
import 'package:flutter/material.dart';
import '../../domain/phase2/account_contacts.dart';
import '../../domain/phase2/patch.dart';
import '../../data/local_marketplace_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'hocalist_account_controller.dart';

PostalAddress contactAddressFromPlace(PlaceDetails place) {
  final value=place.postalAddress;
  return PostalAddress(
    line1:value?.line1?.trim().isNotEmpty==true ? value!.line1 : place.address,
    line2:value?.line2,city:value?.city,state:value?.state,
    postalCode:value?.postalCode,country:value?.country,
  );
}

class PrivateContactEditor extends StatefulWidget {
  const PrivateContactEditor({
    required this.readCurrent,
    required this.onSave,
    this.seller = false,
    this.places,
    this.onResolvedAddress,
    this.onDiscard,
    this.isPopup = false,
    this.addressTitle,
    this.showPhone = true,
    this.readServiceRadius,
    this.onSaveServiceRadius,
    super.key,
  });
  final bool seller;
  final String? addressTitle;
  final bool showPhone;
  final int? Function()? readServiceRadius;
  final Future<void> Function(int radius, String operationKey)? onSaveServiceRadius;
  final PlacesRepository? places;
  final ValueChanged<PlaceDetails>? onResolvedAddress;
  final VoidCallback? onDiscard;
  final bool isPopup;
  final PrivateContactRecord? Function() readCurrent;
  final Future<void> Function(UpdateContactCommand) onSave;
  @override
  State<PrivateContactEditor> createState() => _PrivateContactEditorState();
}

class _PrivateContactEditorState extends State<PrivateContactEditor> {
  final radius = TextEditingController();
  int? pendingRadius;
  final fields = List.generate(7, (_) => TextEditingController());
  PrivateContactRecord? base;
  UpdateContactCommand? pending;
  bool busy = false;
  String? message;
  List<String> _loadedValues = const [];
  Timer? _searchDebounce;
  int _addressEpoch = 0;
  PlacesSession? _addressSession;
  List<PlaceSuggestion> _addressSuggestions = const [];
  bool _resolvingAddress = false;
  String? _addressSearchError;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant PrivateContactEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latest = widget.readCurrent();
    final clean =
        _loadedValues.length == fields.length &&
        List.generate(
          fields.length,
          (i) => fields[i].text == _loadedValues[i],
        ).every((same) => same);
    if (!busy &&
        pending == null &&
        (latest?.userId != base?.userId ||
            (clean && latest?.stamp.revision != base?.stamp.revision))) {
      load();
    }
  }

  void load() {
    _searchDebounce?.cancel();
    _addressEpoch++;
    _addressSession=null;
    _addressSuggestions=const [];
    _resolvingAddress=false;
    _addressSearchError=null;
    base = widget.readCurrent();
    radius.text = (widget.readServiceRadius?.call() ?? 25).toString();
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
    _loadedValues = fields.map((field) => field.text).toList();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    radius.dispose();
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  void streetChanged(String value) {
    _searchDebounce?.cancel();
    final epoch=++_addressEpoch;
    setState(() { _addressSuggestions=const []; _addressSearchError=null; });
    final places=widget.places;
    final query=value.trim();
    if (places==null || query.length<3) return;
    _searchDebounce=Timer(const Duration(milliseconds:350),() async {
      try {
        final session=_addressSession;
        if (session==null || session.isExpiredAt(DateTime.now())) _addressSession=PlacesSession.start();
        final suggestions=await places.search(input:query,session:_addressSession!);
        if (!mounted || epoch!=_addressEpoch) return;
        setState(() { _addressSuggestions=suggestions; });
      } catch (_) {
        if (!mounted || epoch!=_addressEpoch) return;
        setState(() { _addressSession=null; _addressSearchError='Address search could not finish. You can complete the fields below.'; });
      }
    });
  }

  Future<void> selectStreet(PlaceSuggestion suggestion) async {
    final places=widget.places;
    final session=_addressSession;
    if (places==null || session==null || busy || pending!=null) return;
    final userId=base?.userId;
    _searchDebounce?.cancel();
    final epoch=++_addressEpoch;
    setState(() { _resolvingAddress=true; _addressSearchError=null; });
    try {
      final place=await places.resolve(placeId:suggestion.placeId,session:session);
      if (!mounted || epoch!=_addressEpoch || widget.readCurrent()?.userId!=userId) return;
      final address=contactAddressFromPlace(place);
      setState(() {
        fields[1].text=address.line1 ?? '';
        fields[2].text=address.line2 ?? '';
        fields[3].text=address.city ?? '';
        fields[4].text=address.state ?? '';
        fields[5].text=address.postalCode ?? '';
        fields[6].text=address.country ?? '';
        _addressSuggestions=const [];
        _addressSession=null;
      });
      widget.onResolvedAddress?.call(place);
    } catch (_) {
      if (!mounted || epoch!=_addressEpoch) return;
      setState(() {
        _addressSearchError='This address could not be loaded. Search again or complete the fields below.';
        _addressSession=null;
        _addressSuggestions=const [];
      });
    } finally {
      if (mounted && epoch==_addressEpoch) setState(() { _resolvingAddress=false; });
    }
  }

  Patch<String> patch(int i) => fields[i].text.trim().isEmpty
      ? const PatchClear()
      : PatchSet(fields[i].text.trim());
  Future<void> save() async {
    if (busy || base == null) return;
    if (pending == null) {
      if (widget.onSaveServiceRadius != null) {
        final value = int.tryParse(radius.text.trim());
        if (value == null || value < 0 || value > accountServiceRadiusMax) {
          setState(() => message = 'Enter a valid service radius in miles.');
          return;
        }
        pendingRadius = value;
      }
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
      if (pendingRadius != null) await widget.onSaveServiceRadius?.call(pendingRadius!, pending!.idempotencyKey);
      if (!mounted) return;
      setState(() {
        pending = null;
        load();
        pendingRadius = null;
        message = widget.showPhone ? 'Private contact details saved.' : 'Location settings saved.';
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
    final hasChanges = pending != null ||
        _loadedValues.length != fields.length ||
        List.generate(fields.length,
          (i) => fields[i].text != _loadedValues[i]).any((changed) => changed);
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
          Row(children: [
            Expanded(child: BuyerSectionHeading(title: widget.addressTitle ?? 'Private contact details')),
            if (widget.isPopup && widget.onDiscard != null)
              IconButton(
                tooltip: 'Close',
                onPressed: busy ? null : widget.onDiscard,
                icon: const Icon(Icons.close),
              ),
          ]),
          Text(
            widget.showPhone
              ? 'Your saved home address. Saving a phone number here does not verify it for login.'
              : 'Your saved business address. Search for the street or complete the fields below.',
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
                body: 'Please try again.',
              ),
            ),
          for (var i = widget.showPhone ? 0 : 1; i < fields.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: HocalistAccountField(
                fieldKey: Key('privateContact$i'),
                label: labels[i],
                seller: widget.seller,
                controller: fields[i],
                readOnly: busy || pending != null || _resolvingAddress,
                onChanged: (value) {
                  setState(() {});
                  if (i == 1 && widget.places != null) streetChanged(value);
                },
                maxLength: limits[i],
                keyboardType: i == 0 ? TextInputType.phone : TextInputType.text,
              ),
            ),
            if (i==1 && _resolvingAddress)
              const BuyerProgressStrip(label:'Finding address details…'),
            if (i==1 && _addressSearchError!=null)
              Padding(padding:const EdgeInsets.only(top:8),child:Text(_addressSearchError!)),
            if (i==1)
              for (final suggestion in _addressSuggestions)
                Padding(padding:const EdgeInsets.only(top:6),child:Material(
                  color:Colors.transparent,
                  child:InkWell(
                    key:ValueKey('contactAddress-${suggestion.placeId}'),
                    borderRadius:BorderRadius.circular(9),
                    onTap:_resolvingAddress ? null : ()=>selectStreet(suggestion),
                    child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
                      const Icon(Icons.place_outlined,color:BuyerUiTokens.action),
                      const SizedBox(width:8),Expanded(child:Text(suggestion.label)),
                    ])),
                  ),
                )),
          ],
          if (widget.onSaveServiceRadius != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: HocalistAccountField(
                fieldKey: const Key('businessServiceRadius'),
                label: 'Service radius (miles)', seller: widget.seller,
                controller: radius, keyboardType: TextInputType.number,
                readOnly: busy || pending != null,
                onChanged: (_) => setState(() {}),
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
            onPressed: busy || _resolvingAddress || base == null ? null : save,
            label: busy
                ? 'Saving…'
                : pending != null
                ? 'Retry contact save'
                : widget.showPhone ? 'Save contact details' : 'Save changes',
          ),
          if (widget.showPhone) ...[
          const SizedBox(height: 8),
          BuyerSecondaryButton(
            label: widget.isPopup && widget.onDiscard != null && !hasChanges
                ? 'Close'
                : pending != null
                ? 'Discard pending changes'
                : 'Discard changes',
            onPressed: busy
                ? null
                : () {
                    _searchDebounce?.cancel();
                    _addressEpoch++;
                    setState(() {
                      _resolvingAddress=false;
                      _addressSuggestions=const [];
                      _addressSearchError=null;
                      pending = null;
                      load();
                      message = 'Loaded the latest saved contact details.';
                    });
                    pendingRadius = null;
                    widget.onDiscard?.call();
                  },
          ),
          ],
        ],
      ),
    );
  }
}
