import 'dart:typed_data';

/// Endianness helpers used throughout the package.
///
/// All `.mml` files use **little-endian** byte order, matching the native
/// order on x86/ARM platforms.  These helpers make endian conversions explicit
/// and easy to audit.
abstract final class MmlEndian {
  /// The byte order used for all `.mml` files.
  static const Endian fileEndian = Endian.little;

  // ── Read helpers ──────────────────────────────────────────────────────────

  static int readInt32(Uint8List buf, int offset) =>
      ByteData.sublistView(buf).getInt32(offset, fileEndian);

  static int readInt64(Uint8List buf, int offset) =>
      ByteData.sublistView(buf).getInt64(offset, fileEndian);

  static double readFloat32(Uint8List buf, int offset) =>
      ByteData.sublistView(buf).getFloat32(offset, fileEndian);

  static double readFloat64(Uint8List buf, int offset) =>
      ByteData.sublistView(buf).getFloat64(offset, fileEndian);

  static int readUint32(Uint8List buf, int offset) =>
      ByteData.sublistView(buf).getUint32(offset, fileEndian);

  // ── Write helpers ─────────────────────────────────────────────────────────

  static void writeInt32(Uint8List buf, int offset, int value) =>
      ByteData.sublistView(buf).setInt32(offset, value, fileEndian);

  static void writeInt64(Uint8List buf, int offset, int value) =>
      ByteData.sublistView(buf).setInt64(offset, value, fileEndian);

  static void writeFloat32(Uint8List buf, int offset, double value) =>
      ByteData.sublistView(buf).setFloat32(offset, value, fileEndian);

  static void writeFloat64(Uint8List buf, int offset, double value) =>
      ByteData.sublistView(buf).setFloat64(offset, value, fileEndian);

  static void writeUint32(Uint8List buf, int offset, int value) =>
      ByteData.sublistView(buf).setUint32(offset, value, fileEndian);

  // ── Conversion utilities ──────────────────────────────────────────────────

  /// Swaps the byte order of a 32-bit integer.
  static int byteSwap32(int v) =>
      ((v & 0xFF) << 24) |
      ((v >> 8 & 0xFF) << 16) |
      ((v >> 16 & 0xFF) << 8) |
      ((v >> 24) & 0xFF);

  /// Swaps the byte order of a 64-bit integer.
  static int byteSwap64(int v) {
    var lo = byteSwap32(v & 0xFFFFFFFF);
    var hi = byteSwap32((v >> 32) & 0xFFFFFFFF);
    return (lo << 32) | (hi & 0xFFFFFFFF);
  }

  /// Returns `true` when the current CPU uses little-endian byte order.
  static bool get isNativeLittleEndian {
    final check = ByteData(4)..setUint32(0, 1, Endian.little);
    return check.getUint8(0) == 1;
  }
}
