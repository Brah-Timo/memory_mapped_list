// ignore_for_file: avoid_print

/// example/basic_usage.dart
///
/// Demonstrates the minimal API surface of memory_mapped_list.
///
/// Run:
///   dart run example/basic_usage.dart

import 'dart:io';

import 'package:memory_mapped_list/memory_mapped_list.dart';

Future<void> main() async {
  // Ensure we clean up the demo file at the end
  const path = 'basic_demo.mml';
  _cleanUp(path);

  // ─────────────────────────────────────────────────────────────────────────
  print('=== memory_mapped_list — Basic Usage Demo ===\n');

  // 1. Create a list of 1 million doubles — only ~4 MB of RAM used.
  //    The actual data lives in `basic_demo.mml` on disk.
  print('[1/6] Creating list with 1,000,000 doubles …');
  final list = await MemoryMappedList.doubles(
    path: path,
    length: 1000000,
    bufferConfig: PageBufferConfig.defaultConfig(),
  );
  print('      File size: ${MmlMathUtils.humanReadableSize(list.fileSizeBytes)}');
  print('      RAM cache: ${MmlMathUtils.humanReadableSize(
    MmlMathUtils.bufferRamBytes(
      PageBufferConfig.defaultConfig().pageSize,
      PageBufferConfig.defaultConfig().maxPages,
    ),
  )} (constant!)');

  // ─────────────────────────────────────────────────────────────────────────
  print('\n[2/6] Writing values — works exactly like a normal List …');
  final sw = Stopwatch()..start();
  for (var i = 0; i < list.length; i++) {
    list[i] = i * 0.001;
  }
  sw.stop();
  print('      Wrote ${list.length} elements in ${sw.elapsedMilliseconds} ms');

  // ─────────────────────────────────────────────────────────────────────────
  print('\n[3/6] Reading values …');
  print('      list[0]       = ${list[0]}');
  print('      list[500000] = ${list[500000]}');
  print('      list[999999] = ${list[999999]}');

  // ─────────────────────────────────────────────────────────────────────────
  print('\n[4/6] Standard List operations (sort, where, map, …)');
  // Sublist from indices 0-9
  final first10 = list.sublist(0, 10);
  print('      sublist(0,10) = ${first10.map((v) => v.toStringAsFixed(3)).toList()}');

  // indexOf
  final idx = list.indexOf(5.0);
  print('      indexOf(5.0)  = $idx');

  // ─────────────────────────────────────────────────────────────────────────
  print('\n[5/6] Streaming aggregates (O(1) RAM regardless of file size) …');
  final mean = await list.mean();
  final stdev = await list.standardDeviation();
  final bounds = await list.minMax();
  print('      mean          = ${mean.toStringAsFixed(4)}');
  print('      std dev       = ${stdev.toStringAsFixed(4)}');
  print('      min           = ${bounds.min}');
  print('      max           = ${bounds.max.toStringAsFixed(3)}');

  // ─────────────────────────────────────────────────────────────────────────
  print('\n[6/6] Diagnostics …');
  print(list.stats);

  // Always close to flush pending writes and release the file descriptor.
  await list.close();
  print('\n✅ Done!  File released.');

  _cleanUp(path);
}

void _cleanUp(String path) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
}
