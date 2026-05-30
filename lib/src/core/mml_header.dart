// ignore_for_file: avoid_redundant_argument_values

import 'dart:typed_data';

/// The binary layout of every `.mml` file starts with a fixed 128-byte header.
///
/// ```
///  Offset │ Size │ Field
/// ────────┼──────┼──────────────────────────────────────────────────────
///   0     │  4   │ Magic number : 0x4D4D4C01  ("MML\x01")
///   4     │  4   │ Format version : 1
///   8     │  8   │ Element count  (int64, little-endian)
///  16     │  4   │ Element size in bytes (int32)
///  20     │  4   │ Element type ID — see [ElementType] (int32)
///  24     │  8   │ Created-at  (int64, µs since Unix epoch)
///  32     │  8   │ Modified-at (int64, µs since Unix epoch)
///  40     │  4   │ Page size used when the file was created (int32)
///  44     │  4   │ Flags bitmask (int32) — see flag constants below
///  48     │  64  │ User metadata  (UTF-8, NUL-terminated, max 63 chars)
/// 112     │  16  │ Reserved (zeroed)
/// 128     │  …   │ *** DATA STARTS HERE ***
/// ```
///
/// The [MmlFileHeader.headerSize] constant (128) is the only offset that
/// external code should ever depend on.

// ── Element types ────────────────────────────────────────────────────────────

/// Identifies which Dart numeric type is stored in a `.mml` file.
enum ElementType {
  /// 32-bit signed integer — corresponds to [MmlInt32List].
  int32(id: 1, byteSize: 4),

  /// 64-bit signed integer — corresponds to [MmlInt64List].
  int64(id: 2, byteSize: 8),

  /// 32-bit IEEE 754 float — corresponds to [MmlFloat32List].
  float32(id: 3, byteSize: 4),

  /// 64-bit IEEE 754 double — corresponds to [MmlDoubleList].
  float64(id: 4, byteSize: 8),

  /// Variable-length generic objects — corresponds to [MmlGenericList].
  ///
  /// The [byteSize] field is -1 because element sizes are not uniform;
  /// a separate `.mml.idx` index file stores per-element byte offsets.
  generic(id: 99, byteSize: -1);

  /// Numeric identifier stored in the file header.
  final int id;

  /// Fixed byte size per element, or -1 for variable-length types.
  final int byteSize;

  const ElementType({required this.id, required this.byteSize});

  /// Reverse-lookup from the raw [id] stored in the file.
  ///
  /// Returns [ElementType.generic] when the [id] is not recognised so that
  /// older files remain openable after new element types are added.
  static ElementType fromId(int id) =>
      values.firstWhere((e) => e.id == id, orElse: () => generic);
}

// ── Flag bitmask constants ────────────────────────────────────────────────────

/// The file was created with [AccessMode.readOnly]; writes are forbidden.
const int kFlagReadOnly = 0x01;

/// (Reserved) — data is compressed; not yet implemented.
const int kFlagCompressed = 0x02;

/// The header was written but the file was not closed cleanly (dirty flag).
/// When set, the file may contain incomplete writes.
const int kFlagDirtyShutdown = 0x04;

// ── MmlFileHeader ─────────────────────────────────────────────────────────────

/// Metadata stored at the very beginning of every `.mml` file.
///
/// Use [MmlFileHeader.create] to build a fresh header and [MmlFileHeader.fromBytes]
/// to parse an existing one.  The header is always exactly [headerSize] bytes.
final class MmlFileHeader {
  // ── Constants ──────────────────────────────────────────────────────────────

  /// Size of the on-disk header in bytes.  Data always starts at this offset.
  static const int headerSize = 128;

  static const int _magic = 0x4D4D4C01; // "MML\x01"
  static const int _version = 1;

  // ── Fields ─────────────────────────────────────────────────────────────────

  /// Number of elements currently stored.
  int elementCount;

  /// Fixed byte size of each element (−1 for generic/variable).
  final int elementSize;

  /// The logical type stored in this file.
  final ElementType elementType;

  /// Timestamp when the file was first created.
  final DateTime createdAt;

  /// Timestamp of the last [updateLength] or flush call.
  DateTime modifiedAt;

  /// The page size (in bytes) that was used when the buffer was created.
  /// Stored so that the file can be re-opened with a compatible page size.
  final int pageSize;

  /// Bitmask of [kFlagReadOnly], [kFlagCompressed], [kFlagDirtyShutdown], etc.
  int flags;

  /// Up to 63 bytes of freeform UTF-8 metadata set by the caller.
  String metadata;

  // ── Constructor ───────────────────────────────────────────────────────────

  MmlFileHeader({
    required this.elementCount,
    required this.elementSize,
    required this.elementType,
    required this.pageSize,
    this.flags = 0,
    this.metadata = '',
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  /// Named convenience constructor.
  factory MmlFileHeader.create({
    required int elementCount,
    required ElementType elementType,
    required int pageSize,
    String metadata = '',
  }) {
    return MmlFileHeader(
      elementCount: elementCount,
      elementSize: elementType.byteSize,
      elementType: elementType,
      pageSize: pageSize,
      metadata: metadata,
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  /// Encodes this header into a [headerSize]-byte [Uint8List] ready to be
  /// written at offset 0 of the `.mml` file.
  Uint8List toBytes() {
    final bd = ByteData(headerSize);

    bd.setUint32(0, _magic, Endian.little);
    bd.setUint32(4, _version, Endian.little);
    bd.setInt64(8, elementCount, Endian.little);
    bd.setInt32(16, elementSize, Endian.little);
    bd.setInt32(20, elementType.id, Endian.little);
    bd.setInt64(24, createdAt.microsecondsSinceEpoch, Endian.little);
    bd.setInt64(32, modifiedAt.microsecondsSinceEpoch, Endian.little);
    bd.setInt32(40, pageSize, Endian.little);
    bd.setInt32(44, flags, Endian.little);

    // Metadata — max 63 bytes + NUL terminator at byte 111
    final metaBytes = metadata.codeUnits;
    final limit = metaBytes.length.clamp(0, 63);
    for (var i = 0; i < limit; i++) {
      bd.setUint8(48 + i, metaBytes[i] & 0xFF);
    }
    // bytes 48+limit … 111 are already zero from the zeroed ByteData

    // Reserved: bytes 112–127 remain zero.
    return bd.buffer.asUint8List();
  }

  // ── Deserialisation ───────────────────────────────────────────────────────

  /// Parses a header from the first [headerSize] bytes of a `.mml` file.
  ///
  /// Throws [FormatException] if the magic number or version is invalid.
  factory MmlFileHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
        'Header too short: expected $headerSize bytes, got ${bytes.length}.',
      );
    }

    final bd = ByteData.sublistView(bytes, 0, headerSize);

    final magic = bd.getUint32(0, Endian.little);
    if (magic != _magic) {
      throw FormatException(
        'Invalid MML file: wrong magic number '
        '(expected 0x${_magic.toRadixString(16)}, '
        'got 0x${magic.toRadixString(16)}).',
      );
    }

    final version = bd.getUint32(4, Endian.little);
    if (version > _version) {
      throw FormatException(
        'Unsupported MML file version $version '
        '(this library supports up to version $_version).',
      );
    }

    // Read metadata string (NUL-terminated, max 63 bytes)
    final metaBuf = StringBuffer();
    for (var i = 48; i < 112; i++) {
      final c = bd.getUint8(i);
      if (c == 0) break;
      metaBuf.writeCharCode(c);
    }

    return MmlFileHeader(
      elementCount: bd.getInt64(8, Endian.little),
      elementSize: bd.getInt32(16, Endian.little),
      elementType: ElementType.fromId(bd.getInt32(20, Endian.little)),
      pageSize: bd.getInt32(40, Endian.little),
      flags: bd.getInt32(44, Endian.little),
      metadata: metaBuf.toString(),
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        bd.getInt64(24, Endian.little),
      ),
      modifiedAt: DateTime.fromMicrosecondsSinceEpoch(
        bd.getInt64(32, Endian.little),
      ),
    );
  }

  // ── Mutation helpers ──────────────────────────────────────────────────────

  /// Updates [elementCount] and bumps [modifiedAt] to now.
  void updateLength(int newLength) {
    elementCount = newLength;
    modifiedAt = DateTime.now();
  }

  /// Sets the [kFlagDirtyShutdown] bit.  Called before starting any write
  /// session so that a crash can be detected on re-open.
  void markDirty() => flags |= kFlagDirtyShutdown;

  /// Clears the [kFlagDirtyShutdown] bit.  Called at the end of a clean close.
  void markClean() => flags &= ~kFlagDirtyShutdown;

  // ── Flag queries ──────────────────────────────────────────────────────────

  /// `true` if the file was opened read-only.
  bool get isReadOnly => flags & kFlagReadOnly != 0;

  /// `true` if data compression is active (reserved — always `false` now).
  bool get isCompressed => flags & kFlagCompressed != 0;

  /// `true` if the file was not closed cleanly on a previous session.
  bool get isDirtyShutdown => flags & kFlagDirtyShutdown != 0;

  // ── Derived sizes ─────────────────────────────────────────────────────────

  /// Total expected file size in bytes for a fixed-size element type.
  ///
  /// Returns `null` for [ElementType.generic] because element sizes vary.
  int? get expectedFileSize {
    if (elementSize <= 0) return null;
    return headerSize + elementCount * elementSize;
  }

  @override
  String toString() => 'MmlFileHeader('
      'type: ${elementType.name}, '
      'count: $elementCount, '
      'pageSize: $pageSize, '
      'flags: 0x${flags.toRadixString(16).padLeft(2, "0")}, '
      'meta: "$metadata")';
}
