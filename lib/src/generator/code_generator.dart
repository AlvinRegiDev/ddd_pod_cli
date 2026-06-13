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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/parser/models.dart';
import 'package:ddd_pod_cli/src/utils/keywords.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Current CLI version — kept in sync with pubspec.yaml.
const String _kCliVersion = '1.0.0';

// ─────────────────────────────────────────────────────────────────────────────

/// Generates all DDD layer source files for a single feature and writes them
/// to the provided directory map.
final class CodeGenerator {
  CodeGenerator({
    required this.parser,
    required this.packageName,
    required this.featureName,
    required this.endpoint,
    required this.methods,
    this.force = false,
    this.successResponse,
    this.failureResponse,
  });

  final JsonParser parser;
  final String packageName;
  final String featureName;
  final String endpoint;
  final List<String> methods;
  final bool force;
  final dynamic successResponse;
  final dynamic failureResponse;

  // ── Write orchestration ────────────────────────────────────────────────────

  /// Generate and write all feature files into the provided [directories] map.
  void writeToFiles(Map<String, Directory> directories) {
    final snake = _snake;

    // ── application/ ──────────────────────────────────────────────────────
    final appDir = directories['application']!;
    safeWriteToFile(p.join(appDir.path, '${snake}_state.dart'),
        generateStateCode());
    safeWriteToFile(p.join(appDir.path, '${snake}_notifier.dart'),
        generateNotifierCode());
    if (parser.requestJson != null) {
      safeWriteToFile(p.join(appDir.path, '${snake}_form_state.dart'),
          generateFormStateCode());
      safeWriteToFile(p.join(appDir.path, '${snake}_form_notifier.dart'),
          generateFormNotifierCode());
    }
    safeWriteToFile(p.join(appDir.path, 'providers.dart'),
        generateProvidersBarrelCode());

    // ── domain/ ───────────────────────────────────────────────────────────
    final domainDir = directories['domain']!;
    if (parser.domainClasses.isNotEmpty) {
      safeWriteToFile(p.join(domainDir.path, '${snake}_model.dart'),
          generateDomainModelCode());
    }
    safeWriteToFile(p.join(domainDir.path, '${snake}_failure.dart'),
        generateFailureCode());
    safeWriteToFile(
        p.join(domainDir.path, 'i_${snake}_repository.dart'),
        generateIRepositoryCode());

    // ── infrastructure/ ──────────────────────────────────────────────────
    final infraDir = directories['infrastructure']!;
    if (parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty) {
      safeWriteToFile(p.join(infraDir.path, '${snake}_dto.dart'),
          generateDtoCode());
    }
    safeWriteToFile(
        p.join(infraDir.path, '${snake}_remote_data_source.dart'),
        generateRemoteDataSourceCode());
    safeWriteToFile(
        p.join(infraDir.path, '${snake}_repository_impl.dart'),
        generateRepositoryImplCode());
    safeWriteToFile(
        p.join(infraDir.path, '${snake}_mock_interceptor.dart'),
        generateMockInterceptorCode());
    if (offlineCache) {
      safeWriteToFile(
          p.join(infraDir.path, '${snake}_local_data_source.dart'),
          generateLocalDataSourceCode());
    }

    // ── presentation/ ─────────────────────────────────────────────────────
    final presentationDir = directories['presentation'];
    if (presentationDir != null) {
      safeWriteToFile(
          p.join(presentationDir.path, '${snake}_debug_page.dart'),
          generateDebugPageCode());
    }

    // ── test/application/ ─────────────────────────────────────────────────
    final testAppDir = directories['test_application'];
    if (testAppDir != null) {
      safeWriteToFile(
          p.join(testAppDir.path, '${snake}_notifier_test.dart'),
          generateNotifierTestCode());
    }

    // ── Feature barrel ────────────────────────────────────────────────────
    final featurePath = p.dirname(appDir.path);
    safeWriteToFile(p.join(featurePath, '$snake.dart'),
        generateFeatureBarrelCode(directories));
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
    try {
      file.writeAsStringSync(content);
      logger.detail('Written: $path');
    } catch (e) {
      throw DddFileSystemException(
        message: 'Could not write file: $path\n$e',
        hint:
            'Check that you have write permissions to the target directory.',
        path: path,
      );
    }
  }

  /// Compatibility shim — delegates to [safeWriteToFile].
  @Deprecated('Use safeWriteToFile directly')
  void writeFile(File file, String content,
      {required bool isUserEdited}) =>
      safeWriteToFile(file.path, content);

  // ── Derived names ─────────────────────────────────────────────────────────

  String get _snake => StringUtils.toSnakeCase(featureName);
  String get _pascal => StringUtils.toPascalCase(featureName);
  String get _camel =>
      Keywords.getSafeName(StringUtils.snakeToCamel(featureName));

  bool get isPaginatedList => parser.isPaginatedList;
  bool get offlineCache => parser.offlineCache;

  // ── File header ───────────────────────────────────────────────────────────

  String _fileHeader({bool editable = false}) {
    final timestamp = DateTime.now().toIso8601String();
    if (editable) {
      return '''
// GENERATED CODE — Feel free to edit this file.
// Generated by ddd_pod_cli v$_kCliVersion · Feel free to edit this file.
// It will not be overwritten unless you run generate with the --force flag.
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: type=lint, invalid_annotation_target
''';
    }
    return '''
// GENERATED CODE — DO NOT MODIFY BY HAND
// ddd_pod_cli v$_kCliVersion · generated at $timestamp
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: type=lint, invalid_annotation_target
''';
  }

  // ── Path parameter helpers ─────────────────────────────────────────────────

  Map<String, String> get pathParamsMap {
    final map = <String, String>{};
    for (final match
        in RegExp(r':([a-zA-Z0-9_]+)').allMatches(endpoint)) {
      final raw = match.group(1)!;
      map[':$raw'] =
          Keywords.getSafeName(StringUtils.snakeToCamel(raw));
    }
    for (final match
        in RegExp(r'\{([a-zA-Z0-9_]+)\}').allMatches(endpoint)) {
      final raw = match.group(1)!;
      map['{$raw}'] =
          Keywords.getSafeName(StringUtils.snakeToCamel(raw));
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
    if (method.toUpperCase() == 'GET') {
      return 'Future<Either<${_pascal}Failure, $_dataType>>';
    }
    return 'Future<Either<${_pascal}Failure, Unit>>';
  }

  String _remoteSourceReturnType(String method) {
    if (method.toUpperCase() != 'GET') return 'void';
    if (parser.responseDtoClasses.isNotEmpty) {
      return parser.isTopLevelList
          ? 'List<${_pascal}Dto>'
          : '${_pascal}Dto';
    }
    return parser.isTopLevelList
        ? 'List<${parser.responseDtoType}>'
        : parser.responseDtoType;
  }

  String _repositoryParams({bool isWrite = false}) {
    final params = <String>[];
    pathParamsMap.forEach((_, name) => params.add('required String $name'));
    if (!isWrite && isPaginatedList) {
      params.addAll(['required int page', 'required int limit']);
    }
    if (isWrite && parser.requestJson != null) {
      params.add('required ${_pascal}RequestDto request');
    }
    return params.isEmpty ? '' : '{${params.join(', ')}}';
  }

  String _remoteCallArgs({bool isWrite = false}) {
    final args = <String>[];
    pathParamsMap.forEach((_, name) => args.add('$name: $name'));
    if (!isWrite && isPaginatedList) {
      args.addAll(['page: page', 'limit: limit']);
    }
    if (isWrite && parser.requestJson != null) args.add('request: request');
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

  String _cacheParams() {
    return pathParamsMap.values
        .map((n) => 'String $n')
        .join(', ');
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
    return '''
${_fileHeader()}
import 'package:freezed_annotation/freezed_annotation.dart';
${importModel}import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';

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
    final hasDomain = parser.domainClasses.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;
    final importModel = hasDomain
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
    final importDto =
        hasDto && parser.requestJson != null
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
      default:
        return _notifierCode(
            buildParams, callArgs, importModel, importRepoImpl, importDto);
    }
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

@riverpod
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

  /// Fetch the next page and append results to the current list.
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
        return AsyncData([...state.value ?? const [], ...newData]);
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

@riverpod
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

@riverpod
Future<$_dataType> $_camel(${_pascal}Ref ref$paramsArg) async {
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

@riverpod
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
          state = ${_pascal}State.data([...currentState.data, ...newData]);
        }
      },
    );
  }

  ${_submitMethodCode()}
}
''';
    }

    return '''
${_fileHeader(editable: true)}
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
$importModel${importRepoImpl}import '${_snake}_state.dart';
$importDto
part '${_snake}_notifier.g.dart';

@riverpod
class ${_pascal}Notifier extends _\$${_pascal}Notifier {
  @override
  ${_pascal}State build($buildParams) => const ${_pascal}State.initial();

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
  }

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
      final buildCallArgs =
          pathParamsMap.values.join(', ');
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
''';
    } else if (parser.providerType == 'notifier') {
      return '''
  /// Submit form data to the remote source.
  Future<void> submit({$params}) async {
    state = const ${_pascal}State.loading();
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgs);
    result.fold(
      (failure) => state = ${_pascal}State.error(failure),
      (_) => fetch$_pascal(),
    );
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
  /// The server returned an error response.
  const factory ${_pascal}Failure.serverError([String? message]) =
      _ServerError;

  /// A network-level error occurred (timeout, no connection, etc.).
  const factory ${_pascal}Failure.networkError() = _NetworkError;

  /// An unexpected error occurred that was not anticipated.
  const factory ${_pascal}Failure.unexpectedError([String? message]) =
      _UnexpectedError;
}
''';
  }

  // ── REPOSITORY INTERFACE ──────────────────────────────────────────────────

  String generateIRepositoryCode() {
    final sb = StringBuffer()..write(_fileHeader(editable: true));
    sb.writeln("import 'package:fpdart/fpdart.dart';");
    sb.writeln("import '${_snake}_failure.dart';");
    if (parser.domainClasses.isNotEmpty) {
      sb.writeln("import '${_snake}_model.dart';");
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
    final hasDomain = parser.domainClasses.isNotEmpty;

    sb.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
    if (hasDomain) {
      sb.writeln(
          "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';");
      for (final imp in parser.coreDomainImports) {
        sb.writeln("import '$imp';");
      }
    }
    for (final imp in parser.coreDtoImports) {
      sb.writeln("import '$imp';");
    }
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
      final isRootResponse = !dtoClass.isRequest &&
          dtoClass.className == _pascal;
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
      sb.writeln(
          '  factory $fullName.fromJson(Map<String, dynamic> json) =>');
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
                expressionSegments.add(
                    '$dartSeg?.map((e) => e.toDomain()).toList()');
              } else if (isLast && domainField.isNestedObject) {
                expressionSegments.add('$dartSeg?.toDomain()');
              } else {
                expressionSegments.add(dartSeg);
              }
            }
            sb.writeln(
                '      ${domainField.fieldName}: ${expressionSegments.join('?.')},');
          }
          sb.writeln('    );');
          sb.writeln('  }');
        } else if (isRootResponse && parser.corePathToDomain.isNotEmpty) {
          final mapped = parser.fieldMapping[parser.corePathToDomain.first] ??
              StringUtils.snakeToCamel(parser.corePathToDomain.first);
          final coreField = Keywords.getSafeName(mapped);
          if (parser.isListResponse) {
            sb.writeln(
                '  List<${parser.responseDataType}> toDomain() =>');
            sb.writeln(
                '      $coreField?.map((e) => e.toDomain()).toList() ?? const [];');
          } else {
            sb.writeln(
                '  ${parser.responseDataType} toDomain() =>');
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

    final sb = StringBuffer();
    for (final method in methods) {
      final methodName = _methodName(method);
      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      final returnType = _remoteSourceReturnType(method);
      final endpointStr = getInterpolatedEndpoint();
      final dioMethod = method.toLowerCase();

      sb.writeln('  Future<$returnType> $methodName($params) async {');
      sb.writeln('    try {');

      if (method.toUpperCase() == 'GET') {
        final queryParams = isPaginatedList
            ? ", queryParameters: {'page': page, 'limit': limit}"
            : '';
        sb.writeln(
            '      final response = await _dio.get($endpointStr$queryParams);');
        sb.writeln('      if (response.data != null) {');
        if (hasDto) {
          if (parser.isTopLevelList) {
            sb.writeln(
                '        final list = response.data as List<dynamic>;');
            sb.writeln(
                '        return list.map((e) => ${_pascal}Dto.fromJson(e as Map<String, dynamic>)).toList();');
          } else {
            sb.writeln(
                '        return ${_pascal}Dto.fromJson(response.data as Map<String, dynamic>);');
          }
        } else {
          if (parser.isTopLevelList) {
            sb.writeln(
                '        return (response.data as List<dynamic>).cast<${parser.responseDtoType}>();');
          } else {
            sb.writeln(
                '        return response.data as ${parser.responseDtoType};');
          }
        }
        sb.writeln('      }');
        sb.writeln('      throw DioException(');
        sb.writeln('        requestOptions: response.requestOptions,');
        sb.writeln('        response: response,');
        sb.writeln('        type: DioExceptionType.badResponse,');
        sb.writeln('      );');
      } else {
        final dataParam =
            _hasRequestBody(method) ? ', data: request.toJson()' : '';
        sb.writeln(
            '      await _dio.$dioMethod($endpointStr$dataParam);');
      }

      sb.writeln('    } catch (e) {');
      sb.writeln('      rethrow;');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    return '''
${_fileHeader(editable: true)}
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
$importDto
part '${_snake}_remote_data_source.g.dart';

@riverpod
${_pascal}RemoteDataSource ${_camel}RemoteDataSource(${_pascal}RemoteDataSourceRef ref) {
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
    final hasDomain = parser.domainClasses.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final importModel = hasDomain
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
    final importDto = hasDto
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_dto.dart';\n"
        : '';
    final importLocalSource = offlineCache
        ? "import 'package:$packageName/features/$_snake/infrastructure/${_snake}_local_data_source.dart';\n"
        : '';

    final watchLocal = offlineCache
        ? "  final localDataSource = ref.watch(${_camel}LocalDataSourceProvider);\n"
        : '';
    final constructLocal = offlineCache ? ', localDataSource' : '';
    final declareLocal = offlineCache
        ? '  final ${_pascal}LocalDataSource _localDataSource;\n'
        : '';
    final initLocal =
        offlineCache ? ', this._localDataSource' : '';

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

      sb.writeln('  @override');
      sb.writeln(
          '  Future<Either<${_pascal}Failure, $_dataType?>> getCached$_pascal($paramStr) async {');
      sb.writeln('    try {');
      sb.writeln(
          '      final cached = await _localDataSource.getLast$_pascal($callArgs);');
      sb.writeln('      if (cached == null) return right(null);');
      sb.writeln('      return right($mappingExpr);');
      sb.writeln('    } catch (_) {');
      sb.writeln(
          '      return left(const ${_pascal}Failure.unexpectedError());');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    for (final method in methods) {
      final methodName = _methodName(method);
      final params = _repositoryParams(isWrite: _hasRequestBody(method));
      final returnType = _repositoryReturnType(method);
      final callArgs = _remoteCallArgs(isWrite: _hasRequestBody(method));

      sb.writeln('  @override');
      sb.writeln('  $returnType $methodName($params) async {');
      sb.writeln('    try {');

      if (method.toUpperCase() == 'GET') {
        final mappingExpr = hasDomain
            ? (parser.isTopLevelList
                ? 'response.map((dto) => dto.toDomain()).toList()'
                : 'response.toDomain()')
            : 'response';
        final cacheArgs = _cacheCallArgs();
        final cacheArgsStr =
            cacheArgs.isNotEmpty ? '$cacheArgs, ' : '';

        sb.writeln(
            '      final response = await _remoteDataSource.$methodName($callArgs);');
        if (offlineCache) {
          sb.writeln(
              '      await _localDataSource.cache$_pascal(${cacheArgsStr}response);');
        }
        sb.writeln('      return right($mappingExpr);');
      } else {
        sb.writeln(
            '      await _remoteDataSource.$methodName($callArgs);');
        sb.writeln('      return right(unit);');
      }

      sb.writeln('    } on DioException catch (e) {');
      sb.writeln(
          '      if (e.type == DioExceptionType.connectionTimeout ||');
      sb.writeln(
          '          e.type == DioExceptionType.sendTimeout ||');
      sb.writeln(
          '          e.type == DioExceptionType.receiveTimeout ||');
      sb.writeln(
          '          e.type == DioExceptionType.connectionError) {');
      sb.writeln(
          "        return left(const ${_pascal}Failure.networkError());");
      sb.writeln('      }');
      sb.writeln('      final dynamic data = e.response?.data;');
      sb.writeln('      String? errorMessage;');
      sb.writeln('      if (data is Map) {');
      sb.writeln("        final errorVal = data['error'];");
      sb.writeln('        if (errorVal is Map) {');
      sb.writeln(
          "          errorMessage = errorVal['message']?.toString() ?? errorVal['error']?.toString();");
      sb.writeln('        } else {');
      sb.writeln(
          "          errorMessage = errorVal?.toString() ?? data['message']?.toString();");
      sb.writeln('        }');
      sb.writeln('      }');
      sb.writeln('      errorMessage ??= e.message;');
      sb.writeln(
          '      return left(${_pascal}Failure.serverError(errorMessage));');
      sb.writeln('    } catch (e) {');
      sb.writeln(
          '      return left(${_pascal}Failure.unexpectedError(e.toString()));');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln();
    }

    return '''
${_fileHeader(editable: true)}
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:dio/dio.dart';

import 'package:$packageName/features/$_snake/domain/i_${_snake}_repository.dart';
import 'package:$packageName/features/$_snake/domain/${_snake}_failure.dart';
${importModel}import 'package:$packageName/features/$_snake/infrastructure/${_snake}_remote_data_source.dart';
$importLocalSource$importDto
part '${_snake}_repository_impl.g.dart';

@riverpod
I${_pascal}Repository ${_camel}Repository(${_pascal}RepositoryRef ref) {
  final remoteDataSource = ref.watch(${_camel}RemoteDataSourceProvider);
$watchLocal  return ${_pascal}RepositoryImpl(remoteDataSource$constructLocal);
}

class ${_pascal}RepositoryImpl implements I${_pascal}Repository {
  const ${_pascal}RepositoryImpl(this._remoteDataSource$initLocal);

  final ${_pascal}RemoteDataSource _remoteDataSource;
$declareLocal
${sb.toString()}}
''';
  }

  // ── MOCK INTERCEPTOR ──────────────────────────────────────────────────────

  String generateMockInterceptorCode() {
    final responseLiteral = _formatDartLiteral(successResponse);
    // Safely escape the endpoint pattern for use as a RegExp inside Dart source
    final endpointPattern = endpoint
        .replaceAll(RegExp(r':\\w+'), r'\w+')
        .replaceAll(RegExp(r'\{\w+\}'), r'\w+')
        .replaceAll(r'\', r'\\')
        .replaceAll('/', r'\/');

    return '''
${_fileHeader(editable: true)}
import 'dart:convert';

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
    // Simulate realistic network latency
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final pathPattern = RegExp(r'$endpointPattern');
    if (options.path.contains(pathPattern)) {
      handler.resolve(
        Response(
          requestOptions: options,
          data: $responseLiteral,
          statusCode: 200,
        ),
      );
      return;
    }
    super.onRequest(options, handler);
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
        : (isList
            ? 'List<${parser.responseDtoType}>'
            : parser.responseDtoType);

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
    final paramWithComma =
        cacheParams.isNotEmpty ? '$cacheParams, ' : '';
    final callArgs = _cacheCallArgs();

    final String cacheKeyExpr;
    if (pathParamsMap.isNotEmpty) {
      final suffixStr =
          pathParamsMap.values.map((v) => '\$$v').join('_');
      cacheKeyExpr = "'\${_cacheKey}_$suffixStr'";
    } else {
      cacheKeyExpr = '_cacheKey';
    }

    final paramName =
        hasDto ? (isList ? 'List<${_pascal}Dto> dtos' : '${_pascal}Dto dto') : '$dtoType data';

    return '''
${_fileHeader(editable: true)}
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
$importDto
part '${_snake}_local_data_source.g.dart';

@riverpod
${_pascal}LocalDataSource ${_camel}LocalDataSource(${_pascal}LocalDataSourceRef ref) {
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

  Future<void> cache$_pascal($paramWithComma$paramName) async {
    final key = $cacheKeyExpr;
    await _prefs.setString(key, $serializerCall);
  }

  Future<$dtoType?> getLast$_pascal($callArgs) async {
    final key = $cacheKeyExpr;
    final jsonString = _prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      return $deserializerCall;
    } catch (_) {
      return null;
    }
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
    if (parser.requestJson != null) {
      sb.writeln("export '${_snake}_form_notifier.dart';");
      sb.writeln("export '${_snake}_form_state.dart';");
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
    final hasDomain = parser.domainClasses.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final pathParamArgs = pathParamsMap.values
        .map((n) => "'mock_$n'")
        .join(', ');
    final providerArgsStr =
        pathParamArgs.isNotEmpty ? '($pathParamArgs)' : '';

    final isNotifier = parser.providerType == 'notifier' ||
        parser.providerType == 'async_notifier';
    final providerName = isNotifier
        ? '${_camel}NotifierProvider'
        : '${_camel}Provider';
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

    final importModel = hasDomain
        ? "import 'package:$packageName/features/$_snake/domain/${_snake}_model.dart';\n"
        : '';
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
      formStateWatch =
          'final formState = ref.watch(${_camel}FormNotifierProvider);';
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
                    .read(${_camel}FormNotifierProvider.notifier)
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
                      .read(${_camel}FormNotifierProvider.notifier)
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
                      .read(${_camel}FormNotifierProvider.notifier)
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

        final formSubmitArgs = pathParamsMap.values
            .map((n) => "$n: 'mock_$n'")
            .join(', ');

        formSubmitButton = '''
              ElevatedButton(
                onPressed: formState.isSubmitting
                    ? null
                    : () async {
                        final success = await ref
                            .read(${_camel}FormNotifierProvider.notifier)
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
    final hasDomain = parser.domainClasses.isNotEmpty;
    final hasDto = parser.responseDtoClasses.isNotEmpty ||
        parser.requestDtoClasses.isNotEmpty;

    final importModel = hasDomain
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

    final pathParamArgs = pathParamsMap.values
        .map((n) => "'mock_$n'")
        .join(', ');
    final providerArgsStr =
        pathParamArgs.isNotEmpty ? '($pathParamArgs)' : '';

    final isNotifier = parser.providerType == 'notifier' ||
        parser.providerType == 'async_notifier';
    final providerName = isNotifier
        ? '${_camel}NotifierProvider'
        : '${_camel}Provider';

    final mockFields = <String>[];
    final mockMethods = <String>[];

    for (final method in methods) {
      final name = _methodName(method);
      final returnType = _repositoryReturnType(method);
      final innerType =
          returnType.substring('Future<'.length, returnType.length - 1);
      mockFields.add('$innerType? ${name}Result;');

      final params =
          _repositoryParams(isWrite: _hasRequestBody(method));
      mockMethods.add('''
  @override
  $returnType $name($params) async {
    final result = ${name}Result;
    if (result == null) {
      throw UnimplementedError('Set ${name}Result before calling $name.');
    }
    return result;
  }''');
    }

    if (offlineCache) {
      final cacheParams = _cacheParams();
      mockFields
          .add('Either<${_pascal}Failure, $_dataType?>? getCachedResult;');
      mockMethods.add('''
  @override
  Future<Either<${_pascal}Failure, $_dataType?>> getCached$_pascal($cacheParams) async =>
      getCachedResult ?? right(null);''');
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
      if (parser.isListResponse && successResponse is List) {
        final elems = (successResponse as List)
            .map(_formatDartLiteral)
            .join(', ');
        mockDataStr = '[$elems]';
      } else {
        mockDataStr = _formatDartLiteral(successResponse);
      }
    }

    final getMethodName = methods.contains('GET')
        ? _methodName('GET')
        : _methodName(methods.first);
    final getResultField = '${getMethodName}Result';

    final String testCasesCode;
    if (parser.providerType == 'notifier') {
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
    test('success resolves provider to data', () async {
      final mockData = $mockDataStr;
      mockRepository.$getResultField = right(mockData);

      final result = await container
          .read($providerName$providerArgsStr.future);
      expect(result, equals(mockData));

      final state = container.read($providerName$providerArgsStr);
      expect(state, equals(AsyncData(mockData)));
    });

    test('failure resolves provider to AsyncError', () async {
      const failure = ${_pascal}Failure.serverError('Server error');
      mockRepository.$getResultField = left(failure);

      await expectLater(
        container.read($providerName$providerArgsStr.future),
        throwsA(equals(failure)),
      );

      final state = container.read($providerName$providerArgsStr);
      expect(state, isA<AsyncError<$_dataType>>());
    });''';
    }

    return '''
${_fileHeader(editable: true)}
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

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
        ${_camel}RepositoryProvider.overrideWith((_) => mockRepository),
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
          final otherPascal =
              StringUtils.toPascalCase(other.dartName);
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

    final submitParamsStr = submitParams.isNotEmpty
        ? '{${submitParams.join(', ')}}'
        : '';
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
    );
    _validateForm();
    if (!state.isValid) return false;

    state = state.copyWith(isSubmitting: true);
    final repository = ref.read(${_camel}RepositoryProvider);
    final result = await repository.$repoMethod($repoArgsStr);
    state = state.copyWith(isSubmitting: false);
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

  String _validatorMethod(
      DtoField field, Map<String, dynamic>? ruleMap) {
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

    final isEmailField =
        isEmail || typeRule == 'email';
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

  String _generateDtoInstantiation(
      String className, Map<String, dynamic> map) {
    final sb = StringBuffer()..write('${className}Dto(');
    final dtoClass = [
      ...parser.requestDtoClasses,
      ...parser.responseDtoClasses,
    ].firstWhere(
      (c) => c.className == className,
      orElse: () => DtoClass(className: className, fields: const []),
    );

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
            .map((e) =>
                _generateDtoInstantiation(field.nestedClassName!, e))
            .join(', ');
        assignments.add('${field.dartName}: [$elems]');
      } else {
        if ((field.typeName == 'DateTime' || field.typeName == 'DateTime?') && val is String) {
          assignments.add(
              '${field.dartName}: DateTime.parse(${_formatDartLiteral(val)})');
        } else {
          assignments.add(
              '${field.dartName}: ${_formatDartLiteral(val)}');
        }
      }
    }
    sb.write(assignments.join(', '));
    sb.write(')');
    return sb.toString();
  }
}
