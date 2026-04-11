/// Discriminator for API errors used by the UI layer to pick messages.
///
/// Sprint 2 architecture task: typed error model that wraps the generic
/// `ApiException(statusCode, message)` used by `api_client.dart`. Callers
/// map an HTTP status code (or a transport-level failure) to one of these
/// variants and then render a localized string via `apiErrorMessage`.
enum ApiErrorType {
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  serverError,
  networkError,
  timeout,
  unknown;

  /// Maps an HTTP status code to an [ApiErrorType].
  ///
  /// Any 5xx code collapses to [serverError]. Unrecognized codes fall
  /// through to [unknown] so the UI still shows a safe default.
  static ApiErrorType fromStatus(int code) {
    if (code == 401) return ApiErrorType.unauthorized;
    if (code == 403) return ApiErrorType.forbidden;
    if (code == 404) return ApiErrorType.notFound;
    if (code == 409) return ApiErrorType.conflict;
    if (code == 422) return ApiErrorType.validation;
    if (code == 429) return ApiErrorType.rateLimited;
    if (code >= 500) return ApiErrorType.serverError;
    return ApiErrorType.unknown;
  }
}
