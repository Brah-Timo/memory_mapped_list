import 'dart:io';

/// Creates a temporary file path inside [dir].
///
/// The file is **not** created on disk; the returned path can be passed
/// directly to [MemoryMappedList] factories.
String tempPath(Directory dir, String name) => '${dir.path}/$name';

/// Deletes [file] if it exists.  Silently ignores missing files.
void safeDelete(String path) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  // Also delete the companion index file for generic lists
  final idx = File('$path.idx');
  if (idx.existsSync()) idx.deleteSync();
}
