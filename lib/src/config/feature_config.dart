/// Strongly-typed, validated configuration model for a single feature scaffold.
///
/// Parsed from the `config.json` file (or the equivalent flags/args when using
/// the `curl` sub-command). Throws a [ConfigException] for any invalid value,
/// providing a clear, actionable error message to the developer.
library;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
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
  notifier,
  asyncNotifier,
  futureProvider;

  static const _mapping = {
    'notifier': ProviderType.notifier,
    'async_notifier': ProviderType.asyncNotifier,
    'future_provider': ProviderType.futureProvider,
  };

  /// Parse a snake_case string into a [ProviderType].
  /// Throws [ConfigException] on unknown values.
  static ProviderType fromString(String s) =>
      _mapping[s.toLowerCase()] ??
      (throw ConfigException(
        message: 'Unknown provider_type: "$s".',
        hint:
            'Valid values are: "notifier", "async_notifier", "future_provider".',
      ));

  /// The snake_case string used in JSON configs and generated code.
  String get jsonValue => switch (this) {
        ProviderType.notifier => 'notifier',
        ProviderType.asyncNotifier => 'async_notifier',
        ProviderType.futureProvider => 'future_provider',
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

  // ── Factory ──────────────────────────────────────────────────────────────

  /// Parse a raw decoded JSON map into a validated [FeatureConfig].
  ///
  /// Throws [ConfigException] for any invalid or missing required field.
  factory FeatureConfig.fromJson(
    Map<String, dynamic> json, {
    bool withDebugView = false,
  }) {
    // ── feature_name ────────────────────────────────────────────────────────
    final rawName = json['feature_name'];
    if (rawName == null || rawName is! String || rawName.trim().isEmpty) {
      throw const ConfigException(
        message: 'Missing or empty "feature_name" field.',
        hint: 'Add "feature_name": "YourFeatureName" to your config.json.',
      );
    }
    final featureName = rawName.trim();
    _validateIdentifier(featureName);

    // ── methods ─────────────────────────────────────────────────────────────
    final rawMethods = json['methods'];
    final List<HttpMethod> methods;
    if (rawMethods == null) {
      methods = const [HttpMethod.get];
    } else if (rawMethods is List) {
      if (rawMethods.isEmpty) {
        throw const ConfigException(
          message: '"methods" array must not be empty.',
          hint: 'Add at least one method, e.g. ["GET"].',
        );
      }
      methods =
          rawMethods.map((m) => HttpMethod.fromString(m.toString())).toList();
    } else {
      throw ConfigException(
        message:
            '"methods" must be a JSON array, got ${rawMethods.runtimeType}.',
        hint: 'Example: "methods": ["GET", "POST"]',
      );
    }

    // ── api_path ─────────────────────────────────────────────────────────────
    final apiPath = (json['api_path'] ?? json['endpoint'] ?? '/').toString();

    // ── provider_type ────────────────────────────────────────────────────────
    final rawProviderType = json['provider_type'] as String?;
    // Also check inside the response DTO for backwards compatibility
    final dtoOrPayload = json['get_response_dto'] ?? json['payload'];
    final String? rawProviderTypeInDto = dtoOrPayload is Map<String, dynamic>
        ? dtoOrPayload['provider_type'] as String?
        : null;
    final effectiveProviderTypeStr = rawProviderType ?? rawProviderTypeInDto;
    final providerType = effectiveProviderTypeStr != null
        ? ProviderType.fromString(effectiveProviderTypeStr)
        : ProviderType.notifier;

    // ── get_response_dto ─────────────────────────────────────────────────────
    final getResponseDto = json['get_response_dto'] ?? json['payload'] ?? json;

    // ── post_request_body ────────────────────────────────────────────────────
    final postRequestBody = json['post_request_body'] ??
        json['put_request_body'] ??
        json['patch_request_body'] ??
        json['request_body'];

    // ── type_overrides ───────────────────────────────────────────────────────
    final rawTypeOverrides = json['type_overrides'];
    final Map<String, String> typeOverrides;
    if (rawTypeOverrides is Map) {
      typeOverrides = rawTypeOverrides.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } else {
      typeOverrides = const {};
    }

    // ── field_mapping ────────────────────────────────────────────────────────
    final rawFieldMapping = json['field_mapping'];
    final Map<String, String> fieldMapping;
    if (rawFieldMapping is Map) {
      fieldMapping = rawFieldMapping.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } else {
      fieldMapping = const {};
    }

    // ── validation_rules ─────────────────────────────────────────────────────
    final rawValidationRules = json['validation_rules'];
    final Map<String, dynamic> validationRules;
    if (rawValidationRules is Map<String, dynamic>) {
      validationRules = rawValidationRules;
    } else {
      validationRules = const {};
    }

    // ── flags ─────────────────────────────────────────────────────────────────
    final isPaginatedList = json['is_paginated_list'] as bool? ?? false;
    final offlineCache = json['offline_cache'] as bool? ?? false;

    // Warn: paginated_list + future_provider is incompatible
    if (isPaginatedList && providerType == ProviderType.futureProvider) {
      // Will be overridden to async_notifier in the parser; handled there.
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
    );
  }

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// Snake-cased feature name, e.g. `"userProfile"` → `"user_profile"`.
  String get snakeFeatureName => StringUtils.toSnakeCase(featureName);

  /// Provider type string for passing to [JsonParser].
  String get providerTypeString => providerType.jsonValue;

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
