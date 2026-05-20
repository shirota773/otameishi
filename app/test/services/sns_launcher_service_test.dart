import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/services/sns_launcher_service.dart';

void main() {
  group('classifySnsUrl', () {
    test('x.com → SnsKind.x', () {
      expect(classifySnsUrl('https://x.com/yamadat'), SnsKind.x);
      expect(classifySnsUrl('https://www.x.com/yamadat'), SnsKind.x);
    });

    test('twitter.com → SnsKind.x', () {
      expect(classifySnsUrl('https://twitter.com/yamadat'), SnsKind.x);
      expect(classifySnsUrl('https://mobile.twitter.com/yamadat'), SnsKind.x);
    });

    test('instagram.com → SnsKind.instagram', () {
      expect(classifySnsUrl('https://instagram.com/yamadat'), SnsKind.instagram);
      expect(classifySnsUrl('https://www.instagram.com/yamadat'), SnsKind.instagram);
    });

    test('discord.gg / discord.com → SnsKind.discord', () {
      expect(classifySnsUrl('https://discord.gg/abc123'), SnsKind.discord);
      expect(classifySnsUrl('https://discord.com/invite/abc123'), SnsKind.discord);
    });

    test('arbitrary https URL → SnsKind.web', () {
      expect(classifySnsUrl('https://example.com'), SnsKind.web);
      expect(classifySnsUrl('https://blog.example.com/post'), SnsKind.web);
    });

    test('http URL is accepted', () {
      expect(classifySnsUrl('http://x.com/yamadat'), SnsKind.x);
    });

    test('non-URL strings fall back to web', () {
      expect(classifySnsUrl(''), SnsKind.web);
      expect(classifySnsUrl('not a url'), SnsKind.web);
      expect(classifySnsUrl('x.com/yamadat'), SnsKind.web);
    });

    test('case insensitivity', () {
      expect(classifySnsUrl('HTTPS://X.COM/user'), SnsKind.x);
      expect(classifySnsUrl('HTTPS://Instagram.com/user'), SnsKind.instagram);
    });
  });

  group('SnsLauncherServiceImpl.classify', () {
    const service = SnsLauncherServiceImpl();
    test('delegates to classifySnsUrl', () {
      expect(service.classify('https://x.com/u'), SnsKind.x);
    });
  });

  group('SnsLauncherServiceImpl.launch scheme allow-list', () {
    const service = SnsLauncherServiceImpl();

    test('javascript: URL is rejected', () async {
      expect(await service.launch('javascript:alert(1)'), isFalse);
    });

    test('file: URL is rejected', () async {
      expect(await service.launch('file:///etc/passwd'), isFalse);
    });

    test('non-URL string is rejected', () async {
      // Uri.tryParse returns a Uri with empty scheme — must be rejected by the
      // scheme allow-list, not crash url_launcher.
      expect(await service.launch('not a url'), isFalse);
    });
  });
}
