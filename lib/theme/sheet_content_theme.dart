import 'package:flutter/material.dart';

/// Carries the approved role typography through plain copy, options and
/// secondary actions inside a sheet. Explicit artwork and styles still win.
class SheetContentTheme extends StatelessWidget {
  const SheetContentTheme({
    required this.body,
    required this.heading,
    required this.caption,
    required this.action,
    required this.child,
    super.key,
  });

  final TextStyle body, heading, caption, action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Theme(
      data: theme.copyWith(
        textTheme: text.copyWith(
          titleSmall: text.titleSmall?.merge(heading),
          titleMedium: text.titleMedium?.merge(heading),
          bodyMedium: text.bodyMedium?.merge(body),
          bodySmall: text.bodySmall?.merge(caption),
          labelLarge: text.labelLarge?.merge(action),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: text.titleMedium?.merge(heading),
          subtitleTextStyle: text.bodySmall?.merge(caption),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            textStyle: WidgetStatePropertyAll(text.labelLarge?.merge(action)),
          ),
        ),
      ),
      child: DefaultTextStyle.merge(style: body, child: child),
    );
  }
}
