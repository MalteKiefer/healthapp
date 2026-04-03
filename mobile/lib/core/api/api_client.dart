import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'API error $statusCode: $message';
}

class ApiClient {
  late final Dio _dio;
  final CookieJar _cookieJar = CookieJar();
  String _baseUrl = 'https://health.p37.nexus';

  String get baseUrl => _baseUrl;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<void> setBaseUrl(String url) async {
    var cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!cleaned.startsWith('http')) {
      cleaned = cleaned.contains('localhost') || cleaned.contains('10.0.2.2')
          ? 'http://$cleaned'
          : 'https://$cleaned';
    }
    cleaned = cleaned.replaceAll(RegExp(r'/api(/v1)?$'), '');

    // Try to discover the working URL
    for (final candidate in [
      cleaned,
      '$cleaned:3101',
      '${cleaned.replaceFirst('https://', 'http://')}:3101',
    ]) {
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
