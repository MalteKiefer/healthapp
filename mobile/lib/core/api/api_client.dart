import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'API error $statusCode: $message';
}

class ApiClient {
  late final Dio _dio;
  PersistCookieJar? _cookieJar;
  bool _cookieJarInitialized = false;
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  /// Initialises the persistent cookie jar (once) so that session cookies
  /// survive app restarts. Must be called before the first network request.
  Future<void> _ensureCookieJar() async {
    if (_cookieJarInitialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final cookiesPath = '${dir.path}${Platform.pathSeparator}.cookies';
    _cookieJar = PersistCookieJar(storage: FileStorage(cookiesPath));
    _dio.interceptors.add(CookieManager(_cookieJar!));
    _cookieJarInitialized = true;
  }

  Future<void> setBaseUrl(String url) async {
    await _ensureCookieJar();
    var cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!cleaned.startsWith('http')) {
      cleaned = cleaned.contains('localhost') || cleaned.contains('10.0.2.2')
          ? 'http://$cleaned'
          : 'https://$cleaned';
    }
    cleaned = cleaned.replaceAll(RegExp(r'/api(/v1)?$'), '');

    // Try to discover the working URL — never downgrade to HTTP in production
    final bool isLocal = cleaned.contains('localhost') || cleaned.contains('10.0.2.2');
    final candidates = <String>[
      cleaned,
      '$cleaned:3101',
      if (kDebugMode && isLocal)
        '${cleaned.replaceFirst('https://', 'http://')}:3101',
    ];
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
