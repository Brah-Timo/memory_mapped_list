/// Integration tests that exercise the full stack with realistically-sized
/// files.
///
/// These tests are tagged `@Tags(['integration'])` and skipped during regular
/// `dart test` runs.  Run them explicitly with:
///
///   dart test --tags integration
///
/// They create temporary files up to ~10 MB so they complete in a few seconds
/// on any modern SSD.

@Tags(['integration'])
library;

import 'dart:io';

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('mml_integration_');
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

  group('Large file — doubles', () {
    const n = 1000000; // 1 million elements = ~8 MB

    test('write 1 M doubles and read back', () async {
      final path = '${tmpDir.path}/large.mml';
      final list = await MemoryMappedList.doubles(
        path: path,
        length: n,
        bufferConfig: PageBufferConfig.large(),
      );

      for (var i = 0; i < n; i++) {
        list[i] = i.toDouble();
      }
      await list.flush();

      // Spot-check
      expect(list[0], closeTo(0.0, 1e-9));
      expect(list[n ~/ 2], closeTo((n ~/ 2).toDouble(), 1e-9));
      expect(list[n - 1], closeTo((n - 1).toDouble(), 1e-9));

      final stats = list.stats;
      expect(stats.totalElements, equals(n));
      expect(stats.fileSizeBytes, greaterThan(n * 8));

      await list.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('streaming sum over 1 M elements', () async {
      final path = '${tmpDir.path}/sum.mml';
      final list = await MemoryMappedList.doubles(path: path, length: n);

      for (var i = 0; i < n; i++) {
        list[i] = 1.0;
      }

      expect(await list.sum(), closeTo(n.toDouble(), 1.0));
      await list.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('LRU cache hit rate > 90 % for sequential scan', () async {
      final path = '${tmpDir.path}/hitrate.mml';
      final list = await MemoryMappedList.doubles(
        path: path,
        length: n,
        bufferConfig: PageBufferConfig.defaultConfig(),
      );

      // Sequential write
      for (var i = 0; i < n; i++) list[i] = i * 0.001;

      // Sequential read — almost all accesses should hit the same pages
      var accum = 0.0;
      for (var i = 0; i < n; i++) accum += list[i];
      expect(accum, isPositive);

      expect(list.stats.hitRate, greaterThan(0.9));
      await list.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Large file — int32s', () {
    const n = 2000000;

    test('write and re-open 2 M int32 values', () async {
      final path = '${tmpDir.path}/large_i32.mml';
      {
        final list = await MemoryMappedList.int32s(path: path, length: n);
        for (var i = 0; i < n; i++) list[i] = i;
        await list.close();
      }
      final list2 = await MemoryMappedList.int32s(
        path: path,
        length: n,
        mode: AccessMode.readOnly,
      );
      expect(list2[n - 1], equals(n - 1));
      expect(list2[n ~/ 3], equals(n ~/ 3));
      await list2.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Mixed read/write + resize', () {
    test('resize list from 100 to 500 elements', () async {
      final path = '${tmpDir.path}/resize.mml';
      final list = await MemoryMappedList.doubles(path: path, length: 100);
      for (var i = 0; i < 100; i++) list[i] = i.toDouble();

      // Grow
      list.length = 500;
      for (var i = 100; i < 500; i++) list[i] = i.toDouble();

      await list.flush();
      expect(list.length, equals(500));
      expect(list[499], closeTo(499.0, 1e-9));
      await list.close();
    });
  });

  group('Streaming API', () {
    test('writeRange fills a range then stream reads it back', () async {
      const n = 10000;
      final path = '${tmpDir.path}/writerange.mml';
      final list = await MemoryMappedList.doubles(path: path, length: n);

      // Write even indices
      final values =
          List<double>.generate(n ~/ 2, (i) => i.toDouble());
      await list.writeRange(0, values);

      // Read back via stream
      final first500 =
          await list.stream.take(500).toList();
      expect(first500.length, equals(500));
      expect(first500[0], closeTo(0.0, 1e-9));
      await list.close();
    });
  });

  group('Concurrent access simulation', () {
    test('multiple lists can be open simultaneously on different files',
        () async {
      final lists = await Future.wait([
        for (var i = 0; i < 5; i++)
          MemoryMappedList.doubles(
            path: '${tmpDir.path}/concurrent_$i.mml',
            length: 1000,
          ),
      ]);

      for (var li = 0; li < lists.length; li++) {
        for (var j = 0; j < 1000; j++) {
          lists[li][j] = (li * 1000 + j).toDouble();
        }
      }

      for (var li = 0; li < lists.length; li++) {
        expect(lists[li][500], closeTo((li * 1000 + 500).toDouble(), 1e-9));
      }

      await Future.wait(lists.map((l) => l.close()));
    });
  });
}
