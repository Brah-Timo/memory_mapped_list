// ignore_for_file: avoid_redundant_argument_values

import 'dart:convert';
import 'dart:typed_data';

/// Contract for converting Dart objects to/from raw bytes.
///
/// Implement this interface when using [MmlGenericList] with custom types.
///
/// Built-in implementations:
/// * [JsonSerializer] — for any JSON-serialisable object (variable size)
/// * [StringSerializer] — for UTF-8 strings (variable size)
/// * [Int32Serializer] — for `int` stored as 32-bit (fixed 4 bytes)
/// * [Int64Serializer] — for `int` stored as 64-bit (fixed 8 bytes)
/// * [Float64Serializer] — for `double` stored as 64-bit (fixed 8 bytes)
///
/// ### Example — custom struct
/// ```dart
/// class Point {
///   final double x, y;
///   const Point(this.x, this.y);
/// }
///
/// class PointSerializer extends MmlSerializer<Point> {
///   @override
///   Uint8List serialize(Point p) {
///     final bd = ByteData(16);
///     bd.setFloat64(0, p.x, Endian.little);
///     bd.setFloat64(8, p.y, Endian.little);
///     return bd.buffer.asUint8List();
///   }
///
///   @override
///   Point deserialize(Uint8List bytes) {
///     final bd = ByteData.sublistView(bytes);
///     return Point(bd.getFloat64(0, Endian.little), bd.getFloat64(8, Endian.little));
///   }
///
///   @override bool get isFixedSize => true;
///   @override int? get fixedSize => 16;
/// }
/// ```
abstract class MmlSerializer<T> {
  const MmlSerializer();

  /// Converts [value] to its binary representation.
  Uint8List serialize(T value);

  /// Reconstructs a [T] from its binary representation.
  T deserialize(Uint8List bytes);

  /// `true` when every serialized value has the same byte length.
  ///
  /// Fixed-size serializers allow the storage engine to use more efficient
  /// direct-offset arithmetic instead of per-element index lookups.
  bool get isFixedSize;

  /// The fixed byte length, or `null` for variable-size serializers.
  int? get fixedSize;
}

// ── JSON serializer ───────────────────────────────────────────────────────────

/// Serializes objects to/from JSON UTF-8.
///
/// The output is variable-length.  JSON is human-readable but larger and
/// slower than a binary serializer.  Prefer a custom binary [MmlSerializer]
/// for performance-critical code.
///
/// ```dart
/// final s = JsonSerializer<User>(
///   fromJson: User.fromJson,
///   toJson: (u) => u.toJson(),
/// );
/// ```
final class JsonSerializer<T> extends MmlSerializer<T> {
  /// Factory that creates a [T] from a decoded JSON map.
  final T Function(Map<String, dynamic>) fromJson;

  /// Converts a [T] to a JSON-encodable map.
  final Map<String, dynamic> Function(T) toJson;

  const JsonSerializer({required this.fromJson, required this.toJson});

  @override
  Uint8List serialize(T value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson(value))));

  @override
  T deserialize(Uint8List bytes) =>
      fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  @override
  bool get isFixedSize => false;

  @override
  int? get fixedSize => null;
}

// ── String serializer ─────────────────────────────────────────────────────────

/// Serializes [String] values to/from UTF-8 bytes.
///
/// Variable length — the [MmlGenericList] index file tracks each element's
/// byte offset and length.
final class StringSerializer extends MmlSerializer<String> {
  const StringSerializer();

  @override
  Uint8List serialize(String value) =>
      Uint8List.fromList(utf8.encode(value));

  @override
  String deserialize(Uint8List bytes) => utf8.decode(bytes);

  @override
  bool get isFixedSize => false;

  @override
  int? get fixedSize => null;
}

// ── Int32 serializer ──────────────────────────────────────────────────────────

/// Serializes [int] values as little-endian 32-bit signed integers (4 bytes).
///
/// Values must be in the range `[−2 147 483 648, 2 147 483 647]`.
final class Int32Serializer extends MmlSerializer<int> {
  const Int32Serializer();

  @override
  Uint8List serialize(int value) {
    final bd = ByteData(4);
    bd.setInt32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  int deserialize(Uint8List bytes) =>
      ByteData.sublistView(bytes).getInt32(0, Endian.little);

  @override
  bool get isFixedSize => true;

  @override
  int? get fixedSize => 4;
}

// ── Int64 serializer ──────────────────────────────────────────────────────────

/// Serializes [int] values as little-endian 64-bit signed integers (8 bytes).
final class Int64Serializer extends MmlSerializer<int> {
  const Int64Serializer();

  @override
  Uint8List serialize(int value) {
    final bd = ByteData(8);
    bd.setInt64(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  int deserialize(Uint8List bytes) =>
      ByteData.sublistView(bytes).getInt64(0, Endian.little);

  @override
  bool get isFixedSize => true;

  @override
  int? get fixedSize => 8;
}

// ── Float64 serializer ────────────────────────────────────────────────────────

/// Serializes [double] values as little-endian 64-bit IEEE 754 (8 bytes).
final class Float64Serializer extends MmlSerializer<double> {
  const Float64Serializer();

  @override
  Uint8List serialize(double value) {
    final bd = ByteData(8);
    bd.setFloat64(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  double deserialize(Uint8List bytes) =>
      ByteData.sublistView(bytes).getFloat64(0, Endian.little);

  @override
  bool get isFixedSize => true;

  @override
  int? get fixedSize => 8;
}

// ── Float32 serializer ────────────────────────────────────────────────────────

/// Serializes [double] values as little-endian 32-bit IEEE 754 (4 bytes).
final class Float32Serializer extends MmlSerializer<double> {
  const Float32Serializer();

  @override
  Uint8List serialize(double value) {
    final bd = ByteData(4);
    bd.setFloat32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  double deserialize(Uint8List bytes) =>
      ByteData.sublistView(bytes).getFloat32(0, Endian.little);

  @override
  bool get isFixedSize => true;

  @override
  int? get fixedSize => 4;
}

// ── Bytes serializer ──────────────────────────────────────────────────────────

/// Pass-through serializer for raw [Uint8List] blobs.
///
/// Useful when you want to manage your own binary encoding and just need the
/// paging infrastructure.
final class BytesSerializer extends MmlSerializer<Uint8List> {
  const BytesSerializer();

  @override
  Uint8List serialize(Uint8List value) => value;

  @override
  Uint8List deserialize(Uint8List bytes) => bytes;

  @override
  bool get isFixedSize => false;

  @override
  int? get fixedSize => null;
}
