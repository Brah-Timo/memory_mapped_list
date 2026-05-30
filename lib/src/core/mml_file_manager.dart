// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:memory_mapped_list/src/exceptions/mml_exceptions.dart';

/// Low-level file I/O manager for a single `.mml` backing file.
///
/// All reads and writes are expressed as **byte offsets** relative to the start
/// of the file.  The caller (i.e. [PageBuffer] and [MemoryMappedList]) is
/// responsible for translating element indices to byte offsets.
///
/// Both synchronous (`*Sync`) and asynchronous variants are exposed so that
/// callers can choose the most appropriate concurrency model for each operation.
///
/// ### Windows / cross-platform compatibility
///
/// Dart's `FileMode.write` maps to `O_RDWR | O_CREAT | O_TRUNC`, which
/// **always truncates** the file.  To open an *existing* file for read-write
/// access without truncation this class:
///
/// 1. Reads the full file content into memory first.
/// 2. Opens with `FileMode.write` (obtains an `O_RDWR` handle).
/// 3. Immediately writes the saved bytes back, restoring the original content.
///
/// Additionally, `flush()` on a read-only [RandomAccessFile] raises
/// `OS Error: Access denied (errno = 5)` on Windows.  This class skips flush
/// for read-only descriptors and swallows errno-5 errors gracefully on all
/// platforms.
final class MmlFileManager {
  // ── Identity ──────────────────────────────────────────────────────────────

  /// Absolute or relative path to the backing file.
  final String path;

  /// `true` if the file was opened in read-only mode.
  final bool readOnly;

  // ── State ─────────────────────────────────────────────────────────────────

  late RandomAccessFile _raf;
  int _fileSize = 0;
  bool _isOpen = false;

  MmlFileManager({required this.path, required this.readOnly});

  // ── Open / create ─────────────────────────────────────────────────────────

  /// Opens an existing file for reading (and writing when [readOnly] is false).
  ///
  /// Throws [MmlFileNotFoundException] if the file does not exist.
  ///
  /// When [readOnly] is `false` the file content is **preserved** using a
  /// read-first strategy: the current bytes are read, the file is re-opened
  /// (which truncates via `O_TRUNC`), and the saved bytes are written back.
  /// This gives a `O_RDWR` handle while keeping the original file content.
  Future<void> open() async {
    final file = File(path);
    if (!file.existsSync()) {
      throw MmlFileNotFoundException(path);
    }

    if (readOnly) {
      _raf = await file.open(mode: FileMode.read);
      _fileSize = await file.length();
    } else {
      // Read existing content before the O_TRUNC open so we can restore it.
      final existingBytes = await file.readAsBytes();
      _raf = await file.open(mode: FileMode.write); // O_RDWR | O_TRUNC
      // Restore the original file content.
      await _raf.setPosition(0);
      await _raf.writeFrom(existingBytes);
      _fileSize = existingBytes.length;
    }
    _isOpen = true;
  }

  /// Creates a new file and pre-allocates [initialSize] bytes (zero-filled).
  ///
  /// Any existing file at [path] is **truncated**.
  /// Writes data in 1 MB chunks to avoid allocating a huge byte array.
  Future<void> create(int initialSize) async {
    if (initialSize < 0) {
      throw ArgumentError.value(initialSize, 'initialSize');
    }
    final file = File(path);
    _raf = await file.open(mode: FileMode.write);

    const chunkSize = 1024 * 1024; // 1 MB
    final zeros = Uint8List(chunkSize);
    var remaining = initialSize;

    await _raf.setPosition(0);
    while (remaining > 0) {
      final toWrite = remaining < chunkSize ? remaining : chunkSize;
      await _raf.writeFrom(zeros, 0, toWrite);
      remaining -= toWrite;
    }

    _fileSize = initialSize;
    _isOpen = true;
  }

  // ── Synchronous reads ─────────────────────────────────────────────────────

  /// Reads bytes in the range `[start, end)` synchronously.
  ///
  /// If [end] exceeds the file size, the returned buffer is zero-padded.
  Uint8List readBytesSync(int start, int end) {
    _assertOpen();
    final length = end - start;
    final buffer = Uint8List(length);

    // Guard against reads past end-of-file (happens for the last page).
    final clampedEnd = end.clamp(0, _fileSize);
    final readable = clampedEnd - start;
    if (readable <= 0) return buffer; // all zeros

    _raf.setPositionSync(start);
    _raf.readIntoSync(buffer, 0, readable);
    // Bytes beyond [readable] remain zero — correct for freshly extended files.
    return buffer;
  }

  // ── Asynchronous reads ────────────────────────────────────────────────────

  /// Reads bytes in the range `[start, end)` asynchronously.
  Future<Uint8List> readBytes(int start, int end) async {
    _assertOpen();
    final length = end - start;
    final buffer = Uint8List(length);

    final clampedEnd = end.clamp(0, _fileSize);
    final readable = clampedEnd - start;
    if (readable <= 0) return buffer;

    await _raf.setPosition(start);
    await _raf.readInto(buffer, 0, readable);
    return buffer;
  }

  /// Streams the byte range `[start, end)` in chunks of [chunkSize] bytes.
  ///
  /// Ideal for reading very large ranges without allocating a single giant
  /// buffer:  the caller processes each chunk as it arrives.
  Stream<Uint8List> readRangeStream(
    int start,
    int end, {
    int chunkSize = 65536,
  }) async* {
    _assertOpen();
    var position = start;
    while (position < end) {
      final toRead = (end - position).clamp(0, chunkSize);
      yield await readBytes(position, position + toRead);
      position += toRead;
      await Future<void>.delayed(Duration.zero); // breathe
    }
  }

  // ── Synchronous writes ────────────────────────────────────────────────────

  /// Writes [data] to the file at byte [offset] synchronously.
  void writeBytesSync(int offset, Uint8List data) {
    _assertOpen();
    _assertWritable();
    _raf.setPositionSync(offset);
    _raf.writeFromSync(data);
    _updateSize(offset + data.length);
  }

  // ── Asynchronous writes ───────────────────────────────────────────────────

  /// Writes [data] to the file at byte [offset] asynchronously.
  Future<void> writeBytes(int offset, Uint8List data) async {
    _assertOpen();
    _assertWritable();
    await _raf.setPosition(offset);
    await _raf.writeFrom(data);
    _updateSize(offset + data.length);
  }

  /// Convenience alias used by [MemoryMappedList.writeRange].
  Future<void> writeAt(int offset, Uint8List data) => writeBytes(offset, data);

  // ── File growth ───────────────────────────────────────────────────────────

  /// Extends the file to [newSize] bytes synchronously (no-op if already ≥).
  ///
  /// The new region is zero-filled by writing a single zero byte at
  /// `newSize − 1`, which is a common POSIX trick to create a "sparse" file
  /// that the OS will fill with zeros on demand.
  void expandFileSync(int newSize) {
    if (newSize <= _fileSize) return;
    _assertWritable();
    _raf.setPositionSync(newSize - 1);
    _raf.writeByteSync(0);
    _fileSize = newSize;
  }

  /// Asynchronous version of [expandFileSync].
  Future<void> expandFile(int newSize) async {
    if (newSize <= _fileSize) return;
    _assertWritable();
    await _raf.setPosition(newSize - 1);
    await _raf.writeByte(0);
    _fileSize = newSize;
  }

  // ── Sync & close ──────────────────────────────────────────────────────────

  /// Requests the OS to flush the file's write-back cache (fsync).
  ///
  /// On most platforms this makes previously written data durable against a
  /// process crash (but not a sudden power failure on all file systems).
  ///
  /// On Windows, flushing a read-only file descriptor raises
  /// `OS Error: Access denied (errno = 5)`.  This method is a no-op when
  /// [readOnly] is `true` to avoid that platform quirk.
  Future<void> sync() async {
    _assertOpen();
    if (readOnly) return; // Windows: flush on read-only RAF → errno 5
    await _flushSafe();
  }

  /// Flushes pending OS buffers and closes the underlying file descriptor.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> close() async {
    if (!_isOpen) return;
    if (!readOnly) await _flushSafe();
    await _raf.close();
    _isOpen = false;
  }

  /// Calls [RandomAccessFile.flush] and silently swallows the Windows
  /// "Access denied" error (errno = 5) that can occur on some file systems
  /// or when antivirus software holds a lock on the file.
  Future<void> _flushSafe() async {
    try {
      await _raf.flush();
    } on PathAccessException catch (e) {
      // errno 5 == ERROR_ACCESS_DENIED on Windows — treat as non-fatal.
      if (!e.message.contains('errno = 5')) rethrow;
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode != 5) rethrow;
    }
  }

  // ── Properties ────────────────────────────────────────────────────────────

  /// Current size of the file in bytes (tracked in-process; may lag the OS).
  int get fileSize => _fileSize;

  /// `true` if the file is currently open.
  bool get isOpen => _isOpen;

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _assertOpen() {
    if (!_isOpen) {
      throw MmlClosedException(path);
    }
  }

  void _assertWritable() {
    if (readOnly) throw MmlReadOnlyException(path);
  }

  void _updateSize(int newEnd) {
    if (newEnd > _fileSize) _fileSize = newEnd;
  }

  @override
  String toString() =>
      'MmlFileManager(path: "$path", size: ${_fileSize}B, open: $_isOpen)';
}
