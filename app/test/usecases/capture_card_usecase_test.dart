import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:otameishi/services/image_processing_service.dart';
import 'package:otameishi/services/ocr_service.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/services/storage_service.dart';
import 'package:otameishi/usecases/capture_card_usecase.dart';

class _MockImg extends Mock implements ImageProcessingService {}

class _MockOcr extends Mock implements OcrService {}

class _MockStorage extends Mock implements StorageService {}

Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

const _quad = Quad(
  topLeft: Point2D(0, 0),
  topRight: Point2D(100, 0),
  bottomRight: Point2D(100, 80),
  bottomLeft: Point2D(0, 80),
);

final _encoded = EncodedImage(
  bytes: Uint8List(64),
  format: ImageFormat.jpeg,
  width: 100,
  height: 80,
);

void main() {
  late _MockImg imgSvc;
  late _MockOcr ocrSvc;
  late _MockStorage storageSvc;
  late CaptureCardUseCase useCase;
  late Uint8List rawBytes;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_quad);
    registerFallbackValue(ImageFormat.jpeg);
  });

  setUp(() {
    imgSvc = _MockImg();
    ocrSvc = _MockOcr();
    storageSvc = _MockStorage();
    rawBytes = _jpeg(200, 200);

    useCase = CaptureCardUseCase(
      imageProcessing: imgSvc,
      ocr: ocrSvc,
      storage: storageSvc,
    );

    when(() => imgSvc.detectCorners(any())).thenAnswer((_) async => _quad);
    when(() => imgSvc.perspectiveCorrect(any(), any()))
        .thenAnswer((_) async => Uint8List(64));
    when(() => imgSvc.denoise(any())).thenAnswer((_) async => Uint8List(64));
    when(() => imgSvc.encode(
          any(),
          format: any(named: 'format'),
          maxDimension: any(named: 'maxDimension'),
          maxFileBytes: any(named: 'maxFileBytes'),
        )).thenAnswer((_) async => _encoded);
    when(() => storageSvc.saveCardImage(
          any(),
          format: any(named: 'format'),
        )).thenAnswer((_) async => '/mock/card.jpg');
    when(() => ocrSvc.recognizeFromPath(any())).thenAnswer((_) async =>
        const OcrResult(fullText: '山田太郎 @yamadat', lines: ['山田太郎', '@yamadat']));
  });

  test('returns CardDraft with saved imagePath', () async {
    final draft = await useCase.execute(rawBytes);
    expect(draft.imagePath, '/mock/card.jpg');
  });

  test('runs pipeline in order: detect → correct → denoise → encode → save', () async {
    final calls = <String>[];
    when(() => imgSvc.detectCorners(any())).thenAnswer((_) async {
      calls.add('detect');
      return _quad;
    });
    when(() => imgSvc.perspectiveCorrect(any(), any())).thenAnswer((_) async {
      calls.add('correct');
      return Uint8List(64);
    });
    when(() => imgSvc.denoise(any())).thenAnswer((_) async {
      calls.add('denoise');
      return Uint8List(64);
    });
    when(() => imgSvc.encode(
          any(),
          format: any(named: 'format'),
          maxDimension: any(named: 'maxDimension'),
          maxFileBytes: any(named: 'maxFileBytes'),
        )).thenAnswer((_) async {
      calls.add('encode');
      return _encoded;
    });
    when(() => storageSvc.saveCardImage(
          any(),
          format: any(named: 'format'),
        )).thenAnswer((_) async {
      calls.add('save');
      return '/p';
    });

    await useCase.execute(rawBytes);
    expect(calls, ['detect', 'correct', 'denoise', 'encode', 'save']);
  });

  test('extracts X handle and name when OCR succeeds', () async {
    final draft = await useCase.execute(rawBytes);
    expect(draft.extractedData?.xHandles, contains('@yamadat'));
    expect(draft.extractedData?.nameCandidate, '山田太郎');
  });

  test('OCR failure degrades gracefully — image still saved', () async {
    when(() => ocrSvc.recognizeFromPath(any())).thenThrow(Exception('boom'));

    final draft = await useCase.execute(rawBytes);
    expect(draft.imagePath, '/mock/card.jpg');
    expect(draft.ocr, isNull);
    expect(draft.extractedData, isNull);
  });

  test('falls back to full image when detectCorners returns null', () async {
    when(() => imgSvc.detectCorners(any())).thenAnswer((_) async => null);
    final draft = await useCase.execute(rawBytes);
    expect(draft.imagePath, '/mock/card.jpg');
  });

  test('falls back to full image when detectCorners throws', () async {
    when(() => imgSvc.detectCorners(any())).thenThrow(Exception('detect failed'));
    final draft = await useCase.execute(rawBytes);
    expect(draft.imagePath, '/mock/card.jpg');
  });
}
