// Test-mode entry point: runs the capture pipeline on the bundled test
// fixtures, copies corrected JPEGs to the app's external dir so the host can
// pull them via `adb pull`, then shows a Done screen.
//
// Run with:
//   flutter run -t tool/main_pipeline_dump.dart -d emulator-5554
//
// Then pull with:
//   adb pull /sdcard/Android/data/com.otameishi.otameishi/files/corrected_output \
//     test_output/corrected

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:otameishi/core/providers.dart';
import 'package:otameishi/usecases/save_card_usecase.dart';

const _fixtureAssets = <String>[
  'assets/test_fixtures/20260518_003258.jpg',
  'assets/test_fixtures/20260518_003330.jpg',
  'assets/test_fixtures/20260518_003337.jpg',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _PipelineDumpApp()));
}

class _PipelineDumpApp extends StatelessWidget {
  const _PipelineDumpApp();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: _PipelineDumpScreen());
}

class _PipelineDumpScreen extends ConsumerStatefulWidget {
  const _PipelineDumpScreen();

  @override
  ConsumerState<_PipelineDumpScreen> createState() => _PipelineDumpScreenState();
}

class _PipelineDumpScreenState extends ConsumerState<_PipelineDumpScreen> {
  final _log = <String>[];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    setState(() => _log.add(line));
  }

  Future<void> _run() async {
    try {
      final captureUseCase = ref.read(captureCardUseCaseProvider);
      final saveUseCase = await ref.read(saveCardUseCaseProvider.future);

      final externalDir = await getExternalStorageDirectory();
      final outDir = Directory(p.join(externalDir!.path, 'corrected_output'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      for (final asset in _fixtureAssets) {
        final basename = p.basename(asset);
        _say('--- $basename');

        final bytes = await _loadAsset(asset);
        final draft = await captureUseCase.execute(bytes);

        final correctedFile = File(draft.imagePath);
        final destPath = p.join(outDir.path, 'corrected_$basename');
        await correctedFile.copy(destPath);
        _say('  corrected → $destPath  (${correctedFile.lengthSync()} B)');

        if (draft.ocr != null) {
          _say('  OCR lines: ${draft.ocr!.lines.length}');
        }

        await saveUseCase.execute(
          SaveCardInput(draft: draft, tagNames: const ['pipeline-dump']),
        );
      }
      _say('=== DONE ===');
      _say('pull dir: ${outDir.path}');
    } catch (e, st) {
      _say('ERROR: $e');
      _say(st.toString());
    } finally {
      if (mounted) setState(() => _done = true);
    }
  }

  Future<Uint8List> _loadAsset(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_done ? 'Done' : 'Running…')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _log.length,
          itemBuilder: (_, i) => Text(
            _log[i],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
