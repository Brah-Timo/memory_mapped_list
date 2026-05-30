# API Reference

Complete reference for the public API of `memory_mapped_list`.

---

## `MemoryMappedList<T>` (abstract)

Located in `lib/src/core/mml_base.dart`, exported from `memory_mapped_list.dart`.

Mixes in `ListMixin<T>` — every standard `List` method (`sort`, `where`,
`map`, `sublist`, `indexOf`, `contains`, …) is available automatically.

### Factory constructors

#### `MemoryMappedList.doubles`
```dart
static Future<MmlDoubleList> doubles({
  required String path,
  required int length,
  AccessMode mode = AccessMode.create,
  PageBufferConfig? bufferConfig,
  FlushMode flushMode = FlushMode.onClose,
  int batchSize = 1000,
})
```
Creates or opens a file-backed list of 64-bit doubles.

#### `MemoryMappedList.float32s`
```dart
static Future<MmlFloat32List> float32s({...})
```
Creates or opens a file-backed list of 32-bit floats (exposed as `double`).

#### `MemoryMappedList.int32s`
```dart
static Future<MmlInt32List> int32s({...})
```
Creates or opens a file-backed list of 32-bit signed integers.

#### `MemoryMappedList.int64s`
```dart
static Future<MmlInt64List> int64s({...})
```
Creates or opens a file-backed list of 64-bit signed integers.

#### `MemoryMappedList.generic<E>`
```dart
static Future<MmlGenericList<E>> generic<E>({
  required String path,
  required int length,
  required MmlSerializer<E> serializer,
  AccessMode mode = AccessMode.create,
  PageBufferConfig? bufferConfig,
  FlushMode flushMode = FlushMode.onClose,
  int batchSize = 1000,
})
```
Creates or opens a file-backed list of arbitrary objects using a custom serializer.

---

### Instance members

#### `length` → `int`
Number of elements in the list.  Setting `length` truncates or extends the
backing file (extended regions are zero-filled).

#### `operator []` / `operator []=`
Random-access read/write via the LRU page cache.  Throws `RangeError` if the
index is out of bounds, `MmlReadOnlyException` if the list is read-only, and
`MmlClosedException` if the list has been closed.

#### `readRange(int start, int end)` → `Future<List<T>>`
Reads elements `[start, end)` efficiently by fetching whole pages.

#### `writeRange(int start, Iterable<T> values)` → `Future<void>`
Writes values starting at index `start`.  Yields to the event loop every
50 000 writes.

#### `stream` → `Stream<T>`
Produces all elements as an async stream, yielding every 10 000 elements.

#### `chunkedStream({int chunkSize = 10000})` → `Stream<List<T>>`
Produces elements grouped into lists of `chunkSize` for higher-throughput
streaming.

#### `flush()` → `Future<void>`
Flushes all dirty pages to disk and calls `fsync`.  After this call, data
is durable against a process crash.

#### `close()` → `Future<void>`
Flushes and closes the backing file.  Safe to call multiple times.  Any
access after `close()` throws `MmlClosedException`.

#### `stats` → `MmlStats`
Snapshot of current performance metrics (see `MmlStats` below).

#### `isOpen` → `bool`
`true` while the file is open and usable.

#### `filePath` → `String`
Absolute or relative path to the `.mml` file.

#### `fileSizeBytes` → `int`
Current size of the backing file including the 128-byte header.

---

## `MmlDoubleList`

Extends `MemoryMappedList<double>` with numeric aggregate operations.

| Method | Returns | Description |
|--------|---------|-------------|
| `sum()` | `Future<double>` | Sum of all elements |
| `mean()` | `Future<double>` | Arithmetic mean |
| `minMax()` | `Future<({double min, double max})>` | Min and max in one pass |
| `standardDeviation()` | `Future<double>` | Welford single-pass std dev |
| `median()` | `Future<double>` | Median (allocates O(n) RAM) |
| `fill(double value)` | `Future<void>` | Fill every element with `value` |

> `MmlFloat32List`, `MmlInt32List`, and `MmlInt64List` expose similar aggregates
> (`sum`, `mean`, `minMax`, `fill`).

---

## `MmlGenericList<T>`

Stores arbitrary objects via a `MmlSerializer<T>`.

Each element is serialized to a variable-length byte sequence.  A companion
`.mml.idx` index file stores per-element byte offsets.

---

## `MmlSerializer<T>` (abstract)

```dart
abstract class MmlSerializer<T> {
  Uint8List serialize(T value);
  T deserialize(Uint8List bytes);
}
```

Built-in implementations:

| Class | Element type |
|-------|-------------|
| `JsonSerializer<T>` | any JSON-serializable object |
| `StringSerializer` | `String` (UTF-8) |
| `Int32Serializer` | `int` (4 bytes) |
| `Int64Serializer` | `int` (8 bytes) |
| `Float64Serializer` | `double` (8 bytes) |

---

## `AccessMode` (enum)

| Value | Description |
|-------|-------------|
| `create` *(default)* | Create a new file (or truncate existing) |
| `readOnly` | Open existing file for reading only |
| `readWrite` | Open existing file for reading and writing |

---

## `FlushMode` (enum)

| Value | Description |
|-------|-------------|
| `onClose` *(default)* | Flush only on `flush()` / `close()` |
| `immediate` | Flush after every single write |
| `batched` | Flush after every `batchSize` writes |

---

## `PageBufferConfig`

Tuning parameters for the LRU page cache.

```dart
const PageBufferConfig({
  int pageSize    = 16 * 1024, // 16 KB
  int maxPages    = 256,
  bool parallelFlush = true,
})
```

### Preset factories

| Factory | Page size | Max pages | Total cache |
|---------|-----------|-----------|-------------|
| `PageBufferConfig.small()` | 4 KB | 64 | 256 KB |
| `PageBufferConfig.defaultConfig()` | 16 KB | 256 | 4 MB |
| `PageBufferConfig.large()` | 64 KB | 1 024 | 64 MB |
| `PageBufferConfig.lowMemory()` | 4 KB | 16 | 64 KB |

### Property: `totalCacheSize` → `int`
`pageSize × maxPages` — maximum bytes of heap used by the page buffer.

---

## `MmlStats`

Immutable performance snapshot returned by `MemoryMappedList.stats`.

| Property | Type | Description |
|----------|------|-------------|
| `totalElements` | `int` | Current element count |
| `fileSizeBytes` | `int` | Backing file size in bytes |
| `fileSizeMB` | `double` | File size in megabytes |
| `fileSizeGB` | `double` | File size in gigabytes |
| `cachedPages` | `int` | Pages currently in LRU cache |
| `pageHits` | `int` | Cache hits since open |
| `pageMisses` | `int` | Cache misses (disk reads) since open |
| `hitRate` | `double` | Ratio of hits to total accesses [0, 1] |
| `pendingWrites` | `int` | Writes not yet flushed to disk |

---

## `MmlFileHeader`

Binary header at offset 0 of every `.mml` file.  See
[architecture.md](architecture.md) for the full binary layout.

### Key members

| Member | Description |
|--------|-------------|
| `MmlFileHeader.headerSize` | 128 — data starts at this byte offset |
| `MmlFileHeader.create(...)` | Named constructor for new headers |
| `MmlFileHeader.fromBytes(Uint8List)` | Parse from raw bytes |
| `toBytes()` → `Uint8List` | Serialize to 128 bytes |
| `elementCount` | Number of elements stored |
| `elementType` | `ElementType` enum value |
| `flags` | Bitmask — see `kFlagReadOnly`, `kFlagDirtyShutdown` |
| `isReadOnly` | `true` when `kFlagReadOnly` bit is set |
| `isDirtyShutdown` | `true` when file was not closed cleanly |
| `markDirty()` / `markClean()` | Toggle `kFlagDirtyShutdown` |
| `updateLength(int)` | Update count and bump `modifiedAt` |

### Flag constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `kFlagReadOnly` | `0x01` | File opened read-only |
| `kFlagCompressed` | `0x02` | Data compressed (reserved) |
| `kFlagDirtyShutdown` | `0x04` | File not closed cleanly |

---

## Exceptions

All exceptions are in `lib/src/exceptions/`.

| Exception | When thrown |
|-----------|-------------|
| `MmlFileNotFoundException` | `open()` on a non-existent path |
| `MmlReadOnlyException` | Write operation on a read-only list |
| `MmlClosedException` | Any operation after `close()` |
| `MmlRangeException` | `readRange` / `writeRange` with invalid bounds |
| `MmlCorruptFileException` | Unrecoverable file corruption detected |

---

## `MmlMathUtils`

Static utility class for offset/alignment arithmetic.

| Method | Description |
|--------|-------------|
| `elementToByteOffset(index, elementSize)` | Element index → file byte offset |
| `byteOffsetToPageIndex(byteOffset, pageSize)` | Byte offset → page index |
| `totalFileSize(count, elementSize)` | Total file size for a fixed-size list |
| `pagesRequired(byteCount, pageSize)` | Number of pages needed |
| `alignUp(value, alignment)` | Round up to power-of-two alignment |
| `humanReadableSize(bytes)` | Format bytes as "1.23 MB" |
| `memorySavingsRatio(fileSize, pageSize, maxPages)` | RAM savings fraction |

---

## `MmlEndian`

Helpers for little-endian byte conversion.

| Method | Description |
|--------|-------------|
| `getFloat64(buf, offset)` | Read 64-bit double at `offset` |
| `setFloat64(buf, offset, value)` | Write 64-bit double at `offset` |
| `getFloat32(buf, offset)` | Read 32-bit float |
| `setFloat32(buf, offset, value)` | Write 32-bit float |
| `getInt64(buf, offset)` | Read 64-bit int |
| `setInt64(buf, offset, value)` | Write 64-bit int |
| `getInt32(buf, offset)` | Read 32-bit int |
| `setInt32(buf, offset, value)` | Write 32-bit int |
