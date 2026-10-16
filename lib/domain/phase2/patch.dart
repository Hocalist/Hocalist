/// Patch semantics for optional account fields.
///
/// The account RPC distinguishes three states per optional field:
/// - [PatchKeep] — the key is omitted from the JSON payload; SQL keeps the
///   current value.
/// - [PatchClear] — the key is sent with a JSON null; SQL stores NULL.
/// - [PatchSet] — the key is sent with the value; SQL stores it.
///
/// Empty strings are values, not clears. The SQL drafts store `''` as-is and
/// only `display_name` is length-validated after trimming.
library;

/// One optional-field update state.
sealed class Patch<T> {
  const Patch();

  bool get isKeep => this is PatchKeep<T>;

  bool get isClear => this is PatchClear<T>;

  bool get isSet => this is PatchSet<T>;

  /// The set value, or null for keep/clear.
  T? get valueOrNull => switch (this) {
    PatchSet<T>(:final value) => value,
    PatchKeep<T>() || PatchClear<T>() => null,
  };
}

/// Omit the field from the payload.
final class PatchKeep<T> extends Patch<T> {
  const PatchKeep();

  @override
  String toString() => 'PatchKeep()';
}

/// Send the field as JSON null.
final class PatchClear<T> extends Patch<T> {
  const PatchClear();

  @override
  String toString() => 'PatchClear()';
}

/// Send the field with a concrete value.
final class PatchSet<T> extends Patch<T> {
  const PatchSet(this.value);

  final T value;

  @override
  String toString() => 'PatchSet($value)';
}
