# Changelog

All notable changes to this project will be documented in this file.

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
