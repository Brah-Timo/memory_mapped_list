import 'dart:io';
import 'dart:math' as math;

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('mml_double_test_');
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

  group('MmlDoubleList — basic List operations', () {
    test('length returns correct value', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/len.mml',
        length: 500,
      );
      expect(list.length, equals(500));
      await list.close();
    });

    test('read / write round-trip', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/rw.mml',
        length: 256,
      );
      for (var i = 0; i < 256; i++) {
        list[i] = i * math.pi;
      }
      for (var i = 0; i < 256; i++) {
        expect(list[i], closeTo(i * math.pi, 1e-12));
      }
      await list.close();
    });

    test('special values: NaN, infinity, negative infinity', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/special.mml',
        length: 3,
      );
      list[0] = double.nan;
      list[1] = double.infinity;
      list[2] = double.negativeInfinity;

      expect(list[0].isNaN, isTrue);
      expect(list[1], equals(double.infinity));
      expect(list[2], equals(double.negativeInfinity));
      await list.close();
    });

    test('out-of-bounds throws RangeError', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/oob.mml',
        length: 10,
      );
      expect(() => list[-1], throwsRangeError);
      expect(() => list[10], throwsRangeError);
      await list.close();
    });

    test('ListMixin.where works correctly', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/where.mml',
        length: 10,
      );
      for (var i = 0; i < 10; i++) list[i] = i.toDouble();
      final evens = list.where((v) => v % 2 == 0).toList();
      expect(evens, equals([0.0, 2.0, 4.0, 6.0, 8.0]));
      await list.close();
    });

    test('ListMixin.map works correctly', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/map.mml',
        length: 5,
      );
      for (var i = 0; i < 5; i++) list[i] = i.toDouble();
      final squares = list.map((v) => v * v).toList();
      expect(squares, equals([0.0, 1.0, 4.0, 9.0, 16.0]));
      await list.close();
    });

    test('ListMixin.sort works correctly', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/sort.mml',
        length: 5,
      );
      list[0] = 3.0;
      list[1] = 1.0;
      list[2] = 4.0;
      list[3] = 1.0;
      list[4] = 5.0;
      list.sort();
      expect(list[0], equals(1.0));
      expect(list[4], equals(5.0));
      await list.close();
    });
  });

  group('MmlDoubleList — streaming aggregates', () {
    test('sum of [0..N-1]', () async {
      const n = 1000;
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/sum.mml',
        length: n,
      );
      for (var i = 0; i < n; i++) list[i] = i.toDouble();
      // Expected sum = n*(n-1)/2
      expect(await list.sum(), closeTo(n * (n - 1) / 2, 1e-6));
      await list.close();
    });

    test('mean of [0..N-1]', () async {
      const n = 100;
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/mean.mml',
        length: n,
      );
      for (var i = 0; i < n; i++) list[i] = i.toDouble();
      expect(await list.mean(), closeTo((n - 1) / 2, 1e-9));
      await list.close();
    });

    test('minMax returns correct bounds', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/minmax.mml',
        length: 5,
      );
      list[0] = -10.0;
      list[1] = 5.0;
      list[2] = 0.0;
      list[3] = 100.0;
      list[4] = -50.0;
      final r = await list.minMax();
      expect(r.min, equals(-50.0));
      expect(r.max, equals(100.0));
      await list.close();
    });

    test('standardDeviation of constant list is 0', () async {
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/stddev0.mml',
        length: 100,
      );
      await list.fill(42.0);
      expect(await list.standardDeviation(), closeTo(0.0, 1e-9));
      await list.close();
    });

    test('stream yields all elements', () async {
      const n = 50;
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/stream.mml',
        length: n,
      );
      for (var i = 0; i < n; i++) list[i] = i.toDouble();
      final collected = await list.stream.toList();
      expect(collected.length, equals(n));
      expect(collected[49], closeTo(49.0, 1e-9));
      await list.close();
    });

    test('chunkedStream covers every element exactly once', () async {
      const n = 250;
      final list = await MemoryMappedList.doubles(
        path: '${tmpDir.path}/chunked.mml',
        length: n,
      );
      for (var i = 0; i < n; i++) list[i] = i.toDouble();
      var count = 0;
      await for (final chunk in list.chunkedStream(chunkSize: 100)) {
        count += chunk.length;
      }
      expect(count, equals(n));
      await list.close();
    });
  });

  group('MmlDoubleList — persistence', () {
    test('re-opened list has same data', () async {
      final path = '${tmpDir.path}/reopen.mml';
      {
        final list = await MemoryMappedList.doubles(path: path, length: 20);
        for (var i = 0; i < 20; i++) list[i] = i * 1.5;
        await list.close();
      }
      final list2 = await MemoryMappedList.doubles(
        path: path,
        length: 20,
        mode: AccessMode.readOnly,
      );
      for (var i = 0; i < 20; i++) {
        expect(list2[i], closeTo(i * 1.5, 1e-9));
      }
      await list2.close();
    });
  });
}
