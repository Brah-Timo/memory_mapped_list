import 'package:memory_mapped_list/src/exceptions/mml_error_codes.dart';

// ── Base exception ────────────────────────────────────────────────────────────

/// Base class for all exceptions thrown by the `memory_mapped_list` package.
///
/// Every subclass carries:
/// * a human-readable [message]
/// * an optional [filePath] indicating which backing file triggered the error
/// * a machine-readable [errorCode] from [MmlErrorCode]
/// * an optional [cause] — the original exception if this one wraps another
sealed class MmlException implements Exception {
  /// Human-readable description of the error.
  final String message;

  /// Path to the `.mml` file involved, or `null` if not applicable.
  final String? filePath;

  /// Stable numeric code for programmatic error handling.
  final MmlErrorCode errorCode;

  /// Underlying exception that caused this one, if any.
  final Object? cause;

  const MmlException(
    this.message, {
    this.filePath,
    required this.errorCode,
    this.cause,
  });

  @override
  String toString() {
    final sb = StringBuffer()
      ..write('${runtimeType} [${errorCode.code}]: $message');
    if (filePath != null) sb.write('  →  file: "$filePath"');
    if (cause != null) sb.write('\n  caused by: $cause');
    return sb.toString();
  }
}

// ── Concrete exceptions ───────────────────────────────────────────────────────

/// Thrown when an operation is attempted on a list that has been [close]d.
final class MmlClosedException extends MmlException {
  MmlClosedException(String path, {Object? cause})
      : super(
          'Operation attempted on a closed MemoryMappedList.',
          filePath: path,
          errorCode: MmlErrorCode.alreadyClosed,
          cause: cause,
        );
}

/// Thrown when a write or resize is attempted on a read-only list.
final class MmlReadOnlyException extends MmlException {
  MmlReadOnlyException(String path, {Object? cause})
      : super(
          'Write attempted on a read-only MemoryMappedList.',
          filePath: path,
          errorCode: MmlErrorCode.readOnly,
          cause: cause,
        );
}

/// Thrown when an index or range is outside the valid bounds of the list.
final class MmlRangeException extends MmlException {
  /// The invalid start index.
  final int start;

  /// The invalid end index (exclusive).
  final int end;

  /// The current length of the list.
  final int listLength;

  MmlRangeException(this.start, this.end, this.listLength, {Object? cause})
      : super(
          'Range [$start, $end) is out of bounds for list of length $listLength.',
          errorCode: MmlErrorCode.invalidRange,
          cause: cause,
        );
}

/// Thrown when the requested file does not exist.
final class MmlFileNotFoundException extends MmlException {
  MmlFileNotFoundException(String path, {Object? cause})
      : super(
          'MML file not found.',
          filePath: path,
          errorCode: MmlErrorCode.fileNotFound,
          cause: cause,
        );
}

/// Thrown when the file header contains an invalid magic number, an
/// unsupported version, or is otherwise unreadable.
final class MmlCorruptFileException extends MmlException {
  /// A detailed reason for why the file is considered corrupt.
  final String reason;

  MmlCorruptFileException(String path, this.reason, {Object? cause})
      : super(
          'Corrupt MML file: $reason',
          filePath: path,
          errorCode: MmlErrorCode.corruptHeader,
          cause: cause,
        );
}

/// Thrown when the disk has no space for a write or expansion operation.
final class MmlDiskFullException extends MmlException {
  /// Number of bytes that were required but unavailable.
  final int requiredBytes;

  MmlDiskFullException(String path, this.requiredBytes, {Object? cause})
      : super(
          'Disk full: required ${requiredBytes} bytes.',
          filePath: path,
          errorCode: MmlErrorCode.diskFull,
          cause: cause,
        );
}

/// Thrown when the element type recorded in the file header does not match
/// the typed list being opened.
final class MmlTypeMismatchException extends MmlException {
  /// The element type expected by the caller.
  final String expected;

  /// The element type actually found in the file header.
  final String actual;

  MmlTypeMismatchException(
    String path, {
    required this.expected,
    required this.actual,
    Object? cause,
  }) : super(
          'Type mismatch: expected "$expected", found "$actual" in file.',
          filePath: path,
          errorCode: MmlErrorCode.typeMismatch,
          cause: cause,
        );
}

/// Thrown when the file was not closed cleanly on a previous run
/// (the [kFlagDirtyShutdown] flag is set in the header).
///
/// The file may still be usable; the caller should decide whether to
/// trust the data or rebuild from a clean source.
final class MmlDirtyShutdownException extends MmlException {
  MmlDirtyShutdownException(String path, {Object? cause})
      : super(
          'File was not closed cleanly; data may be incomplete.',
          filePath: path,
          errorCode: MmlErrorCode.dirtyShutdown,
          cause: cause,
        );
}

/// Thrown when a serializer encounters bytes it cannot decode.
final class MmlDeserializationException extends MmlException {
  /// Zero-based index of the element that could not be decoded.
  final int elementIndex;

  MmlDeserializationException(
    String path, {
    required this.elementIndex,
    Object? cause,
  }) : super(
          'Failed to deserialize element at index $elementIndex.',
          filePath: path,
          errorCode: MmlErrorCode.corruptData,
          cause: cause,
        );
}

/// Thrown when a low-level I/O operation fails at the OS level.
final class MmlIoException extends MmlException {
  MmlIoException(
    String path,
    String detail, {
    Object? cause,
  }) : super(
          'I/O error: $detail',
          filePath: path,
          errorCode: MmlErrorCode.ioFailure,
          cause: cause,
        );
}
