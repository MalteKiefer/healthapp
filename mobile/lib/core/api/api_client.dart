import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:healthapp/core/security/tls/tofu_pinning_interceptor.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'API error $statusCode: $message';
}

class ApiClient {
  late final Dio _dio;
  CookieJar? _cookieJar;
  TofuPinningInterceptor? _tofuInterceptor;
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    // Cookie jar and TOFU interceptor are installed by the security layer
    // after the vault is unlocked — see main.dart bootstrap.
  }

  /// Installs a vault-backed (or test) cookie jar and rebuilds the
  /// interceptor chain. Safe to call multiple times.
  void setCookieJar(CookieJar jar) {
    _cookieJar = jar;
    _rebuildInterceptors();
  }

  /// Installs the TOFU pinning interceptor and rebuilds the interceptor
  /// chain. Safe to call multiple times.
  void setTofuInterceptor(TofuPinningInterceptor interceptor) {
    _tofuInterceptor = interceptor;
    _rebuildInterceptors();
  }

  void _rebuildInterceptors() {
    _dio.interceptors.clear();
    if (_cookieJar != null) {
      _dio.interceptors.add(CookieManager(_cookieJar!));
    }
    if (_tofuInterceptor != null) {
      _dio.interceptors.add(_tofuInterceptor!);
    }
    // Retry interceptor must come after TOFU pinning so that pinned cookies
    // and security checks are already applied to each retried request.
    _dio.interceptors.add(_RetryInterceptor());
  }

  List<String> _resolveBaseUrlCandidates(String cleaned) {
    final isLocal =
        cleaned.contains('localhost') || cleaned.contains('10.0.2.2');
    const bool allowInsecureLocal = bool.fromEnvironment(
      'HEALTHVAULT_ALLOW_INSECURE_LOCAL',
      defaultValue: false,
    );
    return <String>[
      cleaned,
      '$cleaned:3101',
      if (kDebugMode && allowInsecureLocal && isLocal)
        '${cleaned.replaceFirst('https://', 'http://')}:3101',
    ];
  }

  Future<void> setBaseUrl(String url) async {
    var cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!cleaned.startsWith('http')) {
      cleaned = cleaned.contains('localhost') || cleaned.contains('10.0.2.2')
          ? 'http://$cleaned'
          : 'https://$cleaned';
    }
    cleaned = cleaned.replaceAll(RegExp(r'/api(/v1)?$'), '');

    // Try to discover the working URL — never downgrade to HTTP in production.
    final candidates = _resolveBaseUrlCandidates(cleaned);
    for (final candidate in candidates) {
      try {
        final res = await _dio.get('$candidate/health');
        if (res.statusCode == 200) {
          _baseUrl = candidate;
          return;
        }
      } catch (_) {}
    }
    _baseUrl = cleaned;
  }

  Future<T> get<T>(String path, {T Function(dynamic)? fromJson}) async {
    final res = await _dio.get('$_baseUrl$path');
    _checkResponse(res);
    return fromJson != null ? fromJson(res.data) : res.data as T;
  }

  Future<T> post<T>(String path, {dynamic body, T Function(dynamic)? fromJson}) async {
    final res = await _dio.post('$_baseUrl$path', data: body);
    _checkResponse(res);
    return fromJson != null ? fromJson(res.data) : res.data as T;
  }

  Future<T> patch<T>(String path, {dynamic body, T Function(dynamic)? fromJson}) async {
    final res = await _dio.patch('$_baseUrl$path', data: body);
    _checkResponse(res);
    return fromJson != null ? fromJson(res.data) : res.data as T;
  }

  Future<T> put<T>(String path, {dynamic body, T Function(dynamic)? fromJson}) async {
    final res = await _dio.put('$_baseUrl$path', data: body);
    _checkResponse(res);
    return fromJson != null ? fromJson(res.data) : res.data as T;
  }

  Future<Uint8List> getBytes(String path) async {
    final res = await _dio.get<List<int>>(
      '$_baseUrl$path',
      options: Options(responseType: ResponseType.bytes),
    );
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException(res.statusCode!, 'Download failed');
    }
    return Uint8List.fromList(res.data!);
  }

  Future<T> uploadFile<T>(String path, String filePath, String fileName, {String? category, T Function(dynamic)? fromJson}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      if (category != null) 'category': category,
    });
    final res = await _dio.post('$_baseUrl$path', data: formData);
    _checkResponse(res);
    return fromJson != null ? fromJson(res.data) : res.data as T;
  }

  Future<void> delete(String path) async {
    final res = await _dio.delete('$_baseUrl$path');
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException(res.statusCode!, res.data?.toString() ?? '');
    }
  }

  void _checkResponse(Response res) {
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException(res.statusCode!, res.data?.toString() ?? '');
    }
  }
}

/// Retries transient connection failures with exponential backoff, and
/// short-circuits to a tagged ApiException when the device is offline.
///
/// Placement: installed AFTER the TOFU pinning interceptor in
/// [ApiClient._rebuildInterceptors] so that cookie attachment and TLS
/// pinning have already been applied to the outgoing request before any
/// retry attempt is made.
class _RetryInterceptor extends Interceptor {
  static const int _maxRetries = 2;
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Allows tests to inject a fake connectivity probe.
  @visibleForTesting
  static Future<List<ConnectivityResult>> Function()? connectivityProbe;

  Future<bool> _isOffline() async {
    try {
      final probe = connectivityProbe ?? Connectivity().checkConnectivity;
      final results = await probe();
      if (results.isEmpty) return true;
      return results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      // If we can't determine connectivity, don't pretend we're offline.
      return false;
    }
  }

  bool _isTransient(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_isTransient(err)) {
      return handler.next(err);
    }

    if (await _isOffline()) {
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          error: ApiException(-1, 'No network connection'),
          message: 'No network connection',
        ),
      );
    }

    final attempt = (err.requestOptions.extra['_retryAttempt'] as int?) ?? 0;
    if (attempt >= _maxRetries) {
      return handler.next(err);
    }

    await Future<void>.delayed(_backoff[attempt]);

    final nextOptions = err.requestOptions.copyWith(
      extra: <String, dynamic>{
        ...err.requestOptions.extra,
        '_retryAttempt': attempt + 1,
      },
    );

    try {
      final dio = Dio(BaseOptions(
        baseUrl: err.requestOptions.baseUrl,
        connectTimeout: err.requestOptions.connectTimeout,
        receiveTimeout: err.requestOptions.receiveTimeout,
        sendTimeout: err.requestOptions.sendTimeout,
        headers: err.requestOptions.headers,
      ));
      final response = await dio.fetch<dynamic>(nextOptions);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }
}
