import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin abstraction over the `camera` package.
///
/// The actual camera preview widget lives on the frontend, but ownership of
/// the controller lifecycle (initialize / dispose) and permission gating is
/// a backend concern.
abstract interface class CameraService {
  /// Requests camera permission.  Returns true if granted.
  Future<bool> requestPermission();

  /// Initializes the first back-facing camera at medium resolution.
  Future<void> initialize();

  /// The underlying controller for the frontend to attach a `CameraPreview`.
  CameraController? get controller;

  /// Takes a still capture and returns the encoded bytes (JPEG).
  Future<Uint8List> captureStill();

  Future<void> dispose();
}

class CameraServiceImpl implements CameraService {
  CameraController? _controller;

  @override
  CameraController? get controller => _controller;

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _controller!.initialize();
  }

  @override
  Future<Uint8List> captureStill() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw StateError('Camera not initialized');
    }
    final file = await ctrl.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
