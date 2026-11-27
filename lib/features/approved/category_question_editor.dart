import '../../components/pull_refresh.dart';
import 'package:hocalist/components/hocalist_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/phase2/marketplace/marketplace_composition.dart';
import '../../domain/phase2/catalogue.dart';
import '../../domain/phase2/category_answers.dart';

typedef CategoryQuestionLoader =
    Future<List<CategoryQuestion>> Function(String);

Future<List<CategoryQuestion>> loadCategoryQuestions(String categoryId) async {
  final result = await createMarketplaceDataAdapter(
    client: Supabase.instance.client,
  ).fetchCategoryQuestions(categoryId);
  if (result.isFailure) throw StateError('category_questions_unavailable');
  return result.valueOrNull!;
}

/// The same admin-managed questions are used for buyer requests and Store.
class CategoryQuestionEditor extends StatefulWidget {
  const CategoryQuestionEditor({
    required this.categoryId,
    required this.answers,
    required this.onChanged,
    this.loader = loadCategoryQuestions,
    this.compactRequestFields = false,
    super.key,
  });
  final String categoryId;
  final List<CategoryAnswer> answers;
  final ValueChanged<List<CategoryAnswer>> onChanged;
  final CategoryQuestionLoader loader;
  final bool compactRequestFields;

  @override
  State<CategoryQuestionEditor> createState() => CategoryQuestionEditorState();
}

class CategoryQuestionEditorState extends State<CategoryQuestionEditor> {
  List<CategoryQuestion> _questions = const [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  String? validationMessage({bool requiredAnswers = true}) {
    if (_loading) return 'Please wait for the category questions to load.';
    if (_failed) return 'Try loading the category questions again before continuing.';
    for (final question in _questions) {
      final selected = widget.answers.where(
        (a) => a.groupId == question.group.id,
      );
      final ids = selected.isEmpty ? <String>[] : selected.first.optionIds;
      final valid = ids.where((id) => question.options.any((o) => o.id == id));
      if (valid.length != ids.length ||
          (requiredAnswers && question.group.isRequired && ids.isEmpty)) {
        return 'Choose ${question.group.label.toLowerCase()} before continuing.';
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CategoryQuestionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _questions = const [];
    });
    try {
      final questions = await widget.loader(widget.categoryId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _select(CategoryQuestion question, String id) {
    final previous = widget.answers.where(
      (a) => a.groupId == question.group.id,
    );
    final ids = previous.isEmpty ? <String>[] : [...previous.first.optionIds];
    if (ids.contains(id)) {
      ids.remove(id);
    } else if (question.group.selectionMode == CatalogueSelectionMode.single) {
      ids
        ..clear()
        ..add(id);
    } else if (ids.length < 20) {
      ids.add(id);
    }
    final selected = question.options.where((o) => ids.contains(o.id)).toList();
    widget.onChanged([
      ...widget.answers.where((a) => a.groupId != question.group.id),
      if (selected.isNotEmpty)
        CategoryAnswer(
          groupId: question.group.id,
          label: question.group.label,
          optionIds: selected.map((o) => o.id).toList(),
          labels: selected.map((o) => o.label).toList(),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => PullRefreshAction(onRefresh: _loading ? null : _load, child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: HocalistLoadingIndicator(),
      );
    }
    if (_failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CategoryAnswersView(answers: widget.answers),
        Row(children: [
          const Expanded(child: Text('Category questions could not load.')),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ]),
      ]);
    }
    if (_questions.isEmpty) return const SizedBox.shrink();
    if (widget.compactRequestFields) {
      final mandatory = _questions.any((question) => question.group.isRequired);
      return Card(
        margin: const EdgeInsets.only(top: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Item preferences', style: theme.textTheme.titleMedium),
              Text(
                mandatory
                    ? 'Required fields are marked with an asterisk.'
                    : 'Choose what matters to you. All fields are optional.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _questions.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final question = _questions[i];
                      final first = _questionField(question);
                      if (i + 1 == _questions.length) return first;
                      final second = _questionField(_questions[i + 1]);
                      if (constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(14) > 17) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [first, const SizedBox(height: 8), second],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: first),
                          const SizedBox(width: 8),
                          Expanded(child: second),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final question in _questions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _questionField(question),
          ),
      ],
    );
  }

  Widget _questionField(CategoryQuestion question) {
    final group = question.group;
    final selected = {
      for (final answer in widget.answers)
        if (answer.groupId == group.id) ...answer.optionIds,
    };
    final useDropdown = widget.compactRequestFields &&
        group.selectionMode == CatalogueSelectionMode.single &&
        question.options.isNotEmpty;
    final single = question.options
        .where((option) => selected.contains(option.id))
        .firstOrNull?.id;
    final label = '${group.label}${group.isRequired ? ' *' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        if (useDropdown)
          Semantics(
            label: label,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: single ?? '',
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyMedium,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        group.isRequired ? 'Select' : 'No preference',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final option in question.options)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null || id == (single ?? '')) return;
                    _select(question, id.isEmpty ? single! : id);
                  },
                ),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in question.options)
                FilterChip(
                  label: Text(option.label),
                  selected: selected.contains(option.id),
                  onSelected: (_) => _select(question, option.id),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class CategoryAnswersView extends StatelessWidget {
  const CategoryAnswersView({required this.answers, super.key});
  final List<CategoryAnswer> answers;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final answer in answers)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('${answer.label}: ${answer.labels.join(', ')}'),
        ),
    ],
  );
}
