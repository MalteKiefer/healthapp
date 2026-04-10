import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/tls/tofu_pinning_interceptor.dart';

class _FakeFingerprintResolver implements FingerprintResolver {
  _FakeFingerprintResolver(this.fingerprint);
  final String fingerprint;
  String? lastHost;
  @override
  Future<String?> fingerprintFor(String host) async {
    lastHost = host;
    return fingerprint;
  }
}

class _StubStore {
  String? stored;
  Future<String?> expected(String host) async => stored;
  Future<void> save(String host, String fp) async => stored = fp;
}

void main() {
  group('TofuPinningInterceptor', () {
    test('mismatch throws TlsPinMismatchException', () async {
      final store = _StubStore()..stored = 'old-pin';
      final resolver = _FakeFingerprintResolver('new-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final handler = _CapturingErrorHandler();
      final options = RequestOptions(path: '/x');
      options.baseUrl = 'https://h.example';

      interceptor.onRequest(options, _PassThroughRequestHandler());
      final response = Response(requestOptions: options, statusCode: 200);

      await interceptor.onResponse(
        response,
        _CapturingResponseHandler(handler),
      );
      expect(handler.error, isA<DioException>());
      expect(
        (handler.error as DioException).error,
        isA<TlsPinMismatchException>(),
      );
    });

    test('match passes through', () async {
      final store = _StubStore()..stored = 'same-pin';
      final resolver = _FakeFingerprintResolver('same-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final options = RequestOptions(path: '/x')
        ..baseUrl = 'https://h.example';
      final handler = _CapturingResponseHandler(_CapturingErrorHandler());
      final response = Response(requestOptions: options, statusCode: 200);
      await interceptor.onResponse(response, handler);
      expect(handler.passedThrough, isTrue);
    });

    test('no stored pin triggers TofuPromptRequiredException', () async {
      final store = _StubStore();
      final resolver = _FakeFingerprintResolver('new-pin');
      final interceptor = TofuPinningInterceptor(
        resolver: resolver,
        expectedFor: store.expected,
      );

      final options = RequestOptions(path: '/x')
        ..baseUrl = 'https://h.example';
      final errH = _CapturingErrorHandler();
      final response = Response(requestOptions: options, statusCode: 200);
      await interceptor.onResponse(response, _CapturingResponseHandler(errH));
      expect(errH.error, isA<DioException>());
      expect(
        (errH.error as DioException).error,
        isA<TofuPromptRequiredException>(),
      );
    });
  });
}

class _PassThroughRequestHandler extends RequestInterceptorHandler {}

class _CapturingResponseHandler extends ResponseInterceptorHandler {
  _CapturingResponseHandler(this.errHandler);
  final _CapturingErrorHandler errHandler;
  bool passedThrough = false;
  @override
  void next(Response response) => passedThrough = true;
  @override
  void reject(DioException error, [bool callFollowingErrorInterceptor = false]) {
    errHandler.error = error;
  }
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  Object? error;
  @override
  void next(DioException err) => error = err;
}
