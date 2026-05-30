// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';
import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_base.dart';
import 'package:memory_mapped_list/src/core/mml_file_manager.dart';
import 'package:memory_mapped_list/src/core/mml_header.dart';
import 'package:memory_mapped_list/src/core/mml_page_buffer.dart';
import 'package:memory_mapped_list/src/utils/mml_serializer.dart';

/// ─── File layout for MmlGenericList ────────────────────────────────────────
///
/// Because generic objects have **variable** byte sizes, a separate index file
/// (`.mml.idx`) tracks the byte offset and length of every element in the main
/// data file.
///
///  Main file (`path.mml`):
///  ┌──────────────────────────────┐
///  │  128-byte MmlFileHeader      │
///  ├──────────────────────────────┤
///  │  element 0 bytes             │
///  │  element 1 bytes             │
///  │  …                           │
///  └──────────────────────────────┘
///
///  Index file (`path.mml.idx`):
///  ┌──────────────────────────────┐
///  │  128-byte MmlFileHeader      │  (elementType=int64, elementCount=N*2)
///  ├──────────────────────────────┤
///  │  int64  offset[0]            │  ← byte offset in main file
///  │  int64  length[0]            │  ← byte length of element 0
///  │  int64  offset[1]            │
///  │  int64  length[1]            │
///  │  …                           │
///  └──────────────────────────────┘
///
/// ───────────────────────────────────────────────────────────────────────────

/// A [MemoryMappedList] that can store **any** Dart object via a user-supplied
/// [MmlSerializer].
///
/// Object sizes may vary per element; a companion index file keeps track of
/// where each element starts and how many bytes it occupies.
///
/// ### Example
/// ```dart
/// final serializer = JsonSerializer<User>(
///   fromJson: User.fromJson,
///   toJson: (u) => u.toJson(),
/// );
///
/// final users = await MemoryMappedList.generic<User>(
///   path: 'users.mml',
///   length: 1_000_000,
///   serializer: serializer,
/// );
///
/// users[0] = User(id: 1, name: 'Alice');
/// print(users[0].name); // Alice
///
/// await users.close();
/// ```
final class MmlGenericList<T> extends MemoryMappedList<T> {
  final MmlSerializer<T> _serializer;

  /// Separate file manager for the index file.
  late final MmlFileManager _indexFm;

  /// In-memory cache of the index (offset + length pairs).
  /// Stored as a flat [Int64List]: [offset0, len0, offset1, len1, …]
  late final Int64List _index;

  /// Running byte offset for the next appended element.
  int _dataWriteCursor = MmlFileHeader.headerSize;

  MmlGenericList._({
    required super.fileManager,
    required super.pageBuffer,
    required super.header,
    required super.accessMode,
    required super.length,
    required MmlSerializer<T> serializer,
    super.flushMode,
    super.batchSize,
  }) : _serializer = serializer;

  // ── Factory open ─────────────────────────────────────────────────────────

  static Future<MmlGenericList<E>> open<E>({
    required String path,
    required int length,
    required MmlSerializer<E> serializer,
    AccessMode mode = AccessMode.create,
    PageBufferConfig? bufferConfig,
    FlushMode flushMode = FlushMode.onClose,
    int batchSize = 1000,
  }) async {
    final cfg = bufferConfig ?? PageBufferConfig.defaultConfig();
    final indexPath = '$path.idx';

    final fm = MmlFileManager(
      path: path,
      readOnly: mode == AccessMode.readOnly,
    );
    final indexFm = MmlFileManager(
      path: indexPath,
      readOnly: mode == AccessMode.readOnly,
    );

    final MmlFileHeader header;
    final int effectiveLength;
    final Int64List index;

    if (mode == AccessMode.create) {
      // Main data file: header only for now (data appended as elements are set)
      await fm.create(MmlFileHeader.headerSize);
      header = MmlFileHeader.create(
        elementCount: length,
        elementType: ElementType.generic,
        pageSize: cfg.pageSize,
        metadata: 'MmlGenericList<${E.toString()}> v0.1.0',
      );
      await fm.writeBytes(0, header.toBytes());

      // Index file: 2 int64 entries per element (offset + size)
      final indexDataSize = length * 2 * 8; // 2 × int64 per element
      await indexFm.create(MmlFileHeader.headerSize + indexDataSize);
      final indexHeader = MmlFileHeader.create(
        elementCount: length * 2,
        elementType: ElementType.int64,
        pageSize: cfg.pageSize,
        metadata: 'MmlGenericList.idx',
      );
      await indexFm.writeBytes(0, indexHeader.toBytes());

      effectiveLength = length;
      index = Int64List(length * 2); // all zeros = element not written yet
    } else {
      await fm.open();
      final hBytes = await fm.readBytes(0, MmlFileHeader.headerSize);
      header = MmlFileHeader.fromBytes(hBytes);
      effectiveLength = header.elementCount;

      await indexFm.open();
      final idxHBytes = await indexFm.readBytes(0, MmlFileHeader.headerSize);
      final idxHeader = MmlFileHeader.fromBytes(idxHBytes);
      final idxDataBytes = await indexFm.readBytes(
        MmlFileHeader.headerSize,
        MmlFileHeader.headerSize + idxHeader.elementCount * 8,
      );
      index = idxDataBytes.buffer.asInt64List();
    }

    if (mode != AccessMode.readOnly) header.markDirty();

    final pb = PageBuffer(fileManager: fm, config: cfg);

    final list = MmlGenericList._(
      fileManager: fm,
      pageBuffer: pb,
      header: header,
      accessMode: mode,
      length: effectiveLength,
      serializer: serializer,
      flushMode: flushMode,
      batchSize: batchSize,
    );
    list._indexFm = indexFm;
    list._index = index;

    // Re-compute the write cursor from the index when opening an existing file.
    if (mode != AccessMode.create) {
      var maxEnd = MmlFileHeader.headerSize;
      for (var i = 0; i < effectiveLength; i++) {
        final off = index[i * 2];
        final len = index[i * 2 + 1];
        if (off + len > maxEnd) maxEnd = (off + len).toInt();
      }
      list._dataWriteCursor = maxEnd;
    }

    return list;
  }

  // ── MemoryMappedList contract ─────────────────────────────────────────────

  /// For generic lists the element size is variable; return −1 as sentinel.
  @override
  int get elementSize => -1;

  /// Not used for generic lists (I/O is done element-by-element in []).
  @override
  T deserializeElement(Uint8List page, int offsetInPage) =>
      throw UnimplementedError('MmlGenericList uses custom I/O.');

  @override
  void serializeElement(Uint8List page, int offsetInPage, T value) =>
      throw UnimplementedError('MmlGenericList uses custom I/O.');

  // ── Overridden element accessors ──────────────────────────────────────────

  @override
  T operator [](int index) {
    _checkNotClosedG();
    _checkBoundsG(index);

    final byteOffset = _index[index * 2];
    final byteLength = _index[index * 2 + 1];

    if (byteOffset == 0 && byteLength == 0) {
      throw StateError('Element $index has not been written yet.');
    }

    final data = fileManager.readBytesSync(
      byteOffset.toInt(),
      (byteOffset + byteLength).toInt(),
    );
    return _serializer.deserialize(data);
  }

  @override
  void operator []=(int index, T value) {
    _checkNotClosedG();
    _checkBoundsG(index);
    _checkWritableG();

    final bytes = _serializer.serialize(value);
    final offset = _dataWriteCursor;

    fileManager.writeBytesSync(offset, bytes);
    _dataWriteCursor += bytes.length;

    _index[index * 2] = offset;
    _index[index * 2 + 1] = bytes.length;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  @override
  Future<void> flush() async {
    if (!isOpen) return;
    // Flush main data file
    await super.flush();
    // Write the in-memory index back to the index file
    final idxBytes = _index.buffer.asUint8List();
    await _indexFm.writeBytes(MmlFileHeader.headerSize, idxBytes);
    await _indexFm.sync();
  }

  @override
  Future<void> close() async {
    if (!isOpen) return;
    // Call super.close() first.  super.close() calls flush() → writes the
    // index file — so _indexFm must still be open at that point.
    // super.close() sets _isClosed = true, so any further flush() calls
    // via the base class become no-ops afterwards.
    await super.close();
    // Now that the base class is done, close the companion index file.
    await _indexFm.close();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Returns `true` if the element at [index] has been written at least once.
  bool isElementPresent(int index) {
    _checkBoundsG(index);
    return _index[index * 2 + 1] > 0;
  }

  // ── Private guards ────────────────────────────────────────────────────────

  void _checkNotClosedG() {
    if (!isOpen) throw StateError('MmlGenericList is closed.');
  }

  void _checkBoundsG(int i) {
    if (i < 0 || i >= length) throw RangeError.index(i, this);
  }

  void _checkWritableG() {
    if (accessMode == AccessMode.readOnly) {
      throw StateError('MmlGenericList is read-only.');
    }
  }
}
