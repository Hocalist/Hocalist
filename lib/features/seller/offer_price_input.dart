/// Parses positive offer amounts with optional currency and grouped thousands.
double? parseOfferPrice(String input) {
  final value = input.trim().replaceFirst(RegExp(r'^\$\s*'), '');
  if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$').hasMatch(value)) return null;
  final amount = double.tryParse(value.replaceAll(',', ''));
  return amount != null && amount.isFinite && amount > 0 ? amount : null;
}
