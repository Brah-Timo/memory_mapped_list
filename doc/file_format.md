# `.mml` File Format Specification

Version: **1**  
Magic: `0x4D4D4C01` ("MML\x01")

---

## Overview

A `.mml` file consists of:

1. A fixed **128-byte header** at offset 0 containing metadata.
2. A variable-length **data region** starting at offset 128 holding
   element bytes packed sequentially in little-endian byte order.

For `MmlGenericList` (variable-length elements) a companion **`.mml.idx` index
file** stores per-element byte offsets into the data region.

---

## Header layout

All multi-byte integers are stored **little-endian**.

```
Offset  Bytes  Type    Field
──────  ─────  ──────  ─────────────────────────────────────────────────────
  0      4     uint32  Magic number: 0x4D4D4C01
  4      4     uint32  Format version: 1
  8      8     int64   Element count
 16      4     int32   Element size in bytes (−1 for generic/variable)
 20      4     int32   Element type ID (see table below)
 24      8     int64   Created-at: microseconds since Unix epoch (UTC)
 32      8     int64   Modified-at: microseconds since Unix epoch (UTC)
 40      4     int32   Page size used at file creation
 44      4     int32   Flags bitmask
 48     64     bytes   UTF-8 metadata string, NUL-terminated, max 63 chars
112     16     bytes   Reserved — always zero
128            …       *** DATA STARTS HERE ***
```

Total header size: **128 bytes** (`MmlFileHeader.headerSize`).

---

## Element type IDs

| ID | Dart type | Element size | `ElementType` |
|----|-----------|-------------|---------------|
| 1  | `int` | 4 bytes | `ElementType.int32` |
| 2  | `int` | 8 bytes | `ElementType.int64` |
| 3  | `double` | 4 bytes | `ElementType.float32` |
| 4  | `double` | 8 bytes | `ElementType.float64` |
| 99 | `T` | variable | `ElementType.generic` |

Unknown IDs are mapped to `ElementType.generic` for forward compatibility.

---

## Flag bitmask

| Bit | Constant | Meaning |
|-----|----------|---------|
| 0 (0x01) | `kFlagReadOnly` | File was created with read-only intent |
| 1 (0x02) | `kFlagCompressed` | Data is compressed (reserved, never set) |
| 2 (0x04) | `kFlagDirtyShutdown` | File was not closed cleanly |

The `kFlagDirtyShutdown` bit is set when a write session begins and cleared
when the file is closed cleanly.  If a process crashes between writes and
`close()`, the bit remains set on the next open, signalling that the data
may be partially written.

---

## Data region layout

### Fixed-size types (int32, int64, float32, float64)

Elements are packed consecutively at their natural alignment:

```
Offset = 128 + index × elementSize
```

File size = `128 + elementCount × elementSize`

### Generic type

The data region holds variable-length serialized blobs concatenated without
delimiters.  The companion `.mml.idx` file maps each element index to its
start offset in the data region.

`.mml.idx` layout:
```
Offset = index × 8
Value  = int64 LE  →  byte offset in the .mml data region
```

---

## Validation rules

A `.mml` file is **valid** if:
1. `bytes[0..3]` == `0x4D4D4C01` (magic number)
2. `version` ≤ 1 (supported version)
3. File length ≥ 128 (header present)
4. For fixed-size types: file length == `128 + elementCount × elementSize`

---

## Example: hexdump of a 3-element float64 file

```
Offset  Hex                                      ASCII
──────  ───────────────────────────────────────  ────────────────
00000   4D 4D 4C 01  01 00 00 00  03 00 00 00    MML.............
00012   00 00 00 00  04 00 00 00  04 00 00 00    ................
00024   ...timestamps, pageSize, flags, metadata...
00128   00 00 00 00 00 00 00 00                  element 0: 0.0
00136   9A 99 99 99 99 99 F1 3F                  element 1: 1.1
00144   9A 99 99 99 99 99 01 40                  element 2: 2.2
```

---

## Backwards compatibility

- Files written by `memory_mapped_list` 0.1.x can be read by future versions
  as long as the format version field remains 1.
- Future versions that introduce breaking format changes **must** increment
  the version field.  The parser rejects files with `version > 1` with a
  `FormatException`.
- The 16 reserved bytes at offset 112 are available for future metadata
  extensions without changing the format version.

---

## Reading a `.mml` file without this library

```dart
import 'dart:io';
import 'dart:typed_data';

Future<void> readMml(String path) async {
  final bytes = await File(path).readAsBytes();
  final bd = ByteData.sublistView(bytes);

  final magic   = bd.getUint32(0,  Endian.little); // 0x4D4D4C01
  final count   = bd.getInt64(8,   Endian.little);
  final eltSize = bd.getInt32(16,  Endian.little);
  final typeId  = bd.getInt32(20,  Endian.little);

  const headerSize = 128;
  for (var i = 0; i < count; i++) {
    final offset = headerSize + i * eltSize;
    if (typeId == 4) {                               // float64
      final value = bd.getFloat64(offset, Endian.little);
      print('[$i] = $value');
    }
  }
}
```
