// ignore_for_file: avoid_print

/// example/scientific_analysis.dart
///
/// Demonstrates a realistic workflow: Z-score normalisation of a large
/// sensor dataset with anomaly detection.
///
/// The demo generates synthetic sensor data, normalises it, then identifies
/// readings that deviate by more than 3 standard deviations.
///
/// Run:
///   dart run example/scientific_analysis.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:memory_mapped_list/memory_mapped_list.dart';

Future<void> main() async {
  // ── Setup ────────────────────────────────────────────────────────────────
  const n = 500000; // 500 K readings = ~4 MB
  const rawPath = 'sensor_raw.mml';
  const normPath = 'sensor_normalized.mml';
  const anomalyCsvPath = 'anomalies.csv';

  _cleanUp([rawPath, normPath, anomalyCsvPath]);

  print('=== Scientific Sensor Analysis Demo ===');
  print('Elements: $n (${MmlMathUtils.humanReadableSize(n * 8)})');
  print('RAM cap:  ${MmlMathUtils.humanReadableSize(
    MmlMathUtils.bufferRamBytes(16 * 1024, 256),
  )} (constant)\n');

  // ── Phase 0: Generate synthetic sensor data ────────────────────────────
  print('[0/3] Generating synthetic sensor data …');
  final rng = math.Random(42);
  final raw = await MemoryMappedList.doubles(path: rawPath, length: n);

  for (var i = 0; i < n; i++) {
    // Normal readings: ~1000 ± 50, with rare spikes
    final noise = rng.nextGaussian() * 50;
    final spike = rng.nextDouble() < 0.001 ? (rng.nextDouble() * 1000) : 0.0;
    raw[i] = 1000.0 + noise + spike;
  }
  print('      Generated.\n');

  // ── Phase 1: Compute statistics in a single streaming pass ────────────
  print('[1/3] Computing statistics (Welford single-pass) …');
  final sw = Stopwatch()..start();

  var count = 0;
  var mean = 0.0;
  var m2 = 0.0;
  var minVal = double.infinity;
  var maxVal = double.negativeInfinity;

  await for (final chunk in raw.chunkedStream(chunkSize: 50000)) {
    for (final x in chunk) {
      count++;
      if (x < minVal) minVal = x;
      if (x > maxVal) maxVal = x;
      final delta = x - mean;
      mean += delta / count;
      m2 += delta * (x - mean);
    }
  }
  final variance = count > 1 ? m2 / (count - 1) : 0.0;
  final stdDev = math.sqrt(variance);

  sw.stop();
  print('      Time: ${sw.elapsedMilliseconds} ms');
  print('      Mean:   ${mean.toStringAsFixed(3)}');
  print('      StdDev: ${stdDev.toStringAsFixed(3)}');
  print('      Min:    ${minVal.toStringAsFixed(3)}');
  print('      Max:    ${maxVal.toStringAsFixed(3)}\n');

  // ── Phase 2: Z-score normalisation ────────────────────────────────────
  print('[2/3] Normalising (Z-score) …');
  sw
    ..reset()
    ..start();

  final normalised = await MemoryMappedList.doubles(path: normPath, length: n);
  var i = 0;
  await for (final chunk in raw.chunkedStream(chunkSize: 50000)) {
    await normalised.writeRange(
      i,
      chunk.map((x) => (x - mean) / stdDev),
    );
    i += chunk.length;
  }
  await normalised.flush();
  sw.stop();
  print('      Time: ${sw.elapsedMilliseconds} ms\n');

  // ── Phase 3: Anomaly detection |z| > 3 ───────────────────────────────
  print('[3/3] Detecting anomalies (|z| > 3) …');
  sw
    ..reset()
    ..start();

  final anomalyFile = File(anomalyCsvPath);
  final sink = anomalyFile.openWrite();
  sink.writeln('index,raw_value,z_score');

  var anomalyCount = 0;
  i = 0;
  await for (final z in normalised.stream) {
    if (z.abs() > 3.0) {
      final rawValue = raw[i];
      sink.writeln('$i,${rawValue.toStringAsFixed(4)},${z.toStringAsFixed(4)}');
      anomalyCount++;
    }
    i++;
  }
  await sink.close();
  sw.stop();

  print('      Time: ${sw.elapsedMilliseconds} ms');
  print('      Anomalies found: $anomalyCount '
      '(${(anomalyCount / n * 100).toStringAsFixed(2)} %)');
  print('      Saved to: $anomalyCsvPath');

  // ── Diagnostics ───────────────────────────────────────────────────────
  print('\n=== Buffer statistics ===');
  print('Raw list:  ${raw.stats}');
  print('Norm list: ${normalised.stats}');

  // ── Clean up ─────────────────────────────────────────────────────────
  await raw.close();
  await normalised.close();
  _cleanUp([rawPath, normPath, anomalyCsvPath]);

  print('\n✅  Analysis complete — RAM usage was constant throughout.');
}

void _cleanUp(List<String> paths) {
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) f.deleteSync();
  }
}

extension on math.Random {
  /// Box–Muller transform → standard normal sample.
  double nextGaussian() {
    final u1 = nextDouble();
    final u2 = nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  }
}
