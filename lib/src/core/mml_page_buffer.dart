// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:memory_mapped_list/src/core/mml_file_manager.dart';

// ── PageBufferConfig ──────────────────────────────────────────────────────────

/// Tuning parameters for the [PageBuffer] LRU cache.
///
/// Choose a preset that matches your use-case:
///
/// | Preset          | Page size | Max pages | Total cache |
/// |-----------------|-----------|-----------|-------------|
/// | [small]         | 4 KB      | 64        | 256 KB      |
/// | [defaultConfig] | 16 KB     | 256       | 4 MB        |
/// | [large]         | 64 KB     | 1 024     | 64 MB       |
/// | [lowMemory]     | 4 KB      | 16        | 64 KB       |
final class PageBufferConfig {
  /// Size of each page in bytes.  Must be a power of two ≥ 512.
  final int pageSize;

  /// Maximum number of pages kept in RAM at the same time.
  final int maxPages;

  /// When `true` dirty pages are flushed concurrently using [Future.wait].
  ///
  /// Set to `false` on platforms where concurrent I/O is unreliable or when
  /// sequential write ordering matters.
  final bool parallelFlush;

  const PageBufferConfig({
    this.pageSize = 16 * 1024,   // 16 KB
    this.maxPages = 256,
    this.parallelFlush = true,
  }) : assert(pageSize >= 512, 'pageSize must be at least 512 bytes'),
       assert(maxPages >= 1,   'maxPages must be at least 1');

  /// Small cache — good for short-lived or single-element access patterns.
  factory PageBufferConfig.small() => const PageBufferConfig(
        pageSize: 4 * 1024,
        maxPages: 64,
      );

  /// Balanced default — suitable for most use cases.
  factory PageBufferConfig.defaultConfig() => const PageBufferConfig(
        pageSize: 16 * 1024,
        maxPages: 256,
      );

  /// Large cache — maximises hit rate for random-access patterns.
  factory PageBufferConfig.large() => const PageBufferConfig(
        pageSize: 64 * 1024,
        maxPages: 1024,
        parallelFlush: true,
      );

  /// Low-memory cache — for constrained devices (IoT, mobile).
  factory PageBufferConfig.lowMemory() => const PageBufferConfig(
        pageSize: 4 * 1024,
        maxPages: 16,
        parallelFlush: false,
      );

  /// Total bytes this buffer can hold in RAM.
  int get totalCacheSize => pageSize * maxPages;

  @override
  String toString() =>
      'PageBufferConfig(pageSize: ${pageSize}B, maxPages: $maxPages, '
      'cache: ${totalCacheSize ~/ 1024}KB)';
}

// ── _Page ─────────────────────────────────────────────────────────────────────

/// One cached page (a contiguous slice of the backing file).
final class _Page {
  /// Index of this page: `pageIndex = byteOffset ~/ pageSize`.
  final int pageIndex;

  /// The in-memory copy of the page data (exactly [PageBufferConfig.pageSize]
  /// bytes, possibly zero-padded at the end of the file).
  final Uint8List data;

  /// `true` when the in-memory data differs from what is on disk.
  bool isDirty;

  /// Wall-clock timestamp of the last access — used for LRU ordering.
  DateTime lastAccess;

  /// Total number of times this page has been accessed since it was loaded.
  int accessCount;

  _Page({
    required this.pageIndex,
    required this.data,
  })  : isDirty = false,
        lastAccess = DateTime.now(),
        accessCount = 0;

  /// Updates [lastAccess] and increments [accessCount].
  void touch() {
    lastAccess = DateTime.now();
    accessCount++;
  }

  void markDirty() => isDirty = true;
  void markClean() => isDirty = false;

  @override
  String toString() =>
      '_Page(index: $pageIndex, dirty: $isDirty, accesses: $accessCount)';
}

// ── PageBuffer ────────────────────────────────────────────────────────────────

/// LRU (Least-Recently-Used) page cache that sits between [MemoryMappedList]
/// and [MmlFileManager].
///
/// ### How it works
///
/// 1. The backing file is conceptually divided into fixed-size **pages**.
/// 2. When an element is accessed, its containing page is identified by
///    `pageIndex = byteOffset ~/ pageSize`.
/// 3. If the page is already in the cache (**cache hit**), it is returned
///    immediately and moved to the "most recently used" position.
/// 4. If the page is not cached (**cache miss**), it is loaded from disk.
///    If the cache is full, the **least recently used** page is evicted first.
///    If that page is dirty, it is written back to disk before eviction.
/// 5. When an element is modified, its page is marked **dirty**.  Dirty pages
///    are written to disk lazily on eviction, on [flushAll], or on [flushPage].
///
/// ### Memory model
///
/// ```
/// RAM consumed = maxPages × pageSize  (constant)
/// ```
///
/// No matter how large the file is, the buffer never uses more than
/// `maxPages × pageSize` bytes of heap memory for page data.
final class PageBuffer {
  final MmlFileManager _fileManager;

  /// Configuration for this buffer instance.
  final PageBufferConfig config;

  // LinkedHashMap preserves insertion order — the entry at `keys.first` is
  // always the least-recently-used page (LRU position).
  final LinkedHashMap<int, _Page> _cache = LinkedHashMap();

  // ── Metrics ───────────────────────────────────────────────────────────────

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _flushCount = 0;

  PageBuffer({
    required MmlFileManager fileManager,
    required this.config,
  }) : _fileManager = fileManager;

  // ── Core API ──────────────────────────────────────────────────────────────

  /// Returns the page that covers [byteOffset].
  ///
  /// The returned [Uint8List] is the live buffer — modifications made to it
  /// are reflected in the cache.  Call [markDirty] after writing to ensure
  /// the page is flushed back to disk at the right time.
  Uint8List getPage(int byteOffset) {
    final pageIndex = byteOffset ~/ config.pageSize;

    final cached = _cache[pageIndex];
    if (cached != null) {
      // ── Cache HIT ─────────────────────────────────────────────────────────
      _hits++;
      cached.touch();
      // Promote to MRU position by re-inserting at the end.
      _cache
        ..remove(pageIndex)
        ..[pageIndex] = cached;
      return cached.data;
    }

    // ── Cache MISS ────────────────────────────────────────────────────────
    _misses++;
    return _loadPage(pageIndex);
  }

  /// Marks the page covering [byteOffset] as dirty (needs flushing).
  void markDirty(int byteOffset) {
    final pageIndex = byteOffset ~/ config.pageSize;
    _cache[pageIndex]?.markDirty();
  }

  /// Synchronously flushes the single page covering [byteOffset], if dirty.
  void flushPage(int byteOffset) {
    final pageIndex = byteOffset ~/ config.pageSize;
    final page = _cache[pageIndex];
    if (page != null && page.isDirty) {
      _writePageSync(page);
    }
  }

  /// Synchronously flushes **all** dirty pages.
  void flushAllSync() {
    for (final page in _cache.values) {
      if (page.isDirty) _writePageSync(page);
    }
  }

  /// Asynchronously flushes **all** dirty pages.
  ///
  /// Pages are always written **sequentially** because Dart's
  /// [RandomAccessFile] only supports one pending async operation at a time.
  /// Concurrent writes (e.g. via [Future.wait]) on the same file object
  /// produce a `FileSystemException: An async operation is currently pending`.
  ///
  /// The [PageBufferConfig.parallelFlush] flag is intentionally ignored here
  /// to keep the implementation safe on all platforms.
  Future<void> flushAll() async {
    final dirty = _cache.values.where((p) => p.isDirty).toList();
    if (dirty.isEmpty) return;

    // Sequential writes — safe on every platform and with every RAF instance.
    for (final page in dirty) {
      _writePageSync(page);
    }
  }

  /// Releases all in-memory page data.
  ///
  /// **Important**: call [flushAll] before [dispose] if you want dirty pages
  /// to be persisted.
  void dispose() {
    _cache.clear();
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Number of pages currently held in the cache.
  int get cachedPageCount => _cache.length;

  /// Total cache hits since this buffer was created.
  int get hits => _hits;

  /// Total cache misses (disk reads) since this buffer was created.
  int get misses => _misses;

  /// Total number of page evictions since this buffer was created.
  int get evictions => _evictions;

  /// Total number of page flushes (disk writes) since this buffer was created.
  int get flushCount => _flushCount;

  /// Page size as configured.
  int get pageSize => config.pageSize;

  /// Cache hit rate in [0, 1].  Returns 0 when no accesses have been made.
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0 : _hits / total;
  }

  /// Number of pages that are dirty (modified but not yet written to disk).
  int get dirtyPageCount => _cache.values.where((p) => p.isDirty).length;

  /// A brief diagnostic string.
  @override
  String toString() => 'PageBuffer('
      'pageSize: ${config.pageSize}B, '
      'maxPages: ${config.maxPages}, '
      'cached: $cachedPageCount, '
      'dirty: $dirtyPageCount, '
      'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';

  // ── Private helpers ───────────────────────────────────────────────────────

  Uint8List _loadPage(int pageIndex) {
    // Evict the LRU page if the cache is full.
    if (_cache.length >= config.maxPages) {
      _evict();
    }

    final startByte = pageIndex * config.pageSize;
    final endByte = startByte + config.pageSize;

    final data = _fileManager.readBytesSync(startByte, endByte);
    final page = _Page(pageIndex: pageIndex, data: data);
    _cache[pageIndex] = page;
    return data;
  }

  void _evict() {
    if (_cache.isEmpty) return;

    // The first key in a LinkedHashMap is the least-recently used.
    final lruKey = _cache.keys.first;
    final lruPage = _cache[lruKey]!;

    if (lruPage.isDirty) {
      _writePageSync(lruPage);
    }

    _cache.remove(lruKey);
    _evictions++;
  }

  void _writePageSync(_Page page) {
    final start = page.pageIndex * config.pageSize;
    _fileManager.writeBytesSync(start, page.data);
    page.markClean();
    _flushCount++;
  }
}
