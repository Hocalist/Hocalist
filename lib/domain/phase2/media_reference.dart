/// Media references shared by profile, offer, listing and message contracts.
///
/// Models store server-issued media identifiers and descriptive metadata only.
/// Uploads, buckets, signed delivery URLs and deletion lifecycles are storage
/// integration work (SEC-07) and are deliberately not implemented here.
library;

import 'common.dart';

enum MediaKind { image, document }

/// A reference to one stored media object owned by the Hocalist backend.
class MediaReference {
  MediaReference({
    required String id,
    required this.kind,
    required String fileName,
    this.contentType,
    int? byteSize,
  }) : id = requireNonBlank(id, 'id'),
       fileName = requireNonBlank(fileName, 'fileName'),
       byteSize = byteSize {
    if (byteSize != null && byteSize < 0) {
      throw ArgumentError.value(byteSize, 'byteSize', 'must not be negative');
    }
    if (contentType != null && contentType!.trim().isEmpty) {
      throw ArgumentError.value(
        contentType,
        'contentType',
        'must not be blank when provided',
      );
    }
  }

  /// Server media row identifier. Never a raw device file path.
  final String id;

  final MediaKind kind;

  /// Original file name, kept for display and download naming.
  final String fileName;

  /// Optional MIME type, validated by the storage layer.
  final String? contentType;

  /// Optional size in bytes, validated against storage limits server-side.
  final int? byteSize;

  bool get isImage => kind == MediaKind.image;

  @override
  bool operator ==(Object other) =>
      other is MediaReference &&
      other.id == id &&
      other.kind == kind &&
      other.fileName == fileName &&
      other.contentType == contentType &&
      other.byteSize == byteSize;

  @override
  int get hashCode => Object.hash(id, kind, fileName, contentType, byteSize);

  @override
  String toString() =>
      'MediaReference(id: $id, kind: ${kind.name}, fileName: $fileName)';
}
