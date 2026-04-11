import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lab.dart';
import 'providers.dart';

/// Composite key for a single-marker trend query.
class LabTrendKey {
  final String profileId;
  final String marker;

  const LabTrendKey(this.profileId, this.marker);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabTrendKey &&
          other.profileId == profileId &&
          other.marker == marker;

  @override
  int get hashCode => Object.hash(profileId, marker);
}

/// Fetches the list of marker names available for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/markers`.
final availableLabMarkersProvider =
    FutureProvider.family<List<String>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/labs/markers');

  final items = data['items'] as List? ?? data['markers'] as List? ?? const [];
  final markers = items.map((e) => e.toString()).toList()..sort();
  return markers;
});

/// Fetches the trend for a single marker for a given profile.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trend?marker=X`.
final singleMarkerTrendProvider =
    FutureProvider.family<MarkerTrend, LabTrendKey>((ref, key) async {
  final api = ref.read(apiClientProvider);
  final encoded = Uri.encodeQueryComponent(key.marker);
  final data = await api.get<Map<String, dynamic>>(
    '/api/v1/profiles/${key.profileId}/labs/trend?marker=$encoded',
  );
  return MarkerTrend.fromJson(data);
});

/// Fetches trends for ALL markers for a given profile in one call.
///
/// Backed by `GET /api/v1/profiles/{profileId}/labs/trends`. Provided here as
/// a reusable, public alternative to the private `_trendsProvider` in
/// `labs_screen.dart` so new screens (e.g. `LabTrendsScreen`) can consume it
/// without reaching into private symbols.
final allLabTrendsProvider =
    FutureProvider.family<List<MarkerTrend>, String>((ref, profileId) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get<Map<String, dynamic>>('/api/v1/profiles/$profileId/labs/trends');
  final items = data['items'] as List? ?? const [];
  return items
      .map((e) => MarkerTrend.fromJson(e as Map<String, dynamic>))
      .toList();
});
