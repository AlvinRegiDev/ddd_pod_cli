import 'package:ddd_pod_cli/ddd_pod_cli.dart';

void main() {
  // Define a sample feature configuration JSON
  final rawConfig = {
    'feature_name': 'Todo',
    'api_path': '/api/todos',
    'methods': ['GET', 'POST'],
    'provider_type': 'async_notifier',
    'get_response_dto': {
      'id': 1,
      'title': 'Scaffold DDD Architecture',
      'completed': false,
    },
    'post_request_body': {
      'title': 'Scaffold DDD Architecture',
    }
  };

  // Parse the configuration programmatically
  final config = FeatureConfig.fromJson(rawConfig);
  print('Feature to generate: ${config.featureName}');
  print('Target API Endpoint: ${config.apiPath}');
  print('Provider Generation Type: ${config.providerTypeString}');
}
