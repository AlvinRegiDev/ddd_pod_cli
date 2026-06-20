/// Code generation engine for the ddd_pod_cli tool.
///
/// Consumes the output of [JsonParser] and emits production-ready Dart source
/// files implementing the DDD Feature-First architecture with:
/// - Freezed models and DTOs
/// - Riverpod 2.x notifiers (notifier / async_notifier / future_provider)
/// - fpdart Either-based repository pattern
/// - Dio remote data sources with structured error handling
/// - Optional offline cache (SharedPreferences)
/// - Optional debug/presentation page
/// - Riverpod provider unit tests
/// - Form state + notifier with validation
///
/// Every generated file includes:
/// - A `GENERATED CODE — DO NOT MODIFY BY HAND` banner
/// - The CLI version and generation timestamp
/// - Feature-specific import paths
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/parser/models.dart';
import 'package:ddd_pod_cli/src/utils/keywords.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';
import 'package:ddd_pod_cli/src/utils/import_cycle_detector.dart';

/// Current CLI version — kept in sync with pubspec.yaml.
const String _kCliVersion = '1.0.3';

// ─────────────────────────────────────────────────────────────────────────────

/// Generates all DDD layer source files for a single feature and writes them
/// to the provided directory map.
final class CodeGenerator {
  /// Creates a new [CodeGenerator] instance with the parsed configurations and options.
  CodeGenerator({
    required this.parser,
    required this.packageName,
    required this.featureName,
    required this.endpoint,
    required this.methods,
    this.force = false,
    this.successResponse,
    this.failureResponse,
    this.toDomainFallback = 'defaults',
    this.familyParam,
    this.keepAlive = false,
    this.combinedProviders = const [],
    this.listenProviders = const [],
    this.paginationConfig,
    this.useCustomState = false,
    this.autoDispose = true,
    this.dependencies = const [],
    this.streamConfig,
    this.retryConfig,
    this.searchConfig,
    this.offlineMutationQueue = false,
    this.featureDependencies = const [],
    this.cacheTtlSeconds = 0,
    this.imports = const [],
  });

  /// The parsed JSON parser holding schema details and types.
  final JsonParser parser;

  /// The package name of the host application.
  final String packageName;

  /// The name of the feature to scaffold.
  final String featureName;

  /// The target API endpoint path.
  final String endpoint;

  /// The list of HTTP methods supported by the feature.
  final List<String> methods;

  /// Whether to force overwrite existing files.
  final bool force;

  /// Sample success response data used for tests.
  final dynamic successResponse;

  /// Sample failure response data.
  final dynamic failureResponse;

  /// Fallback strategy for mapping null values: 'defaults' or 'nullable'.
  final String toDomainFallback;

  /// Optional family parameter details for parameterized providers.
  final Map<String, String>? familyParam;

  /// Whether to keep notifier states alive.
  final bool keepAlive;

  /// List of derived/combined providers configurations.
  final List<Map<String, dynamic>> combinedProviders;

  /// List of provider names to listen to for side-effects.
  final List<String> listenProviders;

  /// Custom configuration parameters for paginated features.
  final Map<String, dynamic>? paginationConfig;

  /// Whether to generate union states for UI displays.
  final bool useCustomState;

  /// Whether generated Riverpod providers automatically dispose.
  final bool autoDispose;

  /// List of direct Riverpod provider dependencies.
  final List<String> dependencies;

  /// Configuration details for SSE, WebSockets, or polling streams.
  final Map<String, dynamic>? streamConfig;

  /// Configuration for exponential backoff retries.
  final Map<String, dynamic>? retryConfig;

  /// Configuration for debounced/throttled queries.
  final Map<String, dynamic>? searchConfig;

  /// Whether to queue offline write mutations.
  final bool offlineMutationQueue;

  /// Explicit dependencies on other generated features.
  final List<String> featureDependencies;

  /// Cache TTL in seconds (0 = no expiry). Wired from [FeatureConfig.cacheTtlSeconds].
  final int cacheTtlSeconds;

  /// Custom file imports to add to generated files.
  final List<String> imports;

  // ── Write orchestration ────────────────────────────────────────────────────

  /// Generate and write all feature files into the provided [directories] map.
  void writeToFiles(Map<String, Directory> directories) {
    final snake = _snake;
    final generated = <String, String>{};

    void addFile(String path, String content) {
      generated[path] = content;
    }

    // ── application/ ──────────────────────────────────────────────────────
    final appDir = directories['application']!;
    addFile(p.join(appDir.path, '${snake}_state.dart'), generateStateCode());
    addFile(
        p.join(appDir.path, '${snake}_notifier.dart'), generateNotifierCode());
    if (parser.requestJson != null) {
      addFile(p.join(appDir.path, '${snake}_form_state.dart'),
          generateFormStateCode());
      addFile(p.join(appDir.path, '${snake}_form_notifier.dart'),
          generateFormNotifierCode());
    }
    addFile(p.join(appDir.path, '${snake}_derived_providers.dart'),
        generateDerivedProvidersCode());
    addFile(
        p.join(appDir.path, 'providers.dart'), generateProvidersBarrelCode());

    // ── domain/ ───────────────────────────────────────────────────────────
    final domainDir = directories['domain']!;
    if (parser.domainClasses.isNotEmpty) {
      addFile(p.join(domainDir.path, '${snake}_model.dart'),
          generateDomainModelCode());
    }
    addFile(
        p.join(domainDir.path, '${snake}_failure.dart'), generateFailureCode());
    addFile(p.join(domainDir.path, 'i_${snake}_repository.dart'),
        generateIRepositoryCode());

    // ── infrastructure/ ──────────────────────────────────────────────────
    final infraDir = directories['infrastructure']!;
    if (parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty) {
      addFile(p.join(infraDir.path, '${snake}_dto.dart'), generateDtoCode());
    }
    addFile(p.join(infraDir.path, '${snake}_remote_data_source.dart'),
        generateRemoteDataSourceCode());
    addFile(p.join(infraDir.path, '${snake}_repository_impl.dart'),
        generateRepositoryImplCode());
    addFile(p.join(infraDir.path, '${snake}_mock_interceptor.dart'),
        generateMockInterceptorCode());
    if (offlineCache) {
      addFile(p.join(infraDir.path, '${snake}_local_data_source.dart'),
          generateLocalDataSourceCode());
    }
    if (offlineMutationQueue) {
      addFile(p.join(infraDir.path, '${snake}_offline_queue.dart'),
          generateOfflineQueueCode());
    }

    // ── presentation/ ─────────────────────────────────────────────────────
    final presentationDir = directories['presentation'];
    if (presentationDir != null) {
      addFile(p.join(presentationDir.path, '${snake}_debug_page.dart'),
          generateDebugPageCode());
    }

    // ── observers/ ────────────────────────────────────────────────────────
    final observersDir =
        Directory(p.join(Directory.current.path, 'lib', 'src', 'observers'));
    if (!observersDir.existsSync()) {
      observersDir.createSync(recursive: true);
    }
    addFile(p.join(observersDir.path, 'provider_observer.dart'),
        generateObserverCode());
    addFile(p.join(observersDir.path, 'analytics_observer.dart'),
        generateAnalyticsObserverCode());
    addFile(p.join(observersDir.path, 'debug_observer.dart'),
        generateDebugObserverCode());

    // ── test/application/ ─────────────────────────────────────────────────
    final testAppDir = directories['test_application'];
    if (testAppDir != null) {
      addFile(p.join(testAppDir.path, '${snake}_notifier_test.dart'),
          generateNotifierTestCode());
      addFile(p.join(testAppDir.path, '${snake}_test_overrides.dart'),
          generateTestOverridesCode());
    }

    // ── Feature barrel ────────────────────────────────────────────────────
    final featurePath = p.dirname(appDir.path);
    addFile(p.join(featurePath, '$snake.dart'),
        generateFeatureBarrelCode(directories));

    // Run cycle detection before writing
    final cycles = ImportCycleDetector.detect(generated);
    if (cycles.isNotEmpty) {
      logger.warn(
          'WARNING: Circular dependency cycle(s) detected in generated imports:');
      for (final cycle in cycles) {
        final pathStr = cycle.map((pPath) => p.basename(pPath)).join(' -> ');
        logger.warn('  - $pathStr -> ${p.basename(cycle.first)}');
      }
    }

    // Write all files
    generated.forEach((path, content) {
      safeWriteToFile(path, content);
    });
  }

  // ── File I/O ──────────────────────────────────────────────────────────────

  /// Write [content] to [path], respecting the [force] flag.
  ///
  /// - If the file does not exist, it is created.
  /// - If the file exists and `--force` is set, it is overwritten silently.
  /// - If the file exists and the terminal is interactive, the user is asked.
  /// - In non-interactive environments (CI), the file is skipped.
  ///
  /// Throws [DddFileSystemException] on write failure.
  void safeWriteToFile(String path, String content) {
    final file = File(path);
    if (file.existsSync()) {
      if (force) {
        _writeFile(file, path, content);
        return;
      }
      try {
        final lines = file.readAsLinesSync();
        if (lines.isNotEmpty) {
          final hashLine = lines.firstWhere(
            (l) => l.startsWith('// Config Hash: '),
            orElse: () => '',
          );
          if (hashLine.isNotEmpty) {
            final existingHash =
                hashLine.substring('// Config Hash: '.length).trim();
            if (existingHash == _configHash) {
              logger.detail('Skipped (unchanged config hash): $path');
              return;
            }
          }
        }
      } catch (_) {}

      logger.warn('File already exists: $path');
      if (!stdin.hasTerminal) {
        logger.info('Skipped (non-interactive): $path');
        return;
      }
      final overwrite = logger.confirm(
        'Overwrite?',
        defaultValue: false,
      );
      if (overwrite) {
        _writeFile(file, path, content);
      } else {
        logger.info('Skipped: $path');
      }
    } else {
      _writeFile(file, path, content);
    }
  }

  void _writeFile(File file, String path, String content) {
    // Atomic write: write to a sibling .tmp file then rename.
    // This prevents a corrupt partial file if the process is killed mid-write.
    final tmpPath = '$path.tmp';
    final tmpFile = File(tmpPath);
    try {
      tmpFile.writeAsStringSync(content);
      tmpFile.renameSync(path);
      logger.detail('Written: $path');
    } catch (e) {
      // Fallback to direct write if rename fails (e.g. cross-device link).
      try {
        file.writeAsStringSync(content);
        // Clean up orphaned .tmp if fallback succeeded.
        if (tmpFile.existsSync()) tmpFile.deleteSync();
        logger.detail('Written (direct fallback): $path');
      } catch (e2) {
        // Clean up orphaned .tmp.
        if (tmpFile.existsSync()) {
          try {
            tmpFile.deleteSync();
          } catch (_) {}
        }
        throw DddFileSystemException(
          message: 'Could not write file: $path\n$e2',
          hint:
              'Check that you have write permissions to the target directory.',
          path: path,
        );
      }
    }
  }

  /// Compatibility shim — delegates to [safeWriteToFile].
  @Deprecated('Use safeWriteToFile directly')
  void writeFile(File file, String content, {required bool isUserEdited}) =>
      safeWriteToFile(file.path, content);

  // ── Derived names ─────────────────────────────────────────────────────────

  bool get _hasGet => methods.any((m) => m.toUpperCase() == 'GET');

  String get _elementDataType {
    if (parser.domainClasses.isNotEmpty) {
      return '${_pascal}Model';
    }
    return parser.responseDataType;
  }

  String _getDefaultFallback(String typeName) {
    if (typeName.endsWith('?')) return '';
    if (typeName.startsWith('List<')) return ' ?? const []';
    if (typeName.startsWith('Map<')) return ' ?? const {}';
    return switch (typeName) {
      'String' => " ?? ''",
      'int' => ' ?? 0',
      'double' => ' ?? 0.0',
      'num' => ' ?? 0',
      'bool' => ' ?? false',
      _ => '',
    };
  }

  String _customImports() {
    if (imports.isEmpty) return '';
    return imports.map((imp) => "import '$imp';").join('\n') + '\n';
  }

  String get _snake => StringUtils.toSnakeCase(featureName);
  String get _pascal => StringUtils.toPascalCase(featureName);
  String get _camel =>
      Keywords.getSafeName(StringUtils.snakeToCamel(featureName));

  String get _providerName {
    final isClassNotifier = parser.providerType == 'notifier' ||
        parser.providerType == 'async_notifier' ||
        parser.providerType == 'stream_notifier';
    return isClassNotifier ? '${_camel}NotifierProvider' : '${_camel}Provider';
  }

  bool get isPaginatedList => parser.isPaginatedList;
  bool get offlineCache => parser.offlineCache;

  String get _riverpodAnnotation {
    final keep = keepAlive || !autoDispose;
    final annotationArgs = <String>[];
    if (keep) {
      annotationArgs.add('keepAlive: true');
    }
    if (dependencies.isNotEmpty) {
      final depList = dependencies.map(_formatDependency).join(', ');
      annotationArgs.add('dependencies: [$depList]');
    }
    return annotationArgs.isEmpty
        ? '@riverpod'
        : '@Riverpod(${annotationArgs.join(', ')})';
  }

  String _formatDependency(String dep) {
    if (dep.toLowerCase().endsWith('provider')) {
      return dep;
    }
    final camel = StringUtils.snakeToCamel(dep);
    return '${camel}Provider';
  }

  // ── File header ───────────────────────────────────────────────────────────

  String get _configHash {
    final map = {
      'featureName': featureName,
      'endpoint': endpoint,
      'methods': methods,
      'successResponse': successResponse,
      'failureResponse': failureResponse,
      'toDomainFallback': toDomainFallback,
      'familyParam': familyParam,
      'keepAlive': keepAlive,
      'combinedProviders': combinedProviders,
      'listenProviders': listenProviders,
      'paginationConfig': paginationConfig,
      'useCustomState': useCustomState,
      'autoDispose': autoDispose,
      'dependencies': dependencies,
      'streamConfig': streamConfig,
      'retryConfig': retryConfig,
      'searchConfig': searchConfig,
      'offlineMutationQueue': offlineMutationQueue,
      'featureDependencies': featureDependencies,
      'cacheTtlSeconds': cacheTtlSeconds,
    };
    final jsonStr = jsonEncode(map);
    int hash = 5381;
    for (int i = 0; i < jsonStr.length; i++) {
      hash = ((hash << 5) + hash) + jsonStr.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _fileHeader({bool editable = false}) {
    final timestamp = DateTime.now().toIso8601String();
    final hash = _configHash;
    if (editable) {
      return '''
// GENERATED CODE — Feel free to edit this file.
// Generated by ddd_pod_cli v$_kCliVersion · Feel free to edit this file.
// It will not be overwritten unless you run generate with the --force flag.
// Config Hash: $hash
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: type=lint, invalid_annotation_target, unused_import
''';
    }
    return '''
// GENERATED CODE — DO NOT MODIFY BY HAND
// ddd_pod_cli v$_kCliVersion · generated at $timestamp
// Config Hash: $hash
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: type=lint, invalid_annotation_target, unused_import
''';
  }

  // ── Path parameter helpers ─────────────────────────────────────────────────

  Map<String, String> get pathParamsMap {
    final map = <String, String>{};
    for (final match in RegExp(r':([a-zA-Z0-9_]+)').allMatches(endpoint)) {
      final raw = match.group(1)!;
      map[':$raw'] = Keywords.getSafeName(StringUtils.snakeToCamel(raw));
    }
    for (final match in RegExp(r'\{([a-zA-Z0-9_]+)\}').allMatches(endpoint)) {
      final raw = match.group(1)!;
      map['{$raw}'] = Keywords.getSafeName(StringUtils.snakeToCamel(raw));
    }
    return map;
  }

  String getInterpolatedEndpoint() {
    String path = endpoint;
    final map = pathParamsMap;
    if (map.isEmpty) return "'$endpoint'";
    map.forEach((raw, dartName) {
      path = path.replaceAll(raw, '\$$dartName');
    });
    return "'$path'";
  }

  // ── Method helpers ─────────────────────────────────────────────────────────

  String _methodName(String method) {
    return switch (method.toUpperCase()) {
      'GET' => 'get$_pascal',
      'POST' => 'create$_pascal',
      'PUT' => 'update$_pascal',
      'PATCH' => 'patch$_pascal',
      'DELETE' => 'delete$_pascal',
      _ => '${method.toLowerCase()}$_pascal',
    };
  }

  bool _hasRequestBody(String method) {
    final m = method.toUpperCase();
    return (m == 'POST' || m == 'PUT' || m == 'PATCH') &&
        parser.requestJson != null;
  }

  String _resolveWriteMethodName() {
    for (final m in ['POST', 'PUT', 'PATCH']) {
      if (methods.contains(m)) return _methodName(m);
    }
    final write = methods.firstWhere(
      (m) => _hasRequestBody(m),
      orElse: () => '',
    );
    return write.isNotEmpty ? _methodName(write) : 'create$_pascal';
  }

  // ── Data type helpers ──────────────────────────────────────────────────────

  String get _dataType {
    if (parser.domainClasses.isNotEmpty) {
      return parser.isListResponse
          ? 'List<${_pascal}Model>'
          : '${_pascal}Model';
    }
    return parser.isListResponse
        ? 'List<${parser.responseDataType}>'
        : parser.responseDataType;
  }

  String _repositoryReturnType(String method) {
    final isSync = parser.providerType == 'provider';
    final isStream = parser.providerType == 'stream_provider' ||
        parser.providerType == 'stream_notifier';
    if (method.toUpperCase() == 'GET') {
      if (isStream) {
        return 'Stream<Either<${_pascal}Failure, $_dataType>>';
      }
      return isSync
          ? 'Either<${_pascal}Failure, $_dataType>'
          : 'Future<Either<${_pascal}Failure, $_dataType>>';
    }
    return isSync
        ? 'Either<${_pascal}Failure, Unit>'
        : 'Future<Either<${_pascal}Failure, Unit>>';
  }

  String _remoteSourceReturnType(String method) {
    if (method.toUpperCase() != 'GET') return 'void';
    final isStream = parser.providerType == 'stream_provider' ||
        parser.providerType == 'stream_notifier';
    final baseType = () {
      // isListResponse is true for top-level lists AND for features with internal lists (e.g. Cart).
      // Only treat it as a true list response when isTopLevelList is set, or when isListResponse
      // is set without local DTO classes (i.e. registry-matched core models).
      final isActualListResponse = parser.isTopLevelList ||
          (parser.isListResponse && parser.responseDtoClasses.isEmpty);
      if (parser.responseDtoClasses.isNotEmpty) {
        return isActualListResponse ? 'List<${_pascal}Dto>' : '${_pascal}Dto';
      }
      return isActualListResponse
          ? 'List<${parser.responseDtoType}>'
          : parser.responseDtoType;
    }();
    return isStream ? 'Stream<$baseType>' : baseType;
  }

  String _streamParseBodySnippet(bool hasDto, {bool isDataLocalVar = false}) {
    final varName = isDataLocalVar ? 'decoded' : 'decoded';
    final sb = StringBuffer();
    if (hasDto) {
      if (parser.isTopLevelList) {
        sb.writeln('            final list = $varName as List<dynamic>;');
        sb.writeln(
            '            yield list.map((e) => ${_pascal}Dto.fromJson(e as Map<String, dynamic>)).toList();');
      } else {
        sb.writeln(
            '            yield ${_pascal}Dto.fromJson($varName as Map<String, dynamic>);');
      }
    } else {
      if (parser.isTopLevelList) {
        sb.writeln(
            '            yield ($varName as List<dynamic>).cast<${parser.responseDtoType}>();');
      } else {
        sb.writeln('            yield $varName as ${parser.responseDtoType};');
      }
    }
    return sb.toString();
  }

  String _repositoryParams(
      {bool isWrite = false, bool withCancelToken = true}) {
    final params = <String>[];
    pathParamsMap.forEach((_, name) => params.add('required String $name'));
    if (!isWrite && isPaginatedList) {
      params.addAll(['required int page', 'required int limit']);
    }
    if (isWrite && parser.requestJson != null) {
      params.add('required ${_pascal}RequestDto request');
    }
    if (withCancelToken) {
      params.add('CancelToken? cancelToken');
    }
    return params.isEmpty ? '' : '{${params.join(', ')}}';
  }

  String _remoteCallArgs({bool isWrite = false, bool withCancelToken = true}) {
    final args = <String>[];
    pathParamsMap.forEach((_, name) => args.add('$name: $name'));
    if (!isWrite && isPaginatedList) {
      args.addAll(['page: page', 'limit: limit']);
    }
    if (isWrite && parser.requestJson != null) args.add('request: request');
    if (withCancelToken) {
      args.add('cancelToken: cancelToken');
    }
    return args.join(', ');
  }

  String _notifierBuildParams() {
    return pathParamsMap.values.map((n) => 'String $n').join(', ');
  }

  String _notifierCallArgs() {
    final args = pathParamsMap.values.map((n) => '$n: $n').join(', ');
    return args;
  }

  String _repoArgsPage(int page) {
    final base = _notifierCallArgs();
    final paging = 'page: $page, limit: 10';
    return base.isNotEmpty ? '$base, $paging' : paging;
  }

  String _repoArgsNextPage() {
    final base = _notifierCallArgs();
    const paging = 'page: nextPage, limit: 10';
    return base.isNotEmpty ? '$base, $paging' : paging;
  }

  String _repoArgsPrevPage() {
    final base = _notifierCallArgs();
    const paging = 'page: prevPage, limit: 10';
    return base.isNotEmpty ? '$base, $paging' : paging;
  }

  String _cacheParams() {
    return pathParamsMap.values.map((n) => 'String $n').join(', ');
  }

  String _cacheCallArgs() {
    return pathParamsMap.values.join(', ');
  }

  // ── Offline cache snippet ──────────────────────────────────────────────────

  String _cacheLoadSnippet(String providerType) {
    if (!offlineCache) return '';
    final callArgs = _cacheCallArgs();
    if (providerType == 'async_notifier') {
      return '''
    // Load from local cache first for instant display
    repository.getCached$_pascal($callArgs).then((cacheResult) {
      cacheResult.fold(
        (_) {},
        (cachedData) {
          if (cachedData != null && state is! AsyncData) {
            state = AsyncData(cachedData);
          }
        },
      );
    });
''';
    } else if (providerType == 'notifier') {
      return '''
    // Load from local cache first for instant display
    final cacheResult = await repository.getCached$_pascal($callArgs);
    cacheResult.fold(
      (_) {},
      (cachedData) {
        if (cachedData != null) {
          state = ${_pascal}State.data(cachedData);
        }
      },
    );
''';
    }
    return '';
  }

  // ── STATE ─────────────────────────────────────────────────────────────────

  String generateStateCode() {
    final importModel = parser.domainClasses.isNotEmpty
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
    final sbCoreImports = StringBuffer();
    for (final imp in parser.coreDomainImports) {
      sbCoreImports.writeln("import '$imp';");
    }
    return '''
${_fileHeader()}
import 'package:freezed_annotation/freezed_annotation.dart';
${_customImports()}${importModel}import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';
$sbCoreImports
part '${_snake}_state.freezed.dart';

@freezed
sealed class ${_pascal}State with _\$${_pascal}State {
  const factory ${_pascal}State.initial() = ${_pascal}StateInitial;
  const factory ${_pascal}State.loading() = ${_pascal}StateLoading;
  const factory ${_pascal}State.data($_dataType data) = ${_pascal}StateData;
  const factory ${_pascal}State.error(${_pascal}Failure failure) = ${_pascal}StateError;
}
''';
  }

  // ── NOTIFIER ──────────────────────────────────────────────────────────────

  String generateNotifierCode() {
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;
    final sbDomainImports = StringBuffer();
    if (parser.domainClasses.isNotEmpty) {
      sbDomainImports.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sbDomainImports.writeln("import '$imp';");
    }
    final importModel = sbDomainImports.toString();
    final importDto = hasDto && parser.requestJson != null
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';
    final importRepoImpl =
        "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_repository_impl.dart';\n";
    final buildParams = _notifierBuildParams();
    final callArgs = _notifierCallArgs();

    switch (parser.providerType) {
      case 'async_notifier':
        return _asyncNotifierCode(
            buildParams, callArgs, importModel, importRepoImpl, importDto);
      case 'future_provider':
        return _futureProviderCode(
            buildParams, callArgs, importModel, importRepoImpl);
      case 'provider':
        return _providerCode(
            buildParams, callArgs, importModel, importRepoImpl);
      case 'stream_provider':
        return _streamProviderCode(
            buildParams, callArgs, importModel, importRepoImpl);
      case 'stream_notifier':
        return _streamNotifierCode(
            buildParams, callArgs, importModel, importRepoImpl, importDto);
      default:
        return _notifierCode(
            buildParams, callArgs, importModel, importRepoImpl, importDto);
    }
  }

  String _streamProviderCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
  ) {
    final paramsArg = pathParamsMap.isEmpty
        ? ''
        : ', ${pathParamsMap.values.map((v) => 'String $v').join(', ')}';
    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
Stream<$_dataType> $_camel(Ref ref$paramsArg) async* {
  final repository = ref.watch(${_camel}RepositoryProvider);
  final stream = repository.get$_pascal($callArgs);
  await for (final result in stream) {
    yield result.fold(
      (failure) => throw failure,
      (data) => data,
    );
  }
}
''';
  }

  String _streamNotifierCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
    String importDto,
  ) {
    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl$importDto
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  @override
  Stream<$_dataType> build($buildParams) async* {
    final repository = ref.watch(${_camel}RepositoryProvider);
    final stream = repository.get$_pascal($callArgs);
    await for (final result in stream) {
      yield result.fold(
        (failure) => throw failure,
        (data) => data,
      );
    }
  }

  ${_submitMethodCode()}
}
''';
  }

  String _providerCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
  ) {
    final paramsArg = pathParamsMap.isEmpty
        ? ''
        : ', ${pathParamsMap.values.map((v) => 'String $v').join(', ')}';
    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
$_dataType $_camel(Ref ref$paramsArg) {
  final repository = ref.watch(${_camel}RepositoryProvider);
  final result = repository.get$_pascal($callArgs);
  return result.fold(
    (failure) => throw failure,
    (data) => data,
  );
}
''';
  }

  String _asyncNotifierCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
    String importDto,
  ) {
    if (isPaginatedList) {
      return '''
${_fileHeader(editable: true)}
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl$importDto
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  int _page = 1;
  bool _hasReachedMax = false;

  @override
  FutureOr<$_dataType> build($buildParams) async {
    _page = 1;
    _hasReachedMax = false;
    final repository = ref.watch(${_camel}RepositoryProvider);
    ${_cacheLoadSnippet('async_notifier')}
    final result = await repository.get$_pascal(${_repoArgsPage(1)});
    return result.fold(
      (failure) => throw failure,
      (data) => data,
    );
  }

  /// Re-fetch from the first page, resetting pagination state.
  Future<void> refresh() async {
    state = const AsyncLoading();
    _page = 1;
    _hasReachedMax = false;
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.get$_pascal(${_repoArgsPage(1)});
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }

  Future<void> fetchNextPage() async {
    if (_hasReachedMax || state.isLoading) return;
    state = AsyncLoading<$_dataType>().copyWithPrevious(state);
    final repository = ref.read(${_camel}RepositoryProvider);
    final nextPage = _page + 1;
    final result = await repository.get$_pascal(${_repoArgsNextPage()});
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (newData) {
        if (newData.isEmpty) {
          _hasReachedMax = true;
          return AsyncData(state.value ?? const []);
        }
        _page = nextPage;
        final list = state.value ?? const [];
        final existingIds = list.map((item) {
          try {
            return (item as dynamic).id;
          } catch (_) {
            return item;
          }
        }).toSet();
        final uniqueNewData = newData.where((item) {
          try {
            return !existingIds.contains((item as dynamic).id);
          } catch (_) {
            return true;
          }
        }).toList();
        return AsyncData<$_dataType>([...list, ...uniqueNewData]);
      },
    );
  }

  Future<void> fetchPreviousPage() async {
    if (_page <= 1 || state.isLoading) return;
    state = AsyncLoading<$_dataType>().copyWithPrevious(state);
    final repository = ref.read(${_camel}RepositoryProvider);
    final prevPage = _page - 1;
    final result = await repository.get$_pascal(${_repoArgsPrevPage()});
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (newData) {
        if (newData.isNotEmpty) {
          _page = prevPage;
          final list = state.value ?? const [];
          final existingIds = list.map((item) {
            try {
              return (item as dynamic).id;
            } catch (_) {
              return item;
            }
          }).toSet();
          final uniqueNewData = newData.where((item) {
            try {
              return !existingIds.contains((item as dynamic).id);
            } catch (_) {
              return true;
            }
          }).toList();
          return AsyncData<$_dataType>([...uniqueNewData, ...list]);
        }
        return AsyncData(state.value ?? const []);
      },
    );
  }

  ${_submitMethodCode()}
}
''';
    }

    return '''
${_fileHeader(editable: true)}
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl$importDto
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  @override
  FutureOr<$_dataType> build($buildParams) async {
    final repository = ref.watch(${_camel}RepositoryProvider);
    ${_cacheLoadSnippet('async_notifier')}
    final result = await repository.get$_pascal($callArgs);
    return result.fold(
      (failure) => throw failure,
      (data) => data,
    );
  }

  /// Re-fetch data from the remote source.
  Future<void> refresh() async {
    state = const AsyncLoading();
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.get$_pascal($callArgs);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }

  ${_submitMethodCode()}
}
''';
  }

  String _futureProviderCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
  ) {
    final paramsArg = pathParamsMap.isEmpty
        ? ''
        : ', ${pathParamsMap.values.map((v) => 'String $v').join(', ')}';
    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel$importRepoImpl
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
Future<$_dataType> $_camel(Ref ref$paramsArg) async {
  final repository = ref.watch(${_camel}RepositoryProvider);
  final result = await repository.get$_pascal($callArgs);
  return result.fold(
    (failure) => throw failure,
    (data) => data,
  );
}
''';
  }

  String _notifierCode(
    String buildParams,
    String callArgs,
    String importModel,
    String importRepoImpl,
    String importDto,
  ) {
    if (isPaginatedList) {
      return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel${importRepoImpl}import '${_snake}_state.dart';
$importDto
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  int _page = 1;
  bool _hasReachedMax = false;

  @override
  ${_pascal}State build($buildParams) => const ${_pascal}State.initial();

  /// Fetch from the first page.
  Future<void> fetch$_pascal() async {
    _page = 1;
    _hasReachedMax = false;
    state = const ${_pascal}State.loading();
    final repository = ref.read(${_camel}RepositoryProvider);
    ${_cacheLoadSnippet('notifier')}
    final result = await repository.get$_pascal(${_repoArgsPage(1)});
    state = result.fold(
      ${_pascal}State.error,
      ${_pascal}State.data,
    );
  }

  /// Fetch the next page and append to existing data.
  Future<void> fetchNextPage() async {
    if (_hasReachedMax) return;
    final currentState = state;
    if (currentState is! ${_pascal}StateData) return;
    final repository = ref.read(${_camel}RepositoryProvider);
    final nextPage = _page + 1;
    final result = await repository.get$_pascal(${_repoArgsNextPage()});
    result.fold(
      (failure) => state = ${_pascal}State.error(failure),
      (newData) {
        if (newData.isEmpty) {
          _hasReachedMax = true;
        } else {
          _page = nextPage;
          final existingIds = currentState.data.map((item) {
            try {
              return (item as dynamic).id;
            } catch (_) {
              return item;
            }
          }).toSet();
          final uniqueNewData = newData.where((item) {
            try {
              return !existingIds.contains((item as dynamic).id);
            } catch (_) {
              return true;
            }
          }).toList();
          state = ${_pascal}State.data([...currentState.data, ...uniqueNewData]);
        }
      },
    );
  }

  /// Fetch the previous page and prepend to existing data.
  Future<void> fetchPreviousPage() async {
    if (_page <= 1) return;
    final currentState = state;
    if (currentState is! ${_pascal}StateData) return;
    final repository = ref.read(${_camel}RepositoryProvider);
    final prevPage = _page - 1;
    final result = await repository.get$_pascal(${_repoArgsPrevPage()});
    result.fold(
      (failure) => state = ${_pascal}State.error(failure),
      (newData) {
        if (newData.isNotEmpty) {
          _page = prevPage;
          final existingIds = currentState.data.map((item) {
            try {
              return (item as dynamic).id;
            } catch (_) {
              return item;
            }
          }).toSet();
          final uniqueNewData = newData.where((item) {
            try {
              return !existingIds.contains((item as dynamic).id);
            } catch (_) {
              return true;
            }
          }).toList();
          state = ${_pascal}State.data([...uniqueNewData, ...currentState.data]);
        }
      },
    );
  }

  ${_submitMethodCode()}
}
''';
    }

    final getMethod = _hasGet
        ? '''
  /// Fetch data from the remote source.
  Future<void> fetch$_pascal() async {
    state = const ${_pascal}State.loading();
    final repository = ref.read(${_camel}RepositoryProvider);
    ${_cacheLoadSnippet('notifier')}
    final result = await repository.get$_pascal($callArgs);
    state = result.fold(
      ${_pascal}State.error,
      ${_pascal}State.data,
    );
  }'''
        : '';

    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';
${_customImports()}
import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel${importRepoImpl}import '${_snake}_state.dart';
$importDto
part '${_snake}_notifier.g.dart';

$_riverpodAnnotation
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  @override
  ${_pascal}State build($buildParams) => const ${_pascal}State.initial();

$getMethod

  ${_submitMethodCode()}
}
''';
  }

  // ── SUBMIT METHOD ─────────────────────────────────────────────────────────

  String _submitMethodCode() {
    if (parser.requestJson == null) return '';
    final requestRootClass = _requestRootClass;
    if (requestRootClass == null || requestRootClass.fields.isEmpty) return '';

    final params = requestRootClass.fields
        .map((f) => 'required ${f.typeName} ${f.dartName}')
        .join(', ');
    final assignments = requestRootClass.fields
        .map((f) => '${f.dartName}: ${f.dartName}')
        .join(', ');

    final repoMethod = _resolveWriteMethodName();
    final repoArgs = [
      ...pathParamsMap.values.map((n) => '$n: $n'),
      'request: ${_pascal}RequestDto($assignments)',
    ].join(', ');

    if (parser.providerType == 'async_notifier') {
      final buildCallArgs = pathParamsMap.values.join(', ');
      return '''
  /// Submit form data to the remote source.
  Future<void> submit({$params}) async {
    state = const AsyncValue.loading();
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    state = await AsyncValue.guard(() async {
      result.fold(
        (failure) => throw failure,
        (_) {},
      );
      return build($buildCallArgs);
    });
  }

  /// Submit form data with optimistic update and rollback on failure.
  Future<void> submitWithRollback({$params}) async {
    final previousState = state;
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    result.fold(
      (failure) {
        state = previousState; // Rollback
      },
      (_) {},
    );
  }

  /// Reset the provider state.
  void reset() {
    ref.invalidateSelf();
  }
''';
    } else if (parser.providerType == 'notifier') {
      final successCallback = _hasGet
          ? 'fetch$_pascal()'
          : 'state = const ${_pascal}State.initial()';
      return '''
  /// Submit form data to the remote source.
  Future<void> submit({$params}) async {
    state = const ${_pascal}State.loading();
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    result.fold(
      (failure) => state = ${_pascal}State.error(failure),
      (_) => $successCallback,
    );
  }

  /// Submit form data with optimistic update and rollback on failure.
  Future<void> submitWithRollback({$params}) async {
    final previousState = state;
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    result.fold(
      (failure) {
        state = previousState; // Rollback
      },
      (_) {},
    );
  }

  /// Reset the provider state.
  void reset() {
    state = const ${_pascal}State.initial();
  }
''';
    } else if (parser.providerType == 'stream_notifier') {
      return '''
  /// Submit form data to the remote source.
  Future<bool> submit({$params}) async {
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    return result.isRight();
  }

  /// Reset the provider state.
  void reset() {
    ref.invalidateSelf();
  }
''';
    }
    return '';
  }

  // ── DOMAIN MODEL ──────────────────────────────────────────────────────────

  String generateDomainModelCode() {
    final sb = StringBuffer()..write(_fileHeader());
    sb.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
    for (final imp in parser.coreDomainImports) {
      sb.writeln("import '$imp';");
    }
    sb.write(_customImports());
    sb.writeln();
    sb.writeln("part '${_snake}_model.freezed.dart';");
    sb.writeln();

    for (final domainClass in parser.domainClasses) {
      sb.writeln('@freezed');
      sb.writeln(
          'abstract class ${domainClass.className} with _\$${domainClass.className} {');
      sb.writeln('  const factory ${domainClass.className}({');
      for (final field in domainClass.fields) {
        if (field.enumHint != null && field.enumHint!.isNotEmpty) {
          final escapedHints = field.enumHint!
              .map((v) => "'${v.replaceAll('\n', ' ').replaceAll('\r', ' ')}'")
              .join(', ');
          sb.writeln('    // Observed values: $escapedHints');
        }
        final prefix = field.typeName.endsWith('?') ? '' : 'required ';
        sb.writeln('    $prefix${field.typeName} ${field.fieldName},');
      }
      sb.writeln('  }) = _${domainClass.className};');
      sb.writeln('}');
      sb.writeln();
    }

    return sb.toString();
  }

  // ── FAILURE ───────────────────────────────────────────────────────────────

  String generateFailureCode() {
    return '''
${_fileHeader()}
import 'package:freezed_annotation/freezed_annotation.dart';

part '${_snake}_failure.freezed.dart';

  /// Represents all possible failure states for the $_pascal feature.
@freezed
sealed class ${_pascal}Failure with _\$${_pascal}Failure {
  /// The server returned a generic error response (5xx).
  const factory ${_pascal}Failure.serverError([String? message]) =
      ${_pascal}FailureServerError;

  /// A network-level error occurred (no connection, dropped socket, etc.).
  const factory ${_pascal}Failure.networkError() = ${_pascal}FailureNetworkError;

  /// A request timed out before receiving a response.
  const factory ${_pascal}Failure.timeoutFailure() = ${_pascal}FailureTimeoutFailure;

  /// The server returned HTTP 401 Unauthorized.
  const factory ${_pascal}Failure.unauthorizedFailure([String? message]) =
      ${_pascal}FailureUnauthorizedFailure;

  /// The server returned HTTP 403 Forbidden.
  const factory ${_pascal}Failure.forbiddenFailure([String? message]) =
      ${_pascal}FailureForbiddenFailure;

  /// The server returned HTTP 404 Not Found.
  const factory ${_pascal}Failure.notFoundFailure([String? message]) =
      ${_pascal}FailureNotFoundFailure;

  /// The server returned HTTP 422 Unprocessable Entity (server-side validation).
  ///
  /// [fieldErrors] maps individual field names to their server-side error messages.
  const factory ${_pascal}Failure.validationFailure([
    String? message,
    Map<String, String>? fieldErrors,
  ]) = ${_pascal}FailureValidationFailure;

  /// An unexpected error occurred that was not anticipated.
  const factory ${_pascal}Failure.unexpectedError([String? message]) =
      ${_pascal}FailureUnexpectedError;

  /// The server returned a 429 Rate Limit Exceeded error.
  const factory ${_pascal}Failure.rateLimitExceeded([String? message]) =
      ${_pascal}FailureRateLimitExceeded;

  /// A local cache read or write operation failed.
  const factory ${_pascal}Failure.cacheFailure([String? message]) =
      ${_pascal}FailureCacheFailure;
}
''';
  }

  // ── REPOSITORY INTERFACE ──────────────────────────────────────────────────

  String generateIRepositoryCode() {
    final sb = StringBuffer()..write(_fileHeader(editable: true));
    sb.writeln("import 'package:fpdart/fpdart.dart';");
    sb.writeln("import 'package:dio/dio.dart';");
    sb.write(_customImports());
    sb.writeln("import '${_snake}_failure.dart';");
    if (parser.domainClasses.isNotEmpty) {
      sb.writeln("import '${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sb.writeln("import '$imp';");
    }
    for (final imp in parser.coreDtoImports) {
      sb.writeln("import '$imp';");
    }

    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;
    final hasWrite = methods.any(_hasRequestBody);
    if (hasWrite && hasDto) {
      sb.writeln(
          "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';");
    }

    sb.writeln();
    sb.writeln('/// Contract for the $_pascal repository.');
    sb.writeln('abstract interface class I${_pascal}Repository {');

    if (offlineCache) {
      final cacheParams = _cacheParams();
      final paramStr = cacheParams.isNotEmpty ? cacheParams : '';
      sb.writeln(
          '  Future<Either<${_pascal}Failure, $_dataType?>> getCached$_pascal($paramStr);');
    }

    for (final method in methods) {
      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      final returnType = _repositoryReturnType(method);
      sb.writeln('  $returnType ${_methodName(method)}($params);');
    }

    sb.writeln('}');
    return sb.toString();
  }

  // ── DTO ───────────────────────────────────────────────────────────────────

  String generateDtoCode() {
    final sb = StringBuffer()..write(_fileHeader());

    sb.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
    if (parser.domainClasses.isNotEmpty) {
      sb.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sb.writeln("import '$imp';");
    }
    for (final imp in parser.coreDtoImports) {
      sb.writeln("import '$imp';");
    }
    sb.write(_customImports());
    sb.writeln();
    sb.writeln("part '${_snake}_dto.freezed.dart';");
    sb.writeln("part '${_snake}_dto.g.dart';");
    sb.writeln();

    void writeDtoClass(DtoClass dtoClass) {
      final fullName = '${dtoClass.className}Dto';
      DomainClass? matchingDomain;
      for (final dc in parser.domainClasses) {
        if (dc.dtoClassName == fullName) {
          matchingDomain = dc;
          break;
        }
      }
      final isRootResponse =
          !dtoClass.isRequest && dtoClass.className == _pascal;
      final needsToDomain = matchingDomain != null ||
          (isRootResponse && parser.corePathToDomain.isNotEmpty);

      sb.writeln('@freezed');
      sb.writeln('abstract class $fullName with _\$$fullName {');
      if (needsToDomain) {
        sb.writeln('  const $fullName._();');
        sb.writeln();
      }

      sb.writeln('  const factory $fullName({');
      for (final field in dtoClass.fields) {
        final prefix = field.typeName.endsWith('?') ? '' : 'required ';
        sb.writeln(
            "    @JsonKey(name: '${field.jsonKey}') $prefix${field.typeName} ${field.dartName},");
      }
      sb.writeln('  }) = _\$${fullName}Impl;');
      sb.writeln();
      sb.writeln('  factory $fullName.fromJson(Map<String, dynamic> json) =>');
      sb.writeln('      _\$${fullName}FromJson(json);');

      if (needsToDomain) {
        sb.writeln();
        if (matchingDomain != null) {
          sb.writeln('  ${matchingDomain.className} toDomain() {');
          sb.writeln('    return ${matchingDomain.className}(');
          for (final domainField in matchingDomain.fields) {
            final expressionSegments = <String>[];
            for (int i = 0; i < domainField.jsonPath.length; i++) {
              final segment = domainField.jsonPath[i];
              final isLast = i == domainField.jsonPath.length - 1;
              final mapped = parser.fieldMapping[segment] ??
                  StringUtils.snakeToCamel(segment);
              final dartSeg = Keywords.getSafeName(mapped);
              if (isLast && domainField.isNestedList) {
                expressionSegments
                    .add('$dartSeg?.map((e) => e.toDomain()).toList()');
              } else if (isLast && domainField.isNestedObject) {
                expressionSegments.add('$dartSeg?.toDomain()');
              } else {
                expressionSegments.add(dartSeg);
              }
            }
            var expr = expressionSegments.join('?.');
            if (!domainField.typeName.endsWith('?')) {
              if (expr.contains('?.')) {
                final fallback = _getDefaultFallback(domainField.typeName);
                expr = '($expr)$fallback';
              }
            }
            sb.writeln('      ${domainField.fieldName}: $expr,');
          }
          sb.writeln('    );');
          sb.writeln('  }');
        } else if (isRootResponse && parser.corePathToDomain.isNotEmpty) {
          final mapped = parser.fieldMapping[parser.corePathToDomain.first] ??
              StringUtils.snakeToCamel(parser.corePathToDomain.first);
          final coreField = Keywords.getSafeName(mapped);
          if (parser.isListResponse) {
            sb.writeln('  List<${parser.responseDataType}> toDomain() =>');
            sb.writeln(
                '      $coreField?.map((e) => e.toDomain()).toList() ?? const [];');
          } else {
            sb.writeln('  ${parser.responseDataType} toDomain() =>');
            sb.writeln(
                '      $coreField?.toDomain() ?? const ${parser.responseDataType}();');
          }
        }
      }

      sb.writeln('}');
      sb.writeln();
    }

    for (final dtoClass in parser.responseDtoClasses) {
      writeDtoClass(dtoClass);
    }
    for (final dtoClass in parser.requestDtoClasses) {
      writeDtoClass(dtoClass);
    }

    return sb.toString();
  }

  // ── REMOTE DATA SOURCE ────────────────────────────────────────────────────

  String generateRemoteDataSourceCode() {
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;
    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';

    final isStreamProvider = parser.providerType == 'stream_provider' ||
        parser.providerType == 'stream_notifier';
    final streamImports = isStreamProvider
        ? "import 'dart:async';\nimport 'dart:convert';\nimport 'dart:io';\n"
        : '';

    final sb = StringBuffer();
    for (final method in methods) {
      final methodName = _methodName(method);
      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      final returnType = _remoteSourceReturnType(method);
      final endpointStr = getInterpolatedEndpoint();
      final dioMethod = method.toLowerCase();

      final isSync = parser.providerType == 'provider';
      final isStream = isStreamProvider && method.toUpperCase() == 'GET';

      if (isStream) {
        final streamType = streamConfig?['type']?.toString() ?? 'polling';
        sb.writeln('  $returnType $methodName($params) async* {');
        sb.writeln('    final endpoint = $endpointStr;');
        if (streamType == 'websocket') {
          final parseBody = _streamParseBodySnippet(hasDto);
          sb.writeln('''
    final wsUrl = endpoint.startsWith('https')
        ? endpoint.replaceFirst('https', 'wss')
        : endpoint.startsWith('http')
            ? endpoint.replaceFirst('http', 'ws')
            : endpoint;
    int attempt = 0;
    while (true) {
      try {
        final socket = await WebSocket.connect(wsUrl);
        attempt = 0;
        await for (final message in socket) {
          if (message is String) {
            final decoded = jsonDecode(message);
$parseBody
          }
        }
      } catch (e) {
        attempt++;
        final backoff = Duration(seconds: 1 << attempt);
        await Future.delayed(backoff);
      }
    }''');
        } else if (streamType == 'sse') {
          final parseBody = _streamParseBodySnippet(hasDto);
          sb.writeln('''
    int attempt = 0;
    while (true) {
      try {
        final response = await _dio.get<ResponseBody>(
          endpoint,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            },
          ),
        );
        attempt = 0;
        await for (final line in response.data!.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (line.startsWith('data:')) {
            final dataStr = line.substring(5).trim();
            if (dataStr.isEmpty) continue;
            final decoded = jsonDecode(dataStr);
$parseBody
          }
        }
      } catch (e) {
        attempt++;
        final backoff = Duration(seconds: 1 << attempt);
        await Future.delayed(backoff);
      }
    }''');
        } else {
          final parseBody =
              _streamParseBodySnippet(hasDto, isDataLocalVar: true);
          sb.writeln('''
    final interval = const Duration(seconds: 5);
    while (true) {
      try {
        final response = await _dio.get(endpoint, cancelToken: cancelToken);
        final decoded = response.data;
        if (decoded != null) {
$parseBody
        }
      } catch (e) {
        // Ignored in polling
      }
      await Future.delayed(interval);
    }''');
        }
        sb.writeln('  }');
        sb.writeln();
        continue;
      }

      final sig = isSync
          ? '  $returnType $methodName($params) {'
          : '  Future<$returnType> $methodName($params) async {';
      sb.writeln(sig);
      sb.writeln('    try {');

      if (method.toUpperCase() == 'GET') {
        final queryParams = isPaginatedList
            ? ", queryParameters: {'page': page, 'limit': limit}"
            : '';
        final awaitExpr = isSync ? '' : 'await ';
        if (retryConfig != null && !isSync) {
          sb.writeln(
              '      final response = await _retry(() => _dio.get($endpointStr$queryParams, cancelToken: cancelToken));');
        } else {
          sb.writeln(
              '      final response = ${awaitExpr}_dio.get($endpointStr$queryParams, cancelToken: cancelToken);');
        }
        if (isSync) {
          sb.writeln('      final data = (response as dynamic).data;');
        } else {
          sb.writeln('      final data = response.data;');
        }
        sb.writeln('      if (data != null) {');
        if (hasDto) {
          final isActualListResp = parser.isTopLevelList ||
              (parser.isListResponse && parser.responseDtoClasses.isEmpty);
          if (isActualListResp) {
            sb.writeln('        final list = data as List<dynamic>;');
            sb.writeln(
                '        return list.map((e) => ${_pascal}Dto.fromJson(e as Map<String, dynamic>)).toList();');
          } else {
            sb.writeln(
                '        return ${_pascal}Dto.fromJson(data as Map<String, dynamic>);');
          }
        } else {
          if (parser.isTopLevelList) {
            sb.writeln(
                '        return (data as List<dynamic>).cast<${parser.responseDtoType}>();');
          } else {
            sb.writeln('        return data as ${parser.responseDtoType};');
          }
        }
        sb.writeln('      }');
        if (isSync) {
          sb.writeln('      throw Exception("Response data is null");');
        } else {
          sb.writeln('      throw DioException(');
          sb.writeln('        requestOptions: response.requestOptions,');
          sb.writeln('        response: response,');
          sb.writeln('        type: DioExceptionType.badResponse,');
          sb.writeln('      );');
        }
      } else {
        final dataParam =
            _hasRequestBody(method) ? ', data: request.toJson()' : '';
        final awaitExpr = isSync ? '' : 'await ';
        if (retryConfig != null && !isSync) {
          sb.writeln(
              '      await _retry(() => _dio.$dioMethod($endpointStr$dataParam, cancelToken: cancelToken));');
        } else {
          sb.writeln(
              '      ${awaitExpr}_dio.$dioMethod($endpointStr$dataParam, cancelToken: cancelToken);');
        }
      }

      sb.writeln('    } catch (e) {');
      sb.writeln('      rethrow;');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    final isWebsocket = streamConfig?['type']?.toString() == 'websocket';
    if (retryConfig != null && !isWebsocket) {
      final maxAttempts = retryConfig?['max_attempts'] as int? ?? 3;
      final delayMs = retryConfig?['delay_ms'] as int? ?? 1000;
      sb.writeln('''
  // ignore: unused_element
  Future<T> _retry<T>(Future<T> Function() fn) async {
    int attempts = 0;
    final maxAttempts = $maxAttempts;
    final baseDelay = const Duration(milliseconds: $delayMs);
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          rethrow;
        }
        // Honour the server's Retry-After header when present (429/503).
        Duration delay = baseDelay * (1 << (attempts - 1));
        if (e is DioException) {
          final retryAfterHeader = e.response?.headers.value('retry-after');
          if (retryAfterHeader != null) {
            final seconds = int.tryParse(retryAfterHeader);
            if (seconds != null && seconds > 0) {
              delay = Duration(seconds: seconds);
            }
          }
        }
        await Future.delayed(delay);
      }
    }
  }
''');
    }

    final sbCoreImports = StringBuffer();
    for (final imp in parser.coreDtoImports) {
      sbCoreImports.writeln("import '$imp';");
    }

    return '''
${_fileHeader(editable: true)}
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
${_customImports()}$streamImports$importDto$sbCoreImports
part '${_snake}_remote_data_source.g.dart';

@riverpod
${_pascal}RemoteDataSource ${_camel}RemoteDataSource(Ref ref) {
  // TODO: Replace with your global Dio provider, e.g.:
  //   final dio = ref.watch(dioProvider);
  //   return ${_pascal}RemoteDataSource(dio);
  return ${_pascal}RemoteDataSource(Dio());
}

class ${_pascal}RemoteDataSource {
  const ${_pascal}RemoteDataSource(this._dio);

  final Dio _dio;

${sb.toString()}}
''';
  }

  // ── REPOSITORY IMPL ───────────────────────────────────────────────────────

  String generateRepositoryImplCode() {
    final hasDomain =
        parser.domainClasses.isNotEmpty || parser.coreDomainImports.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final importModel = parser.domainClasses.isNotEmpty
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';
    final importLocalSource = offlineCache
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_local_data_source.dart';\n"
        : '';
    final importOfflineQueue = offlineMutationQueue
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_offline_queue.dart';\n"
        : '';

    final watchLocal = offlineCache
        ? "  final localDataSource = ref.watch(${_camel}LocalDataSourceProvider);\n"
        : '';
    final watchOfflineQueue = offlineMutationQueue
        ? "  final offlineQueue = ref.watch(${_camel}OfflineQueueProvider);\n"
        : '';

    final constructLocal =
        '${offlineCache ? ', localDataSource' : ''}${offlineMutationQueue ? ', offlineQueue' : ''}';
    final declareLocal =
        '${offlineCache ? '  final ${_pascal}LocalDataSource _localDataSource;\n' : ''}${offlineMutationQueue ? '  // ignore: unused_field\n  final ${_pascal}OfflineQueue _offlineQueue;\n' : ''}';
    final initLocal =
        '${offlineCache ? ', this._localDataSource' : ''}${offlineMutationQueue ? ', this._offlineQueue' : ''}';

    final sb = StringBuffer();

    if (offlineCache) {
      final cacheParams = _cacheParams();
      final paramStr = cacheParams.isNotEmpty ? cacheParams : '';
      final callArgs = _cacheCallArgs();
      final mappingExpr = hasDomain
          ? (parser.isTopLevelList
              ? 'cached.map((dto) => dto.toDomain()).toList()'
              : 'cached.toDomain()')
          : 'cached';

      final isSync = parser.providerType == 'provider';
      final awaitExpr = isSync ? '' : 'await ';
      sb.writeln('  @override');
      if (isSync) {
        sb.writeln(
            '  Either<${_pascal}Failure, $_dataType?> getCached$_pascal($paramStr) {');
      } else {
        sb.writeln(
            '  Future<Either<${_pascal}Failure, $_dataType?>> getCached$_pascal($paramStr) async {');
      }
      sb.writeln('    try {');
      sb.writeln(
          '      final cached = ${awaitExpr}_localDataSource.getLast$_pascal($callArgs);');
      sb.writeln('      if (cached == null) return right(null);');
      sb.writeln('      return right($mappingExpr);');
      sb.writeln('    } catch (_) {');
      sb.writeln('      return left(const ${_pascal}Failure.cacheFailure());');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    for (final method in methods) {
      final methodName = _methodName(method);
      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      final returnType = _repositoryReturnType(method);
      final callArgs = _remoteCallArgs(isWrite: _hasRequestBody(method));

      final isSync = parser.providerType == 'provider';
      final isStream = (parser.providerType == 'stream_provider' ||
              parser.providerType == 'stream_notifier') &&
          method.toUpperCase() == 'GET';

      if (isStream) {
        final mappingExpr = hasDomain
            ? (parser.isTopLevelList
                ? 'data.map((dto) => dto.toDomain()).toList()'
                : 'data.toDomain()')
            : 'data';
        sb.writeln('  @override');
        sb.writeln('  $returnType $methodName($params) async* {');
        sb.writeln('    try {');
        sb.writeln(
            '      await for (final data in _remoteDataSource.$methodName($callArgs)) {');
        if (offlineCache) {
          final cacheArgs = _cacheCallArgs();
          final cacheArgsStr = cacheArgs.isNotEmpty ? '$cacheArgs, ' : '';
          sb.writeln(
              '        _localDataSource.cache$_pascal(${cacheArgsStr}data);');
        }
        sb.writeln('        yield right($mappingExpr);');
        sb.writeln('      }');
        sb.writeln('    } on DioException catch (e) {');
        sb.writeln('      if (e.type == DioExceptionType.connectionTimeout ||');
        sb.writeln('          e.type == DioExceptionType.sendTimeout ||');
        sb.writeln('          e.type == DioExceptionType.receiveTimeout ||');
        sb.writeln('          e.type == DioExceptionType.connectionError) {');
        sb.writeln(
            '        yield left(const ${_pascal}Failure.networkError());');
        sb.writeln('      } else {');
        sb.writeln('        final dynamic data = e.response?.data;');
        sb.writeln('        String? errorMessage;');
        sb.writeln('        if (data is Map) {');
        sb.writeln("          final errorVal = data['error'];");
        sb.writeln('          if (errorVal is Map) {');
        sb.writeln(
            "            errorMessage = errorVal['message']?.toString() ?? errorVal['error']?.toString();");
        sb.writeln('          } else {');
        sb.writeln(
            "            errorMessage = errorVal?.toString() ?? data['message']?.toString();");
        sb.writeln('          }');
        sb.writeln('        }');
        sb.writeln('        errorMessage ??= e.message;');
        sb.writeln('        if (e.response?.statusCode == 429) {');
        sb.writeln(
            '          yield left(${_pascal}Failure.rateLimitExceeded(errorMessage));');
        sb.writeln('        } else {');
        sb.writeln(
            '          yield left(${_pascal}Failure.serverError(errorMessage));');
        sb.writeln('        }');
        sb.writeln('      }');
        sb.writeln('    } catch (e) {');
        sb.writeln(
            '      yield left(${_pascal}Failure.unexpectedError(e.toString()));');
        sb.writeln('    }');
        sb.writeln('  }');
        sb.writeln();
        continue;
      }

      final awaitExpr = isSync ? '' : 'await ';
      sb.writeln('  @override');
      if (isSync) {
        sb.writeln('  $returnType $methodName($params) {');
      } else {
        sb.writeln('  $returnType $methodName($params) async {');
      }
      sb.writeln('    try {');

      if (method.toUpperCase() == 'GET') {
        final isActualListResponse = parser.isTopLevelList ||
            (parser.isListResponse && parser.responseDtoClasses.isEmpty);
        final mappingExpr = hasDomain
            ? (isActualListResponse
                ? 'response.map((dto) => dto.toDomain()).toList()'
                : 'response.toDomain()')
            : 'response';
        final cacheArgs = _cacheCallArgs();
        final cacheArgsStr = cacheArgs.isNotEmpty ? '$cacheArgs, ' : '';

        sb.writeln(
            '      final response = ${awaitExpr}_remoteDataSource.$methodName($callArgs);');
        if (offlineCache) {
          sb.writeln(
              '      ${awaitExpr}_localDataSource.cache$_pascal(${cacheArgsStr}response);');
        }
        sb.writeln('      return right($mappingExpr);');
      } else {
        sb.writeln(
            '      ${awaitExpr}_remoteDataSource.$methodName($callArgs);');
        sb.writeln('      return right(unit);');
      }

      sb.writeln('    } on DioException catch (e) {');
      sb.writeln('      if (e.type == DioExceptionType.connectionTimeout ||');
      sb.writeln('          e.type == DioExceptionType.sendTimeout ||');
      sb.writeln('          e.type == DioExceptionType.receiveTimeout) {');
      sb.writeln(
          '        return left(const ${_pascal}Failure.timeoutFailure());');
      sb.writeln('      }');
      sb.writeln('      if (e.type == DioExceptionType.connectionError) {');
      sb.writeln(
          '        return left(const ${_pascal}Failure.networkError());');
      sb.writeln('      }');
      sb.writeln('      final int? statusCode = e.response?.statusCode;');
      sb.writeln('      if (statusCode == 401) {');
      sb.writeln(
          '        return left(const ${_pascal}Failure.unauthorizedFailure());');
      sb.writeln('      }');
      sb.writeln('      if (statusCode == 403) {');
      sb.writeln(
          '        return left(const ${_pascal}Failure.forbiddenFailure());');
      sb.writeln('      }');
      sb.writeln('      if (statusCode == 404) {');
      sb.writeln(
          '        return left(const ${_pascal}Failure.notFoundFailure());');
      sb.writeln('      }');
      sb.writeln('      final dynamic data = e.response?.data;');
      sb.writeln('      String? errorMessage;');
      sb.writeln('      Map<String, String>? fieldErrors;');
      sb.writeln('      if (data is Map) {');
      sb.writeln("        final errorVal = data['error'];");
      sb.writeln('        if (errorVal is Map) {');
      sb.writeln(
          "          errorMessage = errorVal['message']?.toString() ?? errorVal['error']?.toString();");
      sb.writeln('        } else {');
      sb.writeln(
          "          errorMessage = errorVal?.toString() ?? data['message']?.toString();");
      sb.writeln('        }');
      sb.writeln("        final errors = data['errors'];");
      sb.writeln('        if (errors is Map) {');
      sb.writeln('          fieldErrors = {');
      sb.writeln('            for (final e in errors.entries)');
      sb.writeln('              e.key.toString(): e.value.toString(),');
      sb.writeln('          };');
      sb.writeln('        }');
      sb.writeln('      }');
      sb.writeln('      errorMessage ??= e.message;');
      sb.writeln('      if (statusCode == 422) {');
      sb.writeln(
          '        return left(${_pascal}Failure.validationFailure(errorMessage, fieldErrors));');
      sb.writeln('      }');
      sb.writeln('      if (statusCode == 429) {');
      sb.writeln(
          '        return left(${_pascal}Failure.rateLimitExceeded(errorMessage));');
      sb.writeln('      }');
      sb.writeln(
          '      return left(${_pascal}Failure.serverError(errorMessage));');
      sb.writeln('    } catch (e) {');
      sb.writeln(
          '      return left(${_pascal}Failure.unexpectedError(e.toString()));');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    final sbCoreImports = StringBuffer();
    for (final imp in parser.coreDomainImports) {
      sbCoreImports.writeln("import '$imp';");
    }
    for (final imp in parser.coreDtoImports) {
      sbCoreImports.writeln("import '$imp';");
    }

    return '''
${_fileHeader(editable: true)}
import 'package:fpdart/fpdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:dio/dio.dart';
${_customImports()}
import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';
$sbCoreImports${importModel}import 'package:$packageName/features/$_snake/infrastructure/${_snake}_remote_data_source.dart';
$importLocalSource$importOfflineQueue$importDto
part '${_snake}_repository_impl.g.dart';

@riverpod
I${_pascal}Repository ${_camel}Repository(Ref ref) {
  final remoteDataSource = ref.watch(${_camel}RemoteDataSourceProvider);
$watchLocal$watchOfflineQueue  return ${_pascal}RepositoryImpl(remoteDataSource$constructLocal);
}

class ${_pascal}RepositoryImpl implements I${_pascal}Repository {
  const ${_pascal}RepositoryImpl(this._remoteDataSource$initLocal);

  final ${_pascal}RemoteDataSource _remoteDataSource;
$declareLocal
${sb.toString()}}
''';
  }

  // ── MOCK INTERCEPTOR ───────────────────────────────────────────────────────

  String generateMockInterceptorCode() {
    final responseLiteral = _formatDartLiteral(successResponse);
    // Safely escape the endpoint pattern for use as a RegExp inside Dart source
    final endpointPattern = endpoint
        .replaceAll(RegExp(r':\w+'), r'\w+')
        .replaceAll(RegExp(r'\{\w+\}'), r'\w+')
        .replaceAll(r'\', r'\\')
        .replaceAll('/', r'\/');

    return '''
${_fileHeader(editable: true)}
import 'package:dio/dio.dart';

/// A Dio [Interceptor] that short-circuits HTTP requests to the
/// $_pascal endpoint and returns a hardcoded mock response.
///
/// Register this interceptor on your Dio instance during development / testing:
/// ```dart
/// dio.interceptors.add(${_pascal}MockInterceptor());
/// ```
class ${_pascal}MockInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;
    final regExp = RegExp(r'$endpointPattern');
    if (regExp.hasMatch(path)) {
      final response = Response(
        requestOptions: options,
        data: $responseLiteral,
        statusCode: 200,
      );
      handler.resolve(response);
      return;
    }
    handler.next(options);
  }
}
''';
  }

  // ── LOCAL DATA SOURCE ─────────────────────────────────────────────────────

  String generateLocalDataSourceCode() {
    final hasDto = parser.responseDtoClasses.isNotEmpty;
    final isList = parser.isTopLevelList;
    final dtoType = hasDto
        ? (isList ? 'List<${_pascal}Dto>' : '${_pascal}Dto')
        : (isList ? 'List<${parser.responseDtoType}>' : parser.responseDtoType);

    final String serializerCall;
    final String deserializerCall;
    if (hasDto) {
      if (isList) {
        serializerCall = 'jsonEncode(dtos.map((e) => e.toJson()).toList())';
        deserializerCall =
            '(jsonDecode(jsonString) as List<dynamic>).map((e) => ${_pascal}Dto.fromJson(e as Map<String, dynamic>)).toList()';
      } else {
        serializerCall = 'jsonEncode(dto.toJson())';
        deserializerCall =
            '${_pascal}Dto.fromJson(jsonDecode(jsonString) as Map<String, dynamic>)';
      }
    } else {
      serializerCall = 'jsonEncode(data)';
      deserializerCall = 'jsonDecode(jsonString) as $dtoType';
    }

    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';
    final cacheParams = _cacheParams();
    final paramWithComma = cacheParams.isNotEmpty ? '$cacheParams, ' : '';
    final callArgs = _cacheCallArgs();

    final String cacheKeyExpr;
    if (pathParamsMap.isNotEmpty) {
      final suffixStr = pathParamsMap.values.map((v) => '\$$v').join('_');
      cacheKeyExpr = "'\${_cacheKey}_$suffixStr'";
    } else {
      cacheKeyExpr = '_cacheKey';
    }

    final paramName = hasDto
        ? (isList ? 'List<${_pascal}Dto> dtos' : '${_pascal}Dto dto')
        : '$dtoType data';

    // Build TTL-aware store/retrieve logic
    final hasTtl = cacheTtlSeconds > 0;

    final String storeBody;
    if (hasTtl) {
      storeBody = '''
    final key = $cacheKeyExpr;
    final envelope = jsonEncode({
      'data': ${hasDto ? (isList ? 'dtos.map((e) => e.toJson()).toList()' : 'dto.toJson()') : 'data'},
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _prefs.setString(key, envelope);''';
    } else {
      storeBody = '''
    final key = $cacheKeyExpr;
    await _prefs.setString(key, $serializerCall);''';
    }

    final String retrieveBody;
    if (hasTtl) {
      retrieveBody = '''
    final key = $cacheKeyExpr;
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = envelope['cachedAt'] as int?;
      if (cachedAt != null) {
        final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
        if (age > const Duration(seconds: $cacheTtlSeconds).inMilliseconds) {
          await clearCache$_pascal($callArgs); // Expired — clear it.
          return null;
        }
      }
      final jsonString = jsonEncode(envelope['data']);
      return $deserializerCall;
    } catch (_) {
      await clearCache$_pascal($callArgs); // Corrupt entry or schema mismatch — clear it.
      return null;
    }''';
    } else {
      retrieveBody = '''
    final key = $cacheKeyExpr;
    final jsonString = _prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      return $deserializerCall;
    } catch (_) {
      await clearCache$_pascal($callArgs); // Corrupt entry or schema mismatch — clear it.
      return null;
    }''';
    }

    return '''
${_fileHeader(editable: true)}
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
$importDto
part '${_snake}_local_data_source.g.dart';

@riverpod
${_pascal}LocalDataSource ${_camel}LocalDataSource(Ref ref) {
  // TODO: Replace with your global SharedPreferences provider, e.g.:
  //   final prefs = await ref.watch(sharedPreferencesProvider.future);
  //   return ${_pascal}LocalDataSource(prefs);
  throw UnimplementedError(
    'Configure your SharedPreferences provider and wire it here.',
  );
}

class ${_pascal}LocalDataSource {
  const ${_pascal}LocalDataSource(this._prefs);

  final SharedPreferences _prefs;
  static const String _cacheKey = 'CACHED_${_pascal.toUpperCase()}';
${hasTtl ? '\n  /// Cache TTL: $cacheTtlSeconds seconds.\n  // ignore: unused_field\n  static const int _ttlSeconds = $cacheTtlSeconds;' : ''}

  /// Persist [${isList ? 'dtos' : hasDto ? 'dto' : 'data'}] to SharedPreferences.
  Future<void> cache$_pascal($paramWithComma$paramName) async {
$storeBody
  }

  /// Retrieve the cached value, or `null` if absent${hasTtl ? ', expired,' : ''} or corrupt.
  Future<$dtoType?> getLast$_pascal($callArgs) async {
$retrieveBody
  }

  /// Remove the cached entry for $_pascal.
  ///
  /// Call this when you want to force a fresh network fetch on the next read.
  Future<void> clearCache$_pascal($cacheParams) async {
    final key = $cacheKeyExpr;
    await _prefs.remove(key);
  }

  /// Attempt to deserialise the cached entry and clear it on schema mismatch.
  ///
  /// Call this during app startup or after a model migration to ensure stale
  /// data does not persist silently.
  Future<void> migrateCache$_pascal($cacheParams) async {
    final result = await getLast$_pascal($callArgs);
    if (result == null) {
      // Already cleared or never populated — nothing to migrate.
      return;
    }
    // If deserialization succeeded the data is still compatible.
  }
}
''';
  }

  // ── PROVIDERS BARREL ──────────────────────────────────────────────────────

  String generateProvidersBarrelCode() {
    final sb = StringBuffer()..write(_fileHeader());
    sb.writeln(
        '// Barrel file — re-exports all Riverpod providers for this feature.');
    sb.writeln(
        '// Import this file in your UI layer to access all providers with a');
    sb.writeln('// single import.');
    sb.writeln();
    sb.writeln("export '${_snake}_notifier.dart';");
    sb.writeln("export '${_snake}_state.dart';");
    sb.writeln("export '${_snake}_derived_providers.dart';");
    if (parser.requestJson != null) {
      sb.writeln("export '${_snake}_form_notifier.dart';");
      sb.writeln("export '${_snake}_form_state.dart';");
    }
    return sb.toString();
  }

  String generateDerivedProvidersCode() {
    final hasCoreModel = parser.domainClasses.any((c) => c.isCore);
    final hasSelectProviders = !parser.isTopLevelList &&
        !parser.isListResponse &&
        hasCoreModel &&
        !useCustomState;

    final sb = StringBuffer()..write(_fileHeader(editable: true));
    sb.writeln(
        "import 'package:riverpod_annotation/riverpod_annotation.dart';");
    sb.writeln("import 'package:flutter_riverpod/flutter_riverpod.dart';");
    sb.writeln(
        "import 'package:$packageName/features/$_snake/application/providers.dart';");
    if (parser.domainClasses.isNotEmpty) {
      sb.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sb.writeln("import '$imp';");
    }
    // Combined providers custom imports
    for (final cp in combinedProviders) {
      final cpImports = cp['imports'] as List<dynamic>? ?? const [];
      for (final imp in cpImports) {
        sb.writeln("import '$imp';");
      }
    }
    sb.write(_customImports());
    sb.writeln();
    sb.writeln("part '${_snake}_derived_providers.g.dart';");
    sb.writeln();

    final String familyParamDecl;
    final String familyCall;
    if (familyParam != null) {
      final name = familyParam!['name']!;
      final type = familyParam!['type']!;
      familyParamDecl = ', $type $name';
      familyCall = '($name)';
    } else {
      familyParamDecl = '';
      familyCall = '';
    }

    final String elementClass =
        parser.isListResponse ? _elementDataType : _dataType;

    sb.writeln('''
/// Derived state provider representing the search query for filtering the $_pascal list.
@riverpod
class ${_pascal}SearchQuery extends _\$${_pascal}SearchQuery {
  @override
  String build() => '';

  void updateQuery(String newQuery) => state = newQuery;
}

/// Filtered items provider that filters $_pascal list based on search query.
@riverpod
List<$elementClass> filtered${_pascal}Items(Ref ref$familyParamDecl) {
  final query = ref.watch(${_camel}SearchQueryProvider).toLowerCase();
  final state = ref.watch($_providerName$familyCall);

  final List<dynamic> items = state.maybeWhen(
    data: (data) => ${parser.isListResponse ? 'data' : '[data]'},
    orElse: () => <dynamic>[],
  );

  if (query.isEmpty) return items.cast<$elementClass>().toList();
  return items.where((item) {
    final itemStr = item.toString().toLowerCase();
    return itemStr.contains(query);
  }).map((item) => item as $elementClass).toList();
}
''');

    for (final cp in combinedProviders) {
      final name = cp['name'] as String;
      final type = cp['type'] as String? ?? 'dynamic';
      final deps = cp['dependencies'] as List<dynamic>? ?? const [];
      final camelName = StringUtils.snakeToCamel(name);

      sb.writeln('/// Derived state combining: ${deps.join(', ')}');
      sb.writeln('@riverpod');
      sb.writeln('$type $camelName(Ref ref) {');
      for (final dep in deps) {
        final cleanName = dep.toString().replaceAll('Provider', '');
        sb.writeln('  // ignore: unused_local_variable');
        sb.writeln('  final $cleanName = ref.watch(${cleanName}Provider);');
      }
      sb.writeln('''
  // TODO: Add your derived state logic here.
  // E.g., combine watched values and return computed result.
  throw UnimplementedError('Implement derived state logic for $camelName');
}''');
      sb.writeln();
    }

    final isSync = parser.providerType == 'provider';
    if (hasSelectProviders) {
      final coreModel = parser.domainClasses.firstWhere((c) => c.isCore);
      sb.writeln(
          '// ── Select Optimization Providers ──────────────────────────────────');
      sb.writeln();
      for (final field in coreModel.fields) {
        if (!field.isNestedObject && !field.isNestedList) {
          final selectName =
              '${_camel}${StringUtils.toPascalCase(field.fieldName)}Select';
          if (isSync) {
            sb.writeln('@riverpod');
            sb.writeln(
                '${field.typeName} $selectName(Ref ref$familyParamDecl) {');
            sb.writeln(
                '  return ref.watch($_providerName$familyCall.select((s) => s.${field.fieldName}));');
            sb.writeln('}');
          } else if (parser.providerType == 'notifier') {
            final returnType = field.typeName.endsWith('?')
                ? field.typeName
                : '${field.typeName}?';
            sb.writeln('@riverpod');
            sb.writeln('$returnType $selectName(Ref ref$familyParamDecl) {');
            sb.writeln(
                '  return ref.watch($_providerName$familyCall.select((s) => s.maybeWhen(data: (d) => d.${field.fieldName}, orElse: () => null)));');
            sb.writeln('}');
          } else {
            sb.writeln('@riverpod');
            sb.writeln(
                'AsyncValue<${field.typeName}> $selectName(Ref ref$familyParamDecl) {');
            sb.writeln(
                '  return ref.watch($_providerName$familyCall.select((s) => s.whenData((d) => d.${field.fieldName})));');
            sb.writeln('}');
          }
          sb.writeln();
        }
      }
    }

    return sb.toString();
  }

  // ── FEATURE BARREL ────────────────────────────────────────────────────────

  String generateFeatureBarrelCode(Map<String, Directory> directories) {
    final sb = StringBuffer()..write(_fileHeader());
    sb.writeln(
        '// Feature barrel — re-exports the public API of the $_pascal feature.');
    sb.writeln();

    void export(String rel) => sb.writeln("export '$rel';");

    export('application/providers.dart');
    if (directories.containsKey('domain')) {
      if (parser.domainClasses.isNotEmpty) {
        export('domain/${_snake}_model.dart');
      }
      export('domain/${_snake}_failure.dart');
      export('domain/i_${_snake}_repository.dart');
    }
    if (directories.containsKey('infrastructure')) {
      if (parser.responseDtoClasses.isNotEmpty ||
          parser.requestDtoClasses.isNotEmpty) {
        export('infrastructure/${_snake}_dto.dart');
      }
      export('infrastructure/${_snake}_repository_impl.dart');
    }

    return sb.toString();
  }

  // ── DEBUG PAGE ────────────────────────────────────────────────────────────

  String generateDebugPageCode() {
    final hasDomain =
        parser.domainClasses.isNotEmpty || parser.coreDomainImports.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final pathParamArgs =
        pathParamsMap.values.map((n) => "'mock_$n'").join(', ');
    final providerArgsStr = pathParamArgs.isNotEmpty ? '($pathParamArgs)' : '';

    final isNotifier = parser.providerType == 'notifier' ||
        parser.providerType == 'async_notifier';
    final providerName = _providerName;
    final watchExpr = 'ref.watch($providerName$providerArgsStr)';

    final String displayBody;
    if (parser.providerType == 'notifier') {
      displayBody = '''
        state.when(
          initial: () => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Initial State — tap below to fetch data.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => ref
                    .read($providerName$providerArgsStr.notifier)
                    .fetch$_pascal(),
                child: const Text('Fetch Data'),
              ),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          data: (data) => SelectableText(data.toString()),
          error: (failure) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: \$failure',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => ref
                    .read($providerName$providerArgsStr.notifier)
                    .fetch$_pascal(),
                child: const Text('Retry'),
              ),
            ],
          ),
        )''';
    } else {
      displayBody = '''
        state.when(
          data: (data) => SelectableText(data.toString()),
          loading: () => const CircularProgressIndicator(),
          error: (error, stack) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: \$error',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  ${isNotifier ? "ref.read($providerName$providerArgsStr.notifier).refresh();" : "ref.invalidate($providerName);"}
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        )''';
    }

    final sbDomainImports = StringBuffer();
    if (hasDomain) {
      sbDomainImports.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sbDomainImports.writeln("import '$imp';");
    }
    final importModel = sbDomainImports.toString();
    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';

    final formFieldsSb = StringBuffer();
    String importForm = '';
    String formStateWatch = '';
    String formSubmitButton = '';

    if (parser.requestJson != null) {
      importForm = '''
import 'package:$packageName/features/$_snake/application/${_snake}_form_notifier.dart';
import 'package:$packageName/features/$_snake/application/${_snake}_form_state.dart';''';
      formStateWatch = 'final formState = ref.watch(${_camel}FormProvider);';
      final requestRootClass = _requestRootClass;
      if (requestRootClass != null) {
        for (final field in requestRootClass.fields) {
          final name = field.dartName;
          final pascal = StringUtils.toPascalCase(name);
          final label = StringUtils.toPascalCase(name);
          final cleanType = field.typeName.endsWith('?')
              ? field.typeName.substring(0, field.typeName.length - 1)
              : field.typeName;

          if (cleanType == 'String') {
            formFieldsSb.writeln('''
              TextFormField(
                initialValue: formState.$name,
                decoration: InputDecoration(
                  labelText: '$label',
                  errorText: formState.showErrorMessages
                      ? formState.${name}Error
                      : null,
                ),
                onChanged: ref
                    .read(${_camel}FormProvider.notifier)
                    .update$pascal,
              ),
              const SizedBox(height: 16),''');
          } else if (cleanType == 'int' ||
              cleanType == 'double' ||
              cleanType == 'num') {
            final parser = cleanType == 'int'
                ? 'int.tryParse(val) ?? 0'
                : 'double.tryParse(val) ?? 0.0';
            formFieldsSb.writeln('''
              TextFormField(
                initialValue: formState.$name.toString(),
                decoration: InputDecoration(
                  labelText: '$label',
                  errorText: formState.showErrorMessages
                      ? formState.${name}Error
                      : null,
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  ref
                      .read(${_camel}FormProvider.notifier)
                      .update$pascal($parser);
                },
              ),
              const SizedBox(height: 16),''');
          } else if (cleanType == 'bool') {
            formFieldsSb.writeln('''
              CheckboxListTile(
                title: const Text('$label'),
                value: formState.$name,
                onChanged: (val) {
                  ref
                      .read(${_camel}FormProvider.notifier)
                      .update$pascal(val ?? false);
                },
              ),
              const SizedBox(height: 16),''');
          } else {
            formFieldsSb.writeln('''
              TextFormField(
                enabled: false,
                decoration: const InputDecoration(
                  labelText: '$label (complex — edit manually)',
                ),
              ),
              const SizedBox(height: 16),''');
          }
        }

        final formSubmitArgs =
            pathParamsMap.values.map((n) => "$n: 'mock_$n'").join(', ');

        formSubmitButton = '''
              ElevatedButton(
                onPressed: formState.isSubmitting
                    ? null
                    : () async {
                        final success = await ref
                            .read(${_camel}FormProvider.notifier)
                            .submit($formSubmitArgs);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? '✅ Submitted successfully!'
                                    : '❌ Submission failed.',
                              ),
                            ),
                          );
                        }
                      },
                child: formState.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              )''';
      }
    }

    final String scaffoldBody;
    if (parser.requestJson != null) {
      scaffoldBody = '''
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Form',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ${formFieldsSb.toString()}
                      const SizedBox(height: 8),
                      $formSubmitButton,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'API State',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      $displayBody,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      )''';
    } else {
      scaffoldBody = '''
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: $displayBody,
        ),
      )''';
    }

    return '''
${_fileHeader(editable: true)}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
$importModel${importDto}import 'package:$packageName/features/$_snake/application/${_snake}_notifier.dart';
import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/infrastructure/${_snake}_repository_impl.dart';
${parser.providerType == 'notifier' ? "import 'package:$packageName/features/$_snake/application/${_snake}_state.dart';\n" : ''}$importForm

/// Debug / developer page for the $_pascal feature.
///
/// Shows the full API state and (when a request body is configured) a
/// wired form that calls the repository directly. This page is intended
/// for local development and integration testing only. **Remove or guard
/// behind a debug flag before shipping to production.**
class ${_pascal}DebugPage extends ConsumerWidget {
  const ${_pascal}DebugPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = $watchExpr;
    $formStateWatch

    return Scaffold(
      appBar: AppBar(title: const Text('$_pascal · Debug')),
      $scaffoldBody,
    );
  }
}
''';
  }

  // ── NOTIFIER TEST ─────────────────────────────────────────────────────────

  String generateNotifierTestCode() {
    final hasDomain =
        parser.domainClasses.isNotEmpty || parser.coreDomainImports.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final importModel = parser.domainClasses.isNotEmpty
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';
    final importState = parser.providerType == 'notifier'
        ? "import 'package:$packageName/features/$_snake/application/${_snake}_state.dart';\n"
        : '';

    final sbImports = StringBuffer();
    for (final imp in parser.coreDomainImports) {
      sbImports.writeln("import '$imp';");
    }
    for (final imp in parser.coreDtoImports) {
      sbImports.writeln("import '$imp';");
    }

    final pathParamArgs =
        pathParamsMap.values.map((n) => "'mock_$n'").join(', ');
    final providerArgsStr = pathParamArgs.isNotEmpty ? '($pathParamArgs)' : '';

    final providerName = _providerName;

    final mockFields = <String>[];
    final mockMethods = <String>[];

    for (final method in methods) {
      final name = _methodName(method);
      final returnType = _repositoryReturnType(method);
      final String innerType;
      if (returnType.startsWith('Future<')) {
        innerType =
            returnType.substring('Future<'.length, returnType.length - 1);
      } else if (returnType.startsWith('Stream<')) {
        innerType =
            returnType.substring('Stream<'.length, returnType.length - 1);
      } else {
        innerType = returnType;
      }

      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      if (returnType.startsWith('Stream<')) {
        mockFields.add('Stream<$innerType>? ${name}Result;');
        mockMethods.add('''
  @override
  $returnType $name($params) {
    final result = ${name}Result;
    if (result == null) {
      throw UnimplementedError('Set ${name}Result before calling $name.');
    }
    return result;
  }''');
      } else {
        mockFields.add('$innerType? ${name}Result;');
        final isSync = parser.providerType == 'provider';
        final asyncModifier = isSync ? '' : 'async';
        mockMethods.add('''
  @override
  $returnType $name($params) $asyncModifier {
    final result = ${name}Result;
    if (result == null) {
      throw UnimplementedError('Set ${name}Result before calling $name.');
    }
    return result;
  }''');
      }
    }

    if (offlineCache) {
      final cacheParams = _cacheParams();
      mockFields
          .add('Either<${_pascal}Failure, $_dataType?>? getCachedResult;');
      final isSync = parser.providerType == 'provider';
      if (isSync) {
        mockMethods.add('''
  @override
  Either<${_pascal}Failure, $_dataType?> getCached$_pascal($cacheParams) =>
      getCachedResult ?? right(null);''');
      } else {
        mockMethods.add('''
  @override
  Future<Either<${_pascal}Failure, $_dataType?>> getCached$_pascal($cacheParams) async =>
      getCachedResult ?? right(null);''');
      }
    }

    String mockDataStr = 'null';
    if (parser.responseDtoClasses.isNotEmpty) {
      if (parser.isTopLevelList) {
        final listElems = <String>[];
        if (successResponse is List) {
          for (final item in successResponse as List) {
            if (item is Map<String, dynamic>) {
              listElems.add(
                  '${_generateDtoInstantiation(_pascal, item)}${hasDomain ? ".toDomain()" : ""}');
            } else {
              listElems.add(_formatDartLiteral(item));
            }
          }
        }
        mockDataStr = '[${listElems.join(', ')}]';
      } else {
        final mockDtoStr = _generateDtoInstantiation(
          _pascal,
          successResponse is Map<String, dynamic>
              ? successResponse as Map<String, dynamic>
              : const {},
        );
        mockDataStr = hasDomain ? '$mockDtoStr.toDomain()' : mockDtoStr;
      }
    } else if (successResponse != null) {
      final primitives = {
        'int',
        'double',
        'num',
        'String',
        'bool',
        'dynamic',
        'void'
      };
      final isPrimitive = primitives.contains(parser.responseDtoType);
      if (parser.isListResponse && successResponse is List) {
        if (!isPrimitive && hasDomain) {
          final elems = (successResponse as List)
              .map((e) =>
                  '${parser.responseDtoType}.fromJson(${_formatDartLiteral(e)}).toDomain()')
              .join(', ');
          mockDataStr = '[$elems]';
        } else {
          final elems =
              (successResponse as List).map(_formatDartLiteral).join(', ');
          mockDataStr = '[$elems]';
        }
      } else {
        if (!isPrimitive && hasDomain) {
          mockDataStr =
              '${parser.responseDtoType}.fromJson(${_formatDartLiteral(successResponse)}).toDomain()';
        } else {
          mockDataStr = _formatDartLiteral(successResponse);
        }
      }
    }

    final getMethodName = methods.contains('GET')
        ? _methodName('GET')
        : _methodName(methods.first);
    final getResultField = '${getMethodName}Result';

    final isStream = parser.providerType == 'stream_provider' ||
        parser.providerType == 'stream_notifier';
    final getResultAssignment =
        isStream ? 'Stream.value(right(mockData))' : 'right(mockData)';
    final getResultFailureAssignment =
        isStream ? 'Stream.value(left(failure))' : 'left(failure)';

    final requestRootClass = _requestRootClass;
    final submitArgs = StringBuffer();
    if (requestRootClass != null) {
      final fields = requestRootClass.fields;
      for (final f in fields) {
        final val = () {
          if (parser.requestJson is Map<String, dynamic>) {
            final jsonVal = parser.requestJson[f.jsonKey];
            if (jsonVal != null) {
              return _formatDartLiteral(jsonVal);
            }
          }
          final cleanType = f.typeName.endsWith('?')
              ? f.typeName.substring(0, f.typeName.length - 1)
              : f.typeName;
          return switch (cleanType) {
            'String' => "'mock_${f.dartName}'",
            'int' => '1',
            'double' || 'num' => '1.0',
            'bool' => 'true',
            'DateTime' => "DateTime.parse('2026-06-15T22:12:00Z')",
            _ => 'null'
          };
        }();
        submitArgs.write('${f.dartName}: $val, ');
      }
    }

    final String testCasesCode;
    if (parser.providerType == 'notifier') {
      if (_hasGet) {
        testCasesCode = '''
    test('fetch$_pascal transitions to data on success', () async {
      final mockData = $mockDataStr;
      mockRepository.$getResultField = right(mockData);

      final notifier =
          container.read($providerName$providerArgsStr.notifier);
      final states = <${_pascal}State>[];
      container.listen(
        $providerName$providerArgsStr,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await notifier.fetch$_pascal();

      expect(states, equals([
        const ${_pascal}State.initial(),
        const ${_pascal}State.loading(),
        ${_pascal}State.data(mockData),
      ]));
    });

    test('fetch$_pascal transitions to error on failure', () async {
      const failure = ${_pascal}Failure.serverError('Server error');
      mockRepository.$getResultField = left(failure);

      final notifier =
          container.read($providerName$providerArgsStr.notifier);
      final states = <${_pascal}State>[];
      container.listen(
        $providerName$providerArgsStr,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await notifier.fetch$_pascal();

      expect(states, equals([
        const ${_pascal}State.initial(),
        const ${_pascal}State.loading(),
        const ${_pascal}State.error(failure),
      ]));
    });''';
      } else {
        testCasesCode = '''
    test('submit transitions state correctly on success', () async {
      mockRepository.$getResultField = right(unit);

      final notifier =
          container.read($providerName$providerArgsStr.notifier);
      final states = <${_pascal}State>[];
      container.listen(
        $providerName$providerArgsStr,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await notifier.submit($submitArgs);

      expect(states, equals([
        const ${_pascal}State.initial(),
        const ${_pascal}State.loading(),
        const ${_pascal}State.initial(),
      ]));
    });

    test('submit transitions to error on failure', () async {
      const failure = ${_pascal}Failure.serverError('Server error');
      mockRepository.$getResultField = left(failure);

      final notifier =
          container.read($providerName$providerArgsStr.notifier);
      final states = <${_pascal}State>[];
      container.listen(
        $providerName$providerArgsStr,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await notifier.submit($submitArgs);

      expect(states, equals([
        const ${_pascal}State.initial(),
        const ${_pascal}State.loading(),
        const ${_pascal}State.error(failure),
      ]));
    });''';
      }
    } else {
      testCasesCode = '''
    test('success resolves provider to data', () async {
      final mockData = $mockDataStr;
      mockRepository.$getResultField = $getResultAssignment;

      // Listen to the provider to keep it alive
      final subscription = container.listen($providerName$providerArgsStr, (_, __) {});

      final result = await container
          .read($providerName$providerArgsStr.future);
      expect(result, equals(mockData));

      final state = container.read($providerName$providerArgsStr);
      expect(state, equals(AsyncData(mockData)));

      subscription.close();
    });

    test('failure resolves provider to AsyncError', () async {
      const failure = ${_pascal}Failure.serverError('Server error');
      mockRepository.$getResultField = $getResultFailureAssignment;

      // Listen to the provider to keep it alive
      final subscription = container.listen($providerName$providerArgsStr, (_, __) {});

      await expectLater(
        container.read($providerName$providerArgsStr.future),
        throwsA(equals(failure)),
      );

      final state = container.read($providerName$providerArgsStr);
      expect(state, isA<AsyncError<$_dataType>>());

      subscription.close();
    });''';
    }

    return '''
${_fileHeader(editable: true)}
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';
$importModel$importDto$importState${sbImports}import 'package:$packageName/features/$_snake/application/${_snake}_notifier.dart';
import 'package:$packageName/features/$_snake/infrastructure/${_snake}_repository_impl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock repository
// ─────────────────────────────────────────────────────────────────────────────

class Mock${_pascal}Repository implements I${_pascal}Repository {
  ${mockFields.join('\n  ')}

  ${mockMethods.join('\n\n  ')}
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Mock${_pascal}Repository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = Mock${_pascal}Repository();
    container = ProviderContainer(
      overrides: [
        ${_camel}RepositoryProvider.overrideWith((ref) => mockRepository),
      ],
    );
    addTearDown(container.dispose);
  });

  group('${_pascal}Notifier', () {
$testCasesCode
  });
}
''';
  }

  // ── FORM STATE ────────────────────────────────────────────────────────────

  String generateFormStateCode() {
    final requestRootClass = _requestRootClass;
    final sb = StringBuffer();
    if (requestRootClass != null) {
      for (final field in requestRootClass.fields) {
        sb.writeln('    ${_formFieldDef(field)}');
        sb.writeln('    String? ${field.dartName}Error,');
      }
    }

    final importDto = requestRootClass != null
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';

    return '''
${_fileHeader()}
import 'package:freezed_annotation/freezed_annotation.dart';
$importDto
part '${_snake}_form_state.freezed.dart';

@freezed
abstract class ${_pascal}FormState with _\$${_pascal}FormState {
  const factory ${_pascal}FormState({
${sb.toString()}    @Default(false) bool isSubmitting,
    @Default(false) bool showErrorMessages,
    @Default(false) bool isValid,
    @Default(false) bool isSuccess,
    String? errorMessage,
  }) = _${_pascal}FormState;
}
''';
  }

  // ── FORM NOTIFIER ─────────────────────────────────────────────────────────

  String generateFormNotifierCode() {
    final requestRootClass = _requestRootClass;
    if (requestRootClass == null) return '';

    final updatesSb = StringBuffer();
    for (final field in requestRootClass.fields) {
      final name = field.dartName;
      final paramType = _formParamType(field.typeName);
      final pascal = StringUtils.toPascalCase(name);

      final dependentAssignments = <String>[];
      for (final other in requestRootClass.fields) {
        final otherRule = parser.validationRules[other.jsonKey] ??
            parser.validationRules[other.dartName];
        if (otherRule is Map<String, dynamic> &&
            (otherRule['matches'] == field.jsonKey ||
                otherRule['matches'] == field.dartName)) {
          final otherPascal = StringUtils.toPascalCase(other.dartName);
          dependentAssignments.add(
              '${other.dartName}Error: _validate$otherPascal(state.${other.dartName}),');
        }
      }

      final depLines = dependentAssignments.isNotEmpty
          ? '\n      ${dependentAssignments.join('\n      ')}'
          : '';

      updatesSb.writeln('''
  void update$pascal($paramType value) {
    state = state.copyWith($name: value);
    state = state.copyWith(
      ${name}Error: _validate$pascal(state.$name),$depLines
    );
    _validateForm();
  }
''');
    }

    final validatorsSb = StringBuffer();
    for (final field in requestRootClass.fields) {
      final rule = parser.validationRules[field.jsonKey] ??
          parser.validationRules[field.dartName];
      final Map<String, dynamic>? ruleMap =
          rule is Map<String, dynamic> ? rule : null;
      validatorsSb.writeln(_validatorMethod(field, ruleMap));
    }

    final repoMethod = _resolveWriteMethodName();
    final submitParams = <String>[];
    final repoArgs = <String>[];
    pathParamsMap.forEach((_, name) {
      submitParams.add('required String $name');
      repoArgs.add('$name: $name');
    });

    final assignments = requestRootClass.fields
        .map((f) => '${f.dartName}: state.${f.dartName}')
        .join(', ');
    repoArgs.add('request: ${_pascal}RequestDto($assignments)');

    final submitParamsStr =
        submitParams.isNotEmpty ? '{${submitParams.join(', ')}}' : '';
    final repoArgsStr = repoArgs.join(', ');

    final allValid = requestRootClass.fields
        .map((f) =>
            '_validate${StringUtils.toPascalCase(f.dartName)}(state.${f.dartName}) == null')
        .join(' &&\n        ');

    final allErrors = requestRootClass.fields
        .map((f) =>
            '${f.dartName}Error: _validate${StringUtils.toPascalCase(f.dartName)}(state.${f.dartName})')
        .join(',\n      ');

    return '''
${_fileHeader(editable: true)}
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';
import 'package:$packageName/features/$_snake/infrastructure/${_snake}_repository_impl.dart';
import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';
import '${_snake}_form_state.dart';

part '${_snake}_form_notifier.g.dart';

@riverpod
class ${_pascal}FormNotifier extends _\$${_pascal}FormNotifier {
  @override
  ${_pascal}FormState build() => const ${_pascal}FormState();

${updatesSb.toString()}
  void _validateForm() {
    state = state.copyWith(
      isValid: $allValid,
    );
  }

${validatorsSb.toString()}
  /// Validate all fields, then submit the form to the repository.
  ///
  /// Returns `true` on success, `false` on validation failure or remote error.
  Future<bool> submit($submitParamsStr) async {
    state = state.copyWith(
      $allErrors,
      showErrorMessages: true,
      isSuccess: false,
      errorMessage: null,
    );
    _validateForm();
    if (!state.isValid) return false;

    state = state.copyWith(
      isSubmitting: true,
      isSuccess: false,
      errorMessage: null,
    );
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgsStr);
    state = state.copyWith(
      isSubmitting: false,
      isSuccess: result.isRight(),
      errorMessage: result.fold(
        (failure) => switch (failure) {
          ${_pascal}FailureServerError(:final message) => message ?? 'Server error occurred',
          ${_pascal}FailureNetworkError() => 'No internet connection',
          ${_pascal}FailureTimeoutFailure() => 'Request timed out. Please try again.',
          ${_pascal}FailureUnauthorizedFailure(:final message) => message ?? 'Unauthorized. Please log in again.',
          ${_pascal}FailureForbiddenFailure(:final message) => message ?? 'You do not have permission to perform this action.',
          ${_pascal}FailureNotFoundFailure(:final message) => message ?? 'The requested resource was not found.',
          ${_pascal}FailureValidationFailure(:final message) => message ?? 'Validation failed. Please check your input.',
          ${_pascal}FailureUnexpectedError(:final message) => message ?? 'An unexpected error occurred',
          ${_pascal}FailureRateLimitExceeded(:final message) => message ?? 'Rate limit exceeded. Please try again later.',
          ${_pascal}FailureCacheFailure(:final message) => message ?? 'A local cache error occurred.',
        },
        (_) => null,
      ),
    );
    return result.isRight();
  }
}
''';
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  DtoClass? get _requestRootClass {
    final rootName = '${_pascal}Request';
    try {
      return parser.requestDtoClasses
          .firstWhere((c) => c.className == rootName);
    } catch (_) {
      return null;
    }
  }

  String _formFieldDef(DtoField field) {
    final cleanType = field.typeName.endsWith('?')
        ? field.typeName.substring(0, field.typeName.length - 1)
        : field.typeName;
    return switch (cleanType) {
      'String' => "@Default('') String ${field.dartName},",
      'int' => '@Default(0) int ${field.dartName},',
      'double' || 'num' => '@Default(0.0) double ${field.dartName},',
      'bool' => '@Default(false) bool ${field.dartName},',
      _ when cleanType.startsWith('List<') =>
        '@Default([]) $cleanType ${field.dartName},',
      _ => '$cleanType? ${field.dartName},',
    };
  }

  String _formParamType(String typeName) {
    final clean = typeName.endsWith('?')
        ? typeName.substring(0, typeName.length - 1)
        : typeName;
    return switch (clean) {
      'String' => 'String',
      'int' => 'int',
      'double' || 'num' => 'double',
      'bool' => 'bool',
      _ when clean.startsWith('List<') => clean,
      _ => '$clean?',
    };
  }

  String _validatorMethod(DtoField field, Map<String, dynamic>? ruleMap) {
    final name = field.dartName;
    final pascal = StringUtils.toPascalCase(name);
    final paramType = _formParamType(field.typeName);
    final isRequired = !(field.typeName.endsWith('?'));
    final isEmail = name.toLowerCase().contains('email');

    final sb = StringBuffer();
    sb.writeln('  String? _validate$pascal($paramType value) {');

    final required_ = ruleMap?['required'] == true || isRequired;
    final errorMsg = ruleMap?['error_msg'] as String?;
    final minLength = ruleMap?['min_length'] as int?;
    final minVal = ruleMap?['min'] as num?;
    final typeRule = ruleMap?['type'] as String?;
    final regexPattern = ruleMap?['regex'] as String?;
    final matchesField = ruleMap?['matches'] as String?;

    if (!required_) {
      if (paramType == 'String') {
        sb.writeln('    if (value.trim().isEmpty) return null;');
      }
    }

    if (required_) {
      if (paramType == 'String') {
        sb.writeln('    if (value.trim().isEmpty) {');
        sb.writeln(
            "      return ${errorMsg != null ? "'$errorMsg'" : "'${StringUtils.toPascalCase(name)} is required'"};");
        sb.writeln('    }');
      }
    }

    if (minLength != null && paramType == 'String') {
      sb.writeln('    if (value.length < $minLength) {');
      sb.writeln(
          "      return ${errorMsg != null ? "'$errorMsg'" : "'Must be at least $minLength characters'"};");
      sb.writeln('    }');
    }

    if (minVal != null) {
      sb.writeln('    if (value < $minVal) {');
      sb.writeln(
          "      return ${errorMsg != null ? "'$errorMsg'" : "'Must be at least $minVal'"};");
      sb.writeln('    }');
    }

    final isEmailField = isEmail || typeRule == 'email';
    if (isEmailField && paramType == 'String') {
      sb.writeln(
          r"    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');");
      sb.writeln('    if (!emailRegex.hasMatch(value)) {');
      sb.writeln(
          "      return ${errorMsg != null ? "'$errorMsg'" : "'Please enter a valid email address'"};");
      sb.writeln('    }');
    }

    if (regexPattern != null && paramType == 'String') {
      sb.writeln("    final regex = RegExp(r'$regexPattern');");
      sb.writeln('    if (!regex.hasMatch(value)) {');
      sb.writeln(
          "      return ${errorMsg != null ? "'$errorMsg'" : "'Invalid format'"};");
      sb.writeln('    }');
    }

    if (matchesField != null) {
      final matchesCamel = StringUtils.snakeToCamel(matchesField);
      sb.writeln('    if (value != state.$matchesCamel) {');
      sb.writeln(
          "      return ${errorMsg != null ? "'$errorMsg'" : "'Does not match $matchesCamel'"};");
      sb.writeln('    }');
    }

    sb.writeln('    return null;');
    sb.writeln('  }');
    return sb.toString();
  }

  // ── Literal formatting ────────────────────────────────────────────────────

  String _formatDartLiteral(dynamic value) {
    if (value == null) return 'null';
    if (value is String) {
      final escaped = value
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r')
          .replaceAll('\t', '\\t')
          .replaceAll('\$', '\\\$');
      return "'$escaped'";
    }
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      return '[${value.map(_formatDartLiteral).join(', ')}]';
    }
    if (value is Map) {
      final entries = value.entries
          .map((e) =>
              '${_formatDartLiteral(e.key)}: ${_formatDartLiteral(e.value)}')
          .join(', ');
      return '{$entries}';
    }
    return 'null';
  }

  String _generateDtoInstantiation(String className, Map<String, dynamic> map) {
    final cleanClassName =
        className.endsWith('Dto') ? className : '${className}Dto';
    final lookupName = className.endsWith('Dto')
        ? className.substring(0, className.length - 3)
        : className;
    final allDtoClasses = [
      ...parser.requestDtoClasses,
      ...parser.responseDtoClasses,
    ];
    final dtoClass =
        allDtoClasses.where((c) => c.className == lookupName).firstOrNull;

    // If the DTO class is not found locally (e.g. it's a registry-matched core DTO),
    // fall back to .fromJson() to avoid missing required fields.
    if (dtoClass == null) {
      return '$cleanClassName.fromJson(${_formatDartLiteral(map)})';
    }

    final sb = StringBuffer()..write('$cleanClassName(');
    final assignments = <String>[];
    for (final field in dtoClass.fields) {
      final val = map[field.jsonKey];
      if (val == null) {
        assignments.add('${field.dartName}: null');
      } else if (field.isNestedObject && val is Map<String, dynamic>) {
        assignments.add(
            '${field.dartName}: ${_generateDtoInstantiation(field.nestedClassName!, val)}');
      } else if (field.isNestedList && val is List) {
        final elems = val
            .whereType<Map<String, dynamic>>()
            .map((e) => _generateDtoInstantiation(field.nestedClassName!, e))
            .join(', ');
        assignments.add('${field.dartName}: [$elems]');
      } else {
        if ((field.typeName == 'DateTime' || field.typeName == 'DateTime?') &&
            val is String) {
          assignments.add(
              '${field.dartName}: DateTime.parse(${_formatDartLiteral(val)})');
        } else {
          assignments.add('${field.dartName}: ${_formatDartLiteral(val)}');
        }
      }
    }
    sb.write(assignments.join(', '));
    sb.write(')');
    return sb.toString();
  }

  String generateOfflineQueueCode() {
    return '''
${_fileHeader()}
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

part '${_snake}_offline_queue.g.dart';

@riverpod
${_pascal}OfflineQueue ${_camel}OfflineQueue(Ref ref) {
  // TODO: Retrieve SharedPreferences and Dio from your dependency injection graph.
  // E.g., final prefs = ref.watch(sharedPreferencesProvider);
  //       final dio = ref.watch(dioProvider);
  //       return ${_pascal}OfflineQueue(dio, prefs);
  throw UnimplementedError('Please configure SharedPreferences and Dio dependency resolution.');
}

class ${_pascal}OfflineQueue {
  ${_pascal}OfflineQueue(this._dio, this._prefs);

  final Dio _dio;
  final SharedPreferences _prefs;
  static const _key = 'offline_mutations_$_snake';

  Future<void> enqueue({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    final pending = _getPending();
    pending.add({
      'method': method,
      'url': url,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _prefs.setString(_key, jsonEncode(pending));
  }

  List<Map<String, dynamic>> _getPending() {
    final data = _prefs.getString(_key);
    if (data == null) return [];
    try {
      final list = jsonDecode(data);
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Hook called when a synced mutation encounters a 409 Conflict from the server.
  ///
  /// Override this or customize the TODO to implement your resolution strategy.
  Future<void> onConflict(Map<String, dynamic> item, DioException exception) async {
    // TODO: Implement your conflict resolution strategy (e.g. server-wins, client-wins, merge).
  }

  Future<void> sync() async {
    final pending = _getPending();
    if (pending.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (final item in pending) {
      try {
        final method = item['method'] as String;
        final url = item['url'] as String;
        final body = item['body'] as Map<String, dynamic>?;

        await _dio.request(
          url,
          data: body,
          options: Options(method: method),
        );
      } catch (e) {
        if (e is DioException) {
          if (e.response?.statusCode == 409) {
            await onConflict(item, e);
          } else if (
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError
          ) {
            remaining.add(item);
          }
        }
      }
    }

    if (remaining.isEmpty) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, jsonEncode(remaining));
    }
  }
}
''';
  }

  String generateObserverCode() {
    return '''
${_fileHeader()}
import 'package:flutter_riverpod/flutter_riverpod.dart';

base class AppProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    // TODO: Add logging or analytics implementation
    // print('Provider \${provider.name ?? provider.runtimeType} updated: \$newValue');
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    // print('Provider \${provider.name ?? provider.runtimeType} added: \$value');
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    // print('Provider \${provider.name ?? provider.runtimeType} disposed');
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    // print('Provider \${provider.name ?? provider.runtimeType} failed: \$error');
  }
}
''';
  }

  String generateAnalyticsObserverCode() {
    return '''
${_fileHeader()}
import 'package:flutter_riverpod/flutter_riverpod.dart';

base class AnalyticsProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final name = provider.name ?? provider.runtimeType.toString();
    // Firebase / Mixpanel style event formatting
    final eventName = 'provider_update_\${_formatName(name)}';
    _trackEvent(eventName, {
      'provider': name,
      'newValue': newValue.toString(),
    });
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final name = provider.name ?? provider.runtimeType.toString();
    final eventName = 'provider_add_\${_formatName(name)}';
    _trackEvent(eventName, {
      'provider': name,
      'value': value.toString(),
    });
  }

  String _formatName(String name) {
    return name
        .replaceAll(RegExp(r'(Provider|Notifier)\$'), '')
        .replaceAll(RegExp(r'(?<=.)(?=[A-Z])'), '_')
        .toLowerCase();
  }

  void _trackEvent(String eventName, Map<String, dynamic> properties) {
    // TODO: Plug in your Firebase Analytics / Mixpanel client here
    // analytics.logEvent(name: eventName, parameters: properties);
  }
}
''';
  }

  String generateDebugObserverCode() {
    return '''
${_fileHeader()}
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

base class DebugProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      final name = provider.name ?? provider.runtimeType.toString();
      final logMap = {
        'event': 'didUpdateProvider',
        'provider': name,
        'previousValue': previousValue,
        'newValue': newValue,
      };
      _prettyPrint(logMap);
    }
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      final name = provider.name ?? provider.runtimeType.toString();
      final logMap = {
        'event': 'didAddProvider',
        'provider': name,
        'value': value,
      };
      _prettyPrint(logMap);
    }
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      final name = provider.name ?? provider.runtimeType.toString();
      final logMap = {
        'event': 'didDisposeProvider',
        'provider': name,
      };
      _prettyPrint(logMap);
    }
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      final name = provider.name ?? provider.runtimeType.toString();
      final logMap = {
        'event': 'providerDidFail',
        'provider': name,
        'error': error.toString(),
      };
      _prettyPrint(logMap);
    }
  }

  void _prettyPrint(Map<String, dynamic> map) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final pretty = encoder.convert(map);
      debugPrint('┌── Riverpod Debug Event ──────────────────────────────────────');
      debugPrint(pretty);
      debugPrint('└──────────────────────────────────────────────────────────────');
    } catch (_) {
      debugPrint('Riverpod Event: \${map['event']} - \${map['provider']}');
    }
  }
}
''';
  }

  String generateTestOverridesCode() {
    final sbDomainImports = StringBuffer();
    if (parser.domainClasses.isNotEmpty) {
      sbDomainImports.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
    }
    for (final imp in parser.coreDomainImports) {
      sbDomainImports.writeln("import '$imp';");
    }
    final domainImport = sbDomainImports.toString();

    final params = pathParamsMap.values.join(', ');
    final lambdaParams = params.isNotEmpty ? 'ref, $params' : 'ref';
    final buildParams = _notifierBuildParams();

    final String stateType;
    final String overrideBody;
    final String extraClasses;

    switch (parser.providerType) {
      case 'provider':
        stateType = _dataType;
        overrideBody =
            'return $_providerName.overrideWith(($lambdaParams) => mockValue);';
        extraClasses = '';
        break;
      case 'future_provider':
        stateType = 'FutureOr<$_dataType>';
        overrideBody =
            'return $_providerName.overrideWith(($lambdaParams) => mockValue);';
        extraClasses = '';
        break;
      case 'stream_provider':
        stateType = 'Stream<$_dataType>';
        overrideBody =
            'return $_providerName.overrideWith(($lambdaParams) => mockValue);';
        extraClasses = '';
        break;
      case 'notifier':
        stateType = '${_pascal}State';
        overrideBody = params.isNotEmpty
            ? 'return $_providerName.overrideWith2(($params) => Mock${_pascal}Notifier(mockValue));'
            : 'return $_providerName.overrideWith(() => Mock${_pascal}Notifier(mockValue));';
        extraClasses = '''

class Mock${_pascal}Notifier extends ${_pascal}Notifier {
  Mock${_pascal}Notifier(this._mockState);
  final ${_pascal}State _mockState;

  @override
  ${_pascal}State build($buildParams) => _mockState;
}
''';
        break;
      case 'async_notifier':
        stateType = 'FutureOr<$_dataType>';
        overrideBody = params.isNotEmpty
            ? 'return $_providerName.overrideWith2(($params) => Mock${_pascal}Notifier(mockValue));'
            : 'return $_providerName.overrideWith(() => Mock${_pascal}Notifier(mockValue));';
        extraClasses = '''

class Mock${_pascal}Notifier extends ${_pascal}Notifier {
  Mock${_pascal}Notifier(this._mockState);
  final FutureOr<$_dataType> _mockState;

  @override
  FutureOr<$_dataType> build($buildParams) => _mockState;
}
''';
        break;
      case 'stream_notifier':
        stateType = 'Stream<$_dataType>';
        overrideBody = params.isNotEmpty
            ? 'return $_providerName.overrideWith2(($params) => Mock${_pascal}Notifier(mockValue));'
            : 'return $_providerName.overrideWith(() => Mock${_pascal}Notifier(mockValue));';
        extraClasses = '''

class Mock${_pascal}Notifier extends ${_pascal}Notifier {
  Mock${_pascal}Notifier(this._mockState);
  final Stream<$_dataType> _mockState;

  @override
  Stream<$_dataType> build($buildParams) => _mockState;
}
''';
        break;
      default:
        stateType = 'AsyncValue<$_dataType>';
        overrideBody =
            'return $_providerName.overrideWith((ref) => mockValue);';
        extraClasses = '';
    }

    return '''
${_fileHeader()}
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:$packageName/features/$_snake/application/providers.dart';
import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/infrastructure/${_snake}_repository_impl.dart';
$domainImport${_customImports()}
/// Scoped provider override stubs for different environments / tests for $_pascal.
///
/// Use these in your [ProviderContainer] or [ProviderScope] to mock components.
class ${_pascal}TestOverrides {
  /// Override the repository provider with a mock implementation.
  static Override overrideRepository(I${_pascal}Repository mockRepository) {
    return ${_camel}RepositoryProvider.overrideWith((ref) => mockRepository);
  }

  /// Override the root query/data provider with a custom value.
  static Override overrideData($stateType mockValue) {
    $overrideBody
  }
}$extraClasses
''';
  }
}
