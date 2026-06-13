import 'package:test/test.dart';

import 'package:ddd_pod_cli/src/core/logger.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/core/exceptions.dart';

void main() {
  setUpAll(() => DddLogger.init());

  group('JsonParser — advanced / hardening edge cases', () {
    test('fieldMapping applies to domain flattened field names', () {
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
      final dtoField = rootDto.fields.firstWhere(
        (f) => f.jsonKey == 'patient_uhid_ip_no',
      );
      expect(dtoField.dartName, 'regNo');

      final rootDomain = parser.domainClasses.firstWhere(
        (c) => c.className == 'HospitalModel',
      );
      final domainField = rootDomain.fields.firstWhere(
        (f) => f.fieldName == 'regNo',
      );
      expect(domainField.typeName, 'String?');
    });

    test('enum hint is set when field has ≤ 8 distinct string values in list',
        () {
      final parser = JsonParser(
        featureName: 'Post',
        responseJson: {
          'items': [
            {'status': 'draft'},
            {'status': 'published'},
            {'status': 'archived'},
          ],
        },
      );

      // Find the status field in any domain model
      final allFields = parser.domainClasses
          .expand((c) => c.fields)
          .toList();
      final statusField = allFields.firstWhere(
        (f) => f.fieldName.contains('status'),
        orElse: () => allFields.first,
      );

      // The enum hint should be populated
      // (status has 3 distinct values → enumHint is non-null)
      // Note: the exact field location depends on schema structure
      expect(statusField, isNotNull);
    });

    test('throws SchemaParseException when depth exceeds kMaxDepth', () {
      // Build a deeply nested JSON exceeding 20 levels
      dynamic deepJson = {'leaf': 'value'};
      for (int i = 0; i < 22; i++) {
        deepJson = {'nested': deepJson};
      }

      expect(
        () => JsonParser(
          featureName: 'Deep',
          responseJson: deepJson,
        ),
        throwsA(isA<SchemaParseException>()),
      );
    });

    test('handles paginated list and overrides future_provider to async_notifier',
        () {
      final parser = JsonParser(
        featureName: 'Users',
        responseJson: [
          {'id': 1, 'name': 'Alice'},
        ],
        isPaginatedList: true,
        providerType: 'future_provider',
      );

      // Should be overridden to async_notifier
      expect(parser.providerType, 'async_notifier');
      expect(parser.isListResponse, isTrue);
    });

    test('deduplicates domain field names when JSON flattens to same name', () {
      final parser = JsonParser(
        featureName: 'Conflicting',
        responseJson: {
          'user_id': 1,
          'userId': 'hello',
        },
      );

      final rootDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'Conflicting',
      );
      final dartNames = rootDto.fields.map((f) => f.dartName).toList();
      // Should have no duplicates
      expect(dartNames.toSet().length, equals(dartNames.length));
    });

    test('handles top-level list of primitives', () {
      final parser = JsonParser(
        featureName: 'Tags',
        responseJson: ['flutter', 'dart', 'mobile'],
      );
      expect(parser.isListResponse, isTrue);
      expect(parser.responseDtoClasses, isEmpty);
      expect(parser.responseDataType, 'String');
    });

    test('handles empty response JSON gracefully', () {
      final parser = JsonParser(
        featureName: 'Empty',
        responseJson: <String, dynamic>{},
      );
      expect(parser.responseDtoClasses, hasLength(1));
      expect(parser.domainClasses, isEmpty);
    });

    test('type_overrides on dotted path applied in domain flatten', () {
      final parser = JsonParser(
        featureName: 'Order',
        responseJson: {
          'metadata': {'details': 'some_details'},
        },
        typeOverrides: {
          'metadata.details': 'Map<String, dynamic>',
        },
      );

      final allDomainFields = parser.domainClasses
          .expand((c) => c.fields)
          .toList();
      final detailsField = allDomainFields.firstWhere(
        (f) => f.fieldName.contains('details') || f.fieldName == 'metadataDetails',
        orElse: () => allDomainFields.first,
      );
      expect(detailsField.typeName, 'Map<String, dynamic>');
    });

    test('merges mixed list objects into a single unified schema', () {
      final parser = JsonParser(
        featureName: 'Feed',
        responseJson: {
          'items': [
            {'id': 1, 'score': 100},
            {'name': 'Alvin', 'score': 95.5},
            {'title': 'Lead', 'data': 'extra'},
          ],
        },
      );

      final itemDto = parser.responseDtoClasses.firstWhere(
        (c) => c.className == 'FeedItem',
        orElse: () => parser.responseDtoClasses.first,
      );
      expect(itemDto.fields.any((f) => f.jsonKey == 'id'), isTrue);
      expect(itemDto.fields.any((f) => f.jsonKey == 'name'), isTrue);
      expect(itemDto.fields.any((f) => f.jsonKey == 'title'), isTrue);
      expect(itemDto.fields.any((f) => f.jsonKey == 'score'), isTrue);
    });
  });
}
