// ignore_for_file: avoid_redundant_argument_values

import 'dart:ffi';
import 'dart:io';

/// Locates and loads the native shared library (`mml_native`) that wraps
/// the platform `mmap` / `CreateFileMapping` APIs.
///
/// The library is **optional**: all core functionality works without it via
/// Dart's own [RandomAccessFile].  The native layer is only used when
/// `MmlNativeBackend.isAvailable` is `true`, providing a direct OS memory-map
/// that can improve throughput on Linux/macOS/Windows for very large files.
///
/// ### Loading order
///
/// 1. `<exe directory>/mml_native.<ext>` (bundled next to the executable)
/// 2. `<package root>/lib/src/ffi/native/mml_native.<ext>` (dev build)
/// 3. System library path (so that `pub global` installs work)
///
/// Where `<ext>` is:
/// * `so`  — Linux / Android
/// * `dylib` — macOS / iOS
/// * `dll`  — Windows
abstract final class MmlFfiLoader {
  static DynamicLibrary? _cached;
  static bool _attempted = false;

  /// Attempts to load the native library and returns it, or `null` if it
  /// could not be found / loaded.
  ///
  /// The first successful call is cached; subsequent calls return the same
  /// [DynamicLibrary].
  static DynamicLibrary? load() {
    if (_attempted) return _cached;
    _attempted = true;

    final name = _libraryName();
    final candidates = _searchPaths(name);

    for (final path in candidates) {
      try {
        if (File(path).existsSync()) {
          _cached = DynamicLibrary.open(path);
          return _cached;
        }
      } catch (_) {
        // Continue to next candidate.
      }
    }

    // Last resort — try the system linker.
    try {
      _cached = DynamicLibrary.open(name);
      return _cached;
    } catch (_) {
      return null;
    }
  }

  /// `true` when the native library is available and loaded.
  static bool get isAvailable => load() != null;

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _libraryName() {
    if (Platform.isWindows) return 'mml_native.dll';
    if (Platform.isMacOS || Platform.isIOS) return 'mml_native.dylib';
    return 'mml_native.so'; // Linux, Android, Fuchsia
  }

  static List<String> _searchPaths(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return [
      '$exeDir/$name',
      // Development build output
      '${Directory.current.path}/lib/src/ffi/native/$name',
      '${Directory.current.path}/build/$name',
    ];
  }
}
