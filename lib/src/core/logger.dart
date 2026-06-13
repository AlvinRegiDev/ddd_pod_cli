/// Structured, colour-aware logger for the ddd_pod_cli tool.
///
/// Wraps [mason_logger](https://pub.dev/packages/mason_logger) to provide
/// consistent, level-gated output across every subsystem. Supports:
///
/// - Coloured output with auto-detection of CI / non-TTY environments
/// - A `--verbose` mode that prints debug detail lines
/// - A `--quiet` mode that suppresses everything except errors
/// - Spinner-based progress indicators for long-running steps
library;

import 'package:mason_logger/mason_logger.dart';

/// Global singleton logger.
///
/// Initialised by `main()` via [DddLogger.init] before any other code runs.
/// All subsystems import and use this directly.
DddLogger get logger => DddLogger._instance;

/// Convenience typedef so call-sites can write `Progress` without importing
/// mason_logger directly.
typedef DddProgress = Progress;

// ─────────────────────────────────────────────────────────────────────────────

/// A thin façade over [mason_logger.Logger] with domain-specific helpers.
final class DddLogger {
  DddLogger._(this._inner);

  static late DddLogger _instance;

  final Logger _inner;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialise the global [logger] singleton.
  ///
  /// Must be called exactly once, at the top of `main()`, before any other
  /// code uses [logger].
  static void init({bool verbose = false, bool quiet = false}) {
    final level = quiet
        ? Level.error
        : verbose
            ? Level.verbose
            : Level.info;
    _instance = DddLogger._(Logger(level: level));
  }

  // ── Output methods ─────────────────────────────────────────────────────────

  /// Informational message — shown at default verbosity.
  void info(String message) => _inner.info(message);

  /// Success message with a green ✓ icon.
  void success(String message) => _inner.success(message);

  /// Warning message with a yellow ⚠ icon — does not halt execution.
  void warn(String message) => _inner.warn(message);

  /// Error message with a red ✗ icon.
  void err(String message) => _inner.err(message);

  /// Verbose / debug detail — only printed when `--verbose` is set.
  void detail(String message) => _inner.detail(message);

  /// Write a raw line (no prefix). Used for the ASCII banner.
  void write(String message) => _inner.write(message);

  /// Write a blank line.
  void space() => _inner.write('');

  /// Print a formatted error block that includes the error message and an
  /// optional actionable [hint].
  void errorWithHint(String message, {String? hint}) {
    _inner.err(message);
    if (hint != null) {
      _inner.info('  💡 Hint: $hint');
    }
  }

  // ── Progress spinner ───────────────────────────────────────────────────────

  /// Start a spinner labelled with [message].
  ///
  /// Call `.complete()`, `.fail()`, or `.cancel()` on the returned [Progress].
  ///
  /// ```dart
  /// final progress = logger.progress('Scaffolding directories');
  /// try {
  ///   scaffolder.scaffold();
  ///   progress.complete('Directories created');
  /// } catch (e) {
  ///   progress.fail('Failed to scaffold');
  ///   rethrow;
  /// }
  /// ```
  Progress progress(String message) => _inner.progress(message);

  // ── Prompt ─────────────────────────────────────────────────────────────────

  /// Ask a yes/no confirmation question.
  ///
  /// Returns `true` if the user answers `y` or `yes` (case-insensitive).
  /// In non-interactive environments (CI, pipe), returns [defaultValue].
  bool confirm(String question, {bool defaultValue = false}) =>
      _inner.confirm(question, defaultValue: defaultValue);

  /// Prompt the user for a text answer.
  ///
  /// Returns the typed string. Falls back to [defaultValue] in non-interactive
  /// environments.
  String prompt(String question, {String? defaultValue}) =>
      _inner.prompt(question, defaultValue: defaultValue);
}
