/// JSON schema parser and type-inference engine for the ddd_pod_cli tool.
///
/// Analyses raw JSON response / request payloads and produces strongly-typed
/// [DtoClass], [DomainClass], and related metadata used by [CodeGenerator]
/// to emit correct Dart code.
///
/// Key responsibilities:
/// - Recursive type inference with depth-limit and cycle detection
/// - Nullable type annotation based on observed values
/// - Reserved keyword escaping via [Keywords.getSafeName]
/// - Core model reuse via [CoreModelsRegistry]
/// - Field-mapping and type-override support
/// - Enum hinting when a field has ≤ 8 distinct string values
library;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/utils/keywords.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';
import 'package:ddd_pod_cli/src/parser/models.dart';
import 'package:ddd_pod_cli/src/parser/core_models_registry.dart';

/// Maximum recursion depth for nested schema inference.
///
/// Schemas deeper than this will cause a [SchemaParseException] to be thrown.
const int _kMaxDepth = 20;

// ─────────────────────────────────────────────────────────────────────────────

/// Parses JSON schemas into DTO and domain class descriptors.
final class JsonParser {
  JsonParser({
    required this.featureName,
    required this.responseJson,
    this.requestJson,
    String? providerType,
    Map<String, String>? typeOverrides,
    this.registry,
    this.packageName,
    Map<String, String>? fieldMapping,
    bool? isPaginatedList,
    bool? offlineCache,
    Map<String, dynamic>? validationRules,
  }) : typeOverrides = typeOverrides ?? const {},
       fieldMapping = fieldMapping ?? const {},
       isPaginatedList = isPaginatedList ?? false,
       offlineCache = offlineCache ?? false,
       validationRules = validationRules ?? const {} {
    if (providerType != null) {
      this.providerType = providerType;
    }
    if (this.isPaginatedList) {
      isListResponse = true;
      if (this.providerType == 'future_provider') {
        logger.warn(
          'Paginated lists require state mutation. '
          'Overriding "provider_type" from "future_provider" to "async_notifier".',
        );
        this.providerType = 'async_notifier';
      }
    }
    _parse();
  }

  // ── Inputs ─────────────────────────────────────────────────────────────────

  /// Feature name (PascalCase or snake_case, normalised internally).
  final String featureName;

  /// Decoded GET-response JSON schema. May be a [Map], [List], or primitive.
  final dynamic responseJson;

  /// Decoded POST/PUT/PATCH request-body JSON schema. May be null.
  final dynamic requestJson;

  /// Manual type overrides keyed by field name or dotted path.
  final Map<String, String> typeOverrides;

  /// Registry of pre-existing core domain / DTO classes in the target project.
  final CoreModelsRegistry? registry;

  /// Package name of the target project (used for import paths).
  final String? packageName;

  /// JSON-key → Dart-name remappings.
  final Map<String, String> fieldMapping;

  /// Whether to generate paginated-list logic.
  final bool isPaginatedList;

  /// Whether to generate offline-cache (SharedPreferences) layer.
  final bool offlineCache;

  /// Declarative validation rules for form fields.
  final Map<String, dynamic> validationRules;

  // ── Outputs ────────────────────────────────────────────────────────────────

  final Set<String> coreDomainImports = {};
  final Set<String> coreDtoImports = {};

  final List<DtoClass> responseDtoClasses = [];
  final List<DtoClass> requestDtoClasses = [];
  final List<DomainClass> domainClasses = [];

  bool isListResponse = false;
  bool isTopLevelList = false;
  List<String> corePathToDomain = [];
  String providerType = 'notifier';
  String responseDataType = 'dynamic';
  String responseDtoType = 'dynamic';

  // ── Internal state ─────────────────────────────────────────────────────────

  /// Class names currently being inferred — used to detect cyclic schemas.
  final Set<String> _classNamesInProgress = {};

  // ── Root-level config keys that are NOT JSON data fields ──────────────────
  static const _excludedRootKeys = {
    'provider_type',
    'feature_name',
    'api_path',
    'endpoint',
    'methods',
    'get_response_dto',
    'payload',
    'post_request_body',
    'put_request_body',
    'patch_request_body',
    'request_body',
  };

  // ── Parse entry point ──────────────────────────────────────────────────────

  void _parse() {
    final rootClassName = StringUtils.toPascalCase(featureName);

    if (responseJson != null) {
      if (responseJson is List) {
        _parseTopLevelList(responseJson as List, rootClassName);
      } else if (responseJson is Map<String, dynamic>) {
        _parseResponseMap(responseJson as Map<String, dynamic>, rootClassName);
      } else {
        responseDataType = _inferPrimitiveType(responseJson);
        responseDtoType = responseDataType;
      }
    } else {
      responseDataType = 'void';
      responseDtoType = 'void';
    }

    if (requestJson != null) {
      _parseRequestJson(requestJson, rootClassName);
    }

    _buildDomainModels(rootClassName);
  }

  void _parseTopLevelList(List<dynamic> list, String rootClassName) {
    isTopLevelList = true;
    isListResponse = true;
    final maps = list.whereType<Map<String, dynamic>>().toList();
    if (maps.isNotEmpty) {
      responseDataType = '${rootClassName}Model';
      responseDtoType = '${rootClassName}Dto';
      final mergedMap = _mergeMaps(maps);
      _inferDto(mergedMap, rootClassName, responseDtoClasses, false,
          depth: 0);
    } else {
      final elemType = _inferListElementType(list);
      responseDataType = elemType;
      responseDtoType = elemType;
    }
  }

  void _parseResponseMap(
      Map<String, dynamic> map, String rootClassName) {
    if (map.containsKey('provider_type')) {
      providerType = map['provider_type'] as String;
    }

    responseDataType = '${rootClassName}Model';
    responseDtoType = '${rootClassName}Dto';

    _inferDto(map, rootClassName, responseDtoClasses, false,
        isRoot: true, depth: 0);

    const envelopeKeys = ['data', 'result', 'results', 'payload', 'items'];
    String? foundEnvelopeKey;
    for (final key in envelopeKeys) {
      if (map.containsKey(key) && map[key] != null) {
        foundEnvelopeKey = key;
        break;
      }
    }

    if (foundEnvelopeKey != null) {
      final coreVal = map[foundEnvelopeKey];
      if (coreVal is List) {
        final hasMaps = coreVal.any((item) => item is Map<String, dynamic>);
        final override =
            typeOverrides[foundEnvelopeKey];
        final isModelListOverride = override != null &&
            (override.contains('Dto') || override.contains('Model'));
        if (hasMaps || isModelListOverride) {
          corePathToDomain = [foundEnvelopeKey];
          isListResponse = true;
        }
      } else if (coreVal is Map<String, dynamic>) {
        corePathToDomain = [foundEnvelopeKey];
      }
    }
  }

  void _parseRequestJson(dynamic reqJson, String rootClassName) {
    final requestRootName = '${rootClassName}Request';
    if (reqJson is Map<String, dynamic>) {
      _inferDto(reqJson, requestRootName, requestDtoClasses, true,
          isRoot: true, depth: 0);
    } else if (reqJson is List) {
      final maps = reqJson.whereType<Map<String, dynamic>>().toList();
      if (maps.isNotEmpty) {
        final mergedMap = _mergeMaps(maps);
        _inferDto(mergedMap, requestRootName, requestDtoClasses, true,
            depth: 0);
      }
    } else {
      logger.warn(
        'Request body is not a JSON object or array '
        '(got ${reqJson.runtimeType}). Skipping request DTO generation.',
      );
    }
  }

  // ── DTO inference ──────────────────────────────────────────────────────────

  void _inferDto(
    Map<String, dynamic> map,
    String className,
    List<DtoClass> classes,
    bool isRequest, {
    bool isRoot = false,
    List<String> currentPath = const [],
    int depth = 0,
  }) {
    // ── Depth guard ──────────────────────────────────────────────────────────
    if (depth > _kMaxDepth) {
      throw SchemaParseException(
        message:
            'Schema nesting depth exceeds the maximum of $_kMaxDepth levels '
            '(at class "$className").',
        hint:
            'Simplify your JSON schema or add a "type_overrides" entry for '
            'the deeply-nested field.',
      );
    }

    // ── Cycle guard ──────────────────────────────────────────────────────────
    if (_classNamesInProgress.contains(className)) {
      throw SchemaParseException(
        message:
            'Cyclic schema detected for class "$className". '
            'Recursive JSON schemas are not supported.',
        hint:
            'Add a "type_overrides" entry to break the cycle, e.g. '
            '"$className": "Map<String, dynamic>".',
      );
    }
    _classNamesInProgress.add(className);

    try {
      final fields = <DtoField>[];
      final usedNames = <String>{};

      map.forEach((key, value) {
        if (isRoot && _excludedRootKeys.contains(key)) return;

        final fieldPath = [...currentPath, key].join('.');
        final overriddenType = typeOverrides[fieldPath] ?? typeOverrides[key];

        final mappedKey = fieldMapping[key] ?? StringUtils.snakeToCamel(key);
        var dartName = Keywords.getSafeName(mappedKey);
        while (usedNames.contains(dartName)) {
          dartName = _deduplicateName(dartName);
        }
        usedNames.add(dartName);

        if (overriddenType != null) {
          fields.add(DtoField(
              jsonKey: key, dartName: dartName, typeName: overriddenType));
          return;
        }

        if (value is Map<String, dynamic>) {
          _inferDtoObjectField(
              key, dartName, value, className, classes, isRequest,
              currentPath: currentPath, depth: depth, fields: fields);
        } else if (value is List) {
          _inferDtoListField(
              key, dartName, value, className, classes, isRequest,
              currentPath: currentPath, depth: depth, fields: fields);
        } else {
          final primitiveType = _inferPrimitiveType(value);
          final typeName =
              primitiveType == 'dynamic' ? 'dynamic' : '$primitiveType?';
          fields.add(
              DtoField(jsonKey: key, dartName: dartName, typeName: typeName));
        }
      });

      classes.add(
          DtoClass(className: className, fields: fields, isRequest: isRequest));
    } finally {
      _classNamesInProgress.remove(className);
    }
  }

  void _inferDtoObjectField(
    String key,
    String dartName,
    Map<String, dynamic> value,
    String parentClassName,
    List<DtoClass> classes,
    bool isRequest, {
    required List<String> currentPath,
    required int depth,
    required List<DtoField> fields,
  }) {
    final matchedDomainClass = registry?.findMatchingCoreDomainClass(key);
    if (matchedDomainClass != null) {
      final matchedDtoClass =
          registry?.findMatchingCoreDtoClass(matchedDomainClass);
      final dtoTypeName =
          matchedDtoClass ?? '${matchedDomainClass}Dto';

      fields.add(DtoField(
        jsonKey: key,
        dartName: dartName,
        typeName: '$dtoTypeName?',
        isNestedObject: true,
        nestedClassName: matchedDtoClass ?? matchedDomainClass,
      ));

      if (packageName != null) {
        final domainImport = registry?.getImportPath(packageName!,
            matchedDomainClass, isDto: false);
        if (domainImport != null) coreDomainImports.add(domainImport);
        if (matchedDtoClass != null) {
          final dtoImport = registry?.getImportPath(packageName!,
              matchedDtoClass, isDto: true);
          if (dtoImport != null) coreDtoImports.add(dtoImport);
        }
      }
    } else {
      final nestedClassName =
          '$parentClassName${StringUtils.toPascalCase(key)}';
      fields.add(DtoField(
        jsonKey: key,
        dartName: dartName,
        typeName: '${nestedClassName}Dto?',
        isNestedObject: true,
        nestedClassName: nestedClassName,
      ));
      _inferDto(value, nestedClassName, classes, isRequest,
          currentPath: [...currentPath, key], depth: depth + 1);
    }
  }

  void _inferDtoListField(
    String key,
    String dartName,
    List<dynamic> value,
    String parentClassName,
    List<DtoClass> classes,
    bool isRequest, {
    required List<String> currentPath,
    required int depth,
    required List<DtoField> fields,
  }) {
    if (value.isEmpty) {
      fields.add(DtoField(
          jsonKey: key, dartName: dartName, typeName: 'List<dynamic>?'));
      return;
    }

    final hasMap = value.any((item) => item is Map<String, dynamic>);
    if (hasMap) {
      final singularKey = StringUtils.singularize(key);
      final matchedDomainClass =
          registry?.findMatchingCoreDomainClass(singularKey);
      if (matchedDomainClass != null) {
        final matchedDtoClass =
            registry?.findMatchingCoreDtoClass(matchedDomainClass);
        final dtoTypeName =
            matchedDtoClass ?? '${matchedDomainClass}Dto';

        fields.add(DtoField(
          jsonKey: key,
          dartName: dartName,
          typeName: 'List<$dtoTypeName>?',
          isNestedList: true,
          nestedClassName: matchedDtoClass ?? matchedDomainClass,
        ));

        if (packageName != null) {
          final domainImport = registry?.getImportPath(packageName!,
              matchedDomainClass, isDto: false);
          if (domainImport != null) coreDomainImports.add(domainImport);
          if (matchedDtoClass != null) {
            final dtoImport = registry?.getImportPath(packageName!,
                matchedDtoClass, isDto: true);
            if (dtoImport != null) coreDtoImports.add(dtoImport);
          }
        }
      } else {
        final nestedClassName =
            '$parentClassName${StringUtils.toPascalCase(singularKey)}';
        fields.add(DtoField(
          jsonKey: key,
          dartName: dartName,
          typeName: 'List<${nestedClassName}Dto>?',
          isNestedList: true,
          nestedClassName: nestedClassName,
        ));
        final maps = value.whereType<Map<String, dynamic>>().toList();
        final mergedMap = _mergeMaps(maps);
        _inferDto(mergedMap, nestedClassName, classes, isRequest,
            currentPath: [...currentPath, key], depth: depth + 1);
      }
    } else {
      final elementTypeName = _inferListElementType(value);

      // Enum hinting: if the list contains ≤ 8 distinct String values,
      // they may represent an enum. The caller will embed a comment.
      final typeString =
          elementTypeName == 'dynamic' ? 'dynamic' : '$elementTypeName?';
      fields.add(DtoField(
          jsonKey: key, dartName: dartName, typeName: 'List<$typeString>?'));
    }
  }

  // ── Primitive type inference ───────────────────────────────────────────────

  String _inferPrimitiveType(dynamic value) {
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is bool) return 'bool';
    if (value is String) return 'String';
    return 'dynamic';
  }

  String _inferListElementType(List<dynamic> list) {
    final nonNullValues = list.where((v) => v != null).toList();
    if (nonNullValues.isEmpty) return 'dynamic';

    if (nonNullValues.every((v) => v is int)) return 'int';
    if (nonNullValues.every((v) => v is double)) return 'double';
    // Crossover int + double → double
    if (nonNullValues.every((v) => v is num)) return 'double';
    if (nonNullValues.every((v) => v is bool)) return 'bool';
    if (nonNullValues.every((v) => v is String)) return 'String';
    return 'dynamic'; // mixed types
  }

  // ── Enum hinting ───────────────────────────────────────────────────────────

  /// Returns up to [_kEnumHintMax] distinct string values found in a list,
  /// or null if the list contains non-string values or has more distinct
  /// values than the threshold.
  static const int _kEnumHintMax = 8;

  List<String>? _enumHint(List<dynamic> list) {
    if (!list.every((v) => v is String)) return null;
    final distinct = list.cast<String>().toSet().toList();
    if (distinct.length <= _kEnumHintMax) return distinct..sort();
    return null;
  }

  // ── Name helpers ───────────────────────────────────────────────────────────

  String _deduplicateName(String name) {
    final match = RegExp(r'(\d+)$').firstMatch(name);
    if (match != null) {
      final numberStr = match.group(1)!;
      final number = int.parse(numberStr);
      final baseName = name.substring(0, name.length - numberStr.length);
      return '$baseName${number + 1}';
    }
    return '${name}2';
  }

  // ── Map merging ────────────────────────────────────────────────────────────

  Map<String, dynamic> _mergeMaps(List<Map<String, dynamic>> maps) {
    final merged = <String, dynamic>{};
    final allKeys = maps.expand((m) => m.keys).toSet();

    for (final key in allKeys) {
      final values = maps.map((m) => m[key]).where((v) => v != null).toList();
      if (values.isEmpty) {
        merged[key] = null;
        continue;
      }

      if (values.every((v) => v is Map<String, dynamic>)) {
        merged[key] = _mergeMaps(values.cast<Map<String, dynamic>>());
      } else if (values.every((v) => v is List)) {
        merged[key] = _mergeLists(values.cast<List<dynamic>>());
      } else {
        if (values.every((v) => v is String)) {
          merged[key] = 'string';
        } else if (values.every((v) => v is bool)) {
          merged[key] = true;
        } else if (values.every((v) => v is num)) {
          merged[key] = values.any((v) => v is double) ? 1.0 : 1;
        } else {
          merged[key] = null;
        }
      }
    }

    return merged;
  }

  List<dynamic> _mergeLists(List<List<dynamic>> lists) {
    return lists.expand((l) => l).toList();
  }

  // ── Domain model building ──────────────────────────────────────────────────

  void _buildDomainModels(String rootClassName) {
    dynamic coreSchema = responseJson;
    String coreDtoClassName = rootClassName;

    if (corePathToDomain.isNotEmpty) {
      final envelopeKey = corePathToDomain.first;
      final singularKey = StringUtils.singularize(envelopeKey);
      final matchedDomainClass =
          registry?.findMatchingCoreDomainClass(singularKey);
      if (matchedDomainClass != null) return;
      coreSchema = responseJson[envelopeKey];
      final isList = coreSchema is List;
      coreDtoClassName =
          '$rootClassName${StringUtils.toPascalCase(isList ? singularKey : envelopeKey)}';
    } else if (responseJson is List) {
      final singularFeature = StringUtils.singularize(featureName);
      final matchedDomainClass =
          registry?.findMatchingCoreDomainClass(singularFeature);
      if (matchedDomainClass != null) return;
    }

    if (coreSchema == null) return;

    if (coreSchema is List) {
      if (coreSchema.isEmpty) return;
      final maps = coreSchema.whereType<Map<String, dynamic>>().toList();
      if (maps.isEmpty) return;
      coreSchema = _mergeMaps(maps);
    }

    if (coreSchema is! Map<String, dynamic> || coreSchema.isEmpty) return;

    final coreFields = <DomainField>[];
    _gatherDomainFields(
      coreSchema,
      [],
      '',
      coreFields,
      rootClassName,
      coreDtoClassName,
      depth: 0,
    );

    domainClasses.add(DomainClass(
      className: '${rootClassName}Model',
      dtoClassName: '${coreDtoClassName}Dto',
      fields: coreFields,
      isCore: true,
    ));
  }

  void _gatherDomainFields(
    Map<String, dynamic> map,
    List<String> currentPath,
    String prefix,
    List<DomainField> fields,
    String domainPrefix,
    String dtoPrefix, {
    int depth = 0,
  }) {
    if (depth > _kMaxDepth) {
      throw const SchemaParseException(
        message:
            'Domain model nesting depth exceeds the maximum of $_kMaxDepth levels.',
        hint: 'Add a "type_overrides" entry for the deeply-nested field.',
      );
    }

    map.forEach((key, value) {
      if (_excludedRootKeys.contains(key) && currentPath.isEmpty) return;

      final newPath = [...currentPath, key];
      final fieldPath = newPath.join('.');
      final fullPath = corePathToDomain.isEmpty
          ? fieldPath
          : [...corePathToDomain, ...newPath].join('.');
      final overriddenType =
          typeOverrides[fullPath] ?? typeOverrides[fieldPath] ?? typeOverrides[key];

      // Apply fieldMapping to each path segment when building the field name
      final mappedKey = fieldMapping[key] ?? StringUtils.snakeToCamel(key);
      final safeKey = Keywords.getSafeName(mappedKey);
      final newPrefix = prefix.isEmpty
          ? safeKey
          : '$prefix${StringUtils.toPascalCase(safeKey)}';

      final usedNames = fields.map((f) => f.fieldName).toSet();
      var fieldName = newPrefix;
      while (usedNames.contains(fieldName)) {
        fieldName = _deduplicateName(fieldName);
      }

      var finalType = overriddenType;
      if (finalType != null) {
        fields.add(DomainField(
            fieldName: fieldName,
            typeName: finalType,
            jsonPath: newPath));
        return;
      }

      if (value is Map<String, dynamic>) {
        final matchedDomainClass =
            registry?.findMatchingCoreDomainClass(key);
        if (matchedDomainClass != null) {
          fields.add(DomainField(
            fieldName: fieldName,
            typeName: '$matchedDomainClass?',
            jsonPath: newPath,
            isNestedObject: true,
            nestedClassName: matchedDomainClass,
          ));
          if (packageName != null) {
            final domainImport = registry?.getImportPath(packageName!,
                matchedDomainClass, isDto: false);
            if (domainImport != null) coreDomainImports.add(domainImport);
          }
        } else {
          _gatherDomainFields(
            value,
            newPath,
            newPrefix,
            fields,
            domainPrefix,
            '$dtoPrefix${StringUtils.toPascalCase(key)}',
            depth: depth + 1,
          );
        }
      } else if (value is List) {
        if (value.isEmpty) {
          fields.add(DomainField(
              fieldName: fieldName,
              typeName: 'List<dynamic>?',
              jsonPath: newPath));
        } else {
          final hasMap = value.any((item) => item is Map<String, dynamic>);
          if (hasMap) {
            final singularKey = StringUtils.singularize(key);
            final matchedDomainClass =
                registry?.findMatchingCoreDomainClass(singularKey);
            if (matchedDomainClass != null) {
              fields.add(DomainField(
                fieldName: fieldName,
                typeName: 'List<$matchedDomainClass>?',
                jsonPath: newPath,
                isNestedList: true,
                nestedClassName: matchedDomainClass,
              ));
              if (packageName != null) {
                final domainImport = registry?.getImportPath(packageName!,
                    matchedDomainClass, isDto: false);
                if (domainImport != null) {
                  coreDomainImports.add(domainImport);
                }
              }
            } else {
              final nestedClassName =
                  '$domainPrefix${StringUtils.toPascalCase(singularKey)}Model';
              final nestedDtoClassName =
                  '$dtoPrefix${StringUtils.toPascalCase(singularKey)}Dto';

              final maps =
                  value.whereType<Map<String, dynamic>>().toList();
              final mergedMap = _mergeMaps(maps);

              final nestedFields = <DomainField>[];
              _gatherDomainFields(
                mergedMap,
                [],
                '',
                nestedFields,
                '$domainPrefix${StringUtils.toPascalCase(singularKey)}',
                '$dtoPrefix${StringUtils.toPascalCase(singularKey)}',
                depth: depth + 1,
              );

              domainClasses.add(DomainClass(
                className: nestedClassName,
                dtoClassName: nestedDtoClassName,
                fields: nestedFields,
                isCore: false,
              ));

              fields.add(DomainField(
                fieldName: fieldName,
                typeName: 'List<$nestedClassName>?',
                jsonPath: newPath,
                isNestedList: true,
                nestedClassName: nestedClassName,
              ));
            }
          } else {
            // Enum hint for primitive string lists
            final enumValues = _enumHint(value);
            final elementTypeName = _inferListElementType(value);
            final typeString = elementTypeName == 'dynamic'
                ? 'dynamic'
                : '$elementTypeName?';
            fields.add(DomainField(
              fieldName: fieldName,
              typeName: 'List<$typeString>?',
              jsonPath: newPath,
              enumHint: enumValues,
            ));
          }
        }
      } else {
        final primitiveType = _inferPrimitiveType(value);
        final typeName =
            primitiveType == 'dynamic' ? 'dynamic' : '$primitiveType?';
        // Enum hint for primitive string fields in the sample data
        final enumHint = value is String ? [value] : null;
        fields.add(DomainField(
          fieldName: fieldName,
          typeName: typeName,
          jsonPath: newPath,
          enumHint: enumHint,
        ));
      }
    });
  }
}
