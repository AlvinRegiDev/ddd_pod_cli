import 'package:test/test.dart';

import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/generator/code_generator.dart';

void main() {
  group('CodeGenerator regression tests', () {
    test('every generated file contains GENERATED CODE header', () {
      final parser = JsonParser(
        featureName: 'Order',
        responseJson: {'id': 1, 'status': 'pending'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'shop',
        featureName: 'Order',
        endpoint: '/orders/:id',
        methods: ['GET'],
      );

      final files = [
        generator.generateStateCode(),
        generator.generateNotifierCode(),
        generator.generateFailureCode(),
        generator.generateIRepositoryCode(),
        generator.generateDtoCode(),
        generator.generateRemoteDataSourceCode(),
        generator.generateRepositoryImplCode(),
        generator.generateMockInterceptorCode(),
        generator.generateDomainModelCode(),
      ];

      for (final code in files) {
        expect(
          code.contains('GENERATED CODE'),
          isTrue,
          reason: 'Expected GENERATED CODE header in:\n$code',
        );
      }
    });

    test('mutation methods use right(unit) not right(null)', () {
      final parser = JsonParser(
        featureName: 'Task',
        responseJson: {'id': 1},
        requestJson: {'name': 'New Task'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'Task',
        endpoint: '/tasks',
        methods: ['GET', 'POST'],
      );

      final repoImplCode = generator.generateRepositoryImplCode();
      expect(repoImplCode.contains('return right(unit)'), isTrue);
      expect(repoImplCode.contains('return right(null)'), isFalse);
    });

    test('providers barrel exports notifier and state files', () {
      final parser = JsonParser(
        featureName: 'Product',
        responseJson: {'id': 1},
        requestJson: {'name': 'Widget'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'store',
        featureName: 'Product',
        endpoint: '/products',
        methods: ['GET', 'POST'],
      );

      final barrelCode = generator.generateProvidersBarrelCode();
      expect(barrelCode.contains("export 'product_notifier.dart'"), isTrue);
      expect(barrelCode.contains("export 'product_state.dart'"), isTrue);
      expect(
          barrelCode.contains("export 'product_form_notifier.dart'"), isTrue);
      expect(barrelCode.contains("export 'product_form_state.dart'"), isTrue);
    });

    test('providers barrel skips form exports when no request body', () {
      final parser = JsonParser(
        featureName: 'Order',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'shop',
        featureName: 'Order',
        endpoint: '/orders',
        methods: ['GET'],
      );

      final barrelCode = generator.generateProvidersBarrelCode();
      expect(barrelCode.contains('form_notifier'), isFalse);
      expect(barrelCode.contains('form_state'), isFalse);
    });

    test('repository impl imports fpdart and uses Either', () {
      final parser = JsonParser(
        featureName: 'Invoice',
        responseJson: {'id': 1, 'amount': 99.9},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'billing',
        featureName: 'Invoice',
        endpoint: '/invoices',
        methods: ['GET'],
      );

      final implCode = generator.generateRepositoryImplCode();
      expect(implCode.contains("import 'package:fpdart/fpdart.dart'"), isTrue);
      expect(implCode.contains('Either<'), isTrue);
    });

    test('generateFailureCode uses three standard factory constructors', () {
      final parser = JsonParser(
        featureName: 'Payment',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'wallet',
        featureName: 'Payment',
        endpoint: '/payments',
        methods: ['GET'],
      );

      final failureCode = generator.generateFailureCode();
      expect(failureCode.contains('serverError'), isTrue);
      expect(failureCode.contains('networkError'), isTrue);
      expect(failureCode.contains('unexpectedError'), isTrue);
    });

    test('addTearDown(container.dispose) is in generated notifier test', () {
      final parser = JsonParser(
        featureName: 'Cart',
        responseJson: {'id': 1},
        providerType: 'notifier',
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'shop',
        featureName: 'Cart',
        endpoint: '/cart',
        methods: ['GET'],
      );

      final testCode = generator.generateNotifierTestCode();
      expect(testCode.contains('addTearDown(container.dispose)'), isTrue);
    });

    test('domain model code contains enumHint comment when field observed', () {
      final parser = JsonParser(
        featureName: 'Article',
        responseJson: {
          'items': [
            {'status': 'draft'},
            {'status': 'published'},
            {'status': 'archived'},
          ],
        },
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'blog',
        featureName: 'Article',
        endpoint: '/articles',
        methods: ['GET'],
      );

      final domainCode = generator.generateDomainModelCode();
      // The domain model code may contain Observed values comment for status
      // (either as a hint or within nested models)
      expect(domainCode, isNotEmpty);
      expect(domainCode.contains('// Observed values:'), isTrue);
    });

    test('path parameters are correctly interpolated in endpoint', () {
      final parser = JsonParser(
        featureName: 'Comment',
        responseJson: {'id': 1, 'body': 'text'},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'blog',
        featureName: 'Comment',
        endpoint: '/posts/:post_id/comments/{commentId}',
        methods: ['GET'],
      );

      final url = generator.getInterpolatedEndpoint();
      expect(url, contains(r'$postId'));
      expect(url, contains(r'$commentId'));
    });

    test('stream provider and notifier return types and codes', () {
      final parser = JsonParser(
        featureName: 'Feed',
        responseJson: {'id': 1, 'text': 'post'},
        providerType: 'stream_provider',
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'Feed',
        endpoint: '/feed',
        methods: ['GET'],
        streamConfig: {'type': 'websocket'},
      );

      final remoteCode = generator.generateRemoteDataSourceCode();
      expect(remoteCode.contains('Stream<FeedDto>'), isTrue);
      expect(remoteCode.contains('WebSocket.connect'), isTrue);

      final repoCode = generator.generateRepositoryImplCode();
      expect(
          repoCode.contains('Stream<Either<FeedFailure, FeedModel>>'), isTrue);

      final notifierCode = generator.generateNotifierCode();
      expect(notifierCode.contains('Stream<FeedModel> feed('), isTrue);
    });

    test('retry wrapper method generated when retry_config is set', () {
      final parser = JsonParser(
        featureName: 'Job',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'Job',
        endpoint: '/jobs',
        methods: ['GET'],
        retryConfig: {'max_attempts': 5, 'delay_ms': 500},
      );

      final remoteCode = generator.generateRemoteDataSourceCode();
      expect(remoteCode.contains('Future<T> _retry<T>'), isTrue);
      expect(remoteCode.contains('final maxAttempts = 5;'), isTrue);
    });

    test('429 rateLimitExceeded is generated in repository implementation', () {
      final parser = JsonParser(
        featureName: 'Message',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'Message',
        endpoint: '/messages',
        methods: ['GET'],
      );

      final repoCode = generator.generateRepositoryImplCode();
      expect(repoCode.contains('Failure.rateLimitExceeded'), isTrue);
    });

    test('offline mutation queue is generated when config is active', () {
      final parser = JsonParser(
        featureName: 'Task',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'app',
        featureName: 'Task',
        endpoint: '/tasks',
        methods: ['GET', 'POST'],
        offlineMutationQueue: true,
      );

      final queueCode = generator.generateOfflineQueueCode();
      expect(queueCode.contains('class TaskOfflineQueue'), isTrue);
    });

    test(
        'generateTestOverridesCode generates valid template without escaped variables',
        () {
      final parser = JsonParser(
        featureName: 'Product',
        responseJson: {'id': 1},
      );
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'shop',
        featureName: 'Product',
        endpoint: '/products',
        methods: ['GET'],
      );

      final testOverridesCode = generator.generateTestOverridesCode();
      expect(testOverridesCode.contains(r'$domainImport'), isFalse);
      expect(testOverridesCode.contains(r'$stateType'), isFalse);
      expect(testOverridesCode.contains(r'$packageName'), isFalse);
      expect(testOverridesCode.contains(r'$_snake'), isFalse);
      expect(testOverridesCode.contains(r'$_pascal'), isFalse);
      expect(testOverridesCode.contains(r'$_camel'), isFalse);
      expect(testOverridesCode.contains('class ProductTestOverrides'), isTrue);
      expect(testOverridesCode.contains('AsyncValue<ProductModel> mockValue'),
          isTrue);
      expect(testOverridesCode.contains('IProductRepository mockRepository'),
          isTrue);
    });
  });
}
