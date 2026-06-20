# Changelog

All notable changes to this project will be documented in this file.

## 1.0.3

- **Feature**: Improved the dependency scaffolder to directly update `pubspec.yaml` and run `pub get` rather than running slower individual `pub add` command calls.
- **Feature**: Added automatic support for matching and importing existing core domain classes and DTOs from the registry instead of generating duplicates.
- **Feature**: Refactored the test overrides code generator to support `AsyncNotifier`, `Notifier`, `StreamNotifier`, and family/parameterized providers with custom Mock classes and `.overrideWith` / `.overrideWith2` APIs.
- **Feature**: Automatically map and use default fallbacks for nested non-nullable domain model fields from DTO mappings.
- **Fix**: Standardized generated Riverpod Observers to use `base class` syntax to align with modern Dart rules.
- **Fix**: Prevented generation of the unused `_retry` helper for WebSocket-based stream remote data sources.
- **Fix**: Ensured derived providers use specific class/element return types instead of `dynamic` when filtering list responses.
- **Fix**: Handled DTO serialization/deserialization appropriately when mapping registry-matched core models.

## 1.0.2

- **Feature**: Added automatic detection and installation of missing required dependencies and dev dependencies in the target project's `pubspec.yaml` when scaffolding.
- **Feature**: Upgraded Riverpod generation templates to use standard generic `Ref` types for modern Riverpod compatibility.
- **Feature**: Enhanced generated Riverpod unit tests with subscription tracking (`container.listen`/`subscription.close()`) to prevent premature auto-dispose.
- **Fix**: Resolved compilation errors in generated provider test override stubs caused by template escaping.
- **Fix**: Standardized generated form provider naming conventions to prevent view-level mismatches.
- **Fix**: Removed unused `dart:convert` import from generated mock interceptors to avoid linter warnings.
- **Fix**: Resolved internal CLI static analysis issues (unused variables and imports).

## 1.0.1

- Update package README with comprehensive usage instructions, options, and commands documentation.

## 1.0.0

- Initial release of `ddd_pod_cli`.
- Support for scaffolding Domain-Driven Design (DDD) Feature-First architecture with Riverpod 2.0.
- Automatic generation of Freezed models, DTOs, and fpdart/DIO data-source layers from JSON configuration or cURL commands.
- Form validation and state scaffolding templates.
- Reusable core models and Riverpod provider auto-wiring.
- Robust parsing, naming collision mitigation, and reserved keyword renaming.
