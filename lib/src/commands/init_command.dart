/// `init` sub-command — writes a documented template config.json.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:ddd_pod_cli/src/core/exceptions.dart';
import 'package:ddd_pod_cli/src/core/logger.dart';

/// Writes a well-documented template `config.json` to [outputDir].
///
/// Throws [DddFileSystemException] if the file already exists and the user
/// declines to overwrite it, or on write failure.
Future<void> runInitCommand({
  String outputDir = '.',
}) async {
  final outputPath = p.join(
    p.isAbsolute(outputDir)
        ? outputDir
        : p.join(Directory.current.path, outputDir),
    'config.json',
  );
  final outputFile = File(outputPath);

  if (outputFile.existsSync()) {
    final overwrite = logger.confirm(
      'config.json already exists at $outputPath. Overwrite?',
      defaultValue: false,
    );
    if (!overwrite) {
      logger.info('Aborted. No changes made.');
      return;
    }
  }

  const templateJson = {
    '// DOCS':
        'Remove the comment fields (keys starting with //) before running.',
    'feature_name': 'MyFeature',
    '// feature_name': 'PascalCase name used as the class prefix.',
    'api_path': '/api/v1/my_features/:id',
    '// api_path':
        'The API endpoint. Supports :param and {param} path parameters.',
    'methods': ['GET', 'POST'],
    '// methods': 'HTTP methods. Valid values: GET, POST, PUT, PATCH, DELETE.',
    'provider_type': 'async_notifier',
    '// provider_type':
        'Riverpod provider type: notifier | async_notifier | future_provider.',
    'get_response_dto': {
      'id': 1,
      'title': 'Example title',
      'is_active': true,
      'created_at': '2024-01-01T00:00:00Z',
    },
    '// get_response_dto': 'Paste a representative GET response JSON here.',
    'post_request_body': {
      'title': '',
      'is_active': false,
    },
    '// post_request_body': 'Paste a representative POST/PUT request body here.',
    'type_overrides': {
      'created_at': 'DateTime',
    },
    '// type_overrides':
        'Override inferred types. Key = field name or dotted path.',
    'field_mapping': <String, dynamic>{},
    '// field_mapping':
        'Rename JSON keys to Dart field names. Key = JSON key, value = Dart name.',
    'is_paginated_list': false,
    '// is_paginated_list':
        'Set to true to generate paginated list support.',
    'offline_cache': false,
    '// offline_cache':
        'Set to true to generate SharedPreferences offline cache layer.',
    'validation_rules': {
      'title': {
        'required': true,
        'min_length': 3,
        'error_msg': 'Title must be at least 3 characters.',
      },
    },
    '// validation_rules':
        'Validation rules for form fields. Keys match request body field names.',
    'success_response': {
      'id': 1,
      'title': 'Example title',
      'is_active': true,
    },
    '// success_response':
        'Used to populate mock data in generated unit tests.',
  };

  final jsonStr = const JsonEncoder.withIndent('  ').convert(templateJson);

  try {
    outputFile.writeAsStringSync(jsonStr);
  } catch (e) {
    throw DddFileSystemException(
      message: 'Could not write config.json to $outputPath\n$e',
      hint:
          'Check that you have write permissions to the directory.',
      path: outputPath,
    );
  }

  logger.success('Template config.json created at $outputPath');
  logger.info(
    '\nNext steps:\n'
    '  1. Edit $outputPath with your actual API schema.\n'
    '  2. Run: ddd generate $outputPath',
  );
}
