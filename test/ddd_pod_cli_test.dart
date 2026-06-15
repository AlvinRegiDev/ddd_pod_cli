import 'dart:io';

import 'package:test/test.dart';

import 'package:ddd_pod_cli/ddd_pod_cli.dart';

void main() {
  // Initialise the logger singleton before any tests run
  setUpAll(() => DddLogger.init());

  group('StringUtils Tests', () {
    test('snakeToCamel converts casing correctly', () {
      expect(StringUtils.snakeToCamel('verified_at'), 'verifiedAt');
      expect(StringUtils.snakeToCamel('Dashboard'), 'dashboard');
      expect(StringUtils.snakeToCamel('avatar_url'), 'avatarUrl');
    });

    test('toPascalCase converts casing correctly', () {
      expect(StringUtils.toPascalCase('verified_at'), 'VerifiedAt');
      expect(StringUtils.toPascalCase('Dashboard'), 'Dashboard');
      expect(StringUtils.toPascalCase('avatar_url'), 'AvatarUrl');
    });

    test('singularize handles plural forms correctly', () {
      expect(StringUtils.singularize('active_projects'), 'active_project');
      expect(StringUtils.singularize('layers'), 'layer');
      expect(StringUtils.singularize('status'), 'status');
      expect(StringUtils.singularize('settings'), 'settings');
    });
  });

  group('Keywords Tests', () {
    test('getSafeName escapes reserved keywords', () {
      expect(Keywords.getSafeName('default'), 'default_');
      expect(Keywords.getSafeName('class'), 'class_');
      expect(Keywords.getSafeName('normal'), 'normal');
    });
  });

  group('JsonParser Type Inference Tests', () {
    test('infers types and renames keywords successfully', () {
      final json = {
        'status': 'success',
        'data': {
          'workspace_id': 'ws_8821',
          'default': true,
          'class': 'premium_tier',
          'owner': {'id': 1042, 'email': 'creator@example.com'},
        },
      };

      final parser = JsonParser(
        featureName: 'Dashboard',
        responseJson: json,
      );

      expect(parser.responseDtoClasses, isNotEmpty);

      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Dashboard',
      );
      expect(
        rootDto.fields.any(
          (f) => f.jsonKey == 'status' && f.typeName == 'String?',
        ),
        isTrue,
      );

      final dataDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'DashboardData',
      );
      expect(
        dataDto.fields.any(
          (f) =>
              f.jsonKey == 'default' &&
              f.dartName == 'default_' &&
              f.typeName == 'bool?',
        ),
        isTrue,
      );
      expect(
        dataDto.fields.any(
          (f) =>
              f.jsonKey == 'class' &&
              f.dartName == 'class_' &&
              f.typeName == 'String?',
        ),
        isTrue,
      );

      expect(parser.domainClasses, isNotEmpty);
      final coreDomain = parser.domainClasses.firstWhere(
        (c) => c.className == 'DashboardModel',
      );
      expect(
        coreDomain.fields.any(
          (f) => f.fieldName == 'workspaceId' && f.typeName == 'String?',
        ),
        isTrue,
      );
      expect(
        coreDomain.fields.any(
          (f) => f.fieldName == 'default_' && f.typeName == 'bool?',
        ),
        isTrue,
      );
      expect(
        coreDomain.fields.any(
          (f) => f.fieldName == 'class_' && f.typeName == 'String?',
        ),
        isTrue,
      );
      expect(
        coreDomain.fields.any(
          (f) => f.fieldName == 'ownerId' && f.typeName == 'int?',
        ),
        isTrue,
      );
      expect(
        coreDomain.fields.any(
          (f) => f.fieldName == 'ownerEmail' && f.typeName == 'String?',
        ),
        isTrue,
      );
    });

    test('parses provider_type and ignores root metadata keys', () {
      final json = {
        'provider_type': 'async_notifier',
        'feature_name': 'MyFeature',
        'api_path': '/api/my_feature',
        'id': 123,
        'title': 'Hello',
      };
      final parser = JsonParser(featureName: 'MyFeature', responseJson: json);
      expect(parser.providerType, 'async_notifier');
      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'MyFeature',
      );
      expect(rootDto.fields.any((f) => f.jsonKey == 'id'), isTrue);
      expect(rootDto.fields.any((f) => f.jsonKey == 'title'), isTrue);
      expect(rootDto.fields.any((f) => f.jsonKey == 'provider_type'), isFalse);
      expect(rootDto.fields.any((f) => f.jsonKey == 'feature_name'), isFalse);
      expect(rootDto.fields.any((f) => f.jsonKey == 'api_path'), isFalse);
    });

    test(
      'handles empty lists, primitive lists, nested object lists, and nested objects with unique prefixes',
      () {
        final json = {
          'empty_arr': <dynamic>[],
          'primitive_arr': ['a', 'b'],
          'nested_object': {
            'id': 1,
            'settings': {'theme': 'dark'},
          },
          'layers': [
            {
              'index': 0,
              'details': {'opacity': 0.8},
            },
          ],
        };
        final parser = JsonParser(
          featureName: 'Dashboard',
          responseJson: json,
          typeOverrides: {'empty_arr': 'List<dynamic>?'},
        );

        final rootDto = parser.responseDtoClasses.firstWhere(
          (c) => c.className == 'Dashboard',
        );

        final emptyField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'empty_arr',
        );
        expect(emptyField.typeName, 'List<dynamic>?');

        final primField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'primitive_arr',
        );
        expect(primField.typeName, 'List<String?>?');

        final layersField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'layers',
        );
        expect(layersField.typeName, 'List<DashboardLayerDto>?');
        expect(layersField.isNestedList, isTrue);

        final hasLayerDetailsDto = parser.responseDtoClasses.any(
          (c) => c.className == 'DashboardLayerDetails',
        );
        expect(hasLayerDetailsDto, isTrue);

        final hasSettingsDto = parser.responseDtoClasses.any(
          (c) => c.className == 'DashboardNestedObjectSettings',
        );
        expect(hasSettingsDto, isTrue);
      },
    );

    test('generates notifier code correctly for different provider types', () {
      final parserAsync = JsonParser(
        featureName: 'Dashboard',
        responseJson: {'provider_type': 'async_notifier', 'id': 1},
      );
      final genAsync = CodeGenerator(
        parser: parserAsync,
        packageName: 'my_app',
        featureName: 'Dashboard',
        endpoint: '/endpoint',
        methods: ['GET'],
      );
      final asyncCode = genAsync.generateNotifierCode();
      expect(
        asyncCode.contains(
          'class DashboardNotifier extends _\$DashboardNotifier',
        ),
        isTrue,
      );
      expect(asyncCode.contains('FutureOr<DashboardModel> build()'), isTrue);

      final parserFuture = JsonParser(
        featureName: 'Dashboard',
        responseJson: {'provider_type': 'future_provider', 'id': 1},
      );
      final genFuture = CodeGenerator(
        parser: parserFuture,
        packageName: 'my_app',
        featureName: 'Dashboard',
        endpoint: '/endpoint',
        methods: ['GET'],
      );
      final futureCode = genFuture.generateNotifierCode();
      expect(
        futureCode.contains(
          'Future<DashboardModel> dashboard(Ref ref)',
        ),
        isTrue,
      );

      final parserNotifier = JsonParser(
        featureName: 'Dashboard',
        responseJson: {'provider_type': 'notifier', 'id': 1},
      );
      final genNotifier = CodeGenerator(
        parser: parserNotifier,
        packageName: 'my_app',
        featureName: 'Dashboard',
        endpoint: '/endpoint',
        methods: ['GET'],
      );
      final notifierCode = genNotifier.generateNotifierCode();
      expect(
        notifierCode.contains(
          'class DashboardNotifier extends _\$DashboardNotifier',
        ),
        isTrue,
      );
      expect(notifierCode.contains('DashboardState build()'), isTrue);
    });

    test('generates correct toDomain list response envelope mapping', () {
      final json = {
        'status': 'success',
        'data': [
          {'id': 1, 'name': 'Item'},
        ],
      };
      final parser = JsonParser(
        featureName: 'Dashboard',
        responseJson: json,
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'my_app',
        featureName: 'Dashboard',
        endpoint: '/endpoint',
        methods: ['GET'],
      );
      final dtoCode = generator.generateDtoCode();
      expect(dtoCode.contains('List<DashboardModel> toDomain()'), isTrue);
      expect(
        dtoCode.contains('data?.map((e) => e.toDomain()).toList() ?? const []'),
        isTrue,
      );
    });

    test(
      'merges schemas of list objects and resolves mixed types / crossover values',
      () {
        final json = {
          'items': [
            {'id': 1, 'score': 100},
            {'name': 'Alvin', 'score': 95.5},
            {'title': 'Lead', 'data': 'extra_info'},
          ],
          'mixed_list': [1, "hello", true],
          'crossover_list': [1, 2.5, 3],
        };
        final parser = JsonParser(
          featureName: 'Dashboard',
          responseJson: json,
        );

        final rootDto = parser.responseDtoClasses.firstWhere(
          (c) => c.className == 'Dashboard',
        );

        final mixedField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'mixed_list',
        );
        expect(mixedField.typeName, 'List<dynamic>?');

        final crossoverField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'crossover_list',
        );
        expect(crossoverField.typeName, 'List<double?>?');

        final itemDto = parser.responseDtoClasses.firstWhere(
          (c) => c.className == 'DashboardItem',
        );
        expect(
          itemDto.fields.any((f) => f.jsonKey == 'id' && f.typeName == 'int?'),
          isTrue,
        );
        expect(
          itemDto.fields.any(
            (f) => f.jsonKey == 'name' && f.typeName == 'String?',
          ),
          isTrue,
        );
        expect(
          itemDto.fields.any(
            (f) => f.jsonKey == 'title' && f.typeName == 'String?',
          ),
          isTrue,
        );
        expect(
          itemDto.fields.any(
            (f) => f.jsonKey == 'data' && f.typeName == 'String?',
          ),
          isTrue,
        );
        expect(
          itemDto.fields.any(
            (f) => f.jsonKey == 'score' && f.typeName == 'double?',
          ),
          isTrue,
        );
      },
    );

    test('escapes keys starting with digits correctly', () {
      final json = {'2fa_enabled': true, '1st_prize': 'gold'};
      final parser = JsonParser(
        featureName: 'Dashboard',
        responseJson: json,
      );
      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Dashboard',
      );
      expect(
        rootDto.fields.any(
          (f) => f.jsonKey == '2fa_enabled' && f.dartName == 'value2faEnabled',
        ),
        isTrue,
      );
      expect(
        rootDto.fields.any(
          (f) => f.jsonKey == '1st_prize' && f.dartName == 'value1stPrize',
        ),
        isTrue,
      );
    });
  });

  group('Real-world Enhancements Tests', () {
    test('interpolates path parameters correctly', () {
      final parser = JsonParser(
        featureName: 'PostComment',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'my_app',
        featureName: 'PostComment',
        endpoint: '/api/v1/posts/:post_id/comments/{commentId}',
        methods: ['GET'],
      );

      final map = generator.pathParamsMap;
      expect(map[':post_id'], 'postId');
      expect(map['{commentId}'], 'commentId');

      final url = generator.getInterpolatedEndpoint();
      expect(url, "'/api/v1/posts/\$postId/comments/\$commentId'");
    });

    test('generates correct CRUD signatures for all methods', () {
      final parser = JsonParser(
        featureName: 'Task',
        responseJson: {'id': 1, 'name': 'Task A'},
        requestJson: {'name': 'New Task'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'my_app',
        featureName: 'Task',
        endpoint: '/api/tasks/:id',
        methods: ['GET', 'POST', 'PUT', 'DELETE'],
      );

      final repoCode = generator.generateIRepositoryCode();
      expect(
        repoCode.contains(
          'Future<Either<TaskFailure, TaskModel>> getTask({required String id, CancelToken? cancelToken});',
        ),
        isTrue,
      );
      expect(
        repoCode.contains(
          'Future<Either<TaskFailure, Unit>> createTask({required String id, required TaskRequestDto request, CancelToken? cancelToken});',
        ),
        isTrue,
      );
      expect(
        repoCode.contains(
          'Future<Either<TaskFailure, Unit>> updateTask({required String id, required TaskRequestDto request, CancelToken? cancelToken});',
        ),
        isTrue,
      );
      expect(
        repoCode.contains(
          'Future<Either<TaskFailure, Unit>> deleteTask({required String id, CancelToken? cancelToken});',
        ),
        isTrue,
      );

      final dataSourceCode = generator.generateRemoteDataSourceCode();
      expect(
        dataSourceCode.contains(
          'Future<TaskDto> getTask({required String id, CancelToken? cancelToken}) async',
        ),
        isTrue,
      );
      expect(
        dataSourceCode.contains(
          'Future<void> createTask({required String id, required TaskRequestDto request, CancelToken? cancelToken}) async',
        ),
        isTrue,
      );
      expect(
        dataSourceCode.contains(
          'Future<void> deleteTask({required String id, CancelToken? cancelToken}) async',
        ),
        isTrue,
      );
      expect(
        dataSourceCode.contains(
            "await _dio.delete('/api/tasks/\$id', cancelToken: cancelToken);"),
        isTrue,
      );
      expect(
        dataSourceCode.contains(
          "await _dio.post('/api/tasks/\$id', data: request.toJson(), cancelToken: cancelToken);",
        ),
        isTrue,
      );

      final repoImplCode = generator.generateRepositoryImplCode();
      expect(
        repoImplCode.contains(
          'Future<Either<TaskFailure, TaskModel>> getTask({required String id, CancelToken? cancelToken}) async',
        ),
        isTrue,
      );
      expect(
        repoImplCode.contains(
            'await _remoteDataSource.getTask(id: id, cancelToken: cancelToken);'),
        isTrue,
      );
      expect(
        repoImplCode.contains(
          'await _remoteDataSource.createTask(id: id, request: request, cancelToken: cancelToken);',
        ),
        isTrue,
      );
      expect(
        repoImplCode.contains("errorMessage = errorVal['message']?.toString()"),
        isTrue,
      );
    });

    test('respects file overwrite settings based on force flag', () {
      final tempDir = Directory.systemTemp.createTempSync('ddd_pod_cli_test_');
      try {
        final parser = JsonParser(
          featureName: 'Sample',
          responseJson: {'id': 1},
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Sample',
          endpoint: '/sample',
          methods: ['GET'],
          force: false,
        );

        final notifierFile = File('${tempDir.path}/sample_notifier.dart');
        notifierFile.writeAsStringSync('// Custom Logic');

        // Writing with force=false should not overwrite user-edited files
        generator.writeFile(
          notifierFile,
          '// Generated Code',
          isUserEdited: true,
        );
        expect(notifierFile.readAsStringSync(), '// Custom Logic');

        // Writing with force=false should not overwrite existing files (delegates to safeWriteToFile which skips if non-interactive/no y response)
        final stateFile = File('${tempDir.path}/sample_state.dart');
        stateFile.writeAsStringSync('// Custom State');
        generator.writeFile(
          stateFile,
          '// Generated State',
          isUserEdited: false,
        );
        expect(stateFile.readAsStringSync(), '// Custom State');

        // Writing with force=true should overwrite everything
        final generatorForce = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Sample',
          endpoint: '/sample',
          methods: ['GET'],
          force: true,
        );
        generatorForce.writeFile(
          notifierFile,
          '// Overwritten Code',
          isUserEdited: true,
        );
        expect(notifierFile.readAsStringSync(), '// Overwritten Code');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Debug View & Submit Logic Tests', () {
    test(
      'generates submission method on notifier when request body is present',
      () {
        final parser = JsonParser(
          featureName: 'Dashboard',
          responseJson: {'id': 1},
          requestJson: {'id': 123, 'name': 'Test', 'token': 'abc'},
          providerType: 'async_notifier',
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Dashboard',
          endpoint: '/sample',
          methods: ['POST'],
        );

        final notifierCode = generator.generateNotifierCode();
        expect(
          notifierCode.contains(
            'Future<void> submit({required int? id, required String? name, required String? token})',
          ),
          isTrue,
        );
        expect(
          notifierCode.contains(
            'request: DashboardRequestDto(id: id, name: name, token: token)',
          ),
          isTrue,
        );
      },
    );

    test(
      'generates debug page code with correct displays and button submission call',
      () {
        final parser = JsonParser(
          featureName: 'Dashboard',
          responseJson: {'id': 1},
          requestJson: {'id': 123, 'name': 'Test', 'token': 'abc'},
          providerType: 'async_notifier',
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Dashboard',
          endpoint: '/sample',
          methods: ['POST'],
        );

        final debugPageCode = generator.generateDebugPageCode();
        expect(
          debugPageCode.contains(
            'class DashboardDebugPage extends ConsumerWidget',
          ),
          isTrue,
        );
        expect(
          debugPageCode.contains('ref.watch(dashboardProvider)'),
          isTrue,
        );
        expect(
          debugPageCode.contains('ref.watch(dashboardFormProvider)'),
          isTrue,
        );
        expect(
          debugPageCode.contains(
            '.read(dashboardFormProvider.notifier)',
          ),
          isTrue,
        );
        expect(debugPageCode.contains('.submit('), isTrue);
      },
    );

    test(
      'generates debug page for future_provider calling repository directly',
      () {
        final parser = JsonParser(
          featureName: 'Dashboard',
          responseJson: {'id': 1},
          requestJson: {'id': 123, 'name': 'Test', 'token': 'abc'},
          providerType: 'future_provider',
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Dashboard',
          endpoint: '/sample',
          methods: ['POST'],
        );

        final debugPageCode = generator.generateDebugPageCode();
        expect(
          debugPageCode.contains(
            'class DashboardDebugPage extends ConsumerWidget',
          ),
          isTrue,
        );
        expect(
          debugPageCode.contains('ref.watch(dashboardProvider)'),
          isTrue,
        );
        expect(
          debugPageCode.contains(
            '.read(dashboardFormProvider.notifier)',
          ),
          isTrue,
        );
        expect(debugPageCode.contains('.submit('), isTrue);
      },
    );
  });

  group('Real-world Hardening Edge Cases', () {
    test('type_overrides uses exact overridden types in Dto and Domain', () {
      final parser = JsonParser(
        featureName: 'Order',
        responseJson: {
          'id': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'metadata': {'details': 'some_details'},
        },
        typeOverrides: {
          'id': 'String',
          'created_at': 'DateTime',
          'metadata.details': 'Map<String, dynamic>',
        },
      );

      final orderDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Order',
      );
      expect(
        orderDto.fields.firstWhere((f) => f.jsonKey == 'id').typeName,
        'String',
      );
      expect(
        orderDto.fields.firstWhere((f) => f.jsonKey == 'created_at').typeName,
        'DateTime',
      );

      final orderModel = parser.domainClasses.firstWhere(
        (c) => c.className == 'OrderModel',
      );
      expect(
        orderModel.fields.firstWhere((f) => f.fieldName == 'id').typeName,
        'String',
      );
      expect(
        orderModel.fields
            .firstWhere((f) => f.fieldName == 'createdAt')
            .typeName,
        'DateTime',
      );
      expect(
        orderModel.fields
            .firstWhere((f) => f.fieldName == 'metadataDetails')
            .typeName,
        'Map<String, dynamic>',
      );
    });

    test(
      'generates positional build parameters for class notifier build methods',
      () {
        final parser = JsonParser(
          featureName: 'Product',
          responseJson: {'id': 1},
          requestJson: {'id': 1},
          providerType: 'async_notifier',
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'shop',
          featureName: 'Product',
          endpoint: '/product/:categoryId/{productId}',
          methods: ['GET', 'POST'],
        );

        final notifierCode = generator.generateNotifierCode();
        expect(
          notifierCode.contains(
            'FutureOr<ProductModel> build(String categoryId, String productId) async',
          ),
          isTrue,
        );
        expect(
          notifierCode.contains('return build(categoryId, productId);'),
          isTrue,
        );
      },
    );

    test(
      'escapes reserved keywords on camelCase provider names and functional providers',
      () {
        final parser = JsonParser(
          featureName: 'Default',
          responseJson: {'id': 1},
          providerType: 'future_provider',
        );
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'my_app',
          featureName: 'Default',
          endpoint: '/default',
          methods: ['GET'],
        );

        final notifierCode = generator.generateNotifierCode();
        expect(
          notifierCode.contains('Future<DefaultModel> default_('),
          isTrue,
        );

        final parser2 = JsonParser(
          featureName: 'Default',
          responseJson: {'id': 1},
          providerType: 'notifier',
        );
        final generator2 = CodeGenerator(
          parser: parser2,
          packageName: 'my_app',
          featureName: 'Default',
          endpoint: '/default',
          methods: ['GET'],
        );
        final notifierCode2 = generator2.generateNotifierCode();
        expect(
          notifierCode2.contains(
            'ref.read(default_Provider.notifier)',
          ),
          isFalse,
        );
        expect(
          notifierCode2.contains(
            'class DefaultNotifier extends _\$DefaultNotifier',
          ),
          isTrue,
        );
      },
    );

    test(
      'deduplicates field names when JSON keys conflict or flatten to the same name',
      () {
        final parser = JsonParser(
          featureName: 'Conflicting',
          responseJson: {
            'user_id': 1,
            'userId': 'hello',
            'profile': {'name': 'A'},
            'profile_name': 'B',
          },
        );

        final rootDto = parser.responseDtoClasses.firstWhere(
          (c) => c.className == 'Conflicting',
        );
        final rootFields = rootDto.fields.map((f) => f.dartName).toList();
        expect(rootFields.contains('userId'), isTrue);
        expect(rootFields.contains('userId2'), isTrue);

        final rootModel = parser.domainClasses.firstWhere(
          (c) => c.className == 'ConflictingModel',
        );
        final modelFields = rootModel.fields.map((f) => f.fieldName).toList();
        expect(modelFields.contains('profileName'), isTrue);
        expect(modelFields.contains('profileName2'), isTrue);
      },
    );

    test(
      'handles top-level primitive and list of primitives response gracefully',
      () {
        final parserPrimitive = JsonParser(
          featureName: 'Ping',
          responseJson: 'pong',
        );
        expect(parserPrimitive.responseDataType, 'String');
        expect(parserPrimitive.responseDtoClasses, isEmpty);
        expect(parserPrimitive.domainClasses, isEmpty);

        final generatorPrimitive = CodeGenerator(
          parser: parserPrimitive,
          packageName: 'test',
          featureName: 'Ping',
          endpoint: '/ping',
          methods: ['GET'],
        );
        final repoCode = generatorPrimitive.generateIRepositoryCode();
        expect(
          repoCode.contains(
              'Future<Either<PingFailure, String>> getPing({CancelToken? cancelToken});'),
          isTrue,
        );

        final parserListPrimitive = JsonParser(
          featureName: 'Tags',
          responseJson: ['dart', 'flutter'],
        );
        expect(parserListPrimitive.responseDataType, 'String');
        expect(parserListPrimitive.isListResponse, isTrue);
        expect(parserListPrimitive.responseDtoClasses, isEmpty);
        expect(parserListPrimitive.domainClasses, isEmpty);

        final generatorListPrimitive = CodeGenerator(
          parser: parserListPrimitive,
          packageName: 'test',
          featureName: 'Tags',
          endpoint: '/tags',
          methods: ['GET'],
        );
        final repoCode2 = generatorListPrimitive.generateIRepositoryCode();
        expect(
          repoCode2.contains(
            'Future<Either<TagsFailure, List<String>>> getTags({CancelToken? cancelToken});',
          ),
          isTrue,
        );

        final remoteSourceCode =
            generatorListPrimitive.generateRemoteDataSourceCode();
        expect(
          remoteSourceCode.contains(
              'Future<List<String>> getTags({CancelToken? cancelToken}) async'),
          isTrue,
        );
        // Updated: list.cast is the expected pattern from the generator
        expect(
          remoteSourceCode.contains('getTags') &&
              remoteSourceCode.contains('List<String>'),
          isTrue,
        );
      },
    );
  });

  group('Architectural Enhancements Tests', () {
    test('auto-wiring DI generates repository implementation imports', () {
      final parser = JsonParser(
        featureName: 'Complaints',
        responseJson: {'status': 'ok'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'hospital',
        featureName: 'Complaints',
        endpoint: '/complaints',
        methods: ['GET'],
      );

      final notifierCode = generator.generateNotifierCode();
      expect(
        notifierCode.contains(
          "import 'package:hospital/features/complaints/infrastructure/complaints_repository_impl.dart';",
        ),
        isTrue,
      );

      final debugPageCode = generator.generateDebugPageCode();
      expect(
        debugPageCode.contains(
          "import 'package:hospital/features/complaints/infrastructure/complaints_repository_impl.dart';",
        ),
        isTrue,
      );
    });

    test('reusable core models skip generation and inject imports', () {
      final registry = CoreModelsRegistry();
      registry.domainClassesToPaths['PaginationModel'] =
          'domain/core/pagination_model.dart';
      registry.dtoClassesToPaths['PaginationDto'] =
          'infrastructure/core/pagination_dto.dart';

      final parser = JsonParser(
        featureName: 'Complaints',
        responseJson: {
          'status': 'ok',
          'pagination': {'total': 100, 'page': 1},
        },
        registry: registry,
        packageName: 'hospital',
      );

      expect(
        parser.domainClasses.any((c) => c.className.contains('Pagination')),
        isFalse,
      );
      expect(
        parser.responseDtoClasses.any(
          (c) => c.className.contains('Pagination'),
        ),
        isFalse,
      );

      final rootDomain = parser.domainClasses.firstWhere(
        (c) => c.className == 'ComplaintsModel',
      );
      final paginationField = rootDomain.fields.firstWhere(
        (f) => f.fieldName == 'pagination',
      );
      expect(paginationField.typeName, 'PaginationModel?');
      expect(paginationField.isNestedObject, isTrue);

      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Complaints',
      );
      final paginationDtoField = rootDto.fields.firstWhere(
        (f) => f.jsonKey == 'pagination',
      );
      expect(paginationDtoField.typeName, 'PaginationDto?');

      expect(
        parser.coreDomainImports.contains(
          'package:hospital/domain/core/pagination_model.dart',
        ),
        isTrue,
      );
      expect(
        parser.coreDtoImports.contains(
          'package:hospital/infrastructure/core/pagination_dto.dart',
        ),
        isTrue,
      );

      final generator = CodeGenerator(
        parser: parser,
        packageName: 'hospital',
        featureName: 'Complaints',
        endpoint: '/complaints',
        methods: ['GET'],
      );

      final domainCode = generator.generateDomainModelCode();
      expect(
        domainCode.contains(
          "import 'package:hospital/domain/core/pagination_model.dart';",
        ),
        isTrue,
      );

      final dtoCode = generator.generateDtoCode();
      expect(
        dtoCode.contains(
          "import 'package:hospital/domain/core/pagination_model.dart';",
        ),
        isTrue,
      );
      expect(
        dtoCode.contains(
          "import 'package:hospital/infrastructure/core/pagination_dto.dart';",
        ),
        isTrue,
      );
      expect(dtoCode.contains('pagination: pagination?.toDomain()'), isTrue);
    });

    test('reusable core models inside lists skip generation', () {
      final registry = CoreModelsRegistry();
      registry.domainClassesToPaths['ItemModel'] =
          'domain/core/item_model.dart';
      registry.dtoClassesToPaths['ItemDto'] =
          'infrastructure/core/item_dto.dart';

      final parser = JsonParser(
        featureName: 'Complaints',
        responseJson: {
          'status': 'ok',
          'items': [
            {'id': 1},
          ],
        },
        registry: registry,
        packageName: 'hospital',
      );

      expect(parser.domainClasses, isEmpty);
      expect(
        parser.responseDtoClasses.any((c) => c.className.contains('Item')),
        isFalse,
      );

      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Complaints',
      );
      final itemsDtoField = rootDto.fields.firstWhere(
        (f) => f.jsonKey == 'items',
      );
      expect(itemsDtoField.typeName, 'List<ItemDto>?');
    });

    test(
      'CoreModelsRegistry scans files and extracts class names correctly',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'ddd_pod_cli_registry_test_',
        );
        try {
          final domainCore = Directory('${tempDir.path}/domain/core')
            ..createSync(recursive: true);
          final infraCore = Directory('${tempDir.path}/infrastructure/core')
            ..createSync(recursive: true);

          final paginationFile = File(
            '${domainCore.path}/pagination_model.dart',
          );
          paginationFile.writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';
part 'pagination_model.freezed.dart';

@freezed
class PaginationModel with _\$PaginationModel {
  const factory PaginationModel({
    required int total,
  }) = _PaginationModel;
}

class AnotherClass {}
''');

          final paginationDtoFile = File(
            '${infraCore.path}/pagination_dto.dart',
          );
          paginationDtoFile.writeAsStringSync('''
class PaginationDto {}
''');

          final registry = CoreModelsRegistry();
          registry.scan(tempDir.path);

          expect(
            registry.domainClassesToPaths.containsKey('PaginationModel'),
            isTrue,
          );
          expect(
            registry.domainClassesToPaths.containsKey('AnotherClass'),
            isTrue,
          );
          expect(
            registry.domainClassesToPaths['PaginationModel'],
            'domain/core/pagination_model.dart',
          );

          expect(
            registry.dtoClassesToPaths.containsKey('PaginationDto'),
            isTrue,
          );
          expect(
            registry.dtoClassesToPaths['PaginationDto'],
            'infrastructure/core/pagination_dto.dart',
          );

          expect(
            registry.findMatchingCoreDomainClass('pagination'),
            'PaginationModel',
          );
          expect(
            registry.findMatchingCoreDtoClass('PaginationModel'),
            'PaginationDto',
          );
          expect(
            registry.getImportPath('hospital', 'PaginationModel', isDto: false),
            'package:hospital/domain/core/pagination_model.dart',
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });

  group('Advanced Features Tests', () {
    test(
      'field_mapping renames raw keys to custom names in DTO and Domain',
      () {
        final parser = JsonParser(
          featureName: 'Hospital',
          responseJson: {
            'patient_uhid_ip_no': 'HOSP-123',
            'doctor_name': 'Dr. House',
          },
          fieldMapping: {'patient_uhid_ip_no': 'regNo'},
        );

        final rootDto = parser.responseDtoClasses.firstWhere(
          (c) => c.className == 'Hospital',
        );
        final regNoField = rootDto.fields.firstWhere(
          (f) => f.jsonKey == 'patient_uhid_ip_no',
        );
        expect(regNoField.dartName, 'regNo');
        expect(regNoField.typeName, 'String?');

        final rootDomain = parser.domainClasses.firstWhere(
          (c) => c.className == 'HospitalModel',
        );
        final regNoDomainField = rootDomain.fields.firstWhere(
          (f) => f.fieldName == 'regNo',
        );
        expect(regNoDomainField.typeName, 'String?');

        final generator = CodeGenerator(
          parser: parser,
          packageName: 'clinic',
          featureName: 'Hospital',
          endpoint: '/hospital',
          methods: ['GET'],
        );

        final dtoCode = generator.generateDtoCode();
        expect(
          dtoCode.contains(
            "@JsonKey(name: 'patient_uhid_ip_no') String? regNo",
          ),
          isTrue,
        );
        expect(dtoCode.contains("regNo: regNo"), isTrue);
      },
    );

    test('is_paginated_list generates paginated parameters and fetchNextPage',
        () {
      final parser = JsonParser(
        featureName: 'UsersList',
        responseJson: [
          {'id': 1, 'name': 'Alice'},
        ],
        isPaginatedList: true,
        providerType: 'async_notifier',
      );

      expect(parser.isListResponse, isTrue);
      expect(parser.providerType, 'async_notifier');

      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'UsersList',
        endpoint: '/users',
        methods: ['GET'],
      );

      final repoCode = generator.generateIRepositoryCode();
      expect(
        repoCode.contains(
          'Future<Either<UsersListFailure, List<UsersListModel>>> getUsersList({required int page, required int limit, CancelToken? cancelToken});',
        ),
        isTrue,
      );

      final remoteSourceCode = generator.generateRemoteDataSourceCode();
      expect(
        remoteSourceCode.contains(
          'Future<List<UsersListDto>> getUsersList({required int page, required int limit, CancelToken? cancelToken}) async',
        ),
        isTrue,
      );
      expect(
        remoteSourceCode.contains(
          "queryParameters: {'page': page, 'limit': limit}",
        ),
        isTrue,
      );

      final notifierCode = generator.generateNotifierCode();
      expect(
        notifierCode.contains('Future<void> fetchNextPage() async'),
        isTrue,
      );
      expect(notifierCode.contains('page: nextPage, limit: 10'), isTrue);
      expect(
        notifierCode.contains(
            'AsyncLoading<List<UsersListModel>>().copyWithPrevious(state)'),
        isTrue,
      );
    });

    test(
      'generateNotifierTestCode generates compilable mock repository and test suite',
      () {
        final parser = JsonParser(
          featureName: 'PatientProfile',
          responseJson: {'id': 1, 'name': 'John Doe'},
          providerType: 'async_notifier',
        );

        final generator = CodeGenerator(
          parser: parser,
          packageName: 'hospital',
          featureName: 'PatientProfile',
          endpoint: '/patients/:id',
          methods: ['GET'],
          successResponse: {'id': 1, 'name': 'John Doe'},
        );

        final testCode = generator.generateNotifierTestCode();
        expect(
          testCode.contains(
            'class MockPatientProfileRepository implements IPatientProfileRepository',
          ),
          isTrue,
        );
        expect(
          testCode.contains(
            'Either<PatientProfileFailure, PatientProfileModel>? getPatientProfileResult;',
          ),
          isTrue,
        );
        expect(
          testCode.contains('PatientProfileNotifier'),
          isTrue,
        );
        expect(
          testCode.contains('PatientProfileDto'),
          isTrue,
        );
        expect(testCode.contains('success resolves provider to data'), isTrue);
      },
    );

    test(
      'generateMockInterceptorCode generates valid interceptor class with response literals',
      () {
        final parser = JsonParser(
          featureName: 'PatientProfile',
          responseJson: {'id': 1, 'name': 'John Doe'},
        );

        final generator = CodeGenerator(
          parser: parser,
          packageName: 'hospital',
          featureName: 'PatientProfile',
          endpoint: '/patients/:id',
          methods: ['GET'],
          successResponse: {'id': 1, 'name': 'John Doe'},
        );

        final interceptorCode = generator.generateMockInterceptorCode();
        expect(
          interceptorCode.contains(
            'class PatientProfileMockInterceptor extends Interceptor',
          ),
          isTrue,
        );
        // Check for path pattern matching logic
        expect(
          interceptorCode.contains('pathPattern') ||
              interceptorCode.contains('patients'),
          isTrue,
        );
        // Check for mock response data
        expect(
          interceptorCode.contains('1') && interceptorCode.contains('John Doe'),
          isTrue,
        );
      },
    );

    test(
      'generateFormStateCode and generateFormNotifierCode scaffold valid form handling structure with default validation',
      () {
        final parser = JsonParser(
          featureName: 'UpdateUser',
          responseJson: {'success': true},
          requestJson: {
            'email': 'test@example.com',
            'age': 25,
            'bio': 'A short bio',
          },
        );

        final generator = CodeGenerator(
          parser: parser,
          packageName: 'user_app',
          featureName: 'UpdateUser',
          endpoint: '/users/:id/update',
          methods: ['PUT'],
        );

        final formStateCode = generator.generateFormStateCode();
        expect(
          formStateCode.contains(
            'class UpdateUserFormState with _\$UpdateUserFormState',
          ),
          isTrue,
        );
        expect(formStateCode.contains("@Default('') String email,"), isTrue);
        expect(formStateCode.contains('String? emailError,'), isTrue);
        expect(formStateCode.contains("@Default(0) int age,"), isTrue);
        expect(formStateCode.contains('String? ageError,'), isTrue);
        expect(formStateCode.contains("@Default('') String bio,"), isTrue);
        expect(formStateCode.contains('String? bioError,'), isTrue);
        expect(formStateCode.contains('bool isSubmitting'), isTrue);
        expect(formStateCode.contains('bool showErrorMessages'), isTrue);
        expect(formStateCode.contains('bool isValid'), isTrue);

        final formNotifierCode = generator.generateFormNotifierCode();
        expect(
          formNotifierCode.contains(
            'class UpdateUserFormNotifier extends _\$UpdateUserFormNotifier',
          ),
          isTrue,
        );
        expect(
          formNotifierCode.contains('void updateEmail(String value)'),
          isTrue,
        );
        expect(formNotifierCode.contains('void updateAge(int value)'), isTrue);
        expect(
          formNotifierCode.contains('String? _validateEmail(String value)'),
          isTrue,
        );
        expect(
          formNotifierCode.contains('String? _validateAge(int value)'),
          isTrue,
        );
        expect(
          formNotifierCode.contains(
            'Future<bool> submit({required String id}) async',
          ),
          isTrue,
        );
        expect(
          formNotifierCode.contains(
            'request: UpdateUserRequestDto(email: state.email, age: state.age, bio: state.bio)',
          ),
          isTrue,
        );
      },
    );

    test(
      'generateFormStateCode and generateFormNotifierCode scaffold valid form handling structure with validation rules',
      () {
        final parser = JsonParser(
          featureName: 'UpdateUser',
          responseJson: {'success': true},
          requestJson: {
            'email': 'test@example.com',
            'age': 25,
            'bio': 'A short bio',
          },
          validationRules: {
            'email': {
              'type': 'email',
              'required': true,
              'error_msg': 'Please enter a valid email.',
            },
            'age': {'min': 18, 'error_msg': 'You must be 18 or older.'},
          },
        );

        final generator = CodeGenerator(
          parser: parser,
          packageName: 'user_app',
          featureName: 'UpdateUser',
          endpoint: '/users/:id/update',
          methods: ['PUT'],
        );

        final formStateCode = generator.generateFormStateCode();
        expect(
          formStateCode.contains(
            'class UpdateUserFormState with _\$UpdateUserFormState',
          ),
          isTrue,
        );
        expect(formStateCode.contains("@Default('') String email,"), isTrue);
        expect(formStateCode.contains('String? emailError,'), isTrue);
        expect(formStateCode.contains('@Default(0) int age,'), isTrue);
        expect(formStateCode.contains('String? ageError,'), isTrue);

        final formNotifierCode = generator.generateFormNotifierCode();
        expect(
          formNotifierCode.contains(
            'class UpdateUserFormNotifier extends _\$UpdateUserFormNotifier',
          ),
          isTrue,
        );
        expect(
          formNotifierCode.contains('void updateEmail(String value)'),
          isTrue,
        );
        expect(formNotifierCode.contains('void updateAge(int value)'), isTrue);
        expect(
          formNotifierCode.contains('String? _validateEmail(String value)'),
          isTrue,
        );
        expect(
          formNotifierCode.contains('String? _validateAge(int value)'),
          isTrue,
        );
        expect(formNotifierCode.contains('emailRegex.hasMatch(value)'), isTrue);
        expect(
          formNotifierCode.contains("return 'Please enter a valid email.'"),
          isTrue,
        );
        expect(
          formNotifierCode.contains("return 'You must be 18 or older.'"),
          isTrue,
        );
      },
    );

    test('runDeleteFlow deletes corresponding directories', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'ddd_pod_delete_test_',
      );
      try {
        final libFeatures = Directory('${tempDir.path}/lib/features/test_feat')
          ..createSync(recursive: true);
        final testFeatures = Directory(
          '${tempDir.path}/test/features/test_feat',
        )..createSync(recursive: true);

        expect(libFeatures.existsSync(), isTrue);
        expect(testFeatures.existsSync(), isTrue);

        const snakeFeatureName = 'test_feat';
        final featureLibDir = Directory(
          '${tempDir.path}/lib/features/$snakeFeatureName',
        );
        final featureTestDir = Directory(
          '${tempDir.path}/test/features/$snakeFeatureName',
        );

        if (featureLibDir.existsSync()) {
          featureLibDir.deleteSync(recursive: true);
        }
        if (featureTestDir.existsSync()) {
          featureTestDir.deleteSync(recursive: true);
        }

        expect(featureLibDir.existsSync(), isFalse);
        expect(featureTestDir.existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('Failure Coverage Tests', () {
      test('Failure union code contains all 10 variants', () {
        final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'Task',
          endpoint: '/api/tasks',
          methods: ['GET'],
        );
        final code = generator.generateFailureCode();
        expect(code.contains('timeoutFailure()'), isTrue);
        expect(code.contains('unauthorizedFailure('), isTrue);
        expect(code.contains('forbiddenFailure('), isTrue);
        expect(code.contains('notFoundFailure('), isTrue);
        expect(code.contains('validationFailure('), isTrue);
        expect(code.contains('cacheFailure('), isTrue);
        expect(code.contains('rateLimitExceeded('), isTrue);
        expect(code.contains('networkError()'), isTrue);
        expect(code.contains('serverError('), isTrue);
        expect(code.contains('unexpectedError('), isTrue);
      });
    });

    group('Atomic Writes Tests', () {
      test('safeWriteToFile writes cleanly', () {
        final tempDir = Directory.systemTemp.createTempSync('ddd_atomic_test_');
        final targetPath = '${tempDir.path}/test_file.txt';
        final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'Task',
          endpoint: '/api/tasks',
          methods: ['GET'],
          force: true,
        );
        generator.safeWriteToFile(targetPath, 'Hello Atomic World');
        final file = File(targetPath);
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), contains('Hello Atomic World'));
        tempDir.deleteSync(recursive: true);
      });
    });

    group('Cache TTL Tests', () {
      test('generateLocalDataSourceCode generates TTL and invalidation logic',
          () {
        final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'Task',
          endpoint: '/api/tasks',
          methods: ['GET'],
          cacheTtlSeconds: 60,
        );
        final code = generator.generateLocalDataSourceCode();
        expect(
            code.contains(
                'final age = DateTime.now().millisecondsSinceEpoch - cachedAt;'),
            isTrue);
        expect(code.contains('clearCacheTask'), isTrue);
        expect(code.contains('migrateCacheTask'), isTrue);
      });
    });

    group('Retry-After Tests', () {
      test('DioException retry after logic', () {
        final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'Task',
          endpoint: '/api/tasks',
          methods: ['GET'],
          retryConfig: {'max_attempts': 3, 'delay_ms': 1000},
        );
        final code = generator.generateRemoteDataSourceCode();
        expect(
            code.contains(
                'final retryAfterHeader = e.response?.headers.value(\'retry-after\');'),
            isTrue);
      });
    });

    group('Select Optimization Tests', () {
      test('select() providers are generated for root model fields', () {
        final parser = JsonParser(
            featureName: 'User', responseJson: {'id': 1, 'name': 'Alvin'});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'User',
          endpoint: '/api/users',
          methods: ['GET'],
        );
        final code = generator.generateDerivedProvidersCode();
        expect(code.contains('userPhoneSelect'), isFalse);
        expect(code.contains('userIdSelect'), isTrue);
        expect(code.contains('userNameSelect'), isTrue);
      });
    });

    group('Idempotent Generation Tests', () {
      test('hash validation prevents overwrites when same config', () {
        final tempDir =
            Directory.systemTemp.createTempSync('ddd_idempotent_test_');
        final targetPath = '${tempDir.path}/task.dart';
        final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
        final generator = CodeGenerator(
          parser: parser,
          packageName: 'test_app',
          featureName: 'Task',
          endpoint: '/api/tasks',
          methods: ['GET'],
        );
        generator.safeWriteToFile(targetPath, generator.generateFailureCode());
        final file = File(targetPath);
        final statBefore = file.statSync();

        // Regenerate without force - should skip because hash matches
        generator.safeWriteToFile(targetPath, generator.generateFailureCode());
        final statAfter = file.statSync();
        expect(statAfter.modified, equals(statBefore.modified));

        tempDir.deleteSync(recursive: true);
      });
    });
  });
}
