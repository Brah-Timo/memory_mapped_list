import 'dart:io';

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

void main() {
  group('PageBufferConfig', () {
    test('defaultConfig has expected values', () {
      final cfg = PageBufferConfig.defaultConfig();
      expect(cfg.pageSize, equals(16 * 1024));
      expect(cfg.maxPages, equals(256));
      expect(cfg.parallelFlush, isTrue);
      expect(cfg.totalCacheSize, equals(16 * 1024 * 256));
    });

    test('lowMemory config stays under 1 MB', () {
      final cfg = PageBufferConfig.lowMemory();
      expect(cfg.totalCacheSize, lessThan(1024 * 1024));
    });

    test('large config uses 64 KB pages', () {
      final cfg = PageBufferConfig.large();
      expect(cfg.pageSize, equals(64 * 1024));
    });

    test('small config has 64 max pages', () {
      final cfg = PageBufferConfig.small();
      expect(cfg.maxPages, equals(64));
    });
  });

  group('PageBuffer — cache hit/miss', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('mml_test_');
    });

    tearDown(() async {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await tmpDir.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    test('first access is a miss, subsequent access is a hit', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/hit_miss.mml',
        length: 1000,
        bufferConfig: PageBufferConfig.defaultConfig(),
      );

      // First read — cold cache
      final _ = list[0];
      expect(list.stats.pageMisses, greaterThanOrEqualTo(1));

      // Second read of same element — should be a hit
      final prevHits = list.stats.pageHits;
      final __ = list[0];
      expect(list.stats.pageHits, greaterThan(prevHits));

      await list.close();
    });

    test('LRU eviction respects maxPages', () async {
      const pageSize = 512;
      const maxPages = 4;
      const elementSize = 8;
      // Each page holds pageSize / elementSize elements
      const elementsPerPage = pageSize ~/ elementSize;
      const totalElements = elementsPerPage * (maxPages + 4); // 8 pages total

      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/lru.mml',
        length: totalElements,
        bufferConfig: PageBufferConfig(
          pageSize: pageSize,
          maxPages: maxPages,
        ),
      );

      // Access elements spread across more than maxPages pages
      for (var i = 0; i < totalElements; i += elementsPerPage) {
        final _ = list[i];
      }

      // The cache must not exceed maxPages
      expect(list.stats.cachedPages, lessThanOrEqualTo(maxPages));

      await list.close();
    });
  });

  group('PageBuffer — dirty flush', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('mml_test_');
    });

    tearDown(() async {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await tmpDir.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    test('writes survive close and re-open', () async {
      const path_str = 'persist.mml'; // relative inside tmpDir
      final path = '${tmpDir.path}/$path_str';

      // Write
      final list = await MemoryMappedList.doubles(
        path: path,
        length: 100,
      );
      for (var i = 0; i < 100; i++) {
        list[i] = i.toDouble();
      }
      await list.close();

      // Re-read
      final list2 = await MemoryMappedList.doubles(
        path: path,
        length: 100,
        mode: AccessMode.readWrite,
      );
      for (var i = 0; i < 100; i++) {
        expect(list2[i], closeTo(i.toDouble(), 1e-9));
      }
      await list2.close();
    });

    test('batched flush writes after batchSize operations', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/batched.mml',
        length: 5000,
        flushMode: FlushMode.batched,
        batchSize: 1000,
      );

      for (var i = 0; i < 5000; i++) {
        list[i] = i.toDouble();
      }
      await list.close();

      final list2 = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/batched.mml',
        length: 5000,
        mode: AccessMode.readOnly,
      );
      expect(list2[4999], closeTo(4999.0, 1e-9));
      await list2.close();
    });
  });
}
