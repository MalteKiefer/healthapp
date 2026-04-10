import 'dart:typed_data';

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
