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

  /// Reads the pubspec.yaml file, automatically adds missing dependencies,
  /// and runs `pub get` to resolve them.
  Future<void> installMissingDependencies({
    required bool isFlutter,
    bool offline = false,
  }) async {
    final (content, pubspecPath) = _readPubspec();

    // Recommended dependency versions
    final requiredDeps = {
      'flutter_riverpod': '^2.5.1',
      'riverpod_annotation': '^2.3.5',
      'freezed_annotation': '^2.4.4',
      'json_annotation': '^4.9.0',
      'dio': '^5.5.0',
      'fpdart': '^0.6.0',
      if (offline) 'shared_preferences': '^2.2.3',
    };

    final requiredDevDeps = {
      'build_runner': '^2.4.11',
      'freezed': '^2.5.2',
      'json_serializable': '^6.8.0',
      'riverpod_generator': '^2.4.2',
    };

    bool hasDependency(String pubspec, String dep) {
      return RegExp('^\\s*$dep\\s*:', multiLine: true).hasMatch(pubspec);
    }

    final missingDeps = requiredDeps.entries
        .where((e) => !hasDependency(content, e.key))
        .toList();
    final missingDevDeps = requiredDevDeps.entries
        .where((e) => !hasDependency(content, e.key))
        .toList();

    if (missingDeps.isEmpty && missingDevDeps.isEmpty) return;

    logger.info(
        'Detected missing dependencies in target project. Auto-adding to pubspec.yaml...');

    var updatedContent = content;

    if (missingDeps.isNotEmpty) {
      updatedContent = _addDepsToYaml(
        content: updatedContent,
        section: 'dependencies',
        deps: missingDeps.map((e) => '  ${e.key}: ${e.value}').toList(),
      );
    }

    if (missingDevDeps.isNotEmpty) {
      updatedContent = _addDepsToYaml(
        content: updatedContent,
        section: 'dev_dependencies',
        deps: missingDevDeps.map((e) => '  ${e.key}: ${e.value}').toList(),
      );
    }

    try {
      File(pubspecPath).writeAsStringSync(updatedContent);
      logger.success(
          'Automatically updated pubspec.yaml with missing dependencies.');
    } catch (e) {
      logger.warn('Failed to write to pubspec.yaml directly: $e');
      return;
    }

    final success = await Runner.runPubGet(isFlutter: isFlutter);
    if (!success) {
      logger.warn(
        'Failed to run pub get. You might need to resolve dependencies manually.',
      );
    }
  }

  /// Helper to safely inject dependencies under a specific section (dependencies or dev_dependencies).
  String _addDepsToYaml({
    required String content,
    required String section,
    required List<String> deps,
  }) {
    final hasCarriageReturn = content.contains('\r\n');
    final lineSeparator = hasCarriageReturn ? '\r\n' : '\n';
    final lines = content.split(RegExp(r'\r?\n'));

    final sectionRegex = RegExp('^$section\\s*:');
    int sectionIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      if (sectionRegex.hasMatch(lines[i])) {
        sectionIndex = i;
        break;
      }
    }

    if (sectionIndex != -1) {
      // Insert immediately after the section header line
      lines.insertAll(sectionIndex + 1, deps);
    } else {
      // Section not found, append to the end
      if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
        lines.add('');
      }
      lines.add('$section:');
      lines.addAll(deps);
    }

    return lines.join(lineSeparator);
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
