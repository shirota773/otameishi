import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/services/qr_service.dart';
import 'package:otameishi/services/service_models.dart';

void main() {
  const service = QrServiceImpl();

  test('blank string → null', () {
    expect(service.decodePayload(''), isNull);
    expect(service.decodePayload('   '), isNull);
  });

  test('x.com URL → SnsKind.x', () {
    final p = service.decodePayload('https://x.com/yamadat')!;
    expect(p.rawValue, 'https://x.com/yamadat');
    expect(p.snsKind, SnsKind.x);
    expect(p.parsedUrl?.host, 'x.com');
  });

  test('instagram URL → SnsKind.instagram', () {
    final p = service.decodePayload('https://instagram.com/y')!;
    expect(p.snsKind, SnsKind.instagram);
  });

  test('non-URL text → SnsKind.web', () {
    final p = service.decodePayload('hello world')!;
    expect(p.rawValue, 'hello world');
    expect(p.snsKind, SnsKind.web);
  });

  test('trims whitespace', () {
    final p = service.decodePayload('  https://x.com/u  ')!;
    expect(p.rawValue, 'https://x.com/u');
  });
}
