import 'dart:io';

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('mml_int32_test_');
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

  group('MmlInt32List', () {
    test('write and read back 32-bit values', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/i32.mml',
        length: 100,
      );
      for (var i = 0; i < 100; i++) list[i] = i;
      for (var i = 0; i < 100; i++) {
        expect(list[i], equals(i));
      }
      await list.close();
    });

    test('boundary values: INT32_MIN and INT32_MAX', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/boundary.mml',
        length: 2,
      );
      list[0] = -2147483648;
      list[1] = 2147483647;
      expect(list[0], equals(-2147483648));
      expect(list[1], equals(2147483647));
      await list.close();
    });

    test('negative values round-trip correctly', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/neg.mml',
        length: 5,
      );
      list[0] = -1;
      list[1] = -1000;
      list[2] = -2147483648;
      expect(list[0], equals(-1));
      expect(list[1], equals(-1000));
      expect(list[2], equals(-2147483648));
      await list.close();
    });

    test('sum of [0..N-1]', () async {
      const n = 100;
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/sum.mml',
        length: n,
      );
      for (var i = 0; i < n; i++) list[i] = i;
      expect(await list.sum(), equals(n * (n - 1) ~/ 2));
      await list.close();
    });

    test('minMax returns correct bounds', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/minmax.mml',
        length: 5,
      );
      list[0] = 5;
      list[1] = -3;
      list[2] = 100;
      list[3] = 0;
      list[4] = -100;
      final r = await list.minMax();
      expect(r.min, equals(-100));
      expect(r.max, equals(100));
      await list.close();
    });

    test('fill sets every element', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/fill.mml',
        length: 50,
      );
      await list.fill(99);
      for (var i = 0; i < 50; i++) {
        expect(list[i], equals(99));
      }
      await list.close();
    });

    test('isAllZeros returns true for new list', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/zeros.mml',
        length: 100,
      );
      expect(await list.isAllZeros(), isTrue);
      list[50] = 1;
      expect(await list.isAllZeros(), isFalse);
      await list.close();
    });

    test('ListMixin contains works', () async {
      final list = await MemoryMappedList.int32s(
        path: '${tmpDir.path}/contains.mml',
        length: 10,
      );
      for (var i = 0; i < 10; i++) list[i] = i * 10;
      expect(list.contains(50), isTrue);
      expect(list.contains(51), isFalse);
      await list.close();
    });
  });
}
