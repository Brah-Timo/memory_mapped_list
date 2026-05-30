// ignore_for_file: avoid_redundant_argument_values

import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_base.dart';
import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';

/// A [MemoryMappedList] that stores 64-bit IEEE 754 doubles.
///
/// Each element occupies exactly **8 bytes** on disk.
///
/// In addition to the standard [List] interface, this class exposes a set of
/// streaming aggregate operations ([sum], [mean], [standardDeviation], [minMax])
/// that process the entire file in a single pass without loading it into RAM.
///
/// ### Example
/// ```dart
/// final list = await MemoryMappedList.doubles(
///   path: 'temps.mml',
///   length: 50_000_000,
/// );
///
/// for (var i = 0; i < list.length; i++) {
///   list[i] = i * 0.0001;
/// }
///
/// print('mean = ${await list.mean()}');
/// await list.close();
/// ```
final class MmlDoubleList extends MemoryMappedList<double> {
  static const int _elementSize = 8; // sizeof(double)

  MmlDoubleList._({
    required super.fileManager,
    required super.pageBuffer,
    required super.header,
    required super.accessMode,
    required super.length,
    super.flushMode,
    super.batchSize,
  });

  // ── Factory open ─────────────────────────────────────────────────────────

  /// Opens or creates a `.mml` file backed by 64-bit doubles.
  static Future<MmlDoubleList> open({
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
        elementType: ElementType.float64,
        pageSize: cfg.pageSize,
        metadata: 'MmlDoubleList v0.1.0',
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

    return MmlDoubleList._(
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
      ByteData.sublistView(page).getFloat64(offsetInPage, Endian.little);

  @override
  void serializeElement(Uint8List page, int offsetInPage, double value) =>
      ByteData.sublistView(page).setFloat64(offsetInPage, value, Endian.little);

  // ── Numeric aggregates (streaming, O(1) RAM) ──────────────────────────────

  /// Returns the sum of all elements in a single streaming pass.
  Future<double> sum() async {
    var total = 0.0;
    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      for (final v in chunk) {
        total += v;
      }
    }
    return total;
  }

  /// Returns the arithmetic mean of all elements.
  Future<double> mean() async => (await sum()) / length;

  /// Returns both the minimum and maximum values in a single pass.
  Future<({double min, double max})> minMax() async {
    var minVal = double.infinity;
    var maxVal = double.negativeInfinity;
    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      for (final v in chunk) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    return (min: minVal, max: maxVal);
  }

  /// Returns the population standard deviation using **Welford's online
  /// algorithm** (numerically stable, single-pass).
  Future<double> standardDeviation() async {
    var n = 0;
    var mean = 0.0;
    var m2 = 0.0;

    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      for (final x in chunk) {
        n++;
        final delta = x - mean;
        mean += delta / n;
        m2 += delta * (x - mean);
      }
    }
    return n < 2 ? 0.0 : m2 / (n - 1); // sample variance → take sqrt for σ
  }

  /// Returns the median by reading all values into a temporary sorted list.
  ///
  /// **Warning**: allocates O(n) RAM.  Use only when the list fits comfortably
  /// in memory; otherwise prefer streaming approximation algorithms.
  Future<double> median() async {
    final sorted = <double>[];
    await for (final chunk in chunkedStream(chunkSize: 100000)) {
      sorted.addAll(chunk);
    }
    sorted.sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Fills the entire list with [value] using [writeRange].
  Future<void> fill(double value) =>
      writeRange(0, Iterable.generate(length, (_) => value));
}
