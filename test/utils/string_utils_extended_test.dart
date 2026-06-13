import 'package:test/test.dart';

import 'package:ddd_pod_cli/src/utils/string_utils.dart';

void main() {
  group('StringUtils.snakeToCamel', () {
    test('converts snake_case to camelCase', () {
      expect(StringUtils.snakeToCamel('verified_at'), 'verifiedAt');
      expect(StringUtils.snakeToCamel('avatar_url'), 'avatarUrl');
      expect(StringUtils.snakeToCamel('is_active'), 'isActive');
    });

    test('normalises PascalCase to camelCase', () {
      expect(StringUtils.snakeToCamel('UserProfile'), 'userProfile');
      expect(StringUtils.snakeToCamel('MyField'), 'myField');
    });

    test('handles single word', () {
      expect(StringUtils.snakeToCamel('name'), 'name');
    });

    test('handles empty string', () {
      expect(StringUtils.snakeToCamel(''), '');
    });

    test('handles multiple consecutive underscores', () {
      expect(StringUtils.snakeToCamel('a__b'), 'aB');
    });
  });

  group('StringUtils.toPascalCase', () {
    test('converts snake_case to PascalCase', () {
      expect(StringUtils.toPascalCase('verified_at'), 'VerifiedAt');
      expect(StringUtils.toPascalCase('avatar_url'), 'AvatarUrl');
    });

    test('preserves already PascalCase', () {
      expect(StringUtils.toPascalCase('UserProfile'), 'UserProfile');
    });

    test('handles empty string', () {
      expect(StringUtils.toPascalCase(''), '');
    });
  });

  group('StringUtils.toSnakeCase', () {
    test('converts PascalCase to snake_case', () {
      expect(StringUtils.toSnakeCase('UserProfile'), 'user_profile');
    });

    test('converts camelCase to snake_case', () {
      expect(StringUtils.toSnakeCase('verifiedAt'), 'verified_at');
      expect(StringUtils.toSnakeCase('avatarUrl'), 'avatar_url');
    });

    test('handles already snake_case', () {
      expect(StringUtils.toSnakeCase('user_profile'), 'user_profile');
    });

    test('handles single word', () {
      expect(StringUtils.toSnakeCase('User'), 'user');
    });
  });

  group('StringUtils.singularize', () {
    test('handles regular plurals', () {
      expect(StringUtils.singularize('layers'), 'layer');
      expect(StringUtils.singularize('users'), 'user');
      expect(StringUtils.singularize('items'), 'item');
    });

    test('handles -ies → -y', () {
      expect(StringUtils.singularize('categories'), 'category');
      expect(StringUtils.singularize('countries'), 'country');
    });

    test('handles -sses, -ches, -xes', () {
      expect(StringUtils.singularize('classes'), 'class');
      expect(StringUtils.singularize('matches'), 'match');
      expect(StringUtils.singularize('boxes'), 'box');
    });

    test('handles -ves', () {
      expect(StringUtils.singularize('leaves'), 'leaf');
    });

    test('handles invariants', () {
      expect(StringUtils.singularize('status'), 'status');
      expect(StringUtils.singularize('settings'), 'settings');
      expect(StringUtils.singularize('series'), 'series');
    });

    test('handles irregular forms', () {
      expect(StringUtils.singularize('indices'), 'index');
      expect(StringUtils.singularize('matrices'), 'matrix');
      expect(StringUtils.singularize('aliases'), 'alias');
      expect(StringUtils.singularize('children'), 'child');
    });

    test('handles active_projects (snake prefix)', () {
      expect(StringUtils.singularize('active_projects'), 'active_project');
    });
  });

  group('StringUtils.sanitizeIdentifier', () {
    test('replaces spaces with underscores', () {
      expect(StringUtils.sanitizeIdentifier('hello world'), 'hello_world');
    });

    test('removes leading and trailing underscores', () {
      expect(StringUtils.sanitizeIdentifier('_field_'), 'field');
    });

    test('handles special characters', () {
      expect(StringUtils.sanitizeIdentifier('my-field.name'), 'my_field_name');
    });

    test('prefixes leading digit', () {
      expect(StringUtils.sanitizeIdentifier('2fa'), 'value2fa');
    });

    test('returns unnamedField for empty-after-cleaning string', () {
      expect(StringUtils.sanitizeIdentifier('!@#'), 'unnamedField');
    });

    test('does not modify valid identifiers', () {
      expect(StringUtils.sanitizeIdentifier('myField'), 'myField');
      expect(StringUtils.sanitizeIdentifier('_private'), 'private');
    });
  });
}
