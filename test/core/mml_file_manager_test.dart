import 'dart:io';

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

// We test MmlFileManager indirectly through MmlDoubleList to avoid
// reaching into internal APIs.  Direct unit tests verify I/O correctness.

void main() {
  group('MmlFileManager — via MmlDoubleList', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('mml_fm_test_');
    });

    tearDown(() async {
      // On Windows, file handles may be released asynchronously after close().
      // Retry the deletion a few times with a short delay.
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await tmpDir.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    test('create produces correct file size', () async {
      const n = 1000;
      final path = '${tmpDir.path}/size_check.mml';
      final list = await MemoryMappedList.doubles(path: path, length: n);
      await list.close();

      final file = File(path);
      expect(
        file.lengthSync(),
        equals(MmlFileHeader.headerSize + n * 8),
      );
    });

    test('open non-existent file throws MmlFileNotFoundException', () async {
      expect(
        () => MemoryMappedList.doubles(
          path: '${tmpDir.path}/does_not_exist.mml',
          length: 100,
          mode: AccessMode.readOnly,
        ),
        throwsA(isA<MmlFileNotFoundException>()),
      );
    });

    test('write then sync persists data', () async {
      final path = '${tmpDir.path}/sync_test.mml';
      final list = await MemoryMappedList.doubles(path: path, length: 10);
      list[5] = 123.456;
      await list.flush(); // explicit sync
      await list.close();

      final list2 = await MemoryMappedList.doubles(
        path: path,
        length: 10,
        mode: AccessMode.readOnly,
      );
      expect(list2[5], closeTo(123.456, 1e-9));
      await list2.close();
    });

    test('expandFile grows the backing file', () async {
      const initial = 100;
      const expanded = 500;
      final path = '${tmpDir.path}/expand.mml';

      final list = await MemoryMappedList.doubles(
        path: path,
        length: initial,
      );
      await list.close();

      final list2 = await MemoryMappedList.doubles(
        path: path,
        length: initial,
        mode: AccessMode.readWrite,
      )
        ..length = expanded; // triggers expandFile
      expect(list2.length, equals(expanded));
      await list2.close();

      expect(
        File(path).lengthSync(),
        greaterThanOrEqualTo(MmlFileHeader.headerSize + expanded * 8),
      );
    });

    test('readOnly prevents writes', () async {
      final path = '${tmpDir.path}/ro.mml';
      final list = await MemoryMappedList.doubles(path: path, length: 10);
      await list.close();

      final ro = await MemoryMappedList.doubles(
        path: path,
        length: 10,
        mode: AccessMode.readOnly,
      );
      expect(
        () => ro[0] = 1.0,
        throwsA(isA<MmlReadOnlyException>()),
      );
      await ro.close();
    });

    test('operations on closed list throw MmlClosedException', () async {
      final path = '${tmpDir.path}/closed.mml';
      final list = await MemoryMappedList.doubles(path: path, length: 10);
      await list.close();

      expect(() => list[0], throwsA(isA<MmlClosedException>()));
      expect(() => list[0] = 1.0, throwsA(isA<MmlClosedException>()));
    });
  });
}
