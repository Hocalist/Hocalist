import 'package:flutter/material.dart';
import '../../domain/phase2/account_contacts.dart';
import '../../data/phase2/maps/places_repository.dart';
import '../../data/phase2/maps/places_contract.dart';
import '../../components/hocalist_loading_indicator.dart';
import 'private_contact_editor.dart';

class BusinessAddressEditor extends StatefulWidget {
  const BusinessAddressEditor({required this.load,required this.save,required this.onLoaded,this.places,this.onResolvedAddress,this.onDiscard,super.key});
  final Future<PrivateContactRecord> Function() load;
  final Future<PrivateContactRecord> Function(UpdateContactCommand) save;
  final ValueChanged<PrivateContactRecord> onLoaded;
  final PlacesRepository? places;
  final ValueChanged<PlaceDetails>? onResolvedAddress;
  final VoidCallback? onDiscard;
  @override
  State<BusinessAddressEditor> createState()=>_BusinessAddressEditorState();
}
class _BusinessAddressEditorState extends State<BusinessAddressEditor> {
  PrivateContactRecord? record;
  bool loading=true;
  bool failed=false;
  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    setState((){loading=true;failed=false;});
    try {
      final next=await widget.load();
      if(!mounted)return;
      setState(()=>record=next);
      widget.onLoaded(next);
    } catch(_){if(mounted)setState(()=>failed=true);}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override
  Widget build(BuildContext context){
    if(loading)return const Center(child:HocalistLoadingIndicator());
    if(failed)return Column(children:[const Text('Your business address could not be loaded.'),TextButton(onPressed:load,child:const Text('Try again'))]);
    return PrivateContactEditor(
      seller:true,showPhone:false,addressTitle:'Business address',places:widget.places,
      readCurrent:()=>record,onResolvedAddress:widget.onResolvedAddress,
      onDiscard:widget.onDiscard,
      onSave:(command) async {
        final next=await widget.save(command);
        if(!mounted)return;
        setState(()=>record=next);widget.onLoaded(next);
      },
    );
  }
}
