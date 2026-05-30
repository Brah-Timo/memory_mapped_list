# Architecture

`memory_mapped_list` is built from four layered components that together provide
a constant-RAM, disk-backed `List` interface.

```
┌──────────────────────────────────────────────────────────────┐
│  Public API  (lib/memory_mapped_list.dart)                   │
│  MemoryMappedList<T>  ·  MmlDoubleList  ·  MmlInt32List  … │
└────────────────────────┬─────────────────────────────────────┘
                         │ delegates element I/O to
              ┌──────────┴──────────┐
              ▼                     ▼
        PageBuffer            MmlFileManager
        (LRU cache)           (RandomAccessFile I/O)
              │                     │
              └──────── reads / writes pages ──────────┐
                                                        ▼
                                              .mml  backing file
```

## Layers

### 1. `MmlFileManager`

**File**: `lib/src/core/mml_file_manager.dart`

Wraps a single `RandomAccessFile` and exposes byte-level read/write operations:

| Method | Description |
|--------|-------------|
| `create(size)` | Creates and zero-fills a new file |
| `open()` | Opens an existing file (read-only or read-write without truncation) |
| `readBytesSync(start, end)` | Synchronous ranged read |
| `readBytes(start, end)` | Async ranged read |
| `writeBytesSync(offset, data)` | Synchronous positioned write |
| `writeBytes(offset, data)` | Async positioned write |
| `expandFileSync(newSize)` | Grows the file (sparse zero-fill) |
| `sync()` | fsync — skipped silently for read-only files on Windows |
| `close()` | Flushes and closes the file descriptor |

> **Windows note**: `FileMode.write` in Dart always truncates an existing file.
> `MmlFileManager.open()` works around this by reading the full file content
> before the truncating open and immediately writing it back, yielding a true
> `O_RDWR` handle without data loss.

### 2. `PageBuffer`

**File**: `lib/src/core/mml_page_buffer.dart`

An LRU (Least-Recently-Used) cache of fixed-size **pages** loaded from disk.

| Concept | Detail |
|---------|--------|
| Page size | Configurable; default 16 KB |
| Max pages | Configurable; default 256 (total: 4 MB RAM) |
| Eviction | LRU — the oldest page is written back if dirty, then discarded |
| Write strategy | Lazy (dirty pages flushed on eviction, `flushAll`, or `close`) |

Cache hit/miss counters and hit-rate are tracked via `PageBuffer.hits`,
`PageBuffer.misses`, and `PageBuffer.hitRate`.

### 3. `MmlFileHeader`

**File**: `lib/src/core/mml_header.dart`

A 128-byte binary header written at offset 0 of every `.mml` file:

```
Offset  Size  Field
──────  ────  ─────────────────────────────────────────
  0      4    Magic: 0x4D4D4C01 ("MML\x01")
  4      4    Format version (currently 1)
  8      8    Element count (int64 LE)
 16      4    Element size in bytes (int32 LE)
 20      4    Element type ID — see ElementType (int32 LE)
 24      8    Created-at  (µs since Unix epoch, int64 LE)
 32      8    Modified-at (µs since Unix epoch, int64 LE)
 40      4    Page size used at creation (int32 LE)
 44      4    Flags bitmask (int32 LE)
 48     64    UTF-8 metadata (NUL-terminated, max 63 chars)
112     16    Reserved (zeroed)
128          *** DATA STARTS HERE ***
```

Flag constants: `kFlagReadOnly` (0x01), `kFlagCompressed` (0x02),
`kFlagDirtyShutdown` (0x04).

### 4. `MemoryMappedList<T>`

**File**: `lib/src/core/mml_base.dart`

Abstract base class that mixes in `ListMixin<T>` to provide the full Dart
`List` interface.  Concrete subclasses implement only two methods:

```dart
T    deserializeElement(Uint8List page, int offsetInPage);
void serializeElement(Uint8List page, int offsetInPage, T value);
```

#### Typed subclasses

| Class | Element type | Bytes |
|-------|-------------|-------|
| `MmlDoubleList` | `double` (float64) | 8 |
| `MmlFloat32List` | `double` (float32) | 4 |
| `MmlInt32List` | `int` (int32) | 4 |
| `MmlInt64List` | `int` (int64) | 8 |
| `MmlGenericList<T>` | any `T` via `MmlSerializer<T>` | variable |

## Data flow — reading element `i`

```
list[i]
  → byteOffset = 128 + i × elementSize
  → pageIndex  = byteOffset ÷ pageSize
  → PageBuffer.getPage(byteOffset)
      ├─ cache HIT  → return cached Uint8List, bump LRU order
      └─ cache MISS → MmlFileManager.readBytesSync(pageStart, pageEnd)
                      → insert page into LRU cache (evict LRU if full)
  → deserializeElement(page, byteOffset % pageSize)
```

## Data flow — writing element `i`

```
list[i] = value
  → byteOffset = 128 + i × elementSize
  → PageBuffer.getPage(byteOffset)   # load page if not cached
  → serializeElement(page, byteOffset % pageSize, value)
  → PageBuffer.markDirty(byteOffset) # mark page dirty
  → if FlushMode.immediate → PageBuffer.flushPage(byteOffset)
  → if FlushMode.batched && pendingWrites ≥ batchSize → flushAllSync()
```

## Flush modes

| Mode | When dirty pages are written |
|------|------------------------------|
| `onClose` *(default)* | Only on `flush()` / `close()` |
| `immediate` | After every single write |
| `batched` | After every `batchSize` writes (default 1 000) |

## Memory usage formula

```
RAM used = min(maxPages, ceil(fileSize / pageSize)) × pageSize
         ≈ maxPages × pageSize  (once the cache is warm)
```

Default configuration: `256 × 16 384 = 4 194 304 bytes ≈ 4 MB`, regardless of
how large the `.mml` file is.
