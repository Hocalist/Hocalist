import 'package:flutter/material.dart';
import 'pull_refresh.dart';

/// Retains existing callers while moving ordinary reloads to the pull gesture.
class HocalistReloadLink extends StatelessWidget {
  const HocalistReloadLink({required this.onPressed, this.description = 'Reload', this.loading = false, this.color, super.key});
  final VoidCallback? onPressed;
  final String description;
  final bool loading;
  final Color? color;
  @override
  Widget build(BuildContext context) => description.toLowerCase().contains('discard')
      ? TextButton(onPressed: loading ? null : onPressed, child: const Text('Discard changes'))
      : PullRefreshAction(onRefresh: loading ? null : onPressed);
}
