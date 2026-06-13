/// Registry of pre-existing core domain and DTO classes in the target project.
///
/// The registry is populated by scanning the target project's `lib/domain/core`
/// and `lib/infrastructure/core` directories for Dart class declarations.
/// It enables the code generator to **reuse** shared types (e.g. `PaginationModel`,
/// `MetaDto`) rather than duplicating them per-feature.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/utils/string_utils.dart';

/// Holds a registry of class names → relative import paths for core types.
final class CoreModelsRegistry {
  /// Domain class names → relative import path from `lib/`.
  final Map<String, String> domainClassesToPaths = {};

  /// DTO class names → relative import path from `lib/`.
  final Map<String, String> dtoClassesToPaths = {};

  CoreModelsRegistry();

  // ── Scanning ───────────────────────────────────────────────────────────────

  /// Scan the target project's `lib/` directory for core model declarations.
  ///
  /// Looks in:
  /// - `lib/domain/core/` for domain classes
  /// - `lib/infrastructure/core/` for DTO classes
  void scan(String projectLibPath) {
    domainClassesToPaths.clear();
    dtoClassesToPaths.clear();

    final domainCoreDir = Directory(p.join(projectLibPath, 'domain', 'core'));
    if (domainCoreDir.existsSync()) {
      _scanDirectory(domainCoreDir, projectLibPath, domainClassesToPaths);
      logger.detail(
        'Core domain scan: found ${domainClassesToPaths.length} class(es) '
        'in ${domainCoreDir.path}',
      );
    }

    final infraCoreDir =
        Directory(p.join(projectLibPath, 'infrastructure', 'core'));
    if (infraCoreDir.existsSync()) {
      _scanDirectory(infraCoreDir, projectLibPath, dtoClassesToPaths);
      logger.detail(
        'Core DTO scan: found ${dtoClassesToPaths.length} class(es) '
        'in ${infraCoreDir.path}',
      );
    }
  }

  void _scanDirectory(
    Directory dir,
    String projectLibPath,
    Map<String, String> registryMap,
  ) {
    try {
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.dart')) {
          String content;
          try {
            content = entity.readAsStringSync();
          } catch (e) {
            logger.warn('Could not read file ${entity.path}: $e');
            continue;
          }
          final classRegex = RegExp(
            r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+)?class\s+([a-zA-Z0-9_]+)\b',
            multiLine: true,
          );
          final relativePath = p.relative(entity.path, from: projectLibPath);
          for (final match in classRegex.allMatches(content)) {
            final className = match.group(1)!;
            registryMap[className] = relativePath;
          }
        }
      }
    } catch (e) {
      logger.warn('Failed to scan directory ${dir.path}: $e');
    }
  }

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Find a core domain class whose name matches the given JSON [key].
  ///
  /// Checks for both `PascalKey` and `PascalKeyModel` variants.
  String? findMatchingCoreDomainClass(String key) {
    final pascalKey = StringUtils.toPascalCase(StringUtils.singularize(key));
    for (final className in domainClassesToPaths.keys) {
      if (className == pascalKey || className == '${pascalKey}Model') {
        return className;
      }
    }
    return null;
  }

  /// Find a matching core DTO class for the given [domainClassName].
  ///
  /// Checks for `<Base>Dto`, `<DomainClassName>Dto`, and `<Base>` variants.
  String? findMatchingCoreDtoClass(String domainClassName) {
    final base = domainClassName.replaceAll(RegExp(r'Model$'), '');
    for (final className in dtoClassesToPaths.keys) {
      if (className == '${base}Dto' ||
          className == '${domainClassName}Dto' ||
          className == base) {
        return className;
      }
    }
    return null;
  }

  /// Returns the `package:` import path for [className].
  ///
  /// Returns `null` if the class is not in the registry.
  String? getImportPath(
    String packageName,
    String className, {
    required bool isDto,
  }) {
    final registryMap = isDto ? dtoClassesToPaths : domainClassesToPaths;
    final relativePath = registryMap[className];
    if (relativePath == null) return null;
    return 'package:$packageName/$relativePath';
  }

  /// Whether the registry has found any classes at all.
  bool get isEmpty => domainClassesToPaths.isEmpty && dtoClassesToPaths.isEmpty;
}
