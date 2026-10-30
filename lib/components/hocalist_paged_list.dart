import 'package:flutter/material.dart';
import '../theme/seller_ui_foundation.dart';

class HocalistPageControls extends StatelessWidget {
  const HocalistPageControls({
    required this.page,
    required this.onPrevious,
    required this.onNext,
    this.totalPages,
    this.loading = false,
    super.key,
  });
  final int page;
  final int? totalPages;
  final VoidCallback? onPrevious, onNext;
  final bool loading;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: loading ? null : onPrevious,
          child: const Text('Previous'),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            totalPages == null
                ? 'Page ${page + 1}'
                : 'Page ${page + 1} of $totalPages',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: loading ? null : onNext,
          child: Text(loading ? 'Loading…' : 'Next'),
        ),
      ],
    ),
  );
}

/// Displays bounded pages, requesting the next authorised server cursor only
/// when the cached rows cannot fill the next page. No client-side fake totals.
class HocalistPagedList<T> extends StatefulWidget {
  const HocalistPagedList({
    required this.items,
    required this.itemBuilder,
    this.pageSize = 5,
    this.hasMore = false,
    this.loadMore,
    this.resetKey,
    this.loadedCount,
    super.key,
  });
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  final int pageSize;
  final bool hasMore;
  final Future<void> Function()? loadMore;
  final Object? resetKey;
  final int? loadedCount;
  @override
  State<HocalistPagedList<T>> createState() => _HocalistPagedListState<T>();
}

class _HocalistPagedListState<T> extends State<HocalistPagedList<T>> {
  int page = 0, generation = 0;
  bool loading = false;
  String? error;
  @override
  void didUpdateWidget(covariant HocalistPagedList<T> old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) {
      page = 0;
      generation++;
      loading = false;
      error = null;
    }
    final last = ((widget.items.length - 1) / widget.pageSize).floor().clamp(
      0,
      1000000,
    );
    if (page > last) page = last;
  }

  Future<void> next() async {
    if (loading) return;
    final token = generation;
    final requestedPage = widget.items.isEmpty ? 0 : page + 1;
    final nextStart = requestedPage * widget.pageSize;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // A category filter may omit one fetched server page. Bound each click.
      for (
        var i = 0;
        i < 5 &&
            widget.items.length <= nextStart &&
            widget.hasMore &&
            widget.loadMore != null;
        i++
      ) {
        final before = widget.loadedCount ?? widget.items.length;
        await widget.loadMore!();
        if (!mounted || token != generation) return;
        await WidgetsBinding.instance.endOfFrame;
        if ((widget.loadedCount ?? widget.items.length) <= before) break;
      }
      if (mounted && token == generation && widget.items.length > nextStart) {
        setState(() => page = requestedPage);
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(
          () => error = 'Could not load the next page. Please try again.',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canNext =
        widget.items.length > (page + 1) * widget.pageSize || widget.hasMore;
    final total = (widget.items.length / widget.pageSize).ceil().clamp(
      1,
      1000000,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item
            in widget.items.skip(page * widget.pageSize).take(widget.pageSize))
          widget.itemBuilder(context, item),
        if (error != null)
          Text(
            error!,
            style: const TextStyle(color: SellerUiColors.primaryBright),
          ),
        HocalistPageControls(
          page: page,
          totalPages: widget.hasMore ? null : total,
          loading: loading,
          onPrevious: page == 0 ? null : () => setState(() => page--),
          onNext: canNext ? next : null,
        ),
      ],
    );
  }
}
