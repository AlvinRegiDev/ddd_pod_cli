/// ddd_pod_cli — Professional DDD + Riverpod + Freezed Code Generator.
///
/// This barrel file exports the public API surface used by both the CLI
/// entry point and the test suite.
library;

// ── Core infrastructure ──────────────────────────────────────────────────────
export 'src/core/exceptions.dart';
export 'src/core/logger.dart';

// ── Configuration model ───────────────────────────────────────────────────────
export 'src/config/feature_config.dart';

// ── Parser ────────────────────────────────────────────────────────────────────
export 'src/parser/json_parser.dart';
export 'src/parser/models.dart';
export 'src/parser/core_models_registry.dart';
export 'src/parser/curl_parser.dart';

// ── Generator ─────────────────────────────────────────────────────────────────
export 'src/generator/directory_scaffolder.dart';
export 'src/generator/code_generator.dart';
export 'src/generator/runner.dart';

// ── Utilities ─────────────────────────────────────────────────────────────────
export 'src/utils/keywords.dart';
export 'src/utils/string_utils.dart';

// ── Commands ──────────────────────────────────────────────────────────────────
export 'src/commands/generate_command.dart';
export 'src/commands/curl_command.dart';
export 'src/commands/delete_command.dart';
export 'src/commands/init_command.dart';
export 'src/commands/version_command.dart';
