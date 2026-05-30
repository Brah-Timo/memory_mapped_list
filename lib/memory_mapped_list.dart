/// memory_mapped_list
///
/// A high-performance Dart package that provides a [List]-compatible interface
/// backed by disk files using an LRU page-buffer strategy.  The amount of RAM
/// consumed stays **constant** regardless of how large the list is — you can
/// store and process billions of elements on machines with limited memory.
///
/// ## Quick-start
///
/// ```dart
/// import 'package:memory_mapped_list/memory_mapped_list.dart';
///
/// Future<void> main() async {
///   // Create a list of 100 million doubles — only ~4 MB of RAM used.
///   final list = await MemoryMappedList.doubles(
///     path: 'my_data.mml',
///     length: 100_000_000,
///   );
///
///   list[0] = 3.14159;
///   print(list[0]); // 3.14159
///
///   print(await list.mean()); // streaming mean — no extra RAM
///
///   await list.close(); // always close to flush pending writes
/// }
/// ```
///
/// ## Supported types
///
/// | Factory                         | Element type | Bytes/element |
/// |----------------------------------|--------------|---------------|
/// | [MemoryMappedList.doubles]       | `double`     | 8             |
/// | [MemoryMappedList.float32s]      | `double`     | 4             |
/// | [MemoryMappedList.int32s]        | `int`        | 4             |
/// | [MemoryMappedList.int64s]        | `int`        | 8             |
/// | [MemoryMappedList.generic]       | `T`          | variable      |
///
/// ## Architecture
///
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  MemoryMappedList<T>  (abstract, ListMixin)      │
/// │   • operator []  / []=                           │
/// │   • stream / chunkedStream                       │
/// │   • readRange / writeRange                       │
/// │   • flush / close / stats                        │
/// └────────────────┬─────────────────────────────────┘
///                  │ uses
///      ┌───────────┴───────────┐
///      ▼                       ▼
/// PageBuffer               MmlFileManager
/// (LRU cache of pages)     (RandomAccessFile I/O)
/// ```
library memory_mapped_list;

// ── Core public API ──────────────────────────────────────────────────────────
export 'src/core/mml_base.dart'
    show MemoryMappedList, AccessMode, FlushMode, MmlStats;

export 'src/core/mml_page_buffer.dart' show PageBufferConfig;

export 'src/core/mml_header.dart'
    show MmlFileHeader, ElementType, kFlagReadOnly, kFlagCompressed, kFlagDirtyShutdown;

// ── Typed implementations ────────────────────────────────────────────────────
export 'src/types/mml_double_list.dart' show MmlDoubleList;
export 'src/types/mml_float32_list.dart' show MmlFloat32List;
export 'src/types/mml_int32_list.dart' show MmlInt32List;
export 'src/types/mml_int64_list.dart' show MmlInt64List;
export 'src/types/mml_generic_list.dart' show MmlGenericList;

// ── Serialization ────────────────────────────────────────────────────────────
export 'src/utils/mml_serializer.dart'
    show MmlSerializer, JsonSerializer, StringSerializer, Int32Serializer,
        Int64Serializer, Float64Serializer;

// ── Utilities ────────────────────────────────────────────────────────────────
export 'src/utils/mml_endian.dart' show MmlEndian;
export 'src/utils/mml_math_utils.dart' show MmlMathUtils;

// ── Exceptions ───────────────────────────────────────────────────────────────
export 'src/exceptions/mml_exceptions.dart';
export 'src/exceptions/mml_error_codes.dart' show MmlErrorCode;
