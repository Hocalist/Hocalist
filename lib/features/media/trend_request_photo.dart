import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../domain/phase2/discovery.dart';
import 'private_remote_image.dart';

/// Uses the same request-scoped, opted-in seller response as See Sellers.
class TrendRequestPhoto extends StatefulWidget {
  const TrendRequestPhoto({required this.requestId, required this.size,
    required this.version, this.load, this.read, super.key});
  final String requestId;
  final double size;
  final Object? version;
  final Future<HocatrendsSellerResults> Function(String)? load;
  final Future<Uint8List> Function(String)? read;
  @override
  State<TrendRequestPhoto> createState() => _TrendRequestPhotoState();
}

class _TrendRequestPhotoState extends State<TrendRequestPhoto> {
  Future<HocatrendsSellerResults>? result;
  @override
  void initState() { super.initState(); reload(); }
  void reload() {
    result = widget.load == null ? null : Future.sync(() => widget.load!(widget.requestId));
    result?.ignore();
  }
  @override
  void didUpdateWidget(covariant TrendRequestPhoto old) {
    super.didUpdateWidget(old);
    if (old.requestId != widget.requestId || old.version != widget.version ||
        (old.load == null) != (widget.load == null)) reload();
  }
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: FutureBuilder<HocatrendsSellerResults>(future: result, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError &&
          snapshot.data?.topicId == widget.requestId) {
        final photos = [for (final seller in snapshot.data!.items)
          for (final id in seller.offerImageMediaIds) (id: id, seller: seller.displayName)];
        if (photos.isNotEmpty) return PageView(
          key: ValueKey('trend-photo-pages-${widget.requestId}'),
          children: [for (final photo in photos) Tooltip(
            message: 'Photo from ${photo.seller}',
            child: Semantics(label: 'Photo from ${photo.seller}', image: true,
              child: PrivateRemoteImage(id: photo.id, size: widget.size,
                read: widget.read, showWholeImage: true)),
          )],
        );
      }
      final loading = snapshot.connectionState == ConnectionState.waiting;
      return Center(child: Text(
        loading ? 'Loading photo…' : snapshot.hasError ? 'Photo unavailable' : 'No seller photos yet',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
      ));
    }),
  );
}
