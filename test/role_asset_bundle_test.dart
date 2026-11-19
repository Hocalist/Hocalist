import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/theme/role_asset_bundle.dart';

class CountingBundle extends CachingAssetBundle {
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    if (key == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    return ByteData(1);
  }
}

class AssetProbe extends StatefulWidget {
  const AssetProbe({super.key});
  @override
  State<AssetProbe> createState() => AssetProbeState();
}

class AssetProbeState extends State<AssetProbe> {
  AssetBundle? bundle;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultAssetBundle.of(context);
    if (!identical(bundle, next)) {
      bundle = next;
      next.load('shared/chat-back.png');
    }
  }
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('chat data rebuilds retain artwork bundle and image cache keys', (tester) async {
    final parent = CountingBundle();
    final probe = GlobalKey<AssetProbeState>();
    Future<void> rebuild(String variant, AssetBundle bundle) => tester.pumpWidget(
      DefaultAssetBundle(bundle: bundle, child: RoleAssetVariant(
        sourceRoot: 'shared', variantRoot: variant,
        child: AssetProbe(key: probe),
      )),
    );
    await rebuild('seller', parent);
    final original = probe.currentState!.bundle!;
    final firstKey = await const AssetImage('shared/chat-back.png').obtainKey(
      ImageConfiguration(bundle: original),
    );
    for (var i = 0; i < 20; i++) {
      await rebuild('seller', parent);
      expect(probe.currentState!.bundle, same(original));
    }
    final refreshedKey = await const AssetImage('shared/chat-back.png').obtainKey(
      ImageConfiguration(bundle: probe.currentState!.bundle),
    );
    expect(refreshedKey, firstKey);
    expect(parent.loads.where((key) => key == 'seller/chat-back.png'), hasLength(1));

    // A genuine role change must still replace the artwork.
    await rebuild('buyer', parent);
    expect(probe.currentState!.bundle, isNot(same(original)));
    expect(parent.loads.last, 'buyer/chat-back.png');
    final replacement = CountingBundle();
    await rebuild('buyer', replacement);
    expect(replacement.loads, ['buyer/chat-back.png']);
  });
}
