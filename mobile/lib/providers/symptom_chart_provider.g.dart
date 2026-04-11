// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'symptom_chart_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$symptomChartHash() => r'efe80af50253b727f79e8083435fd791155f0cc6';

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

/// Fetches symptom chart data for a given profile id.
///
/// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
/// [SymptomChartData] instance with one [SymptomSeries] per distinct
/// symptom type.
///
/// Copied from [symptomChart].
@ProviderFor(symptomChart)
const symptomChartProvider = SymptomChartFamily();

/// Fetches symptom chart data for a given profile id.
///
/// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
/// [SymptomChartData] instance with one [SymptomSeries] per distinct
/// symptom type.
///
/// Copied from [symptomChart].
class SymptomChartFamily extends Family<AsyncValue<SymptomChartData>> {
  /// Fetches symptom chart data for a given profile id.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
  /// [SymptomChartData] instance with one [SymptomSeries] per distinct
  /// symptom type.
  ///
  /// Copied from [symptomChart].
  const SymptomChartFamily();

  /// Fetches symptom chart data for a given profile id.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
  /// [SymptomChartData] instance with one [SymptomSeries] per distinct
  /// symptom type.
  ///
  /// Copied from [symptomChart].
  SymptomChartProvider call(String profileId) {
    return SymptomChartProvider(profileId);
  }

  @override
  SymptomChartProvider getProviderOverride(
    covariant SymptomChartProvider provider,
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
  String? get name => r'symptomChartProvider';
}

/// Fetches symptom chart data for a given profile id.
///
/// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
/// [SymptomChartData] instance with one [SymptomSeries] per distinct
/// symptom type.
///
/// Copied from [symptomChart].
class SymptomChartProvider extends AutoDisposeFutureProvider<SymptomChartData> {
  /// Fetches symptom chart data for a given profile id.
  ///
  /// Calls `GET /api/v1/profiles/{profileId}/symptoms/chart` and returns a
  /// [SymptomChartData] instance with one [SymptomSeries] per distinct
  /// symptom type.
  ///
  /// Copied from [symptomChart].
  SymptomChartProvider(String profileId)
    : this._internal(
        (ref) => symptomChart(ref as SymptomChartRef, profileId),
        from: symptomChartProvider,
        name: r'symptomChartProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$symptomChartHash,
        dependencies: SymptomChartFamily._dependencies,
        allTransitiveDependencies:
            SymptomChartFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  SymptomChartProvider._internal(
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
    FutureOr<SymptomChartData> Function(SymptomChartRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SymptomChartProvider._internal(
        (ref) => create(ref as SymptomChartRef),
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
  AutoDisposeFutureProviderElement<SymptomChartData> createElement() {
    return _SymptomChartProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SymptomChartProvider && other.profileId == profileId;
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
mixin SymptomChartRef on AutoDisposeFutureProviderRef<SymptomChartData> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _SymptomChartProviderElement
    extends AutoDisposeFutureProviderElement<SymptomChartData>
    with SymptomChartRef {
  _SymptomChartProviderElement(super.provider);

  @override
  String get profileId => (origin as SymptomChartProvider).profileId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
