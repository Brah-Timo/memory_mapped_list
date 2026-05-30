// ignore_for_file: avoid_print

/// example/log_processor.dart
///
/// Demonstrates storing and querying structured data (log entries) using
/// [MmlGenericList] with a [JsonSerializer].
///
/// Run:
///   dart run example/log_processor.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:memory_mapped_list/memory_mapped_list.dart';

// ── Domain model ─────────────────────────────────────────────────────────────

enum LogLevel { debug, info, warning, error, critical }

class LogEntry {
  final int timestampUs; // microseconds since epoch
  final LogLevel level;
  final String service;
  final String message;

  const LogEntry({
    required this.timestampUs,
    required this.level,
    required this.service,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestampUs,
        'lvl': level.index,
        'svc': service,
        'msg': message,
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        timestampUs: j['ts'] as int,
        level: LogLevel.values[j['lvl'] as int],
        service: j['svc'] as String,
        message: j['msg'] as String,
      );

  @override
  String toString() =>
      '[${level.name.toUpperCase().padRight(8)}] '
      '${DateTime.fromMicrosecondsSinceEpoch(timestampUs).toIso8601String()} '
      '$service — $message';
}


// ── Main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  const path = 'logs.mml';
  const n = 1000;
  _cleanUp(path);

  print('=== Log Processor Demo (MmlGenericList<LogEntry>) ===\n');

  // 1. Create a generic list with a JSON serializer
  final serializer = JsonSerializer<LogEntry>(
    fromJson: LogEntry.fromJson,
    toJson: (e) => e.toJson(),
  );

  final logs = await MemoryMappedList.generic<LogEntry>(
    path: path,
    length: n,
    serializer: serializer,
  );

  // 2. Write 1 000 synthetic log entries
  print('[1/3] Writing $n log entries …');
  final rng = math.Random(0);
  final services = ['auth', 'gateway', 'db', 'cache', 'scheduler'];
  final messages = [
    'Request received',
    'Connection timeout',
    'Cache miss',
    'Query executed in 12 ms',
    'Health check passed',
    'Retrying failed request',
    'Disk usage at 80 %',
    'Token refresh succeeded',
  ];

  final baseTs = DateTime(2024, 1, 1).microsecondsSinceEpoch;
  for (var i = 0; i < n; i++) {
    final level = LogLevel.values[rng.nextInt(LogLevel.values.length)];
    logs[i] = LogEntry(
      timestampUs: baseTs + i * 1000000, // one entry per second
      level: level,
      service: services[rng.nextInt(services.length)],
      message: messages[rng.nextInt(messages.length)],
    );
  }
  await logs.flush();
  print('      Written.\n');

  // 3. Query: count entries by level
  print('[2/3] Counting by log level …');
  final counts = Map.fromEntries(
    LogLevel.values.map((l) => MapEntry(l, 0)),
  );
  await for (final chunk in logs.chunkedStream(chunkSize: 100)) {
    for (final entry in chunk) {
      counts[entry.level] = (counts[entry.level] ?? 0) + 1;
    }
  }
  for (final e in counts.entries) {
    print('      ${e.key.name.padRight(10)}: ${e.value}');
  }

  // 4. Query: find first 5 ERROR+ entries
  print('\n[3/3] First 5 error/critical entries:');
  var found = 0;
  await for (final entry in logs.stream) {
    if (entry.level == LogLevel.error || entry.level == LogLevel.critical) {
      print('      $entry');
      found++;
      if (found >= 5) break;
    }
  }

  await logs.close();
  print('\n✅  Log processor done.');
  _cleanUp(path);
}

void _cleanUp(String path) {
  for (final p in [path, '$path.idx']) {
    final f = File(p);
    if (f.existsSync()) f.deleteSync();
  }
}
