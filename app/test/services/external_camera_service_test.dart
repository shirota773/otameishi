import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otameishi/services/external_camera_service.dart';

class _MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late _MockImagePicker picker;

  setUp(() {
    picker = _MockImagePicker();
  });

  test('iOS: capture returns null and isSupported is false', () async {
    final s = ExternalCameraServiceImpl(picker: picker, isIos: true);
    expect(s.isSupported, isFalse);
    expect(await s.capture(), isNull);
    verifyNever(() => picker.pickImage(source: ImageSource.camera));
  });

  test('Android: capture returns the picked file path', () async {
    when(() => picker.pickImage(source: ImageSource.camera))
        .thenAnswer((_) async => XFile('/tmp/external.jpg'));
    final s = ExternalCameraServiceImpl(picker: picker, isIos: false);
    expect(s.isSupported, isTrue);
    expect(await s.capture(), '/tmp/external.jpg');
  });

  test('Android: returns null when user cancels', () async {
    when(() => picker.pickImage(source: ImageSource.camera))
        .thenAnswer((_) async => null);
    final s = ExternalCameraServiceImpl(picker: picker, isIos: false);
    expect(await s.capture(), isNull);
  });
}
