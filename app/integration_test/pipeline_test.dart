import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:otameishi/core/providers.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/usecases/save_card_usecase.dart';

/// End-to-end pipeline test that exercises:
///   • CaptureCardUseCase  (perspective correction + denoise + encode + save + OCR)
///   • SaveCardUseCase     (DB insert with tags)
///   • CardRepository.findAll (verify persistence)
///
/// Test images are bundled as Flutter assets under `assets/test_fixtures/`.
const _fixtureAssets = <String>[
  'assets/test_fixtures/20260518_003258.jpg',
  'assets/test_fixtures/20260518_003330.jpg',
  'assets/test_fixtures/20260518_003337.jpg',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  testWidgets('runs full capture pipeline on each test fixture', (tester) async {
    final captureUseCase = container.read(captureCardUseCaseProvider);
    final saveUseCase = await container.read(saveCardUseCaseProvider.future);
    final cardRepo = await container.read(cardRepositoryProvider.future);

    final initialCount =
        (await cardRepo.findAll(sortBy: CardSortBy.createdAt)).length;

    for (final asset in _fixtureAssets) {
      final basename = p.basename(asset);
      // ignore: avoid_print
      print('\n=== Fixture: $basename ===');
      final stopwatch = Stopwatch()..start();

      final bytes = await _loadAsset(asset);
      // ignore: avoid_print
      print('  source bytes  : ${bytes.lengthInBytes}');

      final draft = await captureUseCase.execute(bytes);

      final correctedFile = File(draft.imagePath);
      expect(correctedFile.existsSync(), isTrue,
          reason: 'corrected image not saved for $basename');
      expect(correctedFile.lengthSync(), greaterThan(0),
          reason: 'corrected image is empty for $basename');

      // Also copy the corrected JPEG into the app's external dir so the
      // host can pull it for visual inspection via `adb pull`.
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final outDir = Directory(p.join(externalDir.path, 'corrected_output'));
        if (!outDir.existsSync()) outDir.createSync(recursive: true);
        final destPath = p.join(outDir.path, 'corrected_$basename');
        await correctedFile.copy(destPath);
        // ignore: avoid_print
        print('  pull-out path : $destPath');
      }

      // ignore: avoid_print
      print('  saved → ${draft.imagePath}');
      // ignore: avoid_print
      print('  size  → ${correctedFile.lengthSync()} bytes');

      final ocr = draft.ocr;
      final extracted = draft.extractedData;

      if (ocr != null) {
        // ignore: avoid_print
        print('  OCR lines (${ocr.lines.length}):');
        for (final line in ocr.lines) {
          // ignore: avoid_print
          print('    │ $line');
        }
      } else {
        // ignore: avoid_print
        print('  OCR: <null>');
      }

      if (extracted != null) {
        // ignore: avoid_print
        print('  xHandles      : ${extracted.xHandles}');
        // ignore: avoid_print
        print('  urls          : ${extracted.urls}');
        // ignore: avoid_print
        print('  nameCandidate : ${extracted.nameCandidate}');
      }

      // Save into DB; tag it so we can see which fixture flowed through.
      final saved = await saveUseCase.execute(
        SaveCardInput(draft: draft, tagNames: const ['integration-test']),
      );
      expect(saved.id, isNotEmpty);

      // ignore: avoid_print
      print('  card.id       : ${saved.id}');
      // ignore: avoid_print
      print('  elapsed (ms)  : ${stopwatch.elapsedMilliseconds}');
    }

    final allCards = await cardRepo.findAll(sortBy: CardSortBy.createdAt);
    expect(allCards.length, initialCount + _fixtureAssets.length,
        reason: 'expected ${_fixtureAssets.length} new cards in DB');

    // ignore: avoid_print
    print('\n=== Summary ===');
    // ignore: avoid_print
    print('  fixtures processed: ${_fixtureAssets.length}');
    // ignore: avoid_print
    print('  cards in DB now   : ${allCards.length}');

    // Print where the corrected images live so we can pull them with adb.
    final docDir = await getApplicationDocumentsDirectory();
    // ignore: avoid_print
    print('  app docs dir      : ${docDir.path}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<Uint8List> _loadAsset(String path) async {
  final byteData = await rootBundle.load(path);
  return byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
}
