import 'package:http/http.dart' as http;

/// Thin HTTP wrapper reserved for a future project-storage API.
/// Unused in v1 except as a dependency of a future [HttpFaceSyncClient].
class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = ''})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _client.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: body,
    );
  }

  void dispose() => _client.close();
}
