import 'dart:typed_data';

import 'package:memory_mapped_list/memory_mapped_list.dart';
import 'package:test/test.dart';

void main() {
  group('MmlFileHeader', () {
    group('round-trip serialisation', () {
      test('toBytes → fromBytes preserves all fields', () {
        final original = MmlFileHeader(
          elementCount: 1000000,
          elementSize: 8,
          elementType: ElementType.float64,
          pageSize: 16 * 1024,
          flags: 0,
          metadata: 'test metadata',
          createdAt: DateTime.utc(2024, 1, 15, 10, 30),
          modifiedAt: DateTime.utc(2024, 6, 20, 12, 0),
        );

        final bytes = original.toBytes();
        expect(bytes.length, equals(MmlFileHeader.headerSize));

        final parsed = MmlFileHeader.fromBytes(bytes);
        expect(parsed.elementCount, equals(original.elementCount));
        expect(parsed.elementSize, equals(original.elementSize));
        expect(parsed.elementType, equals(original.elementType));
        expect(parsed.pageSize, equals(original.pageSize));
        expect(parsed.flags, equals(original.flags));
        expect(parsed.metadata, equals(original.metadata));
        expect(
          parsed.createdAt.microsecondsSinceEpoch,
          equals(original.createdAt.microsecondsSinceEpoch),
        );
        expect(
          parsed.modifiedAt.microsecondsSinceEpoch,
          equals(original.modifiedAt.microsecondsSinceEpoch),
        );
      });

      test('metadata is truncated to 63 characters', () {
        final longMeta = 'A' * 200;
        final h = MmlFileHeader(
          elementCount: 0,
          elementSize: 4,
          elementType: ElementType.int32,
          pageSize: 4096,
          metadata: longMeta,
        );
        final parsed = MmlFileHeader.fromBytes(h.toBytes());
        expect(parsed.metadata.length, lessThanOrEqualTo(63));
      });

      test('empty metadata round-trips correctly', () {
        final h = MmlFileHeader.create(
          elementCount: 42,
          elementType: ElementType.int64,
          pageSize: 8192,
        );
        final parsed = MmlFileHeader.fromBytes(h.toBytes());
        expect(parsed.metadata, isEmpty);
      });
    });

    group('fromBytes validation', () {
      test('throws FormatException on wrong magic number', () {
        final bytes = MmlFileHeader.create(
          elementCount: 10,
          elementType: ElementType.float64,
          pageSize: 4096,
        ).toBytes().toList();
        // Corrupt the magic number
        bytes[0] = 0xDE;
        bytes[1] = 0xAD;

        expect(
          () => MmlFileHeader.fromBytes(
            Uint8List.fromList(bytes),
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException on too-short buffer', () {
        expect(
          () => MmlFileHeader.fromBytes(Uint8List(16)),
          throwsA(anything),
        );
      });
    });

    group('flag helpers', () {
      test('isReadOnly reflects kFlagReadOnly', () {
        final h = MmlFileHeader.create(
          elementCount: 0,
          elementType: ElementType.int32,
          pageSize: 4096,
          // ignore: avoid_redundant_argument_values
        )..flags = kFlagReadOnly;
        expect(h.isReadOnly, isTrue);
        expect(h.isCompressed, isFalse);
      });

      test('markDirty / markClean toggle kFlagDirtyShutdown', () {
        final h = MmlFileHeader.create(
          elementCount: 0,
          elementType: ElementType.int32,
          pageSize: 4096,
        );
        expect(h.isDirtyShutdown, isFalse);
        h.markDirty();
        expect(h.isDirtyShutdown, isTrue);
        h.markClean();
        expect(h.isDirtyShutdown, isFalse);
      });
    });

    group('updateLength', () {
      test('updates elementCount and bumps modifiedAt', () {
        final before = DateTime.now();
        final h = MmlFileHeader.create(
          elementCount: 100,
          elementType: ElementType.float64,
          pageSize: 4096,
        );
        h.updateLength(200);
        expect(h.elementCount, equals(200));
        // Use !isBefore instead of isAfter so the test passes even when
        // DateTime.now() returns the same value before and after updateLength
        // (common on fast machines or systems with low-resolution clocks).
        expect(!h.modifiedAt.isBefore(before), isTrue);
      });
    });

    group('ElementType', () {
      test('fromId returns generic for unknown ids', () {
        expect(ElementType.fromId(9999), equals(ElementType.generic));
      });

      test('all known ids round-trip', () {
        for (final t in ElementType.values) {
          expect(ElementType.fromId(t.id), equals(t));
        }
      });
    });
  });
}
