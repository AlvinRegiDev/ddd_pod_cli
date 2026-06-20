/// Strongly-typed, validated configuration model for a single feature scaffold.
///
/// Parsed from the `config.json` file (or the equivalent flags/args when using
/// the `curl` sub-command). Throws a [ConfigException] for any invalid value,
/// providing a clear, actionable error message to the developer.
library;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

/// Valid HTTP methods the CLI recognises.
enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete,
  head;

  /// Parse a case-insensitive string into an [HttpMethod].
  /// Throws [ConfigException] on unknown values.
  static HttpMethod fromString(String s) => switch (s.toUpperCase()) {
        'GET' => HttpMethod.get,
        'POST' => HttpMethod.post,
        'PUT' => HttpMethod.put,
        'PATCH' => HttpMethod.patch,
        'DELETE' => HttpMethod.delete,
        'HEAD' => HttpMethod.head,
        _ => throw ConfigException(
            message: 'Unknown HTTP method: "$s".',
            hint: 'Valid values are: GET, POST, PUT, PATCH, DELETE, HEAD.',
          ),
      };

  /// Upper-cased string representation (e.g. `"GET"`).
  String get value => name.toUpperCase();
}

/// Valid Riverpod provider types.
enum ProviderType {
  provider,
  notifier,
  asyncNotifier,
  futureProvider,
  streamNotifier,
  streamProvider;

  static const _mapping = {
    'provider': ProviderType.provider,
    'notifier': ProviderType.notifier,
    'async_notifier': ProviderType.asyncNotifier,
    'future_provider': ProviderType.futureProvider,
    'stream_notifier': ProviderType.streamNotifier,
    'stream_provider': ProviderType.streamProvider,
  };

  /// Parse a snake_case string into a [ProviderType].
  /// Throws [ConfigException] on unknown values.
  static ProviderType fromString(String s) =>
      _mapping[s.toLowerCase()] ??
      (throw ConfigException(
        message: 'Unknown provider_type: "$s".',
        hint:
            'Valid values are: "provider", "notifier", "async_notifier", "future_provider", "stream_notifier", "stream_provider".',
      ));

  /// The snake_case string used in JSON configs and generated code.
  String get jsonValue => switch (this) {
        ProviderType.provider => 'provider',
        ProviderType.notifier => 'notifier',
        ProviderType.asyncNotifier => 'async_notifier',
        ProviderType.futureProvider => 'future_provider',
        ProviderType.streamNotifier => 'stream_notifier',
        ProviderType.streamProvider => 'stream_provider',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// FeatureConfig
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a fully validated feature configuration.
final class FeatureConfig {
  const FeatureConfig({
    required this.featureName,
    required this.apiPath,
    required this.methods,
    required this.providerType,
    required this.typeOverrides,
    required this.fieldMapping,
    required this.validationRules,
    required this.isPaginatedList,
    required this.offlineCache,
    required this.withDebugView,
    this.getResponseDto,
    this.postRequestBody,
    this.successResponse,
    this.failureResponse,
    required this.toDomainFallback,
    this.familyParam,
    required this.keepAlive,
    required this.combinedProviders,
    required this.listenProviders,
    this.paginationConfig,
    this.responseRoot,
    required this.useCustomState,
    required this.autoDispose,
    required this.dependencies,
    this.streamConfig,
    this.retryConfig,
    this.searchConfig,
    required this.offlineMutationQueue,
    required this.featureDependencies,
    required this.cacheTtlSeconds,
    required this.imports,
  });

  /// Validated, non-empty feature name (used as the Dart class prefix).
  final String featureName;

  /// API endpoint path, e.g. `/api/v1/workspaces/:id`.
  final String apiPath;

  /// One or more HTTP methods for this endpoint.
  final List<HttpMethod> methods;

  /// Riverpod provider type to generate.
  final ProviderType providerType;

  /// Manual type overrides keyed by field name or dotted path.
  final Map<String, String> typeOverrides;

  /// JSON-key → Dart-name remappings.
  final Map<String, String> fieldMapping;

  /// Declarative validation rules for form fields.
  final Map<String, dynamic> validationRules;

  /// Whether to generate paginated list logic.
  final bool isPaginatedList;

  /// Whether to generate offline-cache (SharedPreferences) layer.
  final bool offlineCache;

  /// Whether to include the debug/presentation layer.
  final bool withDebugView;

  /// Raw GET response schema (used for DTO inference).
  final dynamic getResponseDto;

  /// Raw POST/PUT/PATCH request body schema.
  final dynamic postRequestBody;

  /// Sample success response used to populate mock data in tests.
  final dynamic successResponse;

  /// Sample failure response (optional, informational only).
  final dynamic failureResponse;

  /// Default fallback strategy when data is null: "defaults" or "nullable".
  final String toDomainFallback;

  /// Optional family parameter for parameterized providers.
  final Map<String, String>? familyParam;

  /// Whether provider should keep state alive.
  final bool keepAlive;

  /// Derived/combined providers.
  final List<Map<String, dynamic>> combinedProviders;

  /// Side effects using ref.listen.
  final List<String> listenProviders;

  /// Custom pagination configurations.
  final Map<String, dynamic>? paginationConfig;

  /// Target root property in API responses.
  final String? responseRoot;

  /// Whether to generate custom Freezed Union states for UI.
  final bool useCustomState;

  /// Whether Riverpod should auto-dispose the provider when all listeners are removed.
  final bool autoDispose;

  /// Direct Riverpod provider dependencies.
  final List<String> dependencies;

  /// WebSocket / SSE / Polling Stream configuration.
  final Map<String, dynamic>? streamConfig;

  /// Retry configuration (max attempts, backoff delay, etc.).
  final Map<String, dynamic>? retryConfig;

  /// Search configuration (debounced/throttled queries).
  final Map<String, dynamic>? searchConfig;

  /// Whether to generate offline mutation queue sync mechanism.
  final bool offlineMutationQueue;

  /// Explicit dependencies on other generated features.
  final List<String> featureDependencies;

  /// Cache time-to-live in seconds. `0` means no expiry (existing behaviour).
  ///
  /// When non-zero, the generated [LocalDataSource] wraps stored JSON in a
  /// `{"data": ..., "cachedAt": epochMs}` envelope and returns `null` when
  /// the entry is older than [cacheTtlSeconds].
  final int cacheTtlSeconds;

  /// Custom file imports to add to generated files.
  final List<String> imports;

  // ── Factory ──────────────────────────────────────────────────────────────

  /// Parse a raw decoded JSON map into a validated [FeatureConfig].
  ///
  /// Throws [ConfigException] for any invalid or missing required field.
  factory FeatureConfig.fromJson(
    Map<String, dynamic> json, {
    bool withDebugView = false,
  }) {
    final errors = <String>[];

    // ── feature_name ────────────────────────────────────────────────────────
    final rawName = json['feature_name'];
    String featureName = '';
    if (rawName == null || rawName is! String || rawName.trim().isEmpty) {
      errors.add(
          'Missing or empty "feature_name" field. Add "feature_name": "YourFeatureName" to your config.json.');
    } else {
      featureName = rawName.trim();
      try {
        _validateIdentifier(featureName);
      } on ConfigException catch (e) {
        errors.add(e.message);
      }
    }

    // Auto-convert casing if not PascalCase
    if (featureName.isNotEmpty) {
      final isPascal = RegExp(r'^[A-Z][a-zA-Z0-9]*$').hasMatch(featureName);
      if (!isPascal) {
        final converted = StringUtils.toPascalCase(featureName);
        logger.warn(
          'Feature name "$featureName" is not in PascalCase. '
          'Converting to "$converted".',
        );
        featureName = converted;
      }
    }

    // ── methods ─────────────────────────────────────────────────────────────
    final rawMethods = json['methods'];
    final List<HttpMethod> methods = [];
    if (rawMethods == null) {
      methods.add(HttpMethod.get);
    } else if (rawMethods is List) {
      if (rawMethods.isEmpty) {
        errors.add('"methods" array must not be empty.');
      } else {
        for (final m in rawMethods) {
          try {
            methods.add(HttpMethod.fromString(m.toString()));
          } on ConfigException catch (e) {
            errors.add(e.message);
          }
        }
      }
    } else {
      errors.add(
          '"methods" must be a JSON array. Got ${rawMethods.runtimeType}.');
    }

    // ── api_path ─────────────────────────────────────────────────────────────
    final apiPath = (json['api_path'] ?? json['endpoint'] ?? '/').toString();

    // ── provider_type ────────────────────────────────────────────────────────
    final rawProviderType = json['provider_type'] as String?;
    final dtoOrPayload = json['get_response_dto'] ?? json['payload'];
    final String? rawProviderTypeInDto = dtoOrPayload is Map<String, dynamic>
        ? dtoOrPayload['provider_type'] as String?
        : null;
    final effectiveProviderTypeStr = rawProviderType ?? rawProviderTypeInDto;
    ProviderType providerType = ProviderType.notifier;
    if (effectiveProviderTypeStr != null) {
      try {
        providerType = ProviderType.fromString(effectiveProviderTypeStr);
      } on ConfigException catch (e) {
        errors.add(e.message);
      }
    }

    // ── response_root / envelope navigation ──────────────────────────────────
    final responseRoot = json['response_root']?.toString();
    final rawGetResponse = json['get_response_dto'] ?? json['payload'] ?? json;
    dynamic getResponseDto = rawGetResponse;
    if (responseRoot != null && responseRoot.isNotEmpty) {
      final navigated = _navigateJsonPath(rawGetResponse, responseRoot);
      if (navigated != null) {
        getResponseDto = navigated;
      } else {
        errors.add('Could not find payload at response_root: "$responseRoot"');
      }
    }

    // ── post_request_body ────────────────────────────────────────────────────
    final postRequestBody = json['post_request_body'] ??
        json['put_request_body'] ??
        json['patch_request_body'] ??
        json['request_body'];

    // ── type_overrides ───────────────────────────────────────────────────────
    final rawTypeOverrides = json['type_overrides'];
    final Map<String, String> typeOverrides = {};
    if (rawTypeOverrides is Map) {
      rawTypeOverrides.forEach((k, v) {
        typeOverrides[k.toString()] = v.toString();
      });
    }

    // ── field_mapping ────────────────────────────────────────────────────────
    final rawFieldMapping = json['field_mapping'];
    final Map<String, String> fieldMapping = {};
    if (rawFieldMapping is Map) {
      rawFieldMapping.forEach((k, v) {
        fieldMapping[k.toString()] = v.toString();
      });
    }

    // ── validation_rules ─────────────────────────────────────────────────────
    final rawValidationRules = json['validation_rules'];
    final Map<String, dynamic> validationRules = {};
    if (rawValidationRules is Map<String, dynamic>) {
      validationRules.addAll(rawValidationRules);
    }

    // ── flags ─────────────────────────────────────────────────────────────────
    final isPaginatedList = json['is_paginated_list'] as bool? ?? false;
    final offlineCache = json['offline_cache'] as bool? ?? false;

    // ── toDomain_fallback ────────────────────────────────────────────────────
    final toDomainFallback =
        json['toDomain_fallback']?.toString() ?? 'defaults';
    if (toDomainFallback != 'defaults' && toDomainFallback != 'nullable') {
      errors.add(
          'Invalid "toDomain_fallback" value: "$toDomainFallback". Valid values are: "defaults", "nullable".');
    }

    // ── family_param ─────────────────────────────────────────────────────────
    final rawFamilyParam = json['family_param'];
    Map<String, String>? familyParam;
    if (rawFamilyParam is Map) {
      final name = rawFamilyParam['name']?.toString() ?? '';
      final type = rawFamilyParam['type']?.toString() ?? '';
      if (name.isEmpty || type.isEmpty) {
        errors.add(
            'Invalid "family_param" format. Expected e.g. { "name": "userId", "type": "String" }');
      } else {
        familyParam = {'name': name, 'type': type};
      }
    }

    // ── auto_dispose & keep_alive ────────────────────────────────────────────
    final autoDispose = json['auto_dispose'] as bool? ?? true;
    final keepAlive = json['keep_alive'] as bool? ?? !autoDispose;

    // ── dependencies ─────────────────────────────────────────────────────────
    final rawDeps = json['dependencies'];
    final List<String> dependencies = [];
    if (rawDeps is List) {
      dependencies.addAll(rawDeps.map((e) => e.toString()));
    }

    // ── feature_dependencies ─────────────────────────────────────────────────
    final rawFeatDeps = json['feature_dependencies'];
    final List<String> featureDependencies = [];
    if (rawFeatDeps is List) {
      featureDependencies.addAll(rawFeatDeps.map((e) => e.toString()));
    }

    // ── offline_mutation_queue ───────────────────────────────────────────────
    final offlineMutationQueue =
        json['offline_mutation_queue'] as bool? ?? false;

    // ── stream_config ────────────────────────────────────────────────────────
    final rawStreamConfig = json['stream_config'];
    Map<String, dynamic>? streamConfig;
    if (rawStreamConfig is Map<String, dynamic>) {
      streamConfig = rawStreamConfig;
      final type = streamConfig['type']?.toString();
      if (type != null &&
          type != 'websocket' &&
          type != 'sse' &&
          type != 'polling') {
        errors.add(
            'Invalid stream type "$type" in "stream_config". Valid values: "websocket", "sse", "polling".');
      }
      final pollInterval = streamConfig['poll_interval_seconds'];
      if (pollInterval != null) {
        final pollVal = pollInterval is int
            ? pollInterval
            : int.tryParse(pollInterval.toString());
        if (pollVal == null || pollVal <= 0) {
          errors.add(
              '"poll_interval_seconds" in "stream_config" must be a positive integer.');
        }
      }
    }

    // ── retry_config ─────────────────────────────────────────────────────────
    final rawRetryConfig = json['retry_config'];
    Map<String, dynamic>? retryConfig;
    if (rawRetryConfig is Map<String, dynamic>) {
      retryConfig = rawRetryConfig;
      final maxAttempts = retryConfig['max_attempts'];
      if (maxAttempts != null && maxAttempts is! int) {
        errors.add('"max_attempts" in "retry_config" must be an integer.');
      }
      final delayMs = retryConfig['delay_ms'];
      if (delayMs != null) {
        final delayVal =
            delayMs is int ? delayMs : int.tryParse(delayMs.toString());
        if (delayVal == null || delayVal <= 0) {
          errors
              .add('"delay_ms" in "retry_config" must be a positive integer.');
        }
      }
    }

    // ── search_config ────────────────────────────────────────────────────────
    final rawSearchConfig = json['search_config'];
    Map<String, dynamic>? searchConfig;
    if (rawSearchConfig is Map<String, dynamic>) {
      searchConfig = rawSearchConfig;
      final debounceMs = searchConfig['debounce_ms'];
      if (debounceMs != null && debounceMs is! int) {
        errors.add('"debounce_ms" in "search_config" must be an integer.');
      }
      final throttleMs = searchConfig['throttle_ms'];
      if (throttleMs != null && throttleMs is! int) {
        errors.add('"throttle_ms" in "search_config" must be an integer.');
      }
      final minChars = searchConfig['min_chars'];
      if (minChars != null) {
        final minVal =
            minChars is int ? minChars : int.tryParse(minChars.toString());
        if (minVal == null || minVal < 0) {
          errors.add(
              '"min_chars" in "search_config" must be a non-negative integer.');
        }
      }
    }

    // ── cache_ttl_seconds ────────────────────────────────────────────────────
    final rawCacheTtl = json['cache_ttl_seconds'];
    int cacheTtlSeconds = 0;
    if (rawCacheTtl != null) {
      final ttlVal = rawCacheTtl is int
          ? rawCacheTtl
          : int.tryParse(rawCacheTtl.toString());
      if (ttlVal == null || ttlVal < 0) {
        errors.add(
            '"cache_ttl_seconds" must be a non-negative integer (0 = no expiry).');
      } else {
        cacheTtlSeconds = ttlVal;
      }
    }

    // ── combined_providers ───────────────────────────────────────────────────
    final rawCombined = json['combined_providers'];
    final List<Map<String, dynamic>> combinedProviders = [];
    if (rawCombined is List) {
      for (final c in rawCombined) {
        if (c is Map<String, dynamic>) {
          final name = c['name']?.toString() ?? '';
          final type = c['type']?.toString() ?? 'dynamic';
          final deps = (c['dependencies'] as List? ?? [])
              .map((e) => e.toString())
              .toList();
          final cpImports =
              (c['imports'] as List? ?? []).map((e) => e.toString()).toList();
          if (name.isEmpty) {
            errors.add('Combined provider requires a "name".');
          } else {
            combinedProviders.add({
              'name': name,
              'type': type,
              'dependencies': deps,
              'imports': cpImports,
            });
          }
        }
      }
    }

    // ── listen_providers ─────────────────────────────────────────────────────
    final rawListen = json['listen_providers'];
    final List<String> listenProviders = [];
    if (rawListen is List) {
      listenProviders.addAll(rawListen.map((e) => e.toString()));
    }

    // ── pagination_config ───────────────────────────────────────────────────
    final rawPaginationConfig = json['pagination_config'];
    Map<String, dynamic>? paginationConfig;
    if (rawPaginationConfig is Map<String, dynamic>) {
      paginationConfig = rawPaginationConfig;
      final type = paginationConfig['type']?.toString() ?? 'offset';
      if (type != 'offset' && type != 'cursor' && type != 'bidirectional') {
        errors.add(
            'Invalid pagination type "$type". Valid values: "offset", "cursor", "bidirectional".');
      }
      final pageSize = paginationConfig['page_size'];
      if (pageSize != null) {
        final sizeVal =
            pageSize is int ? pageSize : int.tryParse(pageSize.toString());
        if (sizeVal == null || sizeVal <= 0) {
          errors.add(
              '"page_size" in "pagination_config" must be a positive integer.');
        }
      }
    } else if (isPaginatedList) {
      paginationConfig = {'type': 'offset'};
    }

    // ── use_custom_state ─────────────────────────────────────────────────────
    final useCustomState = json['use_custom_state'] as bool? ?? false;

    // ── imports ──────────────────────────────────────────────────────────────
    final rawImports = json['imports'];
    final List<String> imports = [];
    if (rawImports is List) {
      imports.addAll(rawImports.map((e) => e.toString()));
    }

    // Throw if there are any collected validation errors
    if (errors.isNotEmpty) {
      throw ConfigException(
        message:
            'Configuration validation failed with ${errors.length} error(s):\n' +
                errors.map((e) => '- $e').join('\n'),
        hint: 'Please correct the errors in your configuration and run again.',
      );
    }

    final successResponse = json['success_response'] ?? getResponseDto;
    final failureResponse = json['failure_response'];

    return FeatureConfig(
      featureName: featureName,
      apiPath: apiPath,
      methods: methods,
      providerType: providerType,
      typeOverrides: typeOverrides,
      fieldMapping: fieldMapping,
      validationRules: validationRules,
      isPaginatedList: isPaginatedList,
      offlineCache: offlineCache,
      withDebugView: withDebugView,
      getResponseDto: getResponseDto,
      postRequestBody: postRequestBody,
      successResponse: successResponse,
      failureResponse: failureResponse,
      toDomainFallback: toDomainFallback,
      familyParam: familyParam,
      keepAlive: keepAlive,
      combinedProviders: combinedProviders,
      listenProviders: listenProviders,
      paginationConfig: paginationConfig,
      responseRoot: responseRoot,
      useCustomState: useCustomState,
      autoDispose: autoDispose,
      dependencies: dependencies,
      streamConfig: streamConfig,
      retryConfig: retryConfig,
      searchConfig: searchConfig,
      offlineMutationQueue: offlineMutationQueue,
      featureDependencies: featureDependencies,
      cacheTtlSeconds: cacheTtlSeconds,
      imports: imports,
    );
  }

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// Snake-cased feature name, e.g. `"userProfile"` → `"user_profile"`.
  String get snakeFeatureName => StringUtils.toSnakeCase(featureName);

  /// Provider type string for passing to [JsonParser].
  String get providerTypeString => providerType.jsonValue;

  // ── Private helpers ───────────────────────────────────────────────────────

  static dynamic _navigateJsonPath(dynamic json, String path) {
    if (path.isEmpty) return json;
    final parts = path.split('.');
    dynamic current = json;
    for (final part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  static void _validateIdentifier(String name) {
    // Must start with a letter or underscore
    if (!RegExp(r'^[a-zA-Z_]').hasMatch(name)) {
      throw ConfigException(
        message:
            '"feature_name" must start with a letter or underscore, got: "$name".',
        hint: 'Example: "feature_name": "UserProfile"',
      );
    }
    // Must contain only letters, digits, underscores
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name)) {
      throw ConfigException(
        message:
            '"feature_name" must contain only letters, digits, or underscores, got: "$name".',
        hint: 'Remove spaces and special characters. Example: "UserProfile"',
      );
    }
  }
}
