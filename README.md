# ddd_pod_cli

A robust, enterprise-grade Dart & Flutter CLI tool that scaffolds complete **Domain-Driven Design (DDD)** Feature-First architecture code structures. It generates Riverpod 2.0 controllers/states, Freezed models, type-safe DTOs with fpdart `Either`, and full DIO data-source layers directly from a single JSON configuration file or a live `cURL` command.

---

## Key Features

- 🏗️ **Feature-First DDD Scaffolding**: Automatically generates a clean layer structure (`domain`, `infrastructure`, `application`, and optional `presentation`).
- ⚡ **Riverpod 2.0 Integration**: Generates modern notifier classes (`Notifier`, `AsyncNotifier`, or `FutureProvider`) using the latest generator annotations.
- ❄️ **Freezed Model Generation**: Scaffolds immutable domain models and DTOs with full `fromJson`/`toJson` support.
- 🌐 **cURL-to-DDD Generation**: Paste any `cURL` request, and the CLI will hit the endpoint, perform type inference on the response JSON, and build the entire architecture on the fly.
- 🗒️ **Form & Validation Generation**: Define declarative field validation rules in JSON to auto-scaffold Freezed form states, validation controllers, and inputs.
- 📦 **Re-usable Core Models**: Scans your project to detect and reuse existing domain models to avoid duplicate file generation.
- 💾 **Offline Caching**: Scaffolds a `SharedPreferences`-backed offline cache layer automatically with a single config flag.
- 🧪 **Unit Test Scaffolding**: Generates pre-wired unit tests with mock repositories for the application layer.

---

## Installation

Activate the CLI globally via pub.dev:

```bash
dart pub global activate ddd_pod_cli
```

Make sure your system PATH includes the Dart SDK cache bin directory.

---

## Quick Start

### Step 1: Initialize Configuration

Run `init` in your project root to generate a template configuration file:

```bash
ddd init
```

This creates a pre-configured `config.json` with instructions on custom configurations.

### Step 2: Configure & Generate

Edit the generated `config.json` to define your feature schema, then run:

```bash
ddd generate
```

This will:
1. Parse the JSON schema configuration.
2. Scaffold all directories in `lib/features/your_feature/`.
3. Auto-generate all required DTOs, models, notifier controllers, repository contracts, and network layers.
4. Auto-run `build_runner` to compile Freezed and Riverpod files.

---

## CLI Commands Reference

### `ddd init`
Creates a documented template `config.json` file in the current or specified directory.
- Options:
  - `-o, --output <DIR>`: Directory to write the template file into (defaults to `.`).

### `ddd generate`
Generates a DDD feature from a JSON configuration file.
- Options:
  - `-c, --config <FILE>`: Path to the JSON configuration file (defaults to `config.json`).
  - `-f, --force`: Overwrite existing files without prompting.
  - `--skip-build-runner`: Skip running `build_runner` after code generation.
  - `--debug-view`: Generate a mock debug/presentation page.

### `ddd curl`
Executes a live API request and scaffolds a DDD feature directly from the live response JSON.
- Usage:
  ```bash
  ddd curl "curl -X GET https://api.example.com/v1/users" --feature-name User
  ```
- Options:
  - `-n, --feature-name <NAME>`: PascalCase name of the feature (required).
  - `--provider-type <TYPE>`: Riverpod provider type (`notifier` | `async_notifier` | `future_provider`).
  - `-f, --force`: Overwrite existing files without prompting.
  - `--skip-build-runner`: Skip running `build_runner` after generation.
  - `--debug-view`: Generate a mock debug/presentation page.

### `ddd delete`
Removes all generated files and directories for a given feature.
- Usage:
  ```bash
  ddd delete MyFeature
  ```
- Options:
  - `--dry-run`: Prints what would be deleted without removing files.
  - `--skip-build-runner`: Skip running `build_runner` after deletion.

### `ddd version`
Prints the CLI package version.

---

## Configuration File Structure (`config.json`)

Here is an explanation of the core configuration parameters:

```json
{
  "feature_name": "UserProfile",         // PascalCase feature name used as prefix
  "api_path": "/api/v1/users/:id",       // API endpoint path (interpolates :param)
  "methods": ["GET", "PUT"],            // Supported HTTP methods
  "provider_type": "async_notifier",     // Riverpod provider type: async_notifier | notifier | future_provider
  "get_response_dto": {                  // Response JSON structure for type-inference
    "id": 1,
    "name": "Jane Doe",
    "is_premium": true
  },
  "post_request_body": {                 // Request body JSON structure for POST/PUT requests
    "name": "Jane Doe"
  },
  "type_overrides": {                    // Manually override inferred types
    "created_at": "DateTime"
  },
  "field_mapping": {                     // Rename JSON payload keys to custom Dart fields
    "is_premium": "isPremiumUser"
  },
  "is_paginated_list": false,            // Scaffolds paginated lists (fetchNextPage, hasMore)
  "offline_cache": true,                 // Scaffolds SharedPreferences database caching
  "validation_rules": {                  // Form input validation rules
    "name": {
      "required": true,
      "min_length": 3,
      "error_msg": "Name must be at least 3 characters"
    }
  }
}
```

---

## Generated Directory Structure

A generated feature (e.g. `UserProfile`) follows this structure:

```
lib/features/user_profile/
├── domain/
│   ├── failures.dart               // Custom business logic network/caching failures
│   ├── user_profile.dart          // Immutable Freezed domain entity
│   └── user_profile_repository.dart // Abstract repository interface contract
├── infrastructure/
│   ├── datasources/
│   │   ├── user_profile_local_datasource.dart // (Optional) SharedPreferences cache layer
│   │   └── user_profile_remote_datasource.dart // DIO network request client
│   ├── dtos/
│   │   └── user_profile_dto.dart   // JSON serializers and toDomain/fromDomain converters
│   └── user_profile_repository_impl.dart // Concrete repository implementation
└── application/
    ├── user_profile_notifier.dart  // Riverpod StateNotifier/Notifier logic
    ├── user_profile_state.dart     // UI/Application state representation
    └── user_profile_provider.dart  // Auto-wired Riverpod providers
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
