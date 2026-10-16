import 'package:flutter/material.dart';
import '../theme/buyer_ui_foundation.dart';
import '../theme/seller_ui_foundation.dart';

class HocalistAccountField extends StatefulWidget {
  const HocalistAccountField({
    required this.label,
    required this.controller,
    this.seller = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.fieldKey,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final bool seller, enabled, readOnly, obscureText;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final Key? fieldKey;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  @override
  State<HocalistAccountField> createState() => _HocalistAccountFieldState();
}

class _HocalistAccountFieldState extends State<HocalistAccountField> {
  bool revealed = false;
  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width > 0
              ? MediaQuery.sizeOf(context).width
              : 390.0,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final style = TextStyle(
      fontFamily: 'Nunito',
      fontSize: metrics.fontSize(13),
      fontWeight: FontWeight.w700,
      color: widget.seller ? SellerUiColors.ink : BuyerUiTokens.text,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(9)),
      borderSide: BorderSide(
        color: widget.seller ? SellerUiColors.line : BuyerUiTokens.border,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: style),
        SizedBox(height: metrics.spacing(6)),
        Semantics(
          label: widget.label,
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            obscureText: widget.obscureText && !revealed,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            autocorrect:
                !widget.obscureText &&
                widget.keyboardType != TextInputType.emailAddress,
            enableSuggestions: !widget.obscureText,
            autofillHints: widget.autofillHints,
            textInputAction: widget.textInputAction ?? TextInputAction.next,
            onSubmitted: widget.onSubmitted,
            style: style,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              suffixIcon: widget.obscureText
                  ? IconButton(
                      tooltip:
                          '${revealed ? 'Hide' : 'Show'} ${widget.label.toLowerCase()}',
                      onPressed: widget.enabled
                          ? () => setState(() => revealed = !revealed)
                          : null,
                      icon: Icon(
                        revealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    )
                  : null,
              contentPadding: EdgeInsets.symmetric(
                horizontal: metrics.spacing(12),
                vertical: metrics.spacing(12),
              ),
              constraints: BoxConstraints(
                minHeight: metrics.geometry(widget.maxLines == 1 ? 48 : 72),
              ),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(
                  color: widget.seller
                      ? SellerUiColors.primaryBright
                      : BuyerUiTokens.action,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HocalistAccountFormCard extends StatelessWidget {
  const HocalistAccountFormCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: SellerUiColors.line),
    ),
    child: child,
  );
}
