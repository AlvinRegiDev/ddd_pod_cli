/// Directory scaffolding for the DDD Feature-First structure.
///
/// Creates the standard layer directories for a feature:
/// - `application/` — Riverpod notifiers and Freezed states
/// - `domain/`      — domain models, failures, repository interfaces
/// - `infrastructure/` — DTOs, remote/local data sources, repository impl
/// - `presentation/` (optional) — debug/dev pages
/// - `test/features/<name>/application/` — unit test directory
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/generator/runner.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Scaffolds the DDD directory structure for a single feature.
final class DirectoryScaffolder {
  DirectoryScaffolder({required this.featureName});

  final String featureName;

  // Cached pubspec values — read once per instance
  String? _cachedPackageName;
  bool? _cachedIsFlutter;

  // ── Package detection ──────────────────────────────────────────────────────

  /// Read the package name from `pubspec.yaml` in the current directory.
  ///
  /// Throws [DddFileSystemException] if the file is missing and
  /// [ConfigException] if the package name cannot be extracted.
  String getHostPackageName() {
    if (_cachedPackageName != null) return _cachedPackageName!;
    final (content, _) = _readPubspec();
    final match =
        RegExp(r'^name:\s+(\S+)', multiLine: true).firstMatch(content);
    if (match == null) {
      throw const ConfigException(
        message: 'Could not extract package name from pubspec.yaml.',
        hint: 'Ensure your pubspec.yaml has a valid "name:" field.',
      );
    }
    _cachedPackageName = match.group(1)!;
    return _cachedPackageName!;
  }

  /// Returns `true` if the current project is a Flutter project.
  bool isFlutterProject() {
    if (_cachedIsFlutter != null) return _cachedIsFlutter!;
    try {
      final (content, _) = _readPubspec();
      _cachedIsFlutter = content.contains('sdk: flutter');
    } catch (_) {
      _cachedIsFlutter = false;
    }
    return _cachedIsFlutter!;
  }

  /// Returns `true` if the feature directory already exists.
  bool scaffoldExists() {
    final snakeFeatureName = StringUtils.toSnakeCase(featureName);
    final featurePath = p.join(
      Directory.current.path,
      'lib',
      'features',
      snakeFeatureName,
    );
    return Directory(featurePath).existsSync();
  }

  // ── Scaffolding ────────────────────────────────────────────────────────────

  /// Create the DDD layer directories for this feature.
  ///
  /// Returns a map of layer names → [Directory] instances:
  /// - `'application'`
  /// - `'domain'`
  /// - `'infrastructure'`
  /// - `'test_application'`
  /// - `'presentation'` (only when [withDebugView] is `true`)
  ///
  /// Throws [DddFileSystemException] if any directory cannot be created.
  Map<String, Directory> scaffold({bool withDebugView = false}) {
    final snakeFeatureName = StringUtils.toSnakeCase(featureName);
    final featurePath = p.join(
      Directory.current.path,
      'lib',
      'features',
      snakeFeatureName,
    );

    final appDir = Directory(p.join(featurePath, 'application'));
    final domainDir = Directory(p.join(featurePath, 'domain'));
    final infraDir = Directory(p.join(featurePath, 'infrastructure'));

    _createDir(appDir);
    _createDir(domainDir);
    _createDir(infraDir);

    final testAppPath = p.join(
      Directory.current.path,
      'test',
      'features',
      snakeFeatureName,
      'application',
    );
    final testAppDir = Directory(testAppPath);
    _createDir(testAppDir);

    final dirs = <String, Directory>{
      'application': appDir,
      'domain': domainDir,
      'infrastructure': infraDir,
      'test_application': testAppDir,
    };

    if (withDebugView) {
      final presentationDir = Directory(p.join(featurePath, 'presentation'));
      _createDir(presentationDir);
      dirs['presentation'] = presentationDir;
    }

    return dirs;
  }

  // ── Dependency validation and auto-install ──────────────────────────────────

  /// Reads the pubspec.yaml file and automatically installs any missing recommended dependencies.
  Future<void> installMissingDependencies({required bool isFlutter}) async {
    final (content, _) = _readPubspec();
    const requiredDeps = [
      'flutter_riverpod',
      'riverpod_annotation',
      'freezed_annotation',
      'dio',
      'fpdart',
    ];
    const requiredDevDeps = [
      'build_runner',
      'freezed',
      'json_serializable',
      'riverpod_generator',
    ];

    bool hasDependency(String pubspec, String dep) {
      return RegExp('^\\s*$dep\\s*:', multiLine: true).hasMatch(pubspec);
    }

    final missingDeps =
        requiredDeps.where((dep) => !hasDependency(content, dep)).toList();
    final missingDevDeps =
        requiredDevDeps.where((dep) => !hasDependency(content, dep)).toList();

    if (missingDeps.isEmpty && missingDevDeps.isEmpty) return;

    logger.info('Detected missing dependencies in target project.');

    if (missingDeps.isNotEmpty) {
      final success = await Runner.runPubAdd(
        packages: missingDeps,
        isDev: false,
        isFlutter: isFlutter,
      );
      if (!success) {
        logger.warn(
            'Failed to add some dependencies. You might need to add them manually.');
      }
    }

    if (missingDevDeps.isNotEmpty) {
      final success = await Runner.runPubAdd(
        packages: missingDevDeps,
        isDev: true,
        isFlutter: isFlutter,
      );
      if (!success) {
        logger.warn(
            'Failed to add some dev dependencies. You might need to add them manually.');
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Read pubspec.yaml content and its absolute path.
  (String content, String path) _readPubspec() {
    final pubspecPath = p.join(Directory.current.path, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);
    if (!pubspecFile.existsSync()) {
      throw DddFileSystemException(
        message: 'Could not find pubspec.yaml in the current working directory '
            '(${Directory.current.path}).',
        hint: 'Run ddd_pod_cli from the root of a Flutter/Dart project.',
        path: pubspecPath,
      );
    }
    return (pubspecFile.readAsStringSync(), pubspecPath);
  }

  void _createDir(Directory dir) {
    try {
      dir.createSync(recursive: true);
      logger.detail('Created directory: ${dir.path}');
    } catch (e) {
      throw DddFileSystemException(
        message: 'Failed to create directory: ${dir.path}\n$e',
        hint: 'Check that you have write permissions to the target directory.',
        path: dir.path,
      );
    }
  }
}
