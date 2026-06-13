/// Dart reserved keyword detection and safe name generation.
///
/// Covers all Dart 3.x keywords including context keywords introduced in
/// Dart 3 (sealed, base, final, interface, when) plus common Riverpod
/// generated names that would conflict if used as field names.
library;

/// Utility for detecting and escaping Dart reserved keywords.
abstract final class Keywords {
  /// The complete set of reserved words in Dart 3.x.
  ///
  /// Includes:
  /// - Built-in identifiers
  /// - Limited reserved words
  /// - Context keywords that may clash in common usage
  /// - Common Riverpod generator names
  static const Set<String> _reserved = {
    // ── Dart reserved words ──────────────────────────────────────────────────
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base', // Dart 3 class modifier
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'Function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface', // Dart 3 class modifier
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed', // Dart 3 class modifier
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'type', // Dart 3 context keyword
    'typedef',
    'var',
    'void',
    'when', // Dart 3 pattern matching
    'while',
    'with',
    'yield',

    // ── Riverpod-generated names that clash as field names ────────────────
    'ref',
    'build',
    'state',
    'notifier',

    // ── Flutter widget lifecycle methods ───────────────────────────────────
    'context',
    'mounted',
    'widget',
  };

  /// Returns `true` if [name] is a Dart reserved keyword or a known
  /// name-clash identifier.
  static bool isKeyword(String name) => _reserved.contains(name);

  /// Returns a safe Dart identifier for [name].
  ///
  /// - If [name] is empty, returns `'unnamedField'`.
  /// - If [name] is a reserved keyword, appends `"Value"` (e.g. `'default'` →
  ///   `'defaultValue'`).
  /// - If [name] starts with a digit, prepends `"value"` (e.g. `'2fa'` →
  ///   `'value2fa'`).
  /// - Otherwise, returns [name] unchanged.
  static String getSafeName(String name) {
    if (name.isEmpty) return 'unnamedField';
    if (isKeyword(name)) return '${name}Value';
    final firstChar = name[0];
    if (RegExp(r'[0-9]').hasMatch(firstChar)) return 'value$name';
    return name;
  }
}
