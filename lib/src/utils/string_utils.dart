/// String manipulation utilities for the ddd_pod_cli code generator.
///
/// All methods are pure functions with no side effects. They are used
/// extensively across the parser and generator layers to transform JSON keys
/// into valid, idiomatic Dart identifiers.
library;

/// A collection of string transformation helpers.
abstract final class StringUtils {
  /// Convert a `snake_case` or `PascalCase` string to `camelCase`.
  ///
  /// Examples:
  /// ```
  /// snakeToCamel('verified_at')  → 'verifiedAt'
  /// snakeToCamel('UserProfile')  → 'userProfile'
  /// snakeToCamel('avatar_url')   → 'avatarUrl'
  /// snakeToCamel('2fa_enabled')  → '2faEnabled'  (caller must sanitize further)
  /// ```
  static String snakeToCamel(String s) {
    // Normalize camelCase → snake to preserve existing camel segments
    final withUnderscores = s.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (Match m) => '${m.group(1)}_${m.group(2)}',
    );
    // Replace non-identifier characters with underscores
    final clean = withUnderscores.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final parts = clean.split('_').where((e) => e.isNotEmpty);
    if (parts.isEmpty) return '';

    final first = parts.first.toLowerCase();
    final rest = parts.skip(1).map((p) {
      if (p.isEmpty) return '';
      return '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}';
    }).join();
    return '$first$rest';
  }

  /// Convert a string to `PascalCase`.
  ///
  /// Examples:
  /// ```
  /// toPascalCase('verified_at')  → 'VerifiedAt'
  /// toPascalCase('UserProfile')  → 'UserProfile'
  /// ```
  static String toPascalCase(String s) {
    final camel = snakeToCamel(s);
    if (camel.isEmpty) return '';
    return '${camel[0].toUpperCase()}${camel.substring(1)}';
  }

  /// Convert a `camelCase` or `PascalCase` string to `snake_case`.
  ///
  /// Examples:
  /// ```
  /// toSnakeCase('UserProfile')   → 'user_profile'
  /// toSnakeCase('verifiedAt')    → 'verified_at'
  /// toSnakeCase('already_snake') → 'already_snake'
  /// ```
  static String toSnakeCase(String s) {
    return s
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (Match m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
  }

  /// Attempt to singularize a common English plural word.
  ///
  /// This is a heuristic-based implementation covering the most common cases
  /// encountered in REST API response JSON keys. It is not a full
  /// morphological analyser.
  ///
  /// Examples:
  /// ```
  /// singularize('layers')         → 'layer'
  /// singularize('categories')     → 'category'
  /// singularize('aliases')        → 'alias'
  /// singularize('indices')        → 'index'
  /// singularize('matrices')       → 'matrix'
  /// singularize('series')         → 'series'   (invariant)
  /// singularize('status')         → 'status'   (invariant)
  /// singularize('settings')       → 'settings' (invariant)
  /// singularize('active_projects')→ 'active_project'
  /// ```
  static String singularize(String s) {
    final lower = s.toLowerCase();

    // ── Invariants (words that are the same singular and plural) ──────────
    const invariants = {
      'status',
      'settings',
      'meta',
      'series',
      'species',
      'deer',
      'fish',
      'sheep',
      'moose',
      'means',
      'news',
      'mathematics',
      'physics',
      'data', // treated as plural of datum but often used as-is
    };
    if (invariants.contains(lower)) return s;

    // ── Irregular forms ────────────────────────────────────────────────────
    const irregulars = {
      'children': 'child',
      'people': 'person',
      'men': 'man',
      'women': 'woman',
      'teeth': 'tooth',
      'geese': 'goose',
      'mice': 'mouse',
      'oxen': 'ox',
      'indices': 'index',
      'matrices': 'matrix',
      'vertices': 'vertex',
      'aliases': 'alias',
      'analyses': 'analysis',
      'crises': 'crisis',
      'axes': 'axis',
      'diagnoses': 'diagnosis',
      'theses': 'thesis',
    };
    if (irregulars.containsKey(lower)) return irregulars[lower]!;

    // ── Rules (most-specific first) ────────────────────────────────────────
    if (lower.endsWith('ies') && lower.length > 3) {
      // categories → category
      return '${s.substring(0, s.length - 3)}y';
    }
    if (lower.endsWith('sses') ||
        lower.endsWith('ches') ||
        lower.endsWith('shes') ||
        lower.endsWith('xes')) {
      // classes → class, matches → match, flashes → flash, boxes → box
      return s.substring(0, s.length - 2);
    }
    if (lower.endsWith('ses') && lower.length > 3) {
      // statuses → status; but 'ses' alone stays
      return s.substring(0, s.length - 2);
    }
    if (lower.endsWith('ves') && lower.length > 3) {
      // leaves → leaf, knives → knife
      return '${s.substring(0, s.length - 3)}f';
    }
    if (lower.endsWith('s') && lower.length > 1) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Strip characters that are not valid in a Dart identifier and replace
  /// them with underscores.
  ///
  /// Leading digits are prefixed with `value`. This is a last-resort
  /// sanitiser used when a JSON key contains unusual characters.
  static String sanitizeIdentifier(String s) {
    // Replace any non-identifier character with underscore
    final cleaned = s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    // Collapse consecutive underscores
    final collapsed = cleaned.replaceAll(RegExp(r'_+'), '_');
    // Strip leading/trailing underscores
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    if (trimmed.isEmpty) return 'unnamedField';
    // Prefix if leading digit
    if (RegExp(r'^[0-9]').hasMatch(trimmed)) return 'value$trimmed';
    return trimmed;
  }

  /// Derive the Riverpod provider name from a class name.
  /// Strips trailing 'Notifier' or 'Controller' and appends 'Provider' in camelCase.
  static String deriveProviderName(String className) {
    var base = className;
    if (base.endsWith('Notifier')) {
      base = base.substring(0, base.length - 'Notifier'.length);
    } else if (base.endsWith('Controller')) {
      base = base.substring(0, base.length - 'Controller'.length);
    }
    return '${snakeToCamel(base)}Provider';
  }
}
