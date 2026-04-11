// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vaccination_due_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaccinationDueHash() => r'21d316021bcc2378471f9564bf6b80fadd986835';

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

/// Fetches vaccinations that are due soon or overdue for the given profile.
///
/// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
///
/// Response shape (mirrors `web/src/api/vaccinations.ts`):
/// ```json
/// {
///   "items": [
///     {
///       "id": "...",
///       "vaccine_name": "Tetanus",
///       "trade_name": "...",
///       "manufacturer": "...",
///       "dose_number": 2,
///       "administered_at": "2024-04-10T00:00:00Z",
///       "next_due_at": "2026-04-10T00:00:00Z",
///       "site": "...",
///       "notes": "..."
///     }
///   ],
///   "total": 1
/// }
/// ```
///
/// The existing [Vaccination] model in `models/common.dart` is reused
/// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
/// existing `vaccine` field for compatibility with both the current
/// mobile list screen and the web API shape.
///
/// Copied from [vaccinationDue].
@ProviderFor(vaccinationDue)
const vaccinationDueProvider = VaccinationDueFamily();

/// Fetches vaccinations that are due soon or overdue for the given profile.
///
/// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
///
/// Response shape (mirrors `web/src/api/vaccinations.ts`):
/// ```json
/// {
///   "items": [
///     {
///       "id": "...",
///       "vaccine_name": "Tetanus",
///       "trade_name": "...",
///       "manufacturer": "...",
///       "dose_number": 2,
///       "administered_at": "2024-04-10T00:00:00Z",
///       "next_due_at": "2026-04-10T00:00:00Z",
///       "site": "...",
///       "notes": "..."
///     }
///   ],
///   "total": 1
/// }
/// ```
///
/// The existing [Vaccination] model in `models/common.dart` is reused
/// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
/// existing `vaccine` field for compatibility with both the current
/// mobile list screen and the web API shape.
///
/// Copied from [vaccinationDue].
class VaccinationDueFamily extends Family<AsyncValue<List<Vaccination>>> {
  /// Fetches vaccinations that are due soon or overdue for the given profile.
  ///
  /// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
  ///
  /// Response shape (mirrors `web/src/api/vaccinations.ts`):
  /// ```json
  /// {
  ///   "items": [
  ///     {
  ///       "id": "...",
  ///       "vaccine_name": "Tetanus",
  ///       "trade_name": "...",
  ///       "manufacturer": "...",
  ///       "dose_number": 2,
  ///       "administered_at": "2024-04-10T00:00:00Z",
  ///       "next_due_at": "2026-04-10T00:00:00Z",
  ///       "site": "...",
  ///       "notes": "..."
  ///     }
  ///   ],
  ///   "total": 1
  /// }
  /// ```
  ///
  /// The existing [Vaccination] model in `models/common.dart` is reused
  /// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
  /// existing `vaccine` field for compatibility with both the current
  /// mobile list screen and the web API shape.
  ///
  /// Copied from [vaccinationDue].
  const VaccinationDueFamily();

  /// Fetches vaccinations that are due soon or overdue for the given profile.
  ///
  /// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
  ///
  /// Response shape (mirrors `web/src/api/vaccinations.ts`):
  /// ```json
  /// {
  ///   "items": [
  ///     {
  ///       "id": "...",
  ///       "vaccine_name": "Tetanus",
  ///       "trade_name": "...",
  ///       "manufacturer": "...",
  ///       "dose_number": 2,
  ///       "administered_at": "2024-04-10T00:00:00Z",
  ///       "next_due_at": "2026-04-10T00:00:00Z",
  ///       "site": "...",
  ///       "notes": "..."
  ///     }
  ///   ],
  ///   "total": 1
  /// }
  /// ```
  ///
  /// The existing [Vaccination] model in `models/common.dart` is reused
  /// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
  /// existing `vaccine` field for compatibility with both the current
  /// mobile list screen and the web API shape.
  ///
  /// Copied from [vaccinationDue].
  VaccinationDueProvider call(String profileId) {
    return VaccinationDueProvider(profileId);
  }

  @override
  VaccinationDueProvider getProviderOverride(
    covariant VaccinationDueProvider provider,
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
  String? get name => r'vaccinationDueProvider';
}

/// Fetches vaccinations that are due soon or overdue for the given profile.
///
/// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
///
/// Response shape (mirrors `web/src/api/vaccinations.ts`):
/// ```json
/// {
///   "items": [
///     {
///       "id": "...",
///       "vaccine_name": "Tetanus",
///       "trade_name": "...",
///       "manufacturer": "...",
///       "dose_number": 2,
///       "administered_at": "2024-04-10T00:00:00Z",
///       "next_due_at": "2026-04-10T00:00:00Z",
///       "site": "...",
///       "notes": "..."
///     }
///   ],
///   "total": 1
/// }
/// ```
///
/// The existing [Vaccination] model in `models/common.dart` is reused
/// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
/// existing `vaccine` field for compatibility with both the current
/// mobile list screen and the web API shape.
///
/// Copied from [vaccinationDue].
class VaccinationDueProvider
    extends AutoDisposeFutureProvider<List<Vaccination>> {
  /// Fetches vaccinations that are due soon or overdue for the given profile.
  ///
  /// Backend endpoint: `GET /api/v1/profiles/{profileId}/vaccinations/due`.
  ///
  /// Response shape (mirrors `web/src/api/vaccinations.ts`):
  /// ```json
  /// {
  ///   "items": [
  ///     {
  ///       "id": "...",
  ///       "vaccine_name": "Tetanus",
  ///       "trade_name": "...",
  ///       "manufacturer": "...",
  ///       "dose_number": 2,
  ///       "administered_at": "2024-04-10T00:00:00Z",
  ///       "next_due_at": "2026-04-10T00:00:00Z",
  ///       "site": "...",
  ///       "notes": "..."
  ///     }
  ///   ],
  ///   "total": 1
  /// }
  /// ```
  ///
  /// The existing [Vaccination] model in `models/common.dart` is reused
  /// as-is; no wrapper is introduced. `vaccine_name` is mapped onto the
  /// existing `vaccine` field for compatibility with both the current
  /// mobile list screen and the web API shape.
  ///
  /// Copied from [vaccinationDue].
  VaccinationDueProvider(String profileId)
    : this._internal(
        (ref) => vaccinationDue(ref as VaccinationDueRef, profileId),
        from: vaccinationDueProvider,
        name: r'vaccinationDueProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$vaccinationDueHash,
        dependencies: VaccinationDueFamily._dependencies,
        allTransitiveDependencies:
            VaccinationDueFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  VaccinationDueProvider._internal(
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
    FutureOr<List<Vaccination>> Function(VaccinationDueRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: VaccinationDueProvider._internal(
        (ref) => create(ref as VaccinationDueRef),
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
  AutoDisposeFutureProviderElement<List<Vaccination>> createElement() {
    return _VaccinationDueProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is VaccinationDueProvider && other.profileId == profileId;
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
mixin VaccinationDueRef on AutoDisposeFutureProviderRef<List<Vaccination>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _VaccinationDueProviderElement
    extends AutoDisposeFutureProviderElement<List<Vaccination>>
    with VaccinationDueRef {
  _VaccinationDueProviderElement(super.provider);

  @override
  String get profileId => (origin as VaccinationDueProvider).profileId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
