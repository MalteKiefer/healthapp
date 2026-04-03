import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../models/profile.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final profilesProvider =
    FutureProvider.family<List<Profile>, String>((ref, _) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get<Map<String, dynamic>>('/api/v1/profiles');
  return (data['items'] as List)
      .map((p) => Profile.fromJson(p as Map<String, dynamic>))
      .toList();
});

final selectedProfileProvider = StateProvider<Profile?>((ref) => null);

final languageProvider = StateProvider<String>((ref) => 'de');
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
// 1 = Monday, 7 = Sunday (ISO weekday convention)
final firstDayOfWeekProvider = StateProvider<int>((ref) => 1);
