// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_log_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activityLogHash() => r'f8c139b84c164c4e2760bc6127e78342f8953e8f';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Fetches the activity log for a single profile.
///
/// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
/// list in `{items: [...], total: N}`; this provider unwraps and returns just
/// the parsed [ActivityEntry] list, sorted newest-first (the backend already
/// orders by `created_at DESC`, but we re-sort defensively).
///
/// Invalidate this provider after any mutation that should immediately appear
/// in the activity log.
///
/// Copied from [activityLog].
@ProviderFor(activityLog)
const activityLogProvider = ActivityLogFamily();

/// Fetches the activity log for a single profile.
///
/// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
/// list in `{items: [...], total: N}`; this provider unwraps and returns just
/// the parsed [ActivityEntry] list, sorted newest-first (the backend already
/// orders by `created_at DESC`, but we re-sort defensively).
///
/// Invalidate this provider after any mutation that should immediately appear
/// in the activity log.
///
/// Copied from [activityLog].
class ActivityLogFamily extends Family<AsyncValue<List<ActivityEntry>>> {
  /// Fetches the activity log for a single profile.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
  /// list in `{items: [...], total: N}`; this provider unwraps and returns just
  /// the parsed [ActivityEntry] list, sorted newest-first (the backend already
  /// orders by `created_at DESC`, but we re-sort defensively).
  ///
  /// Invalidate this provider after any mutation that should immediately appear
  /// in the activity log.
  ///
  /// Copied from [activityLog].
  const ActivityLogFamily();

  /// Fetches the activity log for a single profile.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
  /// list in `{items: [...], total: N}`; this provider unwraps and returns just
  /// the parsed [ActivityEntry] list, sorted newest-first (the backend already
  /// orders by `created_at DESC`, but we re-sort defensively).
  ///
  /// Invalidate this provider after any mutation that should immediately appear
  /// in the activity log.
  ///
  /// Copied from [activityLog].
  ActivityLogProvider call(String profileId) {
    return ActivityLogProvider(profileId);
  }

  @override
  ActivityLogProvider getProviderOverride(
    covariant ActivityLogProvider provider,
  ) {
    return call(provider.profileId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'activityLogProvider';
}

/// Fetches the activity log for a single profile.
///
/// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
/// list in `{items: [...], total: N}`; this provider unwraps and returns just
/// the parsed [ActivityEntry] list, sorted newest-first (the backend already
/// orders by `created_at DESC`, but we re-sort defensively).
///
/// Invalidate this provider after any mutation that should immediately appear
/// in the activity log.
///
/// Copied from [activityLog].
class ActivityLogProvider
    extends AutoDisposeFutureProvider<List<ActivityEntry>> {
  /// Fetches the activity log for a single profile.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/activity`. The backend wraps the
  /// list in `{items: [...], total: N}`; this provider unwraps and returns just
  /// the parsed [ActivityEntry] list, sorted newest-first (the backend already
  /// orders by `created_at DESC`, but we re-sort defensively).
  ///
  /// Invalidate this provider after any mutation that should immediately appear
  /// in the activity log.
  ///
  /// Copied from [activityLog].
  ActivityLogProvider(String profileId)
    : this._internal(
        (ref) => activityLog(ref as ActivityLogRef, profileId),
        from: activityLogProvider,
        name: r'activityLogProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$activityLogHash,
        dependencies: ActivityLogFamily._dependencies,
        allTransitiveDependencies: ActivityLogFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  ActivityLogProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.profileId,
  }) : super.internal();

  final String profileId;

  @override
  Override overrideWith(
    FutureOr<List<ActivityEntry>> Function(ActivityLogRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActivityLogProvider._internal(
        (ref) => create(ref as ActivityLogRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        profileId: profileId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ActivityEntry>> createElement() {
    return _ActivityLogProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityLogProvider && other.profileId == profileId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, profileId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ActivityLogRef on AutoDisposeFutureProviderRef<List<ActivityEntry>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _ActivityLogProviderElement
    extends AutoDisposeFutureProviderElement<List<ActivityEntry>>
    with ActivityLogRef {
  _ActivityLogProviderElement(super.provider);

  @override
  String get profileId => (origin as ActivityLogProvider).profileId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
