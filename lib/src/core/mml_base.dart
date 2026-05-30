// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';
import 'package:memory_mapped_list/src/exceptions/mml_exceptions.dart';
import 'package:memory_mapped_list/src/types/mml_double_list.dart';
import 'package:memory_mapped_list/src/types/mml_float32_list.dart';
import 'package:memory_mapped_list/src/types/mml_int32_list.dart';
import 'package:memory_mapped_list/src/types/mml_int64_list.dart';
import 'package:memory_mapped_list/src/types/mml_generic_list.dart';
import 'package:memory_mapped_list/src/utils/mml_serializer.dart';

// ── Access mode ───────────────────────────────────────────────────────────────

/// Controls how the underlying file is opened.
enum AccessMode {
  /// Open an existing file for reading only.
  ///
  /// Any attempt to write ([operator []=], [writeRange], `length=`) will throw
  /// [MmlReadOnlyException].
  readOnly,

  /// Open an existing file for both reading and writing.
  ///
  /// The file must already exist; use [create] to create a new one.
  readWrite,

  /// Create a new file (or truncate an existing one) and open it for
  /// reading and writing.
  create,
}

// ── Flush mode ────────────────────────────────────────────────────────────────

/// Determines when dirty pages are written back to disk.
enum FlushMode {
  /// Every [operator []=] call triggers an immediate page flush.
  ///
  /// Safest option — no data loss on crash — but has significant I/O overhead
  /// for workloads with many small writes.
  immediate,

  /// Pages are only flushed when [MemoryMappedList.flush] or
  /// [MemoryMappedList.close] is called explicitly.
  ///
  /// Fastest option.  Data written since the last flush may be lost if the
  /// process crashes before [close] is called.
  onClose,

  /// Pages are flushed automatically after every [batchSize] write operations.
  ///
  /// Balances throughput and durability.
  batched,
}

// ── MmlStats ──────────────────────────────────────────────────────────────────

/// A snapshot of runtime performance metrics for a [MemoryMappedList].
final class MmlStats {
  /// Total number of elements in the list.
  final int totalElements;

  /// Current size of the backing file in bytes.
  final int fileSizeBytes;

  /// Number of pages currently held in the LRU cache.
  final int cachedPages;

  /// Cache hits since the list was opened.
  final int pageHits;

  /// Cache misses (disk reads) since the list was opened.
  final int pageMisses;

  /// Ratio of hits to total accesses — in [0, 1].
  final double hitRate;

  /// Number of write operations not yet flushed to disk.
  final int pendingWrites;

  const MmlStats({
    required this.totalElements,
    required this.fileSizeBytes,
    required this.cachedPages,
    required this.pageHits,
    required this.pageMisses,
    required this.hitRate,
    required this.pendingWrites,
  });

  /// [fileSizeBytes] expressed in megabytes.
  double get fileSizeMB => fileSizeBytes / (1024 * 1024);

  /// [fileSizeBytes] expressed in gigabytes.
  double get fileSizeGB => fileSizeBytes / (1024 * 1024 * 1024);

  @override
  String toString() => '''
MmlStats {
  elements     : $totalElements
  file size    : ${fileSizeMB.toStringAsFixed(2)} MB
  cached pages : $cachedPages
  hit rate     : ${(hitRate * 100).toStringAsFixed(1)} %
  hits / misses: $pageHits / $pageMisses
  pending      : $pendingWrites writes
}''';
}

// ── MemoryMappedList ──────────────────────────────────────────────────────────

/// Abstract base class for all memory-mapped list types.
///
/// Mixes in [ListMixin] so that every method of Dart's standard [List]
/// interface (`sort`, `where`, `map`, `sublist`, `indexOf`, `contains`, …)
/// is available without any extra implementation work.
///
/// Callers should not instantiate [MemoryMappedList] directly.  Instead use
/// one of the typed factory constructors:
///
/// ```dart
/// final doubles  = await MemoryMappedList.doubles(path: 'f.mml', length: 1e8.toInt());
/// final ints     = await MemoryMappedList.int32s( path: 'f.mml', length: 1e8.toInt());
/// final generics = await MemoryMappedList.generic<Point>(
///   path: 'f.mml', length: 1000, serializer: pointSerializer);
/// ```
abstract class MemoryMappedList<T> with ListMixin<T> {
  // ── Protected collaborators ───────────────────────────────────────────────

  /// Manages the on-disk [RandomAccessFile].
  @protected
  final MmlFileManager fileManager;

  /// LRU page cache — trades RAM for fewer disk reads.
  @protected
  final PageBuffer pageBuffer;

  /// Metadata stored at offset 0 of the backing file.
  @protected
  final MmlFileHeader header;

  // ── Public configuration ──────────────────────────────────────────────────

  /// How the backing file was opened.
  final AccessMode accessMode;

  /// When dirty pages are written back to disk.
  final FlushMode flushMode;

  /// For [FlushMode.batched]: flush after this many write operations.
  final int batchSize;

  // ── Private state ─────────────────────────────────────────────────────────

  int _length;
  bool _isClosed = false;
  int _pendingWrites = 0;

  // ── Constructor ───────────────────────────────────────────────────────────

  @protected
  MemoryMappedList({
    required this.fileManager,
    required this.pageBuffer,
    required this.header,
    required this.accessMode,
    required int length,
    this.flushMode = FlushMode.onClose,
    this.batchSize = 1000,
  }) : _length = length;

  // ── Typed factory constructors ────────────────────────────────────────────

  /// Creates or opens a file-backed list of [double] (64-bit IEEE 754).
  ///
  /// * [path]   — path to the `.mml` file.
  /// * [length] — number of elements.  Ignored when [mode] is [AccessMode.readOnly]
  ///   or [AccessMode.readWrite] (the length is read from the file header).
  /// * [mode]   — defaults to [AccessMode.create].
  /// * [bufferConfig] — controls page size and LRU cache depth.
  static Future<MmlDoubleList> doubles({
    required String path,
    required int length,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) =>
      MmlDoubleList.open(
        path: path,
        length: length,
        mode: mode,
        bufferConfig: bufferConfig ?? PageBufferConfig.defaultConfig(),
        flushMode: flushMode,
        batchSize: batchSize,
      );

  /// Creates or opens a file-backed list of `float` (32-bit IEEE 754).
  ///
  /// Values are stored as 32-bit floats but exposed as Dart [double]s.
  static Future<MmlFloat32List> float32s({
    required String path,
    required int length,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) =>
      MmlFloat32List.open(
        path: path,
        length: length,
        mode: mode,
        bufferConfig: bufferConfig ?? PageBufferConfig.defaultConfig(),
        flushMode: flushMode,
        batchSize: batchSize,
      );

  /// Creates or opens a file-backed list of 32-bit signed integers.
  static Future<MmlInt32List> int32s({
    required String path,
    required int length,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) =>
      MmlInt32List.open(
        path: path,
        length: length,
        mode: mode,
        bufferConfig: bufferConfig ?? PageBufferConfig.defaultConfig(),
        flushMode: flushMode,
        batchSize: batchSize,
      );

  /// Creates or opens a file-backed list of 64-bit signed integers.
  static Future<MmlInt64List> int64s({
    required String path,
    required int length,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) =>
      MmlInt64List.open(
        path: path,
        length: length,
        mode: mode,
        bufferConfig: bufferConfig ?? PageBufferConfig.defaultConfig(),
        flushMode: flushMode,
        batchSize: batchSize,
      );

  /// Creates or opens a file-backed list of arbitrary objects.
  ///
  /// A [serializer] must be provided to convert values to/from bytes.
  static Future<MmlGenericList<E>> generic<E>({
    required String path,
    required int length,
    required MmlSerializer<E> serializer,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) =>
      MmlGenericList.open(
        path: path,
        length: length,
        serializer: serializer,
        mode: mode,
        bufferConfig: bufferConfig ?? PageBufferConfig.defaultConfig(),
        flushMode: flushMode,
        batchSize: batchSize,
      );

  // ── List interface ────────────────────────────────────────────────────────

  @override
  int get length => _length;

  /// Resizing the list truncates or extends the backing file.
  ///
  /// Extended regions are zero-filled.
  @override
  set length(int newLength) {
    _checkNotClosed();
    _checkWritable();
    if (newLength < 0) throw ArgumentError.value(newLength, 'newLength');

    final newFileSize = MmlFileHeader.headerSize + newLength * elementSize;
    if (newLength > _length) {
      fileManager.expandFileSync(newFileSize);
    }
    _length = newLength;
    header.updateLength(newLength);
    _scheduleFlushSync();
  }

  /// Byte width of a single element.  Subclasses must override this.
  @protected
  int get elementSize;

  @override
  T operator [](int index) {
    _checkNotClosed();
    _checkBounds(index);

    final byteOffset =
        MmlFileHeader.headerSize + index * elementSize;
    final page = pageBuffer.getPage(byteOffset);
    final offsetInPage = byteOffset % pageBuffer.pageSize;
    return deserializeElement(page, offsetInPage);
  }

  @override
  void operator []=(int index, T value) {
    _checkNotClosed();
    _checkBounds(index);
    _checkWritable();

    final byteOffset =
        MmlFileHeader.headerSize + index * elementSize;
    final page = pageBuffer.getPage(byteOffset);
    final offsetInPage = byteOffset % pageBuffer.pageSize;
    serializeElement(page, offsetInPage, value);
    pageBuffer.markDirty(byteOffset);

    _pendingWrites++;
    if (flushMode == FlushMode.immediate) {
      pageBuffer.flushPage(byteOffset);
    } else if (flushMode == FlushMode.batched &&
        _pendingWrites >= batchSize) {
      pageBuffer.flushAllSync();
      _pendingWrites = 0;
    }
  }

  // ── Subclass contract ─────────────────────────────────────────────────────

  /// Reads a single element from [page] at [offsetInPage].
  @protected
  T deserializeElement(Uint8List page, int offsetInPage);

  /// Writes a single element into [page] at [offsetInPage].
  @protected
  void serializeElement(Uint8List page, int offsetInPage, T value);

  // ── Batch I/O ─────────────────────────────────────────────────────────────

  /// Reads elements in the half-open range `[start, end)` efficiently by
  /// fetching whole pages at a time.
  ///
  /// This is significantly faster than reading element-by-element when the
  /// range spans multiple pages.
  Future<List<T>> readRange(int start, int end) async {
    _checkNotClosed();
    if (start < 0 || end > _length || start >= end) {
      throw MmlRangeException(start, end, _length);
    }

    final result = <T>[];
    for (var i = start; i < end; i++) {
      result.add(this[i]);
    }
    return result;
  }

  /// Writes [values] into the list starting at [start].
  ///
  /// Internally buffers writes in 10 MB chunks to reduce I/O syscall
  /// frequency while keeping peak RAM usage low.
  Future<void> writeRange(int start, Iterable<T> values) async {
    _checkNotClosed();
    _checkWritable();

    var index = start;
    for (final value in values) {
      if (index >= _length) break;
      this[index++] = value;

      // Yield to the event loop every 50 000 writes so we don't block.
      if (_pendingWrites % 50000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  // ── Streaming API ─────────────────────────────────────────────────────────

  /// Produces all elements as an async [Stream].
  ///
  /// Yields a small batch every 10 000 elements so the event loop stays
  /// responsive during very long iterations.
  Stream<T> get stream async* {
    _checkNotClosed();
    for (var i = 0; i < _length; i++) {
      yield this[i];
      if (i % 10000 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  /// Produces elements grouped into chunks of [chunkSize] for higher-throughput
  /// streaming.
  Stream<List<T>> chunkedStream({int chunkSize = 10000}) async* {
    _checkNotClosed();
    for (var i = 0; i < _length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, _length);
      yield await readRange(i, end);
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Flushes all dirty pages to disk and calls [fsync] on the file descriptor.
  ///
  /// After this call, data written so far is guaranteed to survive a process
  /// crash (though not necessarily a power failure on all platforms).
  Future<void> flush() async {
    _checkNotClosed();
    await pageBuffer.flushAll();
    await fileManager.sync();
    _pendingWrites = 0;
    header.markClean();
    // Rewrite the header to reflect the clean state — skip for read-only
    // files since the file manager will refuse (and the OS may deny) writes.
    if (accessMode != AccessMode.readOnly) {
      await fileManager.writeBytes(0, header.toBytes());
    }
  }

  /// Flushes all dirty pages and closes the backing file.
  ///
  /// After [close] any access attempt throws [MmlClosedException].
  /// It is safe to call [close] multiple times.
  Future<void> close() async {
    if (_isClosed) return;
    await flush();
    pageBuffer.dispose();
    await fileManager.close();
    _isClosed = true;
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Current performance snapshot.
  MmlStats get stats => MmlStats(
        totalElements: _length,
        fileSizeBytes: fileManager.fileSize,
        cachedPages: pageBuffer.cachedPageCount,
        pageHits: pageBuffer.hits,
        pageMisses: pageBuffer.misses,
        hitRate: pageBuffer.hitRate,
        pendingWrites: _pendingWrites,
      );

  /// `true` as long as the backing file is open and usable.
  bool get isOpen => !_isClosed;

  /// Absolute path to the backing `.mml` file.
  String get filePath => fileManager.path;

  /// Current size of the backing file in bytes (includes the 128-byte header).
  int get fileSizeBytes => fileManager.fileSize;

  // ── Guards ────────────────────────────────────────────────────────────────

  void _checkNotClosed() {
    if (_isClosed) throw MmlClosedException(fileManager.path);
  }

  void _checkBounds(int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', null, _length);
    }
  }

  void _checkWritable() {
    if (accessMode == AccessMode.readOnly) {
      throw MmlReadOnlyException(fileManager.path);
    }
  }

  void _scheduleFlushSync() {
    if (flushMode == FlushMode.immediate) {
      pageBuffer.flushAllSync();
    }
  }

  // ── Object override ───────────────────────────────────────────────────────

  @override
  String toString() => 'MemoryMappedList<$T>('
      'length: $_length, '
      'file: "${fileManager.path}", '
      'mode: ${accessMode.name}, '
      'cached: ${pageBuffer.cachedPageCount} pages)';
}
