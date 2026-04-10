import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';
import 'package:healthapp/core/security/tls/cert_fingerprint_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cfs_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<CertFingerprintStore> makeStore() async {
    final vault = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    await vault.create(pin: '123456');
    return CertFingerprintStore(vault: vault);
  }

  test('returns null when no pin stored', () async {
    final store = await makeStore();
    expect(await store.expected('health.example.com'), isNull);
  });

  test('persists and reloads pin', () async {
    final store = await makeStore();
    await store.save('health.example.com', 'ab:cd:ef');
    expect(await store.expected('health.example.com'), 'ab:cd:ef');
  });

  test('delete removes pin', () async {
    final store = await makeStore();
    await store.save('h.com', 'x');
    await store.delete('h.com');
    expect(await store.expected('h.com'), isNull);
  });

  test('separate hosts have separate pins', () async {
    final store = await makeStore();
    await store.save('a.com', '1');
    await store.save('b.com', '2');
    expect(await store.expected('a.com'), '1');
    expect(await store.expected('b.com'), '2');
  });
}
