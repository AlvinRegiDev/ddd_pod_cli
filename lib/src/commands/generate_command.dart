/// `generate` sub-command — scaffolds a DDD feature from a JSON config file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/config/feature_config.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/parser/core_models_registry.dart';
import 'package:ddd_pod_cli/src/generator/code_generator.dart';
import 'package:ddd_pod_cli/src/generator/directory_scaffolder.dart';
import 'package:ddd_pod_cli/src/generator/runner.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Runs the full generate flow from a config file path.
Future<void> runGenerateCommand({
  required String configPath,
  required bool force,
  required bool skipBuildRunner,
  required bool withDebugView,
}) async {
  // ── Resolve config file ────────────────────────────────────────────────────
  final configFilePath = p.isAbsolute(configPath)
      ? configPath
      : p.join(Directory.current.path, configPath);
  final configFile = File(configFilePath);

  if (!configFile.existsSync()) {
    throw DddFileSystemException(
      message: 'Configuration file not found at: $configFilePath',
      hint: 'Run "ddd init" to create a template config.json, or specify the '
          'path explicitly: ddd generate path/to/config.json',
      path: configFilePath,
    );
  }

  // ── Parse config ───────────────────────────────────────────────────────────
  final Map<String, dynamic> rawConfig;
  try {
    final rawContent = configFile.readAsStringSync();
    final decoded = jsonDecode(rawContent);
    if (decoded is! Map<String, dynamic>) {
      throw const ConfigException(
        message: 'Configuration file must contain a JSON object at its root.',
        hint: 'Check that your config.json starts with { and ends with }.',
      );
    }
    rawConfig = decoded;
  } on FormatException catch (e) {
    throw ConfigException(
      message: 'Failed to parse configuration file: ${e.message}',
      hint: 'Validate your config.json with a JSON linter '
          '(e.g. https://jsonlint.com).',
    );
  }

  final config = FeatureConfig.fromJson(
    rawConfig,
    withDebugView: withDebugView,
  );

  logger.info('Feature  : ${config.featureName}');
  logger.info('Endpoint : ${config.apiPath}');
  logger.info('Methods  : ${config.methods.map((m) => m.value).join(", ")}');
  logger.info('Provider : ${config.providerTypeString}');

  // ── Scaffold directories ───────────────────────────────────────────────────
  final scaffolder = DirectoryScaffolder(featureName: config.featureName);
  final packageName = scaffolder.getHostPackageName();
  final isFlutter = scaffolder.isFlutterProject();
  logger.info(
    'Package  : $packageName (Flutter: $isFlutter)',
  );

  await scaffolder.installMissingDependencies(isFlutter: isFlutter);

  final dirProgress = logger.progress('Scaffolding DDD directory structure');
  final Map<String, Directory> directories;
  try {
    directories = scaffolder.scaffold(withDebugView: config.withDebugView);
    dirProgress.complete('Directories created');
  } catch (e) {
    dirProgress.fail('Failed to scaffold directories');
    rethrow;
  }

  // ── Scan core models ───────────────────────────────────────────────────────
  final registry = CoreModelsRegistry();
  registry.scan(p.join(Directory.current.path, 'lib'));
  if (!registry.isEmpty) {
    logger.detail(
      'Reusing core models from registry: '
      '${registry.domainClassesToPaths.keys.join(", ")}',
    );
  }

  // ── Parse schemas ──────────────────────────────────────────────────────────
  final parseProgress = logger.progress('Parsing schemas & inferring types');
  final JsonParser parser;
  try {
    parser = JsonParser(
      featureName: config.featureName,
      responseJson: config.getResponseDto,
      requestJson: config.postRequestBody,
      providerType: config.providerTypeString,
      typeOverrides: config.typeOverrides,
      registry: registry,
      packageName: packageName,
      fieldMapping: config.fieldMapping,
      isPaginatedList: config.isPaginatedList,
      offlineCache: config.offlineCache,
      validationRules: config.validationRules,
    );
    parseProgress.complete(
      'Inferred ${parser.responseDtoClasses.length} DTO class(es), '
      '${parser.domainClasses.length} domain model(s)',
    );
  } catch (e) {
    parseProgress.fail('Schema parsing failed');
    rethrow;
  }

  // ── Generate code ──────────────────────────────────────────────────────────
  final genProgress = logger.progress('Generating DDD source files');
  try {
    final generator = CodeGenerator(
      parser: parser,
      packageName: packageName,
      featureName: config.featureName,
      endpoint: config.apiPath,
      methods: config.methods.map((m) => m.value).toList(),
      force: force,
      successResponse: config.successResponse,
      failureResponse: config.failureResponse,
      toDomainFallback: config.toDomainFallback,
      familyParam: config.familyParam,
      keepAlive: config.keepAlive,
      combinedProviders: config.combinedProviders,
      listenProviders: config.listenProviders,
      paginationConfig: config.paginationConfig,
      useCustomState: config.useCustomState,
      autoDispose: config.autoDispose,
      dependencies: config.dependencies,
      streamConfig: config.streamConfig,
      retryConfig: config.retryConfig,
      searchConfig: config.searchConfig,
      offlineMutationQueue: config.offlineMutationQueue,
      featureDependencies: config.featureDependencies,
      cacheTtlSeconds: config.cacheTtlSeconds,
    );
    generator.writeToFiles(directories);
    genProgress.complete('All files written successfully');
  } catch (e) {
    genProgress.fail('Code generation failed');
    rethrow;
  }

  // ── Format ─────────────────────────────────────────────────────────────────
  final snakeFeature = StringUtils.toSnakeCase(config.featureName);
  final featurePath = p.join('lib', 'features', snakeFeature);
  Runner.runFormat(featurePath);

  // ── build_runner ───────────────────────────────────────────────────────────
  if (skipBuildRunner) {
    logger.warn(
      'Skipping build_runner. Run it manually:\n'
      '  ${isFlutter ? "flutter" : "dart"} run build_runner build --delete-conflicting-outputs',
    );
  } else {
    await Runner.runBuildRunner(isFlutter: isFlutter);
  }

  logger.success(
    '\nScaffolding complete! Check the generated files in: $featurePath/',
  );
}
