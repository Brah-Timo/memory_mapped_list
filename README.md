# memory_mapped_list

> **Process billions of elements. Use constant RAM.** 🚀

A pure-Dart package that provides a `List`-compatible interface backed by binary
files using an **LRU page-buffer** strategy.  Store and process datasets far
larger than the available RAM, while writing code that looks exactly like
ordinary Dart list manipulation.

[![Pub Version](https://img.shields.io/badge/pub-0.1.0-blue)](https://pub.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20iOS%20%7C%20Android-lightgrey)]()

---


<img width="1376" height="768" alt="image" src="https://github.com/user-attachments/assets/e22b1c10-b1ef-4ac7-a36c-d7652be22a1b" />



---

## The Problem

```dart
// ❌ Crashes with OutOfMemoryError on most machines
final list = List<double>.filled(1_000_000_000, 0.0); // 8 GB of RAM needed
```

## The Solution

```dart
// ✅ Works with ~4 MB of RAM regardless of list size
final list = await MemoryMappedList.doubles(
  path: 'my_data.mml',
  length: 1_000_000_000, // one billion elements!
);
// ↑ exactly 4 MB RAM · ~7.6 GB file on disk
```

---

## Features

| Feature | Description |
|---|---|
| 🎯 **Drop-in List API** | Full `List<T>` interface via `ListMixin` — `sort`, `where`, `map`, `sublist`, `indexOf`, etc. all work out of the box |
| 💾 **Disk-backed storage** | Data lives on disk; RAM stays constant at `pageSize × maxPages` |
| 📄 **LRU page cache** | Configurable cache keeps hot pages in memory for high hit rates |
| 🔢 **Typed lists** | `int32`, `int64`, `float32`, `float64` — each with optimal byte layout |
| 🧩 **Generic list** | Any Dart object via a custom `MmlSerializer` |
| 🌊 **Streaming API** | `stream` and `chunkedStream` for zero-copy sequential processing |
| ⚡ **Batch I/O** | `readRange` / `writeRange` for high-throughput bulk operations |
| 📈 **Aggregate stats** | `sum`, `mean`, `standardDeviation`, `minMax` — all streaming |
| 🔁 **Flush modes** | `immediate`, `onClose`, `batched` — balance durability vs speed |
| 🛡️ **Rich exceptions** | Typed exceptions with stable numeric error codes |
| 🌍 **Cross-platform** | Windows, Linux, macOS, iOS, Android — Pure Dart, no native required |
| 🔌 **Optional FFI** | Native `mmap` / `CreateFileMapping` layer for maximum throughput |

---

## Installation

```yaml
dependencies:
  memory_mapped_list: ^0.1.0
```

```bash
dart pub get
```

---

## Quick Start

```dart
import 'package:memory_mapped_list/memory_mapped_list.dart';

void main() async {
  // ── Create ──────────────────────────────────────────────────────────
  final list = await MemoryMappedList.doubles(
    path: 'data.mml',
    length: 100_000_000, // 100 million doubles = 762 MB on disk, 4 MB RAM
  );

  // ── Write — identical to List<double> ─────────────────────────────
  list[0] = 3.14159;
  list[99_999_999] = 2.71828;
  for (var i = 0; i < 1000; i++) list[i] = i * 0.01;

  // ── Read ──────────────────────────────────────────────────────────
  print(list[0]);            // 3.14159
  print(list.length);        // 100000000

  // ── Standard List operations ──────────────────────────────────────
  list.sort();               // sorts in-place (with page cache)
  list.where((v) => v > 0);  // lazy iterable
  list.sublist(0, 10);       // returns List<double>

  // ── Streaming aggregates (O(1) RAM) ───────────────────────────────
  print(await list.sum());
  print(await list.mean());
  print(await list.standardDeviation());
  final bounds = await list.minMax();
  print('${bounds.min} … ${bounds.max}');

  // ── Stream API ────────────────────────────────────────────────────
  await for (final value in list.stream) {
    // process one element at a time
  }
  await for (final chunk in list.chunkedStream(chunkSize: 50_000)) {
    // process 50 000 elements at a time
  }

  // ── Diagnostics ───────────────────────────────────────────────────
  print(list.stats); // hit rate, file size, pending writes …

  // ── Always close! ─────────────────────────────────────────────────
  await list.close(); // flushes dirty pages, releases file descriptor
}
```

---

## Supported Types

| Factory | Dart type | Bytes / element | Notes |
|---|---|---|---|
| `MemoryMappedList.doubles()` | `double` | 8 | 64-bit IEEE 754 |
| `MemoryMappedList.float32s()` | `double` | 4 | 32-bit IEEE 754; half the disk space |
| `MemoryMappedList.int32s()` | `int` | 4 | Range: −2 147 483 648 … 2 147 483 647 |
| `MemoryMappedList.int64s()` | `int` | 8 | Full 64-bit integer range |
| `MemoryMappedList.generic<T>()` | `T` | variable | Requires `MmlSerializer<T>` |

---

## Access Modes

```dart
// Create new file (or overwrite existing)
final list = await MemoryMappedList.doubles(
  path: 'data.mml', length: 1000, mode: AccessMode.create);

// Open existing for read + write
final list = await MemoryMappedList.doubles(
  path: 'data.mml', length: 1000, mode: AccessMode.readWrite);

// Open existing, read-only
final list = await MemoryMappedList.doubles(
  path: 'data.mml', length: 1000, mode: AccessMode.readOnly);
```

---

## Flush Modes

```dart
// Safest: every write is immediately persisted
final list = await MemoryMappedList.doubles(
  path: 'x.mml', length: 100, flushMode: FlushMode.immediate);

// Fastest: only flush on explicit flush() or close()
final list = await MemoryMappedList.doubles(
  path: 'x.mml', length: 100, flushMode: FlushMode.onClose);

// Balanced: auto-flush every 1 000 writes
final list = await MemoryMappedList.doubles(
  path: 'x.mml', length: 100,
  flushMode: FlushMode.batched, batchSize: 1000);
```

---

## Page Buffer Configuration

```dart
// Balanced default (4 MB cache)
PageBufferConfig.defaultConfig()     // 16 KB pages × 256 = 4 MB

// Larger cache for random-access patterns (64 MB)
PageBufferConfig.large()             // 64 KB pages × 1024 = 64 MB

// Tiny footprint for constrained devices (64 KB)
PageBufferConfig.lowMemory()         // 4 KB pages × 16 = 64 KB

// Custom
PageBufferConfig(pageSize: 32 * 1024, maxPages: 512) // 16 MB
```

---

## Generic List

```dart
class Point {
  final double x, y;
  const Point(this.x, this.y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Point.fromJson(Map<String, dynamic> j) =>
      Point(j['x'] as double, j['y'] as double);
}

final serializer = JsonSerializer<Point>(
  fromJson: Point.fromJson,
  toJson: (p) => p.toJson(),
);

final points = await MemoryMappedList.generic<Point>(
  path: 'points.mml',
  length: 10_000_000,
  serializer: serializer,
);

points[0] = const Point(1.0, 2.0);
print(points[0].x); // 1.0

await points.close();
```

---

## Memory Model

```
RAM consumed  =  pageSize × maxPages  (constant)

Example — 10 million doubles, default config:
  File on disk :  128B header + 10M × 8B  =  76.3 MB
  RAM (MML)    :  16 KB × 256            =   4.0 MB  ← always!
  RAM (List)   :  10M × 8B              =  76.3 MB

  Savings: 94.7 %
```

**Formula:**

```
byteOffset  = headerSize + index × elementSize
pageIndex   = byteOffset ÷ pageSize
offsetInPage = byteOffset mod pageSize
```

---

## File Format

Every `.mml` file starts with a **128-byte binary header**:

```
 Offset │ Size │ Field
────────┼──────┼──────────────────────────────────────────────────
  0     │  4   │ Magic: 0x4D4D4C01 ("MML\x01")
  4     │  4   │ Format version (currently 1)
  8     │  8   │ Element count (int64, little-endian)
 16     │  4   │ Element size in bytes
 20     │  4   │ Element type ID (1=int32 2=int64 3=float32 4=float64 99=generic)
 24     │  8   │ Created-at  (µs since Unix epoch)
 32     │  8   │ Modified-at (µs since Unix epoch)
 40     │  4   │ Page size used
 44     │  4   │ Flags (0x01=readOnly, 0x02=compressed, 0x04=dirtyShutdown)
 48     │ 64   │ User metadata (UTF-8, NUL-terminated)
112     │ 16   │ Reserved
128     │  …   │ DATA
```

This makes `.mml` files **self-describing** — they can be reopened without
knowing the element count or type in advance.

---

## When to Use

| Scenario | Dart `List` | `memory_mapped_list` |
|---|---|---|
| < 1 M elements | ✅ fastest | ✅ |
| 1 M – 100 M elements | ⚠️ heavy RAM | ✅ recommended |
| > 100 M elements | ❌ OOM | ✅ |
| Files > available RAM | ❌ | ✅ |
| Scientific data analysis | ⚠️ | ✅ streaming aggregates |
| Log processing pipelines | ⚠️ | ✅ `chunkedStream` |
| ML feature stores | ❌ | ✅ `float32s` list |
| Time-series databases | ❌ | ✅ `int64s` + `doubles` |

---

## Performance Tips

1. **Use `PageBufferConfig.large()`** for random-access workloads.
2. **Use `chunkedStream`** instead of element-by-element iteration — it reads
   whole pages at a time.
3. **Use `writeRange`** for bulk writes — it batches 50 000 writes per event-loop
   yield to reduce overhead.
4. **Use `FlushMode.batched`** when writing large amounts of data to reduce
   syscall pressure.
5. **Sequential access** achieves >95 % cache hit rate with the default config.

---

## Error Handling

```dart
try {
  final list = await MemoryMappedList.doubles(
    path: 'missing.mml', length: 0, mode: AccessMode.readOnly);
} on MmlFileNotFoundException catch (e) {
  print('File not found: ${e.filePath}');  // typed exception
  print('Error code: ${e.errorCode.code}'); // numeric code
}
```

All exceptions extend `MmlException` and carry a `MmlErrorCode` for
programmatic handling without string parsing.

---

## Running the Examples

```bash
dart run example/basic_usage.dart
dart run example/scientific_analysis.dart
dart run example/log_processor.dart
```

## Running the Benchmarks

```bash
dart run benchmark/vs_dart_list.dart
dart run benchmark/vs_file_read.dart
```

## Running the Tests

```bash
# Unit tests
dart test

# Integration tests (creates files up to ~10 MB, takes a few seconds)
dart test --tags integration
```

---

## Contributing

Pull requests welcome!  Please:

1. Run `dart analyze` — zero warnings required.
2. Add tests for any new functionality.
3. Update `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com).

---

## License

[MIT](LICENSE) © 2026 yourname
