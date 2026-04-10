@Tags(['slow'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';

void main() {
  test('production Argon2id parameters derive within 2 seconds', () async {
    final service = KekService.production();
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    final sw = Stopwatch()..start();
    final key = await service.deriveKek('123456', salt);
    sw.stop();
    expect(key, hasLength(32));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
        reason: 'Argon2id took too long: ${sw.elapsed}');
  }, tags: ['slow']);
}
