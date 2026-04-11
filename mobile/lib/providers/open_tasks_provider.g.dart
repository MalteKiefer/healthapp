// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'open_tasks_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$openTasksHash() => r'b29a7bcc0e3afcd997497166dbf1aca61d3a92c0';

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

/// Fetches only the open (not-yet-done) tasks for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
/// only tasks that have not been completed. The response is expected to
/// follow the same `{ "items": [...] }` envelope used by the regular
/// tasks list endpoint.
///
/// Usage:
/// ```dart
/// final asyncTasks = ref.watch(openTasksProvider(profileId));
/// ```
///
/// Copied from [openTasks].
@ProviderFor(openTasks)
const openTasksProvider = OpenTasksFamily();

/// Fetches only the open (not-yet-done) tasks for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
/// only tasks that have not been completed. The response is expected to
/// follow the same `{ "items": [...] }` envelope used by the regular
/// tasks list endpoint.
///
/// Usage:
/// ```dart
/// final asyncTasks = ref.watch(openTasksProvider(profileId));
/// ```
///
/// Copied from [openTasks].
class OpenTasksFamily extends Family<AsyncValue<List<Task>>> {
  /// Fetches only the open (not-yet-done) tasks for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
  /// only tasks that have not been completed. The response is expected to
  /// follow the same `{ "items": [...] }` envelope used by the regular
  /// tasks list endpoint.
  ///
  /// Usage:
  /// ```dart
  /// final asyncTasks = ref.watch(openTasksProvider(profileId));
  /// ```
  ///
  /// Copied from [openTasks].
  const OpenTasksFamily();

  /// Fetches only the open (not-yet-done) tasks for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
  /// only tasks that have not been completed. The response is expected to
  /// follow the same `{ "items": [...] }` envelope used by the regular
  /// tasks list endpoint.
  ///
  /// Usage:
  /// ```dart
  /// final asyncTasks = ref.watch(openTasksProvider(profileId));
  /// ```
  ///
  /// Copied from [openTasks].
  OpenTasksProvider call(String profileId) {
    return OpenTasksProvider(profileId);
  }

  @override
  OpenTasksProvider getProviderOverride(covariant OpenTasksProvider provider) {
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
  String? get name => r'openTasksProvider';
}

/// Fetches only the open (not-yet-done) tasks for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
/// only tasks that have not been completed. The response is expected to
/// follow the same `{ "items": [...] }` envelope used by the regular
/// tasks list endpoint.
///
/// Usage:
/// ```dart
/// final asyncTasks = ref.watch(openTasksProvider(profileId));
/// ```
///
/// Copied from [openTasks].
class OpenTasksProvider extends AutoDisposeFutureProvider<List<Task>> {
  /// Fetches only the open (not-yet-done) tasks for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/tasks/open`, which returns
  /// only tasks that have not been completed. The response is expected to
  /// follow the same `{ "items": [...] }` envelope used by the regular
  /// tasks list endpoint.
  ///
  /// Usage:
  /// ```dart
  /// final asyncTasks = ref.watch(openTasksProvider(profileId));
  /// ```
  ///
  /// Copied from [openTasks].
  OpenTasksProvider(String profileId)
    : this._internal(
        (ref) => openTasks(ref as OpenTasksRef, profileId),
        from: openTasksProvider,
        name: r'openTasksProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$openTasksHash,
        dependencies: OpenTasksFamily._dependencies,
        allTransitiveDependencies: OpenTasksFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  OpenTasksProvider._internal(
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
    FutureOr<List<Task>> Function(OpenTasksRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: OpenTasksProvider._internal(
        (ref) => create(ref as OpenTasksRef),
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
  AutoDisposeFutureProviderElement<List<Task>> createElement() {
    return _OpenTasksProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OpenTasksProvider && other.profileId == profileId;
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
mixin OpenTasksRef on AutoDisposeFutureProviderRef<List<Task>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _OpenTasksProviderElement
    extends AutoDisposeFutureProviderElement<List<Task>>
    with OpenTasksRef {
  _OpenTasksProviderElement(super.provider);

  @override
  String get profileId => (origin as OpenTasksProvider).profileId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
