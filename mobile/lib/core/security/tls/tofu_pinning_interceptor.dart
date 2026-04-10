import 'package:dio/dio.dart';

/// Abstraction over "what is the SPKI-SHA256 of the peer cert for this
/// host right now". The production implementation hooks into a custom
/// IOHttpClientAdapter (Task 19); tests inject a fake.
abstract class FingerprintResolver {
  Future<String?> fingerprintFor(String host);
}

class TlsPinMismatchException implements Exception {
  TlsPinMismatchException({
    required this.host,
    required this.expected,
    required this.actual,
  });
  final String host;
  final String expected;
  final String actual;
  @override
  String toString() =>
      'TlsPinMismatchException(host=$host expected=$expected actual=$actual)';
}

class TofuPromptRequiredException implements Exception {
  TofuPromptRequiredException({required this.host, required this.fingerprint});
  final String host;
  final String fingerprint;
}

/// Dio interceptor that enforces SPKI-pin-on-use. Expects `fingerprintFor`
/// to be configured against the same HttpClient that Dio uses, so the
/// post-handshake cert can be retrieved.
class TofuPinningInterceptor extends Interceptor {
  TofuPinningInterceptor({
    required this.resolver,
    required this.expectedFor,
  });

  final FingerprintResolver resolver;
  final Future<String?> Function(String host) expectedFor;

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final host = Uri.parse(response.requestOptions.baseUrl).host;
    final actual = await resolver.fingerprintFor(host);
    if (actual == null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TofuPromptRequiredException(host: host, fingerprint: ''),
        ),
      );
      return;
    }
    final expected = await expectedFor(host);
    if (expected == null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TofuPromptRequiredException(host: host, fingerprint: actual),
        ),
      );
      return;
    }
    if (expected != actual) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: TlsPinMismatchException(
            host: host,
            expected: expected,
            actual: actual,
          ),
        ),
      );
      return;
    }
    handler.next(response);
  }
}
