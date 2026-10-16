/// Shared value objects for the Phase 2 Hocalist domain contracts.
///
/// This library is pure Dart. It does not import Flutter or any package, and
/// it performs no network, storage, timezone-conversion or financial work.
/// Every type here is a proposal for integration review, not a deployed
/// database or API contract.
library;

/// Server-owned revision and timestamp metadata for a mutable business record.
///
/// [revision] increments on every accepted server write and is the value a
/// stale-write check compares against. Clients read it; they never assign it.
class RecordStamp {
  RecordStamp({
    required this.revision,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  /// Monotonic server revision. Never written from a client command.
  final int revision;

  /// Server creation time, normalized to UTC.
  final DateTime createdAt;

  /// Server last-write time, normalized to UTC.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is RecordStamp &&
      other.revision == revision &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(revision, createdAt, updatedAt);

  @override
  String toString() =>
      'RecordStamp(revision: $revision, createdAt: $createdAt, '
      'updatedAt: $updatedAt)';
}

/// Bounded, cursor-based read window for list queries.
class PageQuery {
  factory PageQuery({int limit = 50, String? cursor}) {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 200');
    }
    if (cursor != null && cursor.trim().isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be blank');
    }
    return PageQuery._(limit, cursor);
  }

  const PageQuery._(this.limit, this.cursor);

  /// The default first page used when a caller does not supply one.
  static const PageQuery standard = PageQuery._(50, null);

  final int limit;

  /// Opaque server cursor. Clients never parse or construct it.
  final String? cursor;

  @override
  String toString() => 'PageQuery(limit: $limit, cursor: $cursor)';
}

/// One page of server results plus the cursor for the next page.
class PageSlice<T> {
  PageSlice({required List<T> items, this.nextCursor})
    : items = List<T>.unmodifiable(items) {
    if (nextCursor != null && nextCursor!.trim().isEmpty) {
      throw ArgumentError.value(nextCursor, 'nextCursor', 'must not be blank');
    }
  }

  final List<T> items;

  /// Opaque server cursor, or null when this is the last page.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  @override
  String toString() => 'PageSlice(items: ${items.length}, hasMore: $hasMore)';
}

/// Postal address values collected by request and profile forms.
///
/// Request location is private until the buyer chooses to share it; the exact
/// address must not appear in public profile projections.
class PostalAddress {
  const PostalAddress({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  bool get isEmpty =>
      isBlank(line1) &&
      isBlank(line2) &&
      isBlank(city) &&
      isBlank(state) &&
      isBlank(postalCode) &&
      isBlank(country);

  bool get isNotEmpty => !isEmpty;

  /// Number of populated address fields, useful for debugging without
  /// exposing the values.
  int get populatedFieldCount => [
    line1,
    line2,
    city,
    state,
    postalCode,
    country,
  ].where((value) => !isBlank(value)).length;

  @override
  bool operator ==(Object other) =>
      other is PostalAddress &&
      other.line1 == line1 &&
      other.line2 == line2 &&
      other.city == city &&
      other.state == state &&
      other.postalCode == postalCode &&
      other.country == country;

  @override
  int get hashCode =>
      Object.hash(line1, line2, city, state, postalCode, country);

  /// Redacted on purpose: addresses are private data and must not reach logs.
  @override
  String toString() =>
      'PostalAddress([redacted], populatedFields: $populatedFieldCount)';
}

/// True when [value] is null or only whitespace.
bool isBlank(String? value) => value == null || value.trim().isEmpty;

/// Throws [ArgumentError] when [value] is null or only whitespace, otherwise
/// returns it unchanged. Used to reject structurally invalid identifiers.
String requireNonBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}

/// Returns null for a blank [value], otherwise the value unchanged. Used for
/// optional identifiers such as a parent category or slug.
String? optionalNonBlank(String? value, String name) {
  if (value == null) return null;
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank when provided');
  }
  return value;
}

/// Validates every id and returns an unmodifiable copy. Used for media id
/// lists so a blank reference cannot reach a command or record.
List<String> requireNonBlankIds(Iterable<String> ids, String name) {
  final validated = <String>[];
  for (final id in ids) {
    validated.add(requireNonBlank(id, name));
  }
  return List<String>.unmodifiable(validated);
}
