import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Launches an external camera app (Android chooser when multiple camera-capable
/// apps are installed) and returns the captured image's file path.
///
/// On iOS this is a no-op (returns null) — iOS does not allow third-party
/// camera choosers via standard intents.  Frontend should hide the "外部カメラ
/// で撮影" option on iOS so users aren't surprised.
abstract interface class ExternalCameraService {
  /// Returns the captured image's file path, or null when the user cancelled
  /// or the platform doesn't support external cameras.
  Future<String?> capture();

  /// Whether this service can launch an external camera on the current
  /// platform.  Used by UI to decide whether to show the option.
  bool get isSupported;
}

/// Production implementation backed by [ImagePicker].
class ExternalCameraServiceImpl implements ExternalCameraService {
  ExternalCameraServiceImpl({ImagePicker? picker, bool? isIos})
      : _picker = picker ?? ImagePicker(),
        _isIos = isIos ?? Platform.isIOS;

  final ImagePicker _picker;
  final bool _isIos;

  @override
  bool get isSupported => !_isIos;

  @override
  Future<String?> capture() async {
    if (_isIos) return null;
    final picked = await _picker.pickImage(source: ImageSource.camera);
    return picked?.path;
  }
}
