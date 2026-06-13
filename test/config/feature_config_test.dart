import 'package:test/test.dart';

import 'package:ddd_pod_cli/src/config/feature_config.dart';
import 'package:ddd_pod_cli/src/core/exceptions.dart';

void main() {
  group('FeatureConfig.fromJson', () {
    test('parses a valid minimal config', () {
      final config = FeatureConfig.fromJson({
        'feature_name': 'UserProfile',
        'api_path': '/api/v1/users',
        'methods': ['GET'],
        'get_response_dto': {'id': 1, 'name': 'Alice'},
      });

      expect(config.featureName, 'UserProfile');
      expect(config.apiPath, '/api/v1/users');
      expect(config.methods, [HttpMethod.get]);
      expect(config.providerType, ProviderType.notifier);
    });

    test('throws ConfigException on missing feature_name', () {
      expect(
        () => FeatureConfig.fromJson({'api_path': '/api/test', 'methods': ['GET']}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on empty feature_name', () {
      expect(
        () => FeatureConfig.fromJson({'feature_name': '   ', 'methods': ['GET']}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on feature_name starting with digit', () {
      expect(
        () => FeatureConfig.fromJson({'feature_name': '1User', 'methods': ['GET']}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on feature_name with spaces', () {
      expect(
        () => FeatureConfig.fromJson(
            {'feature_name': 'User Profile', 'methods': ['GET']}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on empty methods array', () {
      expect(
        () => FeatureConfig.fromJson(
            {'feature_name': 'Item', 'methods': <dynamic>[]}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException on unknown HTTP method', () {
      expect(
        () => FeatureConfig.fromJson(
            {'feature_name': 'Item', 'methods': ['SPIDER']}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('defaults methods to GET when not provided', () {
      final config = FeatureConfig.fromJson({'feature_name': 'Item'});
      expect(config.methods, [HttpMethod.get]);
    });

    test('throws ConfigException on unknown provider_type', () {
      expect(
        () => FeatureConfig.fromJson({
          'feature_name': 'Item',
          'methods': ['GET'],
          'provider_type': 'mega_provider',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('parses all known provider_type values', () {
      expect(
        FeatureConfig.fromJson({
          'feature_name': 'A',
          'provider_type': 'notifier',
        }).providerType,
        ProviderType.notifier,
      );
      expect(
        FeatureConfig.fromJson({
          'feature_name': 'A',
          'provider_type': 'async_notifier',
        }).providerType,
        ProviderType.asyncNotifier,
      );
      expect(
        FeatureConfig.fromJson({
          'feature_name': 'A',
          'provider_type': 'future_provider',
        }).providerType,
        ProviderType.futureProvider,
      );
    });

    test('parses type_overrides map', () {
      final config = FeatureConfig.fromJson({
        'feature_name': 'Order',
        'type_overrides': {'created_at': 'DateTime', 'id': 'String'},
      });
      expect(config.typeOverrides['created_at'], 'DateTime');
      expect(config.typeOverrides['id'], 'String');
    });

    test('parses field_mapping map', () {
      final config = FeatureConfig.fromJson({
        'feature_name': 'Order',
        'field_mapping': {'patient_uhid': 'regNo'},
      });
      expect(config.fieldMapping['patient_uhid'], 'regNo');
    });

    test('parses is_paginated_list and offline_cache flags', () {
      final config = FeatureConfig.fromJson({
        'feature_name': 'Items',
        'is_paginated_list': true,
        'offline_cache': true,
      });
      expect(config.isPaginatedList, isTrue);
      expect(config.offlineCache, isTrue);
    });

    test('snakeFeatureName converts PascalCase correctly', () {
      final config = FeatureConfig.fromJson({'feature_name': 'UserProfile'});
      expect(config.snakeFeatureName, 'user_profile');
    });

    test('providerTypeString returns correct snake_case string', () {
      final config = FeatureConfig.fromJson({
        'feature_name': 'A',
        'provider_type': 'async_notifier',
      });
      expect(config.providerTypeString, 'async_notifier');
    });

    test('HttpMethod.value returns uppercase method string', () {
      expect(HttpMethod.get.value, 'GET');
      expect(HttpMethod.delete.value, 'DELETE');
    });
  });
}
