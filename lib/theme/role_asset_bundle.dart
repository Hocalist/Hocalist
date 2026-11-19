import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps shared page structure while allowing each role to use its approved
/// artwork. Requests below [sourceRoot] are transparently served from
/// [variantRoot]; all other assets continue through the parent bundle.
class RoleAssetVariant extends StatefulWidget {
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
  State<RoleAssetVariant> createState() => _RoleAssetVariantState();
}

class _RoleAssetVariantState extends State<RoleAssetVariant> {
  AssetBundle? _parent;
  late _RoleAssetBundle _bundle;

  void _replaceBundle() {
    _bundle = _RoleAssetBundle(
      parent: _parent!,
      sourceRoot: widget.sourceRoot,
      variantRoot: widget.variantRoot,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = DefaultAssetBundle.of(context);
    if (!identical(parent, _parent)) {
      _parent = parent;
      _replaceBundle();
    }
  }

  @override
  void didUpdateWidget(covariant RoleAssetVariant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceRoot != widget.sourceRoot ||
        oldWidget.variantRoot != widget.variantRoot) {
      _replaceBundle();
    }
  }

  // AssetImage includes bundle identity in its cache key. Keep it stable on
  // data refreshes so unchanged artwork does not disappear and decode again.
  @override
  Widget build(BuildContext context) => DefaultAssetBundle(
    bundle: _bundle,
    child: widget.child,
  );
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
