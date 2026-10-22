import 'catalogue.dart';

/// Server-labelled answers; commands transmit IDs only, never trusted labels.
class CategoryAnswer {
  CategoryAnswer({
    required this.groupId,
    required this.label,
    required List<String> optionIds,
    required List<String> labels,
  }) : optionIds = List.unmodifiable(optionIds),
       labels = List.unmodifiable(labels);
  final String groupId;
  final String label;
  final List<String> optionIds;
  final List<String> labels;
  Map<String, Object?> toJson() => {
    'group_id': groupId,
    'label': label,
    'option_ids': optionIds,
    'labels': labels,
  };
  static List<CategoryAnswer> decode(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > 40) {
      throw const FormatException('category_answers');
    }
    final result = <CategoryAnswer>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map ||
          value['group_id'] is! String ||
          value['label'] is! String ||
          value['option_ids'] is! List ||
          value['labels'] is! List) {
        throw const FormatException('category_answers');
      }
      final ids = value['option_ids'] as List, labels = value['labels'] as List;
      if (!seen.add(value['group_id'] as String) ||
          ids.length > 20 ||
          ids.length != labels.length ||
          ids.any((v) => v is! String) ||
          labels.any((v) => v is! String || v.length > 120)) {
        throw const FormatException('category_answers');
      }
      result.add(
        CategoryAnswer(
          groupId: value['group_id'] as String,
          label: value['label'] as String,
          optionIds: ids.cast<String>(),
          labels: labels.cast<String>(),
        ),
      );
    }
    return List.unmodifiable(result);
  }
}

Map<String, Object?> categoryAnswerInput(List<CategoryAnswer> answers) => {
  for (final answer in answers) answer.groupId: answer.optionIds,
};

class CategoryQuestion {
  CategoryQuestion(this.group, List<CatalogueOption> options)
    : options = List.unmodifiable(options);
  final CatalogueOptionGroup group;
  final List<CatalogueOption> options;
}
