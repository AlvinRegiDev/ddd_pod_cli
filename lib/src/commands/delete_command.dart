/// `delete` sub-command — removes all generated files for a feature.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/generator/directory_scaffolder.dart';
import 'package:ddd_pod_cli/src/generator/runner.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Deletes all generated DDD directories for [featureName].
///
/// If [dryRun] is `true`, only prints what would be deleted without actually
/// removing anything.
Future<void> runDeleteCommand({
  required String featureName,
  required bool skipBuildRunner,
  bool dryRun = false,
}) async {
  final snakeFeature = StringUtils.toSnakeCase(featureName);

  final featureLibPath = p.join(
    Directory.current.path,
    'lib',
    'features',
    snakeFeature,
  );
  final featureTestPath = p.join(
    Directory.current.path,
    'test',
    'features',
    snakeFeature,
  );

  final featureLibDir = Directory(featureLibPath);
  final featureTestDir = Directory(featureTestPath);

  bool hasAnything = false;

  if (featureLibDir.existsSync()) {
    hasAnything = true;
    logger.info(
      '${dryRun ? "[DRY RUN] Would delete" : "Deleting"}: $featureLibPath',
    );
    if (!dryRun) featureLibDir.deleteSync(recursive: true);
  }

  if (featureTestDir.existsSync()) {
    hasAnything = true;
    logger.info(
      '${dryRun ? "[DRY RUN] Would delete" : "Deleting"}: $featureTestPath',
    );
    if (!dryRun) featureTestDir.deleteSync(recursive: true);
  }

  if (!hasAnything) {
    logger.warn(
      'No generated directories found for feature "$featureName".\n'
      'Expected:\n'
      '  $featureLibPath\n'
      '  $featureTestPath',
    );
    return;
  }

  if (dryRun) {
    logger.info(
        '[DRY RUN] Nothing was deleted. Re-run without --dry-run to proceed.');
    return;
  }

  logger.success('Feature "$featureName" removed successfully.');

  // ── build_runner ───────────────────────────────────────────────────────────
  if (skipBuildRunner) {
    logger.warn('Skipping build_runner (--skip-build-runner).');
  } else {
    final scaffolder = DirectoryScaffolder(featureName: featureName);
    final isFlutter = scaffolder.isFlutterProject();
    await Runner.runBuildRunner(isFlutter: isFlutter);
  }
}
