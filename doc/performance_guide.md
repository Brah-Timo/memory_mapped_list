# Performance Guide

## Understanding the performance model

`memory_mapped_list` trades **raw throughput** for **constant RAM usage**.

| Metric | Dart `List<double>` | `MmlDoubleList` |
|--------|--------------------|--------------------|
| RAM (N=1M doubles) | ~8 MB | ~4 MB (default cache) |
| RAM (N=1B doubles) | ~8 GB | ~4 MB (default cache) |
| Sequential write | very fast (L1/L2 cache) | slower (disk I/O) |
| Sequential read | very fast | fast after warm-up |
| Random access | O(1) RAM | O(1) RAM |
| File persistence | no (data lost on exit) | yes (survives restart) |

The key insight: once a page is loaded the **cache hit rate approaches 1.0**
for sequential access patterns, making repeated reads nearly as fast as an
in-memory list.

---

## Choosing `PageBufferConfig`

### Sequential scan (the most common pattern)

Use `PageBufferConfig.defaultConfig()` or `PageBufferConfig.large()`.
Sequential access loads pages in order; a modest cache already achieves
> 95 % hit rate because the previous page is still in cache while the next
is being processed.

```dart
final list = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 50000000,
  bufferConfig: PageBufferConfig.large(), // 64 MB — fewer disk reads
);
```

### Random access

Larger cache = more pages available = higher hit rate.
Use `PageBufferConfig.large()` or a custom config with many small pages:

```dart
final list = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 50000000,
  bufferConfig: const PageBufferConfig(
    pageSize: 4 * 1024,   // 4 KB — more granular pages
    maxPages: 4096,       // 16 MB total
  ),
);
```

### Low-memory devices (IoT, mobile)

```dart
bufferConfig: PageBufferConfig.lowMemory() // 64 KB total
```

### Write-heavy workloads

Disable parallel flush to guarantee write ordering:

```dart
bufferConfig: const PageBufferConfig(
  parallelFlush: false,
)
```

---

## Choosing `FlushMode`

| Mode | Use when |
|------|----------|
| `onClose` *(default)* | Maximum throughput; data persisted on `close()` |
| `batched` | Periodic checkpointing; `batchSize` trades safety for speed |
| `immediate` | Every write must be durable (e.g. financial data) |

**Benchmark rule of thumb**:
- `onClose` is ≈ 5–20× faster than `immediate` for bulk writes.
- `batched` with `batchSize = 10000` offers a good middle ground.

```dart
// High-throughput batch load — flush only on close.
final list = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 10000000,
  flushMode: FlushMode.onClose,
);

// Checkpointed writes — flush every 10 000 elements.
final list = await MemoryMappedList.doubles(
  path: 'data.mml',
  length: 10000000,
  flushMode: FlushMode.batched,
  batchSize: 10000,
);
```

---

## Streaming vs indexed access

For full-scan aggregations (sum, mean, etc.) always prefer the **streaming API**
over index-based loops:

```dart
// ✅ Fast — uses chunkedStream, yields to event loop, LRU-friendly
await for (final chunk in list.chunkedStream(chunkSize: 100000)) {
  for (final v in chunk) total += v;
}

// ⚠️ Slower — 10 000 event-loop yields per 10 000 elements
await for (final v in list.stream) {
  total += v;
}

// ❌ Slowest for large files — no yielding, not LRU-friendly for huge N
for (var i = 0; i < list.length; i++) total += list[i];
```

The built-in aggregate methods (`sum`, `mean`, `standardDeviation`, `minMax`)
already use `chunkedStream` internally.

---

## Parallel flush

When `PageBufferConfig.parallelFlush = true` (the default), all dirty pages are
flushed concurrently via `Future.wait`.  This can yield a significant speedup on
SSDs or network file systems where parallel writes are efficient.

Disable parallel flush when:
- Write ordering matters (e.g. write-ahead log)
- The underlying storage device is a single spinning disk
- Testing on a slow CI environment

---

## Benchmarking tips

Always measure with `FlushMode.onClose` (default) and `PageBufferConfig.large()`
to establish a baseline, then tighten config as needed.

Check the cache hit rate after a workload:

```dart
await list.close(); // ensure stats are final
print(list.stats.hitRate); // aim for > 0.9 on sequential scans
```

Use `MmlMathUtils.memorySavingsRatio` to quantify RAM savings:

```dart
final saving = MmlMathUtils.memorySavingsRatio(
  list.fileSizeBytes,
  PageBufferConfig.defaultConfig().pageSize,
  PageBufferConfig.defaultConfig().maxPages,
);
print('RAM saving: ${(saving * 100).toStringAsFixed(1)} %');
```

---

## Platform-specific notes

### Windows

- `flush()` on a read-only file descriptor is skipped silently (avoids the
  `OS Error: Access denied, errno = 5` Windows quirk).
- Opening an existing file in `readWrite` mode uses a read-all/write-back
  strategy to bypass Dart's `O_TRUNC` limitation.  For very large existing
  files, prefer `AccessMode.readOnly` when no writes are needed.

### Linux / macOS

- Sequential write performance scales well with `parallelFlush = true`.
- On NFS or network-mounted volumes, `fsync` may be slow — consider
  `FlushMode.onClose` to batch all fsync calls into a single operation.

### Mobile (iOS / Android)

Use `PageBufferConfig.lowMemory()` to stay within memory budget.  Avoid
`FlushMode.immediate` on mobile; prefer `batched` with a generous `batchSize`.
