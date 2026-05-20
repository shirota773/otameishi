import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../services/service_models.dart';
import '../theme/app_theme.dart';

/// Camera capture screen.  Initializes the camera service on entry, runs the
/// capture pipeline on shutter tap, and navigates to the review screen.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  bool _initializing = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cam = ref.read(cameraServiceProvider);
    try {
      final granted = await cam.requestPermission();
      if (!granted) {
        setState(() {
          _initializing = false;
          _error = 'カメラの許可が必要です';
        });
        return;
      }
      await cam.initialize();
    } catch (e) {
      setState(() {
        _initializing = false;
        _error = 'カメラを起動できませんでした';
      });
      return;
    }
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _shoot() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final cam = ref.read(cameraServiceProvider);
      final bytes = await cam.captureStill();
      await _process(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _error = '撮影に失敗しました';
        });
      }
    }
  }

  Future<void> _process(Uint8List bytes) async {
    final useCase = ref.read(captureCardUseCaseProvider);
    final draft = await useCase.execute(bytes);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/capture/review', arguments: draft);
  }

  @override
  Widget build(BuildContext context) {
    final cam = ref.watch(cameraServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initializing)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('戻る'),
                      ),
                    ],
                  ),
                ),
              )
            else if (cam.controller != null && cam.controller!.value.isInitialized)
              Positioned.fill(child: CameraPreview(cam.controller!))
            else
              const Center(child: Text('カメラ未対応', style: TextStyle(color: Colors.white))),

            // Top bar
            Positioned(
              top: AppSpacing.s4,
              left: AppSpacing.s4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),

            // Shutter
            if (!_initializing && _error == null)
              Positioned(
                bottom: AppSpacing.s10,
                left: 0,
                right: 0,
                child: Center(child: _ShutterButton(busy: _processing, onTap: _shoot)),
              ),

            if (_processing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x88000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: AppSpacing.s4),
                        Text('解析中…', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '撮影',
      button: true,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandPrimaryLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Make CardDraft visible to other screens via this re-export — keeps imports tidy.
class CaptureScreenArgs {
  final CardDraft draft;
  const CaptureScreenArgs(this.draft);
}
