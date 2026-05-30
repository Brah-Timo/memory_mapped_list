// ignore_for_file: avoid_redundant_argument_values

import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_base.dart';
import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';

/// A [MemoryMappedList] that stores 64-bit signed integers.
///
/// Each element occupies exactly **8 bytes** on disk.
/// Value range: `−9 223 372 036 854 775 808` to `9 223 372 036 854 775 807`.
///
/// Useful for storing Unix timestamps (microseconds), large primary keys,
/// file offsets, or any counter that overflows 32 bits.
///
/// ### Example
/// ```dart
/// final timestamps = await MemoryMappedList.int64s(
///   path: 'events.mml',
///   length: 500_000_000,
/// );
///
/// timestamps[0] = DateTime.now().microsecondsSinceEpoch;
/// print(DateTime.fromMicrosecondsSinceEpoch(timestamps[0]));
///
/// await timestamps.close();
/// ```
final class MmlInt64List extends MemoryMappedList<int> {
  static const int _elementSize = 8; // sizeof(int64)

  MmlInt64List._({
    required super.fileManager,
    required super.pageBuffer,
    required super.header,
    required super.accessMode,
    required super.length,
    super.flushMode,
    super.batchSize,
  });

  // ── Factory open ─────────────────────────────────────────────────────────

  /// Opens or creates a `.mml` file backed by 64-bit signed integers.
  static Future<MmlInt64List> open({
    required String path,
    required int length,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) async {
    final cfg = bufferConfig ?? PageBufferConfig.defaultConfig();
    final fm = MmlFileManager(
      path: path,
      readOnly: mode == AccessMode.readOnly,
    );

    final MmlFileHeader header;
    final int effectiveLength;

    if (mode == AccessMode.create) {
      final fileSize = MmlFileHeader.headerSize + length * _elementSize;
      await fm.create(fileSize);
      header = MmlFileHeader.create(
        elementCount: length,
        elementType: ElementType.int64,
        pageSize: cfg.pageSize,
        metadata: 'MmlInt64List v0.1.0',
      );
      await fm.writeBytes(0, header.toBytes());
      effectiveLength = length;
    } else {
      await fm.open();
      final headerBytes = await fm.readBytes(0, MmlFileHeader.headerSize);
      header = MmlFileHeader.fromBytes(headerBytes);
      effectiveLength = header.elementCount;
    }

    if (mode != AccessMode.readOnly) header.markDirty();

    final pb = PageBuffer(fileManager: fm, config: cfg);
    return MmlInt64List._(
      fileManager: fm,
      pageBuffer: pb,
      header: header,
      accessMode: mode,
      length: effectiveLength,
      flushMode: flushMode,
      batchSize: batchSize,
    );
  }

  // ── MemoryMappedList contract ─────────────────────────────────────────────

  @override
  int get elementSize => _elementSize;

  @override
  int deserializeElement(Uint8List page, int offsetInPage) =>
      ByteData.sublistView(page).getInt64(offsetInPage, Endian.little);

  @override
  void serializeElement(Uint8List page, int offsetInPage, int value) =>
      ByteData.sublistView(page).setInt64(offsetInPage, value, Endian.little);

  // ── Aggregates ────────────────────────────────────────────────────────────

  /// Streaming sum (may overflow for very large lists — consider using [mean]
  /// or a streaming approach with Kahan summation).
  Future<int> sum() async {
    var total = 0;
    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      for (final v in chunk) total += v;
    }
    return total;
  }

  /// Arithmetic mean as a double.
  Future<double> mean() async => (await sum()) / length;

  /// Minimum and maximum in a single pass.
  Future<({int min, int max})> minMax() async {
    const int64Max = 9223372036854775807;
    const int64Min = -9223372036854775808;
    var minVal = int64Max;
    var maxVal = int64Min;
    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      for (final v in chunk) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    return (min: minVal, max: maxVal);
  }

  /// Treats each element as a Unix timestamp (microseconds since epoch) and
  /// returns the corresponding [DateTime] at [index].
  DateTime timestampAt(int index) =>
      DateTime.fromMicrosecondsSinceEpoch(this[index], isUtc: true);

  /// Writes [dt] as a microsecond Unix timestamp at [index].
  void setTimestamp(int index, DateTime dt) =>
      this[index] = dt.microsecondsSinceEpoch;

  /// Fills every element with [value].
  Future<void> fill(int value) =>
      writeRange(0, Iterable.generate(length, (_) => value));
}
