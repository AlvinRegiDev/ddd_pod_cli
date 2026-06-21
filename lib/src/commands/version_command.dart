/// `version` sub-command — prints the current CLI version.
library;

import 'package:ddd_pod_cli/src/core/logger.dart';

/// The current CLI version — kept in sync with pubspec.yaml.
const String _kCliVersion = '1.0.4';

/// Prints the current CLI version to stdout.
void runVersionCommand() {
  logger.info('ddd_pod_cli v$_kCliVersion');
  logger.detail('A DDD+Riverpod+Freezed code generator.');
  logger.detail('https://github.com/AlvinRegiDev/ddd_pod_cli');
}
