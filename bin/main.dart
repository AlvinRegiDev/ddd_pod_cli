// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/args.dart';

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/commands/generate_command.dart';
import 'package:ddd_pod_cli/src/commands/curl_command.dart';
import 'package:ddd_pod_cli/src/commands/delete_command.dart';
import 'package:ddd_pod_cli/src/commands/init_command.dart';
import 'package:ddd_pod_cli/src/commands/version_command.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _kCliVersion = '1.0.0';

// ─────────────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  // Catch Ctrl-C cleanly
  ProcessSignal.sigint.watch().listen((_) {
    print('\n\n⚠️  Interrupted. Exiting…');
    exit(130);
  });

  // ── Top-level arg parser ─────────────────────────────────────────────────
  final globalParser = ArgParser()
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Print verbose / debug output.')
    ..addFlag('quiet',
        abbr: 'q', negatable: false, help: 'Suppress all output except errors.')
    ..addFlag('no-color',
        negatable: false, help: 'Disable ANSI colour in output.')
    ..addCommand('generate', _buildGenerateParser())
    ..addCommand('curl', _buildCurlParser())
    ..addCommand('delete', _buildDeleteParser())
    ..addCommand('init', _buildInitParser())
    ..addCommand('version');

  // ── Parse ─────────────────────────────────────────────────────────────────
  ArgResults results;
  try {
    results = globalParser.parse(args);
  } on FormatException catch (e) {
    // Print help without the logger (not initialised yet)
    print('Error: ${e.message}\n');
    _printHelp(globalParser);
    exit(1);
  }

  // ── Initialise logger ──────────────────────────────────────────────────────
  final verbose = results['verbose'] as bool;
  final quiet = results['quiet'] as bool;
  DddLogger.init(verbose: verbose, quiet: quiet);

  // ── Banner ────────────────────────────────────────────────────────────────
  if (!quiet) _printBanner();

  // ── Dispatch ──────────────────────────────────────────────────────────────
  final commandName = results.command?.name;

  // Backwards-compatible: no sub-command + positional args → treat as generate
  if (commandName == null) {
    if (results.rest.isEmpty) {
      _printHelp(globalParser);
      exit(0);
    }
    // Legacy: `ddd_pod config.json [--force]`
    await _legacyGenerate(results, globalParser);
    return;
  }

  try {
    switch (commandName) {
      case 'generate':
        await _runGenerate(results.command!);
      case 'curl':
        await _runCurl(results.command!);
      case 'delete':
        await _runDelete(results.command!);
      case 'init':
        await _runInit(results.command!);
      case 'version':
        runVersionCommand();
      default:
        logger.err('Unknown command: $commandName');
        _printHelp(globalParser);
        exit(1);
    }
  } on DddCliException catch (e) {
    logger.errorWithHint(e.message, hint: e.hint);
    exit(1);
  } catch (e, st) {
    logger.err('Unexpected error: $e');
    logger.detail('Stack trace:\n$st');
    exit(1);
  }
  exit(0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-parsers
// ─────────────────────────────────────────────────────────────────────────────

ArgParser _buildGenerateParser() => ArgParser()
  ..addOption(
    'config',
    abbr: 'c',
    defaultsTo: 'config.json',
    help: 'Path to the config.json file.',
    valueHelp: 'FILE',
  )
  ..addFlag('force',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite existing files without prompting.')
  ..addFlag('skip-build-runner',
      negatable: false, help: 'Skip running build_runner after generation.')
  ..addFlag('debug-view',
      negatable: false, help: 'Generate a debug/presentation page.');

ArgParser _buildCurlParser() => ArgParser()
  ..addOption(
    'feature-name',
    abbr: 'n',
    help: 'PascalCase feature name (required).',
    valueHelp: 'NAME',
  )
  ..addOption(
    'provider-type',
    help:
        'Riverpod provider type: notifier | async_notifier | future_provider.',
    valueHelp: 'TYPE',
  )
  ..addFlag('force',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite existing files without prompting.')
  ..addFlag('skip-build-runner',
      negatable: false, help: 'Skip running build_runner after generation.')
  ..addFlag('debug-view',
      negatable: false, help: 'Generate a debug/presentation page.');

ArgParser _buildDeleteParser() => ArgParser()
  ..addFlag('skip-build-runner',
      negatable: false, help: 'Skip running build_runner after deletion.')
  ..addFlag('dry-run',
      negatable: false,
      help: 'Print what would be deleted without actually removing files.');

ArgParser _buildInitParser() => ArgParser()
  ..addOption(
    'output',
    abbr: 'o',
    defaultsTo: '.',
    help: 'Directory to write config.json into.',
    valueHelp: 'DIR',
  );

// ─────────────────────────────────────────────────────────────────────────────
// Command runners
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _runGenerate(ArgResults sub) async {
  final configPath = sub['config'] as String;
  final force = sub['force'] as bool;
  final skipBuildRunner = sub['skip-build-runner'] as bool;
  final debugView = sub['debug-view'] as bool;

  await runGenerateCommand(
    configPath: configPath,
    force: force,
    skipBuildRunner: skipBuildRunner,
    withDebugView: debugView,
  );
}

Future<void> _runCurl(ArgResults sub) async {
  final featureName = sub['feature-name'] as String?;
  if (featureName == null || featureName.isEmpty) {
    throw const ConfigException(
      message: 'The --feature-name flag is required for the curl command.',
      hint:
          'Example: ddd curl "curl https://api.example.com/v1/items" --feature-name Item',
    );
  }
  if (sub.rest.isEmpty) {
    throw const ConfigException(
      message: 'No cURL command provided.',
      hint:
          'Example: ddd curl "curl -X GET https://api.example.com/v1/items" --feature-name Item',
    );
  }

  await runCurlCommand(
    curlCommand: sub.rest.join(' '),
    featureName: featureName,
    force: sub['force'] as bool,
    skipBuildRunner: sub['skip-build-runner'] as bool,
    withDebugView: sub['debug-view'] as bool,
    providerType: sub['provider-type'] as String?,
  );
}

Future<void> _runDelete(ArgResults sub) async {
  if (sub.rest.isEmpty) {
    throw const ConfigException(
      message: 'No feature name provided to delete.',
      hint: 'Example: ddd delete MyFeature',
    );
  }
  await runDeleteCommand(
    featureName: sub.rest.first,
    skipBuildRunner: sub['skip-build-runner'] as bool,
    dryRun: sub['dry-run'] as bool,
  );
}

Future<void> _runInit(ArgResults sub) async {
  final outputDir = sub['output'] as String;
  await runInitCommand(outputDir: outputDir);
}

// ─────────────────────────────────────────────────────────────────────────────
// Backwards-compat legacy mode
// ─────────────────────────────────────────────────────────────────────────────

/// Handle the old invocation style: `ddd config.json [--force] [FeatureName]`
Future<void> _legacyGenerate(ArgResults results, ArgParser globalParser) async {
  final restArgs = results.rest;
  String? configPath;
  bool force = false;
  bool skipBuildRunner = false;
  String? deleteFeature;
  String? curlCommand;
  String? curlFeatureName;

  int i = 0;
  while (i < restArgs.length) {
    final arg = restArgs[i];
    if (arg == '--force' || arg == '-f') {
      force = true;
    } else if (arg == '--skip-build-runner') {
      skipBuildRunner = true;
    } else if (arg == 'delete' && i + 1 < restArgs.length) {
      deleteFeature = restArgs[i + 1];
      i++;
    } else if (arg == 'curl' && i + 1 < restArgs.length) {
      curlCommand = restArgs[i + 1];
      i++;
    } else if (arg == '--feature-name' && i + 1 < restArgs.length) {
      curlFeatureName = restArgs[i + 1];
      i++;
    } else if (!arg.startsWith('-')) {
      configPath ??= arg;
    }
    i++;
  }

  if (deleteFeature != null) {
    await runDeleteCommand(
      featureName: deleteFeature,
      skipBuildRunner: skipBuildRunner,
    );
    return;
  }

  if (curlCommand != null && curlFeatureName != null) {
    await runCurlCommand(
      curlCommand: curlCommand,
      featureName: curlFeatureName,
      force: force,
      skipBuildRunner: skipBuildRunner,
      withDebugView: false,
    );
    return;
  }

  await runGenerateCommand(
    configPath: configPath ?? 'config.json',
    force: force,
    skipBuildRunner: skipBuildRunner,
    withDebugView: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner & help
// ─────────────────────────────────────────────────────────────────────────────

void _printBanner() {
  print('');
  print('  ██████╗ ██████╗ ██████╗      ██████╗███╗   ███╗██████╗');
  print('  ██╔══██╗██╔══██╗██╔══██╗    ██╔════╝████╗ ████║██╔══██╗');
  print('  ██║  ██║██║  ██║██║  ██║    ██║     ██╔████╔██║██║  ██║');
  print('  ██║  ██║██║  ██║██║  ██║    ██║     ██║╚██╔╝██║██║  ██║');
  print('  ██████╔╝██████╔╝██████╔╝    ╚██████╗██║ ╚═╝ ██║██████╔╝');
  print('  ╚═════╝ ╚═════╝ ╚═════╝      ╚═════╝╚═╝     ╚═╝╚═════╝');
  print('');
  print('  DDD + Riverpod + Freezed Code Generator  v$_kCliVersion');
  print('');
}

void _printHelp(ArgParser parser) {
  print('''
USAGE
  ddd <command> [options]

COMMANDS
  generate    Scaffold a DDD feature from a config.json file
  curl        Scaffold from a live API cURL request
  delete      Remove all generated files for a feature
  init        Create a documented config.json template
  version     Print the CLI version

GLOBAL FLAGS
  -v, --verbose   Print verbose / debug output
  -q, --quiet     Suppress all output except errors
  --no-color      Disable ANSI colours

EXAMPLES
  ddd init
  ddd generate --config config.json --force
  ddd curl "curl https://api.example.com/v1/users" --feature-name User
  ddd delete UserProfile
  ddd delete MyFeature --dry-run
  ddd version
''');
}
