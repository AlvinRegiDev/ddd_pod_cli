import 'package:test/test.dart';
import 'package:ddd_pod_cli/src/parser/json_parser.dart';
import 'package:ddd_pod_cli/src/generator/code_generator.dart';

void main() {
  group('Observer Code Generation Tests', () {
    test(
        'generateAnalyticsObserverCode generates Firebase/Mixpanel events observer',
        () {
      final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'test_app',
        featureName: 'Task',
        endpoint: '/api/tasks',
        methods: ['GET'],
      );

      final code = generator.generateAnalyticsObserverCode();
      expect(
          code.contains(
              'class AnalyticsProviderObserver extends ProviderObserver'),
          isTrue);
      expect(
          code.contains(
              'final eventName = \'provider_update_\${_formatName(name)}\';'),
          isTrue);
      expect(code.contains('void _trackEvent('), isTrue);
    });

    test('generateDebugObserverCode generates kDebugMode JSON observer', () {
      final parser = JsonParser(featureName: 'Task', responseJson: {'id': 1});
      final generator = CodeGenerator(
        parser: parser,
        packageName: 'test_app',
        featureName: 'Task',
        endpoint: '/api/tasks',
        methods: ['GET'],
      );

      final code = generator.generateDebugObserverCode();
      expect(
          code.contains('class DebugProviderObserver extends ProviderObserver'),
          isTrue);
      expect(code.contains('if (kDebugMode)'), isTrue);
      expect(code.contains('debugPrint(\'┌── Riverpod Debug Event'), isTrue);
    });
  });
}
