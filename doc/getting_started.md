# Getting Started

## Installation

Add `memory_mapped_list` to your `pubspec.yaml`:

```yaml
dependencies:
  memory_mapped_list: ^0.1.0
```

Then run:

```sh
dart pub get
```

## Requirements

- Dart SDK **≥ 3.6.0**
- Supported platforms: Windows, Linux, macOS, iOS, Android

---

## Quick start — doubles

```dart
import 'package:memory_mapped_list/memory_mapped_list.dart';

Future<void> main() async {
  // 1. Create a list of 1 000 000 doubles.
  //    Only ~4 MB of RAM is used regardless of file size.
  final list = await MemoryMappedList.doubles(
    path: 'my_data.mml',
    length: 1000000,
  );

  // 2. Write values — identical syntax to a normal Dart List.
  for (var i = 0; i < list.length; i++) {
    list[i] = i * 0.001;
  }

  // 3. Read values.
  print(list[0]);        // 0.0
  print(list[500000]);   // 500.0

  // 4. Use any standard List method.
  final first10 = list.sublist(0, 10);
  final positives = list.where((v) => v > 0).toList();

  // 5. Streaming aggregates — O(1) RAM.
  final mean   = await list.mean();
  final stdDev = await list.standardDeviation();
  final bounds = await list.minMax();

  // 6. Always close to flush pending writes.
  await list.close();
}
```

---

## Open an existing file

```dart
// Read-only (fastest; no flush needed on close).
final ro = await MemoryMappedList.doubles(
  path: 'my_data.mml',
  length: 1000000,
  mode: AccessMode.readOnly,
);
print(ro[42]);
await ro.close();

// Read-write (modify existing data in-place).
final rw = await MemoryMappedList.doubles(
  path: 'my_data.mml',
  length: 1000000,
  mode: AccessMode.readWrite,
);
rw[0] = 99.9;
await rw.close();
```

---

## Integer lists

```dart
// 32-bit integers
final ids = await MemoryMappedList.int32s(
  path: 'user_ids.mml',
  length: 5000000,
);
for (var i = 0; i < ids.length; i++) ids[i] = i;
await ids.close();

// 64-bit integers
final timestamps = await MemoryMappedList.int64s(
  path: 'timestamps.mml',
  length: 1000000,
);
```

---

## Generic objects

Use `MmlGenericList<T>` with a custom serializer to store any Dart object:

```dart
import 'dart:convert';
import 'package:memory_mapped_list/memory_mapped_list.dart';

class Point {
  final double x, y;
  const Point(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Point.fromJson(Map<String, dynamic> j) =>
      Point(j['x'] as double, j['y'] as double);
}

final serializer = JsonSerializer<Point>(
  fromJson: Point.fromJson,
  toJson:   (p) => p.toJson(),
);

final points = await MemoryMappedList.generic<Point>(
  path: 'points.mml',
  length: 100000,
  serializer: serializer,
);

points[0] = const Point(1.0, 2.0);
print(points[0].x); // 1.0

await points.close();
```

---

## Tuning the page buffer

Choose a preset or provide a custom config:

```dart
// Large cache — best for random-access patterns.
final list = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 10000000,
  bufferConfig: PageBufferConfig.large(), // 64 MB cache
);

// Low-memory — for IoT or constrained devices.
final list2 = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 10000000,
  bufferConfig: PageBufferConfig.lowMemory(), // 64 KB cache
);

// Custom config.
final list3 = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 10000000,
  bufferConfig: const PageBufferConfig(
    pageSize: 32 * 1024,  // 32 KB pages
    maxPages: 512,        // 16 MB total
    parallelFlush: false, // sequential flush for ordered writes
  ),
);
```

---

## Flush modes

```dart
// Default: flush on close only (fastest writes, least durable).
final fast = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 1000,
  flushMode: FlushMode.onClose,
);

// Immediate: flush after every write (safest, slowest).
final safe = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 1000,
  flushMode: FlushMode.immediate,
);

// Batched: flush every 500 writes.
final balanced = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 1000,
  flushMode: FlushMode.batched,
  batchSize: 500,
);
```

---

## Streaming API

```dart
// Process each element individually.
await for (final value in list.stream) {
  process(value);
}

// Process in chunks for higher throughput.
await for (final chunk in list.chunkedStream(chunkSize: 50000)) {
  for (final v in chunk) {
    process(v);
  }
}

// Write a range from an Iterable.
final values = Iterable.generate(1000, (i) => i.toDouble());
await list.writeRange(0, values);
```

---

## Diagnostics

```dart
final stats = list.stats;
print('Elements : ${stats.totalElements}');
print('File     : ${stats.fileSizeMB.toStringAsFixed(2)} MB');
print('Cache    : ${stats.cachedPages} pages');
print('Hit rate : ${(stats.hitRate * 100).toStringAsFixed(1)} %');
print('Pending  : ${stats.pendingWrites} writes');
```

---

## Error handling

```dart
try {
  final list = await MemoryMappedList.doubles(
    path: 'nonexistent.mml',
    length: 1000,
    mode: AccessMode.readOnly,
  );
} on MmlFileNotFoundException catch (e) {
  print('File not found: $e');
}

// Writing to a read-only list.
try {
  ro[0] = 1.0;
} on MmlReadOnlyException catch (e) {
  print('Cannot write: $e');
}

// Accessing a closed list.
await list.close();
try {
  list[0];
} on MmlClosedException catch (e) {
  print('List is closed: $e');
}
```

---

## Next steps

- [Architecture](architecture.md) — internal design and data flow
- [API Reference](api_reference.md) — complete member documentation
- [Performance Guide](performance_guide.md) — tuning tips and benchmarks
- [File Format](file_format.md) — `.mml` binary layout specification
- [Migration Guide](migration_guide.md) — upgrading between versions
