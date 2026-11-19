import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/discovery/discovery_adapter.dart';
import 'package:hocalist/features/discovery/seller_search_location.dart';
void main() {
 const business = SellerDiscoveryOriginInput(areaLabel:'Johnson City, NY',latitude:42,longitude:-76,radiusMiles:17);
 SellerDiscoveryOrigin result(SellerDiscoveryOriginInput i) => SellerDiscoveryOrigin(configured:true,areaLabel:i.areaLabel,coordinatesPresent:i.latitude!=null,radiusMiles:i.radiusMiles);
 test('opening an empty search leaves it empty without restoring the business address',() async {
  SellerDiscoveryOriginInput? written;
  final search=SellerSearchLocation(loadOrigin:()async=>const SellerDiscoveryOrigin.notConfigured(),readDefault:()async=>business,
    persist:(i,k)async{written=i;return result(i);},resolve:(_)async=>throw StateError('not needed'));
  final origin=await search.load();expect(origin.coordinatesPresent,isFalse);expect(written,isNull);
 });
 test('clear removes search location; retries reuse payload',() async {
  final writes=<SellerDiscoveryOriginInput>[];var fail=true;
  final search=SellerSearchLocation(loadOrigin:()async=>result(business),readDefault:()async=>business,
    persist:(i,k)async{writes.add(i);if(fail){fail=false;throw StateError('network');}return result(i);},
    resolve:(area)async=>SellerDiscoveryOriginInput(areaLabel:area,latitude:41,longitude:-74));
  const override=SellerDiscoveryOriginInput(areaLabel:'Other city',radiusMiles:50);
  await expectLater(search.save(override,'search'),throwsStateError);
  await search.save(override,'search');expect(writes[0],same(writes[1]));expect(writes.last.latitude,41);
  await search.save(const SellerDiscoveryOriginInput(),'clear');expect(writes.last.areaLabel,isNull);expect(writes.last.latitude,isNull);expect(writes.last.longitude,isNull);
 });
 test('existing search remains active; missing coordinates never become invented distances',() async {
  var writes=0;
  final search=SellerSearchLocation(loadOrigin:()async=>result(business),readDefault:()async=>const SellerDiscoveryOriginInput(),
    persist:(i,k)async{writes++;return result(i);},resolve:(_)async=>const SellerDiscoveryOriginInput());
  expect((await search.load()).coordinatesPresent,isTrue);expect(writes,0);
  await expectLater(search.save(const SellerDiscoveryOriginInput(areaLabel:'Unknown'),'bad'),throwsException);expect(writes,0);
 });
}
