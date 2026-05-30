// ignore_for_file: avoid_redundant_argument_values

import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_base.dart';
import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';

/// A [MemoryMappedList] that stores 32-bit IEEE 754 floats (float32).
///
/// Each element occupies exactly **4 bytes** on disk, so a float32 list of
/// the same length uses **half** the disk space of a double list.  Values
/// are exposed as Dart [double]s (the conversion is transparent).
///
/// Precision is limited to ≈ 7 significant decimal digits.  Use
/// [MmlDoubleList] when you need full 64-bit precision.
///
/// ### Example
/// ```dart
/// final list = await MemoryMappedList.float32s(
///   path: 'weights.mml',
///   length: 200_000_000, // saves ~800 MB vs float64
/// );
///
/// list[0] = 3.14; // stored as 32-bit float
/// print(list[0]); // ~3.14 (limited precision)
///
/// await list.close();
/// ```
final class MmlFloat32List extends MemoryMappedList<double> {
  static const int _elementSize = 4; // sizeof(float)

  MmlFloat32List._({
    required super.fileManager,
    required super.pageBuffer,
    required super.header,
    required super.accessMode,
    required super.length,
    super.flushMode,
    super.batchSize,
  });

  // ── Factory open ─────────────────────────────────────────────────────────

  /// Opens or creates a `.mml` file backed by 32-bit floats.
  static Future<MmlFloat32List> open({
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
        elementType: ElementType.float32,
        pageSize: cfg.pageSize,
        metadata: 'MmlFloat32List v0.1.0',
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
    return MmlFloat32List._(
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
  double deserializeElement(Uint8List page, int offsetInPage) =>
      ByteData.sublistView(page).getFloat32(offsetInPage, Endian.little);

  @override
  void serializeElement(Uint8List page, int offsetInPage, double value) =>
      ByteData.sublistView(page).setFloat32(offsetInPage, value, Endian.little);

  // ── Aggregates ────────────────────────────────────────────────────────────

  /// Streaming sum (uses double accumulator to reduce rounding error).
  Future<double> sum() async {
    var total = 0.0;
    await for (final chunk in chunkedStream(chunkSize: 200000)) {
      for (final v in chunk) total += v;
    }
    return total;
  }

  /// Arithmetic mean.
  Future<double> mean() async => (await sum()) / length;

  /// Minimum and maximum in one pass.
  Future<({double min, double max})> minMax() async {
    var minVal = double.infinity;
    var maxVal = double.negativeInfinity;
    await for (final chunk in chunkedStream(chunkSize: 200000)) {
      for (final v in chunk) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    return (min: minVal, max: maxVal);
  }

  /// Fills every element with [value].
  Future<void> fill(double value) =>
      writeRange(0, Iterable.generate(length, (_) => value));
}
