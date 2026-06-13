/// Immutable data models representing the parsed schema used by [CodeGenerator].
///
/// These are internal value objects — they carry no behaviour beyond
/// structured data storage. All fields are final and constructors use
/// named parameters with explicit defaults for optional values.
library;

// ─────────────────────────────────────────────────────────────────────────────
// DTO layer
// ─────────────────────────────────────────────────────────────────────────────

/// Describes a single field in a generated Freezed DTO class.
final class DtoField {
  const DtoField({
    required this.jsonKey,
    required this.dartName,
    required this.typeName,
    this.isNestedObject = false,
    this.isNestedList = false,
    this.nestedClassName,
  });

  /// The original JSON key (used in `@JsonKey(name: '...')`).
  final String jsonKey;

  /// The safe, camelCase Dart field name.
  final String dartName;

  /// The fully-qualified Dart type string (e.g. `'String?'`, `'List<ItemDto>?'`).
  final String typeName;

  /// Whether this field maps to a nested Freezed DTO object.
  final bool isNestedObject;

  /// Whether this field maps to a list of nested Freezed DTO objects.
  final bool isNestedList;

  /// The class name of the nested type when [isNestedObject] or
  /// [isNestedList] is `true`.
  final String? nestedClassName;
}

/// Describes a generated Freezed DTO class (response or request).
final class DtoClass {
  const DtoClass({
    required this.className,
    required this.fields,
    this.isRequest = false,
  });

  /// The PascalCase class name **without** the `Dto` suffix.
  final String className;

  /// Ordered list of fields in the generated class.
  final List<DtoField> fields;

  /// `true` if this DTO represents a request body; `false` for responses.
  final bool isRequest;
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain layer
// ─────────────────────────────────────────────────────────────────────────────

/// Describes a single field in a generated Freezed domain model.
final class DomainField {
  const DomainField({
    required this.fieldName,
    required this.typeName,
    required this.jsonPath,
    this.isNestedList = false,
    this.isNestedObject = false,
    this.nestedClassName,
    this.enumHint,
  });

  /// The camelCase Dart field name.
  final String fieldName;

  /// The fully-qualified Dart type string.
  final String typeName;

  /// The dotted JSON path from the DTO root to this field
  /// (used to generate `toDomain()` mapping expressions).
  final List<String> jsonPath;

  /// Whether this field maps to a list of nested domain objects.
  final bool isNestedList;

  /// Whether this field maps to a nested domain object.
  final bool isNestedObject;

  /// The class name of the nested type when [isNestedObject] or
  /// [isNestedList] is `true`.
  final String? nestedClassName;

  /// Optional: the distinct string values observed in the sample data.
  ///
  /// When non-null, the code generator will emit a comment listing these
  /// values as potential enum candidates. Only set when the field is a
  /// String (or list of strings) with ≤ 8 distinct values.
  final List<String>? enumHint;
}

/// Describes a generated Freezed domain model class.
final class DomainClass {
  const DomainClass({
    required this.className,
    required this.fields,
    required this.dtoClassName,
    this.isCore = false,
  });

  /// The PascalCase class name (includes the `Model` suffix, e.g. `'UserModel'`).
  final String className;

  /// Ordered list of fields in the generated model.
  final List<DomainField> fields;

  /// The corresponding DTO class name used when generating `toDomain()`.
  final String dtoClassName;

  /// `true` if this is the root response model for the feature.
  final bool isCore;
}
