import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_type.dart';

/// Returns a short, user-friendly English message for any error thrown by
/// the API layer.
///
/// Recognized inputs:
///   * [ApiException] — mapped through [ApiErrorType.fromStatus].
///   * [DioException] — connect/receive/send timeouts become
///     [ApiErrorType.timeout]; connection errors become
///     [ApiErrorType.networkError]; responses with a status code are
///     mapped through [ApiErrorType.fromStatus].
///   * Anything else — falls back to `error.toString()`.
///
/// English only for now. i18n will be added in a later sprint.
String apiErrorMessage(Object error) {
  if (error is ApiException) {
    return _messageFor(ApiErrorType.fromStatus(error.statusCode));
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return _messageFor(ApiErrorType.timeout);
      case DioExceptionType.connectionError:
        return _messageFor(ApiErrorType.networkError);
      case DioExceptionType.badCertificate:
        return _messageFor(ApiErrorType.networkError);
      case DioExceptionType.cancel:
        return _messageFor(ApiErrorType.unknown);
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final status = error.response?.statusCode;
        if (status != null) {
          return _messageFor(ApiErrorType.fromStatus(status));
        }
        return _messageFor(ApiErrorType.networkError);
    }
  }

  return error.toString();
}

String _messageFor(ApiErrorType type) {
  switch (type) {
    case ApiErrorType.unauthorized:
      return 'Session expired. Please log in again.';
    case ApiErrorType.forbidden:
      return "You don't have permission to access this.";
    case ApiErrorType.notFound:
      return 'Not found.';
    case ApiErrorType.conflict:
      return 'Conflict with existing data.';
    case ApiErrorType.validation:
      return 'Invalid input.';
    case ApiErrorType.rateLimited:
      return 'Too many requests. Please wait a moment.';
    case ApiErrorType.serverError:
      return 'Server error. Please try again later.';
    case ApiErrorType.networkError:
      return 'No network connection.';
    case ApiErrorType.timeout:
      return 'Request timed out.';
    case ApiErrorType.unknown:
      return 'Something went wrong.';
  }
}
