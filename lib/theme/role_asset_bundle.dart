import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps shared page structure while allowing each role to use its approved
/// artwork. Requests below [sourceRoot] are transparently served from
/// [variantRoot]; all other assets continue through the parent bundle.
class RoleAssetVariant extends StatelessWidget {
  const RoleAssetVariant({
    required this.sourceRoot,
    required this.variantRoot,
    required this.child,
    super.key,
  });

  final String sourceRoot;
  final String variantRoot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultAssetBundle(
      bundle: _RoleAssetBundle(
        parent: DefaultAssetBundle.of(context),
        sourceRoot: sourceRoot,
        variantRoot: variantRoot,
      ),
      child: child,
    );
  }
}

class _RoleAssetBundle extends CachingAssetBundle {
  _RoleAssetBundle({
    required this.parent,
    required String sourceRoot,
    required String variantRoot,
  }) : sourcePrefix = _prefix(sourceRoot),
       variantPrefix = _prefix(variantRoot);

  final AssetBundle parent;
  final String sourcePrefix;
  final String variantPrefix;

  static String _prefix(String value) =>
      value.endsWith('/') ? value : '$value/';

  String _map(String key) {
    if (!key.startsWith(sourcePrefix)) return key;
    return '$variantPrefix${key.substring(sourcePrefix.length)}';
  }

  @override
  Future<ByteData> load(String key) => parent.load(_map(key));
}
