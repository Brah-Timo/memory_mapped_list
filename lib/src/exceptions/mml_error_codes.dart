/// Stable numeric error codes for every exception thrown by this package.
///
/// These codes are embedded in every [MmlException] and can be used to
/// programmatically distinguish error categories without relying on string
/// parsing.
///
/// Code ranges:
///
/// | Range      | Category          |
/// |------------|-------------------|
/// | 1000–1099  | File I/O errors   |
/// | 1100–1199  | Access / mode     |
/// | 1200–1299  | Data integrity    |
/// | 1300–1399  | Resource limits   |
/// | 1400–1499  | Type / format     |
/// | 1500–1599  | Internal / assert |
enum MmlErrorCode {
  // ── File I/O ──────────────────────────────────────────────────────────────
  /// The requested file does not exist.
  fileNotFound(1001),

  /// A file I/O operation failed at the OS level.
  ioFailure(1002),

  /// There is not enough free disk space for the operation.
  diskFull(1003),

  /// The file could not be created (e.g. permission denied).
  fileCreateFailed(1004),

  // ── Access / mode ─────────────────────────────────────────────────────────
  /// A write operation was attempted on a read-only list.
  readOnly(1101),

  /// An operation was attempted after [MemoryMappedList.close] was called.
  alreadyClosed(1102),

  // ── Data integrity ────────────────────────────────────────────────────────
  /// The `.mml` file header is corrupt or has an invalid magic number.
  corruptHeader(1201),

  /// An element's serialized bytes could not be decoded.
  corruptData(1202),

  /// The file was not closed cleanly and may contain incomplete writes.
  dirtyShutdown(1203),

  // ── Resource limits ───────────────────────────────────────────────────────
  /// An index access is outside the valid range `[0, length)`.
  rangeError(1301),

  /// A requested range `[start, end)` is invalid.
  invalidRange(1302),

  // ── Type / format ─────────────────────────────────────────────────────────
  /// The element type stored in the file does not match the list type.
  typeMismatch(1401),

  /// The file was created with an unsupported format version.
  unsupportedVersion(1402),

  // ── Internal ─────────────────────────────────────────────────────────────
  /// An unexpected internal error occurred.  Please file a bug.
  internalError(1500);

  /// The numeric error code.
  final int code;

  const MmlErrorCode(this.code);

  @override
  String toString() => 'MmlErrorCode.$name ($code)';
}
