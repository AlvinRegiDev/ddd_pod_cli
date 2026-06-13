/// `curl` sub-command — scaffold from a live API cURL request.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/parser/curl_parser.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/parser/core_models_registry.dart';
import 'package:ddd_pod_cli/src/generator/code_generator.dart';
import 'package:ddd_pod_cli/src/generator/directory_scaffolder.dart';
import 'package:ddd_pod_cli/src/generator/runner.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Executes a live cURL request and scaffolds a DDD feature from the response.
Future<void> runCurlCommand({
  required String curlCommand,
  required String featureName,
  required bool force,
  required bool skipBuildRunner,
  required bool withDebugView,
  String? providerType,
}) async {
  // ── Parse cURL ─────────────────────────────────────────────────────────────
  logger.info('Parsing cURL command…');
  final curlReq = CurlParser.parse(curlCommand);
  logger.info('Method  : ${curlReq.method}');
  logger.info('URL     : ${curlReq.url}');
  if (curlReq.body != null) {
    logger.detail('Body    : ${curlReq.body}');
  }

  // ── Execute request ────────────────────────────────────────────────────────
  final netProgress = logger.progress('Executing live API request');
  final dynamic responseJson;
  try {
    responseJson = await CurlParser.execute(curlReq);
    netProgress.complete('API call succeeded');
  } catch (e) {
    netProgress.fail('API call failed');
    rethrow;
  }

  final endpoint = Uri.parse(curlReq.url).path;
  final methods = [curlReq.method];
  final requestJson =
      curlReq.body != null ? jsonDecode(curlReq.body!) : null;

  // ── Scaffold directories ───────────────────────────────────────────────────
  final scaffolder = DirectoryScaffolder(featureName: featureName);
  final packageName = scaffolder.getHostPackageName();
  final isFlutter = scaffolder.isFlutterProject();
  logger.info('Package  : $packageName (Flutter: $isFlutter)');

  final dirProgress =
      logger.progress('Scaffolding DDD directory structure');
  final Map<String, Directory> directories;
  try {
    directories = scaffolder.scaffold(withDebugView: withDebugView);
    dirProgress.complete('Directories created');
  } catch (e) {
    dirProgress.fail('Failed to scaffold directories');
    rethrow;
  }

  // ── Core models ────────────────────────────────────────────────────────────
  final registry = CoreModelsRegistry();
  registry.scan(p.join(Directory.current.path, 'lib'));

  // ── Parse ──────────────────────────────────────────────────────────────────
  final parseProgress = logger.progress('Inferring types from response');
  final JsonParser parser;
  try {
    parser = JsonParser(
      featureName: featureName,
      responseJson: responseJson,
      requestJson: requestJson,
      providerType: providerType,
      registry: registry,
      packageName: packageName,
    );
    parseProgress.complete(
      'Inferred ${parser.responseDtoClasses.length} DTO class(es)',
    );
  } catch (e) {
    parseProgress.fail('Type inference failed');
    rethrow;
  }

  // ── Generate ───────────────────────────────────────────────────────────────
  final genProgress = logger.progress('Generating DDD source files');
  try {
    final generator = CodeGenerator(
      parser: parser,
      packageName: packageName,
      featureName: featureName,
      endpoint: endpoint,
      methods: methods,
      force: force,
      successResponse: responseJson,
    );
    generator.writeToFiles(directories);
    genProgress.complete('All files written successfully');
  } catch (e) {
    genProgress.fail('Code generation failed');
    rethrow;
  }

  // ── Format + build_runner ──────────────────────────────────────────────────
  final snakeFeature = StringUtils.toSnakeCase(featureName);
  final featurePath = p.join('lib', 'features', snakeFeature);
  Runner.runFormat(featurePath);

  if (skipBuildRunner) {
    logger.warn('Skipping build_runner (--skip-build-runner).');
  } else {
    await Runner.runBuildRunner(isFlutter: isFlutter);
  }

  logger.success(
      '\nCURL scaffold complete! Files in: $featurePath/');
}
