import 'package:memory_mapped_list/src/core/mml_header.dart';

/// Byte-offset and alignment arithmetic used internally by the package.
///
/// All methods are `static` and `const`-friendly so they can be inlined by
/// the compiler.
abstract final class MmlMathUtils {
  // ── Index ↔ byte-offset ───────────────────────────────────────────────────

  /// Converts an element [index] to its absolute byte offset in the file.
  ///
  /// ```
  /// byteOffset = headerSize + index × elementSize
  /// ```
  static int elementToByteOffset(int index, int elementSize) =>
      MmlFileHeader.headerSize + index * elementSize;

  /// Converts a byte [offset] to the page index for a given [pageSize].
  ///
  /// ```
  /// pageIndex = byteOffset ÷ pageSize
  /// ```
  static int byteOffsetToPageIndex(int byteOffset, int pageSize) =>
      byteOffset ~/ pageSize;

  /// Returns the byte offset of the start of the page containing [byteOffset].
  static int pageStart(int byteOffset, int pageSize) =>
      (byteOffset ~/ pageSize) * pageSize;

  /// Returns the relative offset of [byteOffset] within its page.
  ///
  /// ```
  /// offsetInPage = byteOffset mod pageSize
  /// ```
  static int offsetInPage(int byteOffset, int pageSize) =>
      byteOffset % pageSize;

  // ── File size calculations ────────────────────────────────────────────────

  /// Computes the total file size for a fixed-size element list.
  ///
  /// ```
  /// fileSize = headerSize + elementCount × elementSize
  /// ```
  static int totalFileSize(int elementCount, int elementSize) =>
      MmlFileHeader.headerSize + elementCount * elementSize;

  /// Returns the number of pages required to hold [byteCount] bytes.
  static int pagesRequired(int byteCount, int pageSize) =>
      (byteCount + pageSize - 1) ~/ pageSize;

  // ── Alignment helpers ─────────────────────────────────────────────────────

  /// Rounds [value] up to the nearest multiple of [alignment].
  ///
  /// [alignment] must be a power of two.
  static int alignUp(int value, int alignment) {
    assert(alignment > 0 && (alignment & (alignment - 1)) == 0,
        'alignment must be a power of two');
    return (value + alignment - 1) & ~(alignment - 1);
  }

  /// Rounds [value] down to the nearest multiple of [alignment].
  static int alignDown(int value, int alignment) {
    assert(alignment > 0 && (alignment & (alignment - 1)) == 0,
        'alignment must be a power of two');
    return value & ~(alignment - 1);
  }

  /// Returns `true` if [value] is aligned to [alignment].
  static bool isAligned(int value, int alignment) =>
      value % alignment == 0;

  // ── Range helpers ─────────────────────────────────────────────────────────

  /// Clamps [value] to `[lo, hi]`.
  static int clamp(int value, int lo, int hi) =>
      value < lo ? lo : (value > hi ? hi : value);

  /// Returns the number of chunks of size [chunkSize] needed to cover
  /// [totalCount] elements.
  static int chunksRequired(int totalCount, int chunkSize) =>
      (totalCount + chunkSize - 1) ~/ chunkSize;

  // ── Human-readable size ───────────────────────────────────────────────────

  /// Formats [bytes] as a human-readable string (KB, MB, GB, TB).
  static String humanReadableSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(2)} ${units[unit]}';
  }

  /// Estimated RAM usage of the page buffer.
  static int bufferRamBytes(int pageSize, int maxPages) => pageSize * maxPages;

  /// Savings ratio: `1 − bufferRam / fileSize`.  Clamped to [0, 1].
  static double memorySavingsRatio(int fileSize, int pageSize, int maxPages) {
    if (fileSize == 0) return 0;
    final ram = bufferRamBytes(pageSize, maxPages);
    return clamp(((fileSize - ram) * 100) ~/ fileSize, 0, 100) / 100;
  }
}
