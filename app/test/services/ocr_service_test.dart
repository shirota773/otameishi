import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/services/ocr_service.dart';

void main() {
  group('extractXHandles', () {
    test('single handle', () {
      expect(extractXHandles('Hello @yamadat world'), ['@yamadat']);
    });

    test('multiple handles, de-duplicated case-insensitively', () {
      expect(
        extractXHandles('@alice and @bob and @ALICE'),
        ['@alice', '@bob'],
      );
    });

    test('ignores @ followed by no characters', () {
      expect(extractXHandles('email@'), isEmpty);
    });

    test('respects 15-char max', () {
      expect(
        extractXHandles('@thisistoolongtobehandle'),
        ['@thisistoolongto'],
      );
    });

    test('empty text → empty list', () {
      expect(extractXHandles(''), isEmpty);
    });
  });

  group('extractUrls', () {
    test('finds https URLs', () {
      expect(
        extractUrls('Visit https://example.com today'),
        ['https://example.com'],
      );
    });

    test('finds http URLs', () {
      expect(extractUrls('http://example.com'), ['http://example.com']);
    });

    test('strips trailing punctuation', () {
      expect(extractUrls('See https://example.com.'), ['https://example.com']);
      expect(extractUrls('(https://x.com)'), ['https://x.com']);
    });

    test('de-duplicates case-insensitively', () {
      expect(
        extractUrls('https://x.com and https://X.com'),
        ['https://x.com'],
      );
    });

    test('handles Japanese punctuation breaks', () {
      expect(
        extractUrls('連絡はhttps://example.com、よろしく'),
        ['https://example.com'],
      );
    });
  });

  group('extractNameCandidate', () {
    test('returns first non-handle non-URL line', () {
      expect(
        extractNameCandidate(['@yamadat', 'https://x.com/y', '山田太郎']),
        '山田太郎',
      );
    });

    test('skips blank lines', () {
      expect(extractNameCandidate(['', '   ', '田中']), '田中');
    });

    test('returns null if no candidate', () {
      expect(extractNameCandidate(['@a', 'https://b.com']), isNull);
      expect(extractNameCandidate([]), isNull);
    });

    test('accepts English names', () {
      expect(extractNameCandidate(['John Doe']), 'John Doe');
    });

    test('rejects pure-punctuation lines', () {
      expect(extractNameCandidate(['---', '★★★', 'Name']), 'Name');
    });
  });
}
