/// Sealed exception hierarchy for the ddd_pod_cli tool.
///
/// Every subsystem throws a typed subclass of [DddCliException] so that
/// callers can pattern-match on specific failure kinds and provide
/// actionable hints to the end user.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Base
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all CLI-level exceptions.
sealed class DddCliException implements Exception {
  const DddCliException({required this.message, this.hint});

  /// Human-readable description of the failure.
  final String message;

  /// Optional one-line hint shown below the error (e.g. "Run 'dart pub get'").
  final String? hint;

  @override
  String toString() => 'DddCliException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the JSON config file is missing, malformed, or contains invalid
/// field values (e.g. unknown provider_type, empty feature_name).
final class ConfigException extends DddCliException {
  const ConfigException({required super.message, super.hint});

  @override
  String toString() => 'ConfigException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// Schema / Parsing
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the JSON response / request schema cannot be parsed — e.g.
/// because of a cyclic reference or a schema that exceeds the maximum
/// supported nesting depth.
final class SchemaParseException extends DddCliException {
  const SchemaParseException({required super.message, super.hint});

  @override
  String toString() => 'SchemaParseException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// File System
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when a file or directory cannot be created, read, or written — e.g.
/// due to missing permissions or a full disk.
final class DddFileSystemException extends DddCliException {
  const DddFileSystemException({
    required super.message,
    super.hint,
    this.path,
  });

  /// The file-system path that caused the failure, when known.
  final String? path;

  @override
  String toString() =>
      'DddFileSystemException: $message${path != null ? " (path: $path)" : ""}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Dependency
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the target project is missing required pub dependencies.
final class DependencyException extends DddCliException {
  const DependencyException({
    required super.message,
    super.hint,
    required this.missing,
  });

  /// Names of the missing packages.
  final List<String> missing;

  @override
  String toString() => 'DependencyException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// Build Runner
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when `dart run build_runner build` exits with a non-zero code or
/// fails to start.
final class BuildRunnerException extends DddCliException {
  /// Creates a new [BuildRunnerException] with the given message, optional hint,
  /// and exit code.
  const BuildRunnerException({
    required super.message,
    super.hint,
    this.exitCode,
  });

  /// The process exit code, if available.
  final int? exitCode;

  @override
  String toString() => 'BuildRunnerException: $message'
      '${exitCode != null ? " (exit code: $exitCode)" : ""}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Network
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown by the cURL flow when the HTTP request fails — e.g. due to a
/// connection timeout, a non-2xx status code, or a response that is too large.
final class NetworkException extends DddCliException {
  const NetworkException({
    required super.message,
    super.hint,
    this.statusCode,
    this.responseBody,
  });

  /// The HTTP status code returned by the server, if any.
  final int? statusCode;

  /// The response body returned by the server.
  final String? responseBody;

  @override
  String toString() => 'NetworkException: $message'
      '${statusCode != null ? " (HTTP $statusCode)" : ""}';
}
