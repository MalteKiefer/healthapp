// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_trends_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$availableLabMarkersHash() =>
    r'66ac63be4a01706864509e5921a2c6ed9413fbe9';

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

/// Fetches the list of marker names available for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
///
/// Copied from [availableLabMarkers].
@ProviderFor(availableLabMarkers)
const availableLabMarkersProvider = AvailableLabMarkersFamily();

/// Fetches the list of marker names available for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
///
/// Copied from [availableLabMarkers].
class AvailableLabMarkersFamily extends Family<AsyncValue<List<String>>> {
  /// Fetches the list of marker names available for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
  ///
  /// Copied from [availableLabMarkers].
  const AvailableLabMarkersFamily();

  /// Fetches the list of marker names available for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
  ///
  /// Copied from [availableLabMarkers].
  AvailableLabMarkersProvider call(String profileId) {
    return AvailableLabMarkersProvider(profileId);
  }

  @override
  AvailableLabMarkersProvider getProviderOverride(
    covariant AvailableLabMarkersProvider provider,
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
  String? get name => r'availableLabMarkersProvider';
}

/// Fetches the list of marker names available for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
///
/// Copied from [availableLabMarkers].
class AvailableLabMarkersProvider
    extends AutoDisposeFutureProvider<List<String>> {
  /// Fetches the list of marker names available for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
  ///
  /// Copied from [availableLabMarkers].
  AvailableLabMarkersProvider(String profileId)
    : this._internal(
        (ref) => availableLabMarkers(ref as AvailableLabMarkersRef, profileId),
        from: availableLabMarkersProvider,
        name: r'availableLabMarkersProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$availableLabMarkersHash,
        dependencies: AvailableLabMarkersFamily._dependencies,
        allTransitiveDependencies:
            AvailableLabMarkersFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  AvailableLabMarkersProvider._internal(
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
    FutureOr<List<String>> Function(AvailableLabMarkersRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AvailableLabMarkersProvider._internal(
        (ref) => create(ref as AvailableLabMarkersRef),
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
  AutoDisposeFutureProviderElement<List<String>> createElement() {
    return _AvailableLabMarkersProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AvailableLabMarkersProvider && other.profileId == profileId;
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
mixin AvailableLabMarkersRef on AutoDisposeFutureProviderRef<List<String>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _AvailableLabMarkersProviderElement
    extends AutoDisposeFutureProviderElement<List<String>>
    with AvailableLabMarkersRef {
  _AvailableLabMarkersProviderElement(super.provider);

  @override
  String get profileId => (origin as AvailableLabMarkersProvider).profileId;
}

String _$singleMarkerTrendHash() => r'fec31ef4cb6fa524bc9fd3abf66ca99687fb8c58';

/// Fetches the trend for a single marker for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
///
/// Copied from [singleMarkerTrend].
@ProviderFor(singleMarkerTrend)
const singleMarkerTrendProvider = SingleMarkerTrendFamily();

/// Fetches the trend for a single marker for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
///
/// Copied from [singleMarkerTrend].
class SingleMarkerTrendFamily extends Family<AsyncValue<MarkerTrend>> {
  /// Fetches the trend for a single marker for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
  ///
  /// Copied from [singleMarkerTrend].
  const SingleMarkerTrendFamily();

  /// Fetches the trend for a single marker for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
  ///
  /// Copied from [singleMarkerTrend].
  SingleMarkerTrendProvider call(String profileId, String marker) {
    return SingleMarkerTrendProvider(profileId, marker);
  }

  @override
  SingleMarkerTrendProvider getProviderOverride(
    covariant SingleMarkerTrendProvider provider,
  ) {
    return call(provider.profileId, provider.marker);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'singleMarkerTrendProvider';
}

/// Fetches the trend for a single marker for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
///
/// Copied from [singleMarkerTrend].
class SingleMarkerTrendProvider extends AutoDisposeFutureProvider<MarkerTrend> {
  /// Fetches the trend for a single marker for a given profile.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
  ///
  /// Copied from [singleMarkerTrend].
  SingleMarkerTrendProvider(String profileId, String marker)
    : this._internal(
        (ref) =>
            singleMarkerTrend(ref as SingleMarkerTrendRef, profileId, marker),
        from: singleMarkerTrendProvider,
        name: r'singleMarkerTrendProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$singleMarkerTrendHash,
        dependencies: SingleMarkerTrendFamily._dependencies,
        allTransitiveDependencies:
            SingleMarkerTrendFamily._allTransitiveDependencies,
        profileId: profileId,
        marker: marker,
      );

  SingleMarkerTrendProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.profileId,
    required this.marker,
  }) : super.internal();

  final String profileId;
  final String marker;

  @override
  Override overrideWith(
    FutureOr<MarkerTrend> Function(SingleMarkerTrendRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SingleMarkerTrendProvider._internal(
        (ref) => create(ref as SingleMarkerTrendRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        profileId: profileId,
        marker: marker,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<MarkerTrend> createElement() {
    return _SingleMarkerTrendProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SingleMarkerTrendProvider &&
        other.profileId == profileId &&
        other.marker == marker;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, profileId.hashCode);
    hash = _SystemHash.combine(hash, marker.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SingleMarkerTrendRef on AutoDisposeFutureProviderRef<MarkerTrend> {
  /// The parameter `profileId` of this provider.
  String get profileId;

  /// The parameter `marker` of this provider.
  String get marker;
}

class _SingleMarkerTrendProviderElement
    extends AutoDisposeFutureProviderElement<MarkerTrend>
    with SingleMarkerTrendRef {
  _SingleMarkerTrendProviderElement(super.provider);

  @override
  String get profileId => (origin as SingleMarkerTrendProvider).profileId;
  @override
  String get marker => (origin as SingleMarkerTrendProvider).marker;
}

String _$allLabTrendsHash() => r'07458a368445974c74db6d863cd407933ad83c3b';

/// Fetches trends for ALL markers for a given profile in one call.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
/// a reusable, public alternative to the private `_trendsProvider` in
/// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
/// without reaching into private symbols.
///
/// Copied from [allLabTrends].
@ProviderFor(allLabTrends)
const allLabTrendsProvider = AllLabTrendsFamily();

/// Fetches trends for ALL markers for a given profile in one call.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
/// a reusable, public alternative to the private `_trendsProvider` in
/// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
/// without reaching into private symbols.
///
/// Copied from [allLabTrends].
class AllLabTrendsFamily extends Family<AsyncValue<List<MarkerTrend>>> {
  /// Fetches trends for ALL markers for a given profile in one call.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
  /// a reusable, public alternative to the private `_trendsProvider` in
  /// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
  /// without reaching into private symbols.
  ///
  /// Copied from [allLabTrends].
  const AllLabTrendsFamily();

  /// Fetches trends for ALL markers for a given profile in one call.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
  /// a reusable, public alternative to the private `_trendsProvider` in
  /// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
  /// without reaching into private symbols.
  ///
  /// Copied from [allLabTrends].
  AllLabTrendsProvider call(String profileId) {
    return AllLabTrendsProvider(profileId);
  }

  @override
  AllLabTrendsProvider getProviderOverride(
    covariant AllLabTrendsProvider provider,
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
  String? get name => r'allLabTrendsProvider';
}

/// Fetches trends for ALL markers for a given profile in one call.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
/// a reusable, public alternative to the private `_trendsProvider` in
/// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
/// without reaching into private symbols.
///
/// Copied from [allLabTrends].
class AllLabTrendsProvider
    extends AutoDisposeFutureProvider<List<MarkerTrend>> {
  /// Fetches trends for ALL markers for a given profile in one call.
  ///
  /// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
  /// a reusable, public alternative to the private `_trendsProvider` in
  /// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
  /// without reaching into private symbols.
  ///
  /// Copied from [allLabTrends].
  AllLabTrendsProvider(String profileId)
    : this._internal(
        (ref) => allLabTrends(ref as AllLabTrendsRef, profileId),
        from: allLabTrendsProvider,
        name: r'allLabTrendsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$allLabTrendsHash,
        dependencies: AllLabTrendsFamily._dependencies,
        allTransitiveDependencies:
            AllLabTrendsFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  AllLabTrendsProvider._internal(
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
    FutureOr<List<MarkerTrend>> Function(AllLabTrendsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AllLabTrendsProvider._internal(
        (ref) => create(ref as AllLabTrendsRef),
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
  AutoDisposeFutureProviderElement<List<MarkerTrend>> createElement() {
    return _AllLabTrendsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AllLabTrendsProvider && other.profileId == profileId;
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
mixin AllLabTrendsRef on AutoDisposeFutureProviderRef<List<MarkerTrend>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _AllLabTrendsProviderElement
    extends AutoDisposeFutureProviderElement<List<MarkerTrend>>
    with AllLabTrendsRef {
  _AllLabTrendsProviderElement(super.provider);

  @override
  String get profileId => (origin as AllLabTrendsProvider).profileId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
