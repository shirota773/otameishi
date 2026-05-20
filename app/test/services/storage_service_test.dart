import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/services/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;
  late StorageServiceImpl service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('otameishi_storage_test_');
    service = StorageServiceImpl(baseDirectoryOverride: tmpDir);
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('saveCardImage writes bytes and returns a real path', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final path = await service.saveCardImage(bytes, format: ImageFormat.jpeg);
    expect(await File(path).exists(), isTrue);
    expect(await File(path).readAsBytes(), bytes);
  });

  test('jpeg extension', () async {
    final path = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    expect(p.extension(path), '.jpg');
  });

  test('webp extension', () async {
    final path = await service.saveCardImage(Uint8List(4), format: ImageFormat.webp);
    expect(p.extension(path), '.webp');
  });

  test('files land under <base>/card_images/', () async {
    final path = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    expect(p.dirname(path), endsWith('card_images'));
  });

  test('deleteCardImage removes the file', () async {
    final path = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    await service.deleteCardImage(path);
    expect(await File(path).exists(), isFalse);
  });

  test('deleteCardImage on missing path is a no-op', () async {
    await service.deleteCardImage(p.join(tmpDir.path, 'missing.jpg'));
  });

  test('cleanupOrphans removes files not in valid set', () async {
    final keep = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    final orphan = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);

    final removed = await service.cleanupOrphans({keep});

    expect(removed, 1);
    expect(await File(keep).exists(), isTrue);
    expect(await File(orphan).exists(), isFalse);
  });

  test('cleanupOrphans rejects empty validPaths to prevent accidental wipe', () async {
    await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    expect(() => service.cleanupOrphans({}), throwsArgumentError);
  });

  test('multiple saves produce unique paths', () async {
    final p1 = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    final p2 = await service.saveCardImage(Uint8List(4), format: ImageFormat.jpeg);
    expect(p1, isNot(p2));
  });
}
