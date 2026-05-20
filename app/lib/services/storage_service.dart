import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'service_models.dart';

/// Saves card image bytes to app-local storage and manages their lifecycle.
abstract interface class StorageService {
  /// Saves [bytes] under app-local storage and returns the absolute path.
  Future<String> saveCardImage(
    Uint8List bytes, {
    required ImageFormat format,
  });

  /// Deletes a previously saved image file.  No-op if the file does not exist.
  Future<void> deleteCardImage(String path);

  /// Deletes any image file under the card directory that is not in [validPaths].
  /// Returns the number of orphans removed.
  Future<int> cleanupOrphans(Set<String> validPaths);
}

class StorageServiceImpl implements StorageService {
  StorageServiceImpl({Directory? baseDirectoryOverride})
      : _baseOverride = baseDirectoryOverride;

  final Directory? _baseOverride;
  static const _subdir = 'card_images';
  static const _uuid = Uuid();

  Future<Directory> _cardsDir() async {
    final base = _baseOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> saveCardImage(
    Uint8List bytes, {
    required ImageFormat format,
  }) async {
    final dir = await _cardsDir();
    final ext = switch (format) {
      ImageFormat.jpeg => 'jpg',
      ImageFormat.webp => 'webp',
    };
    final path = p.join(dir.path, '${_uuid.v4()}.$ext');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> deleteCardImage(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<int> cleanupOrphans(Set<String> validPaths) async {
    // Refuse to delete anything if the caller passed an empty set.  An empty
    // set almost always indicates a bug (failed DB read, race condition) and
    // unguarded deletion would wipe every saved card image — the only copy.
    if (validPaths.isEmpty) {
      throw ArgumentError(
        'cleanupOrphans requires a non-empty validPaths set; '
        'pass the canonical list of in-use image paths first.',
      );
    }
    final dir = await _cardsDir();
    if (!await dir.exists()) return 0;
    int removed = 0;
    await for (final entity in dir.list()) {
      if (entity is File && !validPaths.contains(entity.path)) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }
}
