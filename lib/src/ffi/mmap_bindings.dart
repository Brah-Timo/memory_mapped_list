// ignore_for_file: avoid_redundant_argument_values, camel_case_types
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

import 'mml_ffi_loader.dart';

// ─── C type aliases ──────────────────────────────────────────────────────────

// POSIX / Win32 types used in the native signatures below.
typedef _MmlHandle = Pointer<Void>;
typedef _MmlHandlePtr = Pointer<_MmlHandle>;

// ─── Native function signatures ───────────────────────────────────────────────

// int mml_open(const char* path, int64_t size, int flags, MmlHandle** out)
typedef _MmlOpen_C = Int32 Function(
  Pointer<Uint8> path,
  Int64 size,
  Int32 flags,
  _MmlHandlePtr out,
);
typedef MmlOpen = int Function(
  Pointer<Uint8> path,
  int size,
  int flags,
  _MmlHandlePtr out,
);

// void* mml_data(MmlHandle* handle)
typedef _MmlData_C = Pointer<Uint8> Function(_MmlHandle handle);
typedef MmlData = Pointer<Uint8> Function(_MmlHandle handle);

// int  mml_flush(MmlHandle* handle, int64_t offset, int64_t length)
typedef _MmlFlush_C = Int32 Function(
  _MmlHandle handle,
  Int64 offset,
  Int64 length,
);
typedef MmlFlush = int Function(_MmlHandle handle, int offset, int length);

// int  mml_close(MmlHandle* handle)
typedef _MmlClose_C = Int32 Function(_MmlHandle handle);
typedef MmlClose = int Function(_MmlHandle handle);

// int64_t mml_size(MmlHandle* handle)
typedef _MmlSize_C = Int64 Function(_MmlHandle handle);
typedef MmlSize = int Function(_MmlHandle handle);

// const char* mml_error_string(int code)
typedef _MmlErrorString_C = Pointer<Uint8> Function(Int32 code);
typedef MmlErrorString = Pointer<Uint8> Function(int code);

// ─── Flags ────────────────────────────────────────────────────────────────────

/// Open the mapping read-only.
const int kMmlFlagReadOnly = 0x01;

/// Create the file if it does not exist.
const int kMmlFlagCreate = 0x02;

/// Hint that access will be sequential (POSIX: MADV_SEQUENTIAL).
const int kMmlFlagSequential = 0x04;

/// Hint that access will be random (POSIX: MADV_RANDOM).
const int kMmlFlagRandom = 0x08;

// ─── MmapBindings ─────────────────────────────────────────────────────────────

/// Low-level FFI bindings to the `mml_native` C library.
///
/// This class is only usable when [MmlFfiLoader.isAvailable] is `true`.
/// All production code that calls native functions must guard with that check.
///
/// These bindings are intentionally thin — they map 1:1 to the C API and
/// perform no Dart-level logic.  Higher-level wrapping belongs in a separate
/// `NativePageBuffer` class (not yet implemented; planned for v0.2).
final class MmapBindings {
  final DynamicLibrary _lib;

  late final MmlOpen open;
  late final MmlData data;
  late final MmlFlush flush;
  late final MmlClose close;
  late final MmlSize size;
  late final MmlErrorString errorString;

  MmapBindings._(this._lib) {
    open = _lib.lookupFunction<_MmlOpen_C, MmlOpen>('mml_open');
    data = _lib.lookupFunction<_MmlData_C, MmlData>('mml_data');
    flush = _lib.lookupFunction<_MmlFlush_C, MmlFlush>('mml_flush');
    close = _lib.lookupFunction<_MmlClose_C, MmlClose>('mml_close');
    size = _lib.lookupFunction<_MmlSize_C, MmlSize>('mml_size');
    errorString =
        _lib.lookupFunction<_MmlErrorString_C, MmlErrorString>('mml_error_string');
  }

  /// Creates an [MmapBindings] instance using the pre-loaded library.
  ///
  /// Throws [StateError] when the native library has not been loaded.
  /// Always check [MmlFfiLoader.isAvailable] before calling this.
  factory MmapBindings.fromLoader() {
    final lib = MmlFfiLoader.load();
    if (lib == null) {
      throw StateError(
        'mml_native library is not available on this platform.  '
        'Check MmlFfiLoader.isAvailable before using native bindings.',
      );
    }
    return MmapBindings._(lib);
  }
}
