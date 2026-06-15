/// cURL command parser and HTTP executor for the ddd_pod_cli tool.
///
/// Parses a raw cURL command string into a structured [CurlRequest], then
/// executes it against a live server and returns the decoded JSON response.
///
/// Supported cURL flags:
/// - `-X` / `--request`          HTTP method override
/// - `-H` / `--header`           Request headers
/// - `-d` / `--data` / `--data-raw` / `--data-binary`  Request body
/// - `--url`                     Explicit URL flag
/// - `-u` / `--user`             Basic authentication (user:password)
/// - Positional URL argument
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddd_pod_cli/src/core/exceptions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a parsed cURL request.
final class CurlRequest {
  const CurlRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parses and executes cURL commands.
abstract final class CurlParser {
  /// Connection + receive timeout for live HTTP requests.
  static const Duration _timeout = Duration(seconds: 15);

  /// Maximum response body size (10 MB). Responses larger than this will
  /// cause a [NetworkException] to be thrown.
  static const int _maxResponseBytes = 10 * 1024 * 1024;

  // ── Parsing ──────────────────────────────────────────────────────────────

  /// Parse [curlCommand] into a [CurlRequest].
  ///
  /// Throws [NetworkException] if no URL can be extracted from the command.
  static CurlRequest parse(String curlCommand) {
    final tokens = _tokenize(curlCommand);

    String method = 'GET';
    String? url;
    final headers = <String, String>{};
    String? body;

    int i = 0;
    while (i < tokens.length) {
      final t = tokens[i];

      // Skip the 'curl' command itself
      if (t == 'curl') {
        i++;
        continue;
      }

      if (t == '-X' || t == '--request') {
        if (i + 1 < tokens.length) {
          method = tokens[i + 1].toUpperCase();
          i += 2;
        } else {
          i++;
        }
      } else if (t == '-H' || t == '--header') {
        if (i + 1 < tokens.length) {
          final headerVal = tokens[i + 1];
          final colonIdx = headerVal.indexOf(':');
          if (colonIdx > 0) {
            final key = headerVal.substring(0, colonIdx).trim();
            final value = headerVal.substring(colonIdx + 1).trim();
            headers[key] = value;
          }
          i += 2;
        } else {
          i++;
        }
      } else if (t == '-d' ||
          t == '--data' ||
          t == '--data-raw' ||
          t == '--data-binary' ||
          t == '--data-urlencode') {
        if (i + 1 < tokens.length) {
          body = tokens[i + 1];
          i += 2;
        } else {
          i++;
        }
      } else if (t == '--url') {
        // Explicit --url flag
        if (i + 1 < tokens.length) {
          url = tokens[i + 1];
          i += 2;
        } else {
          i++;
        }
      } else if (t == '-u' || t == '--user') {
        // Basic Authentication: user:password → Authorization: Basic <b64>
        if (i + 1 < tokens.length) {
          final credentials = tokens[i + 1];
          final encoded = base64Encode(utf8.encode(credentials));
          headers['Authorization'] = 'Basic $encoded';
          i += 2;
        } else {
          i++;
        }
      } else if (t.startsWith('http://') ||
          t.startsWith('https://') ||
          t.contains('://')) {
        url = t;
        i++;
      } else if (t.startsWith('-')) {
        // Unknown flag — skip it and its argument if the next token
        // doesn't look like a flag or URL
        if (i + 1 < tokens.length &&
            !tokens[i + 1].startsWith('-') &&
            !tokens[i + 1].startsWith('http')) {
          i += 2;
        } else {
          i++;
        }
      } else {
        // Bare token — treat as URL if it looks like one
        if (t.contains('.') && !t.startsWith('-')) {
          url ??= t;
        }
        i++;
      }
    }

    if (url == null) {
      throw const NetworkException(
        message: 'Could not extract a URL from the cURL command.',
        hint:
            'Ensure the command contains a URL starting with http:// or https://, '
            'or use the --url flag.',
      );
    }

    url = _stripQuotes(url);

    // Infer POST if body was provided and method was not explicitly set
    if (body != null && method == 'GET') {
      method = 'POST';
    }

    return CurlRequest(
      method: method,
      url: url,
      headers: headers,
      body: body != null ? _stripQuotes(body) : null,
    );
  }

  // ── Execution ─────────────────────────────────────────────────────────────

  /// Execute [request] against the live server and return the decoded JSON.
  ///
  /// Throws [NetworkException] on:
  /// - Connection timeout
  /// - Non-2xx HTTP status
  /// - Response body exceeding [_maxResponseBytes]
  /// - JSON parse failure (returns raw string instead — no exception)
  static Future<dynamic> execute(CurlRequest request) async {
    final client = HttpClient()..connectionTimeout = _timeout;

    try {
      final uri = Uri.parse(request.url);
      final httpRequest = await client
          .openUrl(request.method, uri)
          .timeout(_timeout, onTimeout: () {
        throw const NetworkException(
          message: 'Connection timed out.',
          hint: 'Check that the server is reachable and try again, or use '
              '--skip-build-runner with a config.json instead.',
        );
      });

      request.headers.forEach((key, val) {
        httpRequest.headers.set(key, val);
      });

      if (request.body != null) {
        final bodyBytes = utf8.encode(request.body!);
        httpRequest.headers.contentLength = bodyBytes.length;
        httpRequest.add(bodyBytes);
      }

      final response = await httpRequest.close().timeout(_timeout);

      // Guard response size
      int receivedBytes = 0;
      final buffer = StringBuffer();
      await for (final chunk in response.transform(utf8.decoder)) {
        receivedBytes += chunk.length;
        if (receivedBytes > _maxResponseBytes) {
          throw const NetworkException(
            message: 'Response body exceeds the 10 MB size limit.',
            hint: 'The API returned an unusually large payload. Use a '
                'config.json with a representative sample instead.',
          );
        }
        buffer.write(chunk);
      }

      final responseBody = buffer.toString();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NetworkException(
          message: 'Server returned HTTP ${response.statusCode}: $responseBody',
          statusCode: response.statusCode,
          responseBody: responseBody,
          hint:
              'Check the URL and any required authentication headers (-H or -u).',
        );
      }

      try {
        return jsonDecode(responseBody);
      } catch (_) {
        // Non-JSON response — return the raw body
        return responseBody;
      }
    } on NetworkException {
      rethrow;
    } on SocketException catch (e) {
      throw NetworkException(
        message: 'Could not connect to server: ${e.message}.',
        hint: 'Verify the URL is correct and the server is reachable from this '
            'machine.',
      );
    } catch (e) {
      throw NetworkException(
        message: 'HTTP request failed: $e',
        hint: 'Check the cURL command for typos.',
      );
    } finally {
      client.close();
    }
  }

  // ── Tokenizer ─────────────────────────────────────────────────────────────

  static List<String> _tokenize(String cmd) {
    final tokens = <String>[];
    final sb = StringBuffer();
    bool inDoubleQuote = false;
    bool inSingleQuote = false;
    bool escape = false;

    // Normalise line continuations (allowing trailing spaces after backslash)
    final normalized = cmd
        .replaceAll(RegExp(r'\\\s*\n'), ' ')
        .replaceAll(RegExp(r'\\\s*\r\n'), ' ');

    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];

      if (escape) {
        sb.write(char);
        escape = false;
        continue;
      }

      if (char == '\\') {
        escape = true;
        continue;
      }

      if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }

      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        continue;
      }

      if ((char == ' ' || char == '\t' || char == '\n' || char == '\r') &&
          !inDoubleQuote &&
          !inSingleQuote) {
        if (sb.isNotEmpty) {
          tokens.add(sb.toString());
          sb.clear();
        }
      } else {
        sb.write(char);
      }
    }

    if (sb.isNotEmpty) tokens.add(sb.toString());
    return tokens;
  }

  static String _stripQuotes(String s) {
    if (s.length >= 2) {
      if (s.startsWith("'") && s.endsWith("'")) {
        return s.substring(1, s.length - 1);
      }
      if (s.startsWith('"') && s.endsWith('"')) {
        return s.substring(1, s.length - 1);
      }
    }
    return s;
  }
}
