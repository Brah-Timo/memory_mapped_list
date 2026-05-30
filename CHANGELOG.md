# Changelog

All notable changes to `memory_mapped_list` will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

_(nothing yet)_

---

## [0.1.0] — 2026-05-30

### Added

#### Core
- `MemoryMappedList<T>` abstract base class mixing in `ListMixin<T>` for full
  `List` API compatibility (`sort`, `where`, `map`, `sublist`, `indexOf`, etc.)
- LRU page-buffer (`PageBuffer`) with configurable `pageSize` and `maxPages`
- `MmlFileManager` — `RandomAccessFile` I/O with sync and async variants
- `MmlFileHeader` — 128-byte self-describing binary header (magic, version,
  element count, type, timestamps, page size, flags, metadata)
- Three flush modes: `immediate`, `onClose`, `batched`
- Three access modes: `create`, `readWrite`, `readOnly`

#### Typed Lists
- `MmlDoubleList` — 64-bit IEEE 754 doubles (8 bytes/element)
- `MmlFloat32List` — 32-bit IEEE 754 floats (4 bytes/element)
- `MmlInt32List` — 32-bit signed integers (4 bytes/element)
- `MmlInt64List` — 64-bit signed integers (8 bytes/element)
- `MmlGenericList<T>` — variable-length elements with separate `.mml.idx`
  index file; element count and size tracked per entry

#### Serialisers
- `MmlSerializer<T>` abstract base
- `JsonSerializer<T>` — JSON UTF-8, variable size
- `StringSerializer` — UTF-8 strings, variable size
- `Int32Serializer`, `Int64Serializer`, `Float64Serializer`, `Float32Serializer` — fixed-size binary
- `BytesSerializer` — raw `Uint8List` pass-through

#### Streaming & Batch API
- `stream` — async generator yielding all elements one by one
- `chunkedStream({int chunkSize})` — yields `List<T>` chunks
- `readRange(int start, int end)` — batch async read
- `writeRange(int start, Iterable<T>)` — batch async write

#### Aggregates (on typed lists)
- `sum()`, `mean()`, `minMax()`, `standardDeviation()` — single-pass streaming
- `median()` (doubles only) — loads sorted copy into RAM, explicit O(n) warning
- `fill(T value)` — bulk fill via `writeRange`
- `isAllZeros()` (int32 only)
- `timestampAt(int)` / `setTimestamp(int, DateTime)` (int64 only)

#### Exceptions
- `MmlException` sealed base class
- `MmlClosedException`, `MmlReadOnlyException`, `MmlRangeException`,
  `MmlFileNotFoundException`, `MmlCorruptFileException`, `MmlDiskFullException`,
  `MmlTypeMismatchException`, `MmlDirtyShutdownException`,
  `MmlDeserializationException`, `MmlIoException`
- `MmlErrorCode` enum with stable numeric codes (1000–1599)

#### Utilities
- `MmlEndian` — little-endian read/write helpers
- `MmlMathUtils` — offset arithmetic, alignment, human-readable sizes, savings ratio
- `PageBufferConfig` presets: `defaultConfig`, `small`, `large`, `lowMemory`
- `MmlStats` — snapshot of hit rate, file size, cached pages, pending writes

#### FFI (optional)
- `MmlFfiLoader` — platform-aware dynamic library loader
- `MmapBindings` — Dart FFI bindings to `mml_native` C library
- `mml_native.c` — cross-platform wrapper: POSIX `mmap` + Win32 `CreateFileMapping`
- `CMakeLists.txt` + `build.sh` for compiling the native layer

#### Tests
- Unit tests: `mml_header_test.dart`, `mml_page_buffer_test.dart`,
  `mml_file_manager_test.dart`
- Type tests: `mml_double_list_test.dart`, `mml_int32_list_test.dart`
- Integration tests (tagged `integration`): large file, streaming, concurrent,
  resize

#### Examples & Benchmarks
- `example/basic_usage.dart` — minimal API walkthrough
- `example/scientific_analysis.dart` — Z-score normalisation + anomaly detection
- `example/log_processor.dart` — `MmlGenericList<LogEntry>` with `JsonSerializer`
- `benchmark/vs_dart_list.dart` — sequential read/write vs `List<double>`
- `benchmark/vs_file_read.dart` — full-file read vs paged MML vs chunkedStream

---

[Unreleased]: https://github.com/Brah-Timo/memory_mapped_list/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Brah-Timo/memory_mapped_list/releases/tag/v0.1.0
