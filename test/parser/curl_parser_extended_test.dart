import 'package:test/test.dart';

import 'package:ddd_pod_cli/src/parser/curl_parser.dart';
import 'package:ddd_pod_cli/src/core/exceptions.dart';

void main() {
  group('CurlParser.parse', () {
    test('parses a basic GET URL', () {
      final req = CurlParser.parse('curl https://api.example.com/v1/users');
      expect(req.method, 'GET');
      expect(req.url, 'https://api.example.com/v1/users');
      expect(req.body, isNull);
    });

    test('ignores leading "curl" token', () {
      final req =
          CurlParser.parse('curl -X GET https://api.example.com/v1/items');
      expect(req.method, 'GET');
      expect(req.url, 'https://api.example.com/v1/items');
    });

    test('handles --url flag', () {
      final req = CurlParser.parse(
          'curl --url https://api.example.com/v1/orders --request GET');
      expect(req.url, 'https://api.example.com/v1/orders');
      expect(req.method, 'GET');
    });

    test('parses -X method override', () {
      final req =
          CurlParser.parse('curl -X POST https://api.example.com/v1/users');
      expect(req.method, 'POST');
    });

    test('parses -H headers', () {
      final req = CurlParser.parse(
        'curl https://api.example.com/v1/users '
        '-H "Authorization: Bearer token123" '
        '-H "Content-Type: application/json"',
      );
      expect(req.headers['Authorization'], 'Bearer token123');
      expect(req.headers['Content-Type'], 'application/json');
    });

    test('parses -u Basic Auth as Authorization header', () {
      final req = CurlParser.parse(
        'curl https://api.example.com/v1/users -u admin:secret',
      );
      expect(req.headers.containsKey('Authorization'), isTrue);
      expect(req.headers['Authorization'], startsWith('Basic '));
    });

    test('parses -d request body', () {
      final req = CurlParser.parse(
        'curl -X POST https://api.example.com/v1/users '
        "-d '{\"name\": \"Alice\"}'",
      );
      expect(req.method, 'POST');
      expect(req.body, isNotNull);
    });

    test('infers POST method when -d body is provided and no -X specified', () {
      final req = CurlParser.parse(
        "curl https://api.example.com/v1/users --data '{\"x\":1}'",
      );
      expect(req.method, 'POST');
    });

    test('throws NetworkException when no URL found', () {
      expect(
        () => CurlParser.parse(
            'curl -X GET --header "Authorization: Bearer abc"'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('handles line continuation (backslash-newline)', () {
      const curlCmd = '''curl \\
  -X GET \\
  https://api.example.com/v1/users \\
  -H "Accept: application/json"''';
      final req = CurlParser.parse(curlCmd);
      expect(req.url, 'https://api.example.com/v1/users');
      expect(req.method, 'GET');
      expect(req.headers['Accept'], 'application/json');
    });

    test('handles --data-raw flag', () {
      final req = CurlParser.parse(
        'curl -X POST https://example.com/api --data-raw body_data',
      );
      expect(req.body, 'body_data');
    });

    test('handles --data-binary flag', () {
      final req = CurlParser.parse(
        'curl -X POST https://example.com/api --data-binary @file',
      );
      expect(req.body, '@file');
    });

    test('strips outer single quotes from URL', () {
      final req = CurlParser.parse(
        "curl 'https://api.example.com/v1/data'",
      );
      expect(req.url, 'https://api.example.com/v1/data');
    });
  });
}
