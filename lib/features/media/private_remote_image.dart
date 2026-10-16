import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/media/image_gateway.dart';

class PrivateRemoteImage extends StatefulWidget {
  const PrivateRemoteImage({
    required this.id,
    this.size = 100,
    this.read,
    super.key,
  });
  final String id;
  final double size;
  final Future<Uint8List> Function(String id)? read;
  @override
  State<PrivateRemoteImage> createState() => _PrivateRemoteImageState();
}

class _PrivateRemoteImageState extends State<PrivateRemoteImage> {
  late Future<Uint8List> loading;
  Uint8List? bytes;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final run = ++generation;
    loading =
        Future.sync(
          () =>
              widget.read?.call(widget.id) ??
              ImageGateway(Supabase.instance.client).read(widget.id),
        ).then((value) {
          if (mounted && run == generation) bytes = value;
          return value;
        });
  }

  @override
  void didUpdateWidget(covariant PrivateRemoteImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      evict();
      load();
    }
  }

  void evict() {
    if (bytes != null) MemoryImage(bytes!).evict();
    bytes = null;
  }

  @override
  void dispose() {
    generation++;
    evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: FutureBuilder<Uint8List>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        }
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(load),
            child: const Text('Retry photo'),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    ),
  );
}
