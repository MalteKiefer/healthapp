import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/passkey/passkey_service.dart';

final passkeyServiceProvider = Provider<PasskeyService>((ref) {
  return const PasskeyMethodChannelService();
});

final passkeySupportProvider = FutureProvider<PasskeySupport>((ref) async {
  final svc = ref.watch(passkeyServiceProvider);
  return svc.support();
});
