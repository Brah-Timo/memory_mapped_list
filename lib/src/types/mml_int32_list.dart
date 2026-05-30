// ignore_for_file: avoid_redundant_argument_values

import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_base.dart';
import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';

/// A [MemoryMappedList] that stores 32-bit signed integers.
///
/// Each element occupies exactly **4 bytes** on disk.
/// Value range: `−2 147 483 648` to `2 147 483 647`.
///
/// ### Example
/// ```dart
/// final ids = await MemoryMappedList.int32s(
///   path: 'user_ids.mml',
///   length: 1_000_000_000,
/// );
///
/// ids[0] = 42;
/// print(ids[0]); // 42
///
/// await ids.close();
/// ```
final class MmlInt32List extends MemoryMappedList<int> {
  static const int _elementSize = 4; // sizeof(int32)

  MmlInt32List._({
    required super.fileManager,
    required super.pageBuffer,
    required super.header,
    required super.accessMode,
    required super.length,
    super.flushMode,
    super.batchSize,
  });

  // ── Factory open ─────────────────────────────────────────────────────────

  /// Opens or creates a `.mml` file backed by 32-bit signed integers.
  static Future<MmlInt32List> open({
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
        elementType: ElementType.int32,
        pageSize: cfg.pageSize,
        metadata: 'MmlInt32List v0.1.0',
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
    return MmlInt32List._(
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
      ByteData.sublistView(page).getInt32(offsetInPage, Endian.little);

  @override
  void serializeElement(Uint8List page, int offsetInPage, int value) {
    // Clamp to int32 range to avoid silent truncation.
    assert(
      value >= -2147483648 && value <= 2147483647,
      'Value $value overflows int32.',
    );
    ByteData.sublistView(page).setInt32(offsetInPage, value, Endian.little);
  }

  // ── Aggregates ────────────────────────────────────────────────────────────

  /// Streaming sum (accumulated as 64-bit int to avoid overflow).
  Future<int> sum() async {
    var total = 0;
    await for (final chunk in chunkedStream(chunkSize: 200000)) {
      for (final v in chunk) total += v;
    }
    return total;
  }

  /// Arithmetic mean as a double.
  Future<double> mean() async => (await sum()) / length;

  /// Minimum and maximum in a single pass.
  Future<({int min, int max})> minMax() async {
    var minVal = 0x7FFFFFFF;   // INT32_MAX
    var maxVal = -0x80000000;  // INT32_MIN
    await for (final chunk in chunkedStream(chunkSize: 200000)) {
      for (final v in chunk) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    return (min: minVal, max: maxVal);
  }

  /// Fills every element with [value].
  Future<void> fill(int value) =>
      writeRange(0, Iterable.generate(length, (_) => value));

  /// Returns `true` if every element equals zero (fast path: checks pages).
  Future<bool> isAllZeros() async {
    await for (final chunk in chunkedStream(chunkSize: 200000)) {
      for (final v in chunk) {
        if (v != 0) return false;
      }
    }
    return true;
  }
}
