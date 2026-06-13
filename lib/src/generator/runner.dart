/// External process runners for the ddd_pod_cli tool.
///
/// Provides controlled wrappers around `dart`/`flutter` sub-processes used
/// during and after code generation:
/// - `dart run build_runner build` — generates `.g.dart` / `.freezed.dart` files
/// - `dart format` — formats generated Dart source files
/// - `dart pub get` — used by the `init` command after writing pubspec changes
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';

/// Runs external Dart / Flutter tooling processes.
abstract final class Runner {
  // ── build_runner ───────────────────────────────────────────────────────────

  /// Run `dart run build_runner build --delete-conflicting-outputs`.
  ///
  /// Returns `true` if the process exits with code 0, `false` otherwise.
  ///
  /// Throws [BuildRunnerException] if the process cannot be started (e.g.
  /// the command is not found on `PATH`).
  ///
  /// Standard output is always forwarded to the terminal. Standard error is
  /// forwarded only on failure (or always if `--verbose` is active — the
  /// logger handles that internally through the process stream).
  static Future<bool> runBuildRunner({bool isFlutter = false}) async {
    final command = isFlutter ? 'flutter' : 'dart';
    final args = isFlutter
        ? ['pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs']
        : ['run', 'build_runner', 'build', '--delete-conflicting-outputs'];

    logger.info(
      'Running build_runner build --delete-conflicting-outputs via $command…',
    );

    final Process process;
    try {
      process = await Process.start(
        command,
        args,
        workingDirectory: Directory.current.path,
      );
    } on ProcessException catch (e) {
      throw BuildRunnerException(
        message:
            'Could not start $command. Is it installed and on your PATH?\n'
            'Process error: ${e.message}',
        hint: isFlutter
            ? 'Run "flutter doctor" to check your Flutter installation.'
            : 'Run "dart --version" to verify your Dart SDK is installed.',
      );
    }

    // Forward stdout always; stderr only on failure.
    final stderrLines = <String>[];
    process.stdout.transform(utf8.decoder).listen(stdout.write);
    process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrLines.add(chunk);
      // Also write to stderr so it appears immediately in verbose mode
      logger.detail(chunk.trimRight());
    });

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      // Print stderr output on failure so the user can diagnose the issue
      if (stderrLines.isNotEmpty) {
        stderr.write(stderrLines.join());
      }
      logger.err('build_runner failed with exit code $exitCode.');
      return false;
    }

    logger.success('build_runner completed successfully!');
    return true;
  }

  // ── dart format ────────────────────────────────────────────────────────────

  /// Run `dart format` on [path].
  ///
  /// [path] should be scoped as narrowly as possible (e.g. the generated
  /// feature directory, not the entire project root) to minimise formatting
  /// time.
  ///
  /// Returns `true` on success, `false` on formatting failure.
  static bool runFormat(String path) {
    logger.info('Formatting generated files in $path…');
    final result = Process.runSync(
      'dart',
      ['format', path],
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) {
      logger.warn('dart format failed: ${result.stderr}');
      return false;
    }
    logger.success('Code formatted successfully.');
    return true;
  }

  // ── dart pub get ──────────────────────────────────────────────────────────

  /// Run `dart pub get` (or `flutter pub get`) in [workingDirectory].
  ///
  /// Returns `true` on success. Does **not** throw on failure — a warning is
  /// logged instead, so the user can run `pub get` manually if needed.
  static Future<bool> runPubGet({
    bool isFlutter = false,
    String? workingDirectory,
  }) async {
    final command = isFlutter ? 'flutter' : 'dart';
    final args = ['pub', 'get'];
    final cwd = workingDirectory ?? Directory.current.path;

    logger.info('Running $command pub get in $cwd…');

    final Process process;
    try {
      process = await Process.start(command, args, workingDirectory: cwd);
    } on ProcessException catch (e) {
      logger.warn('Could not run $command pub get: ${e.message}');
      return false;
    }

    process.stdout.transform(utf8.decoder).listen(logger.detail);
    process.stderr.transform(utf8.decoder).listen(logger.detail);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      logger.warn(
        '$command pub get exited with code $exitCode. '
        'You may need to run it manually.',
      );
      return false;
    }

    logger.success('Dependencies resolved successfully.');
    return true;
  }
}
