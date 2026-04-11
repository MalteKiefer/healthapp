import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthapp/core/security/key_management/dek_service.dart';
import 'package:healthapp/core/security/key_management/kek_service.dart';
import 'package:healthapp/core/security/secure_store/encrypted_cookie_jar.dart';
import 'package:healthapp/core/security/secure_store/encrypted_vault.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ecj_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<EncryptedVault> makeVault() async {
    final v = EncryptedVault(
      file: File('${tempDir.path}/vault.enc'),
      kek: KekService.fastForTests(),
      dek: DekService(),
    );
    await v.create(pin: '123456');
    return v;
  }

  test('saves and loads cookies per host', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('session', 'abc')]);
    final cookies = await jar.loadForRequest(url);
    expect(cookies, hasLength(1));
    expect(cookies.first.name, 'session');
    expect(cookies.first.value, 'abc');
  });

  test('persists across lock/unlock of the vault', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    await jar.flush();
    vault.lock();
    await vault.unlock(pin: '123456');
    await jar.reload();
    final cookies = await jar.loadForRequest(url);
    expect(cookies.single.value, 'v');
  });

  test('locking the jar returns empty cookies until reload', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    jar.lock();
    expect(await jar.loadForRequest(url), isEmpty);
  });

  test('deleteAll empties the jar', () async {
    final vault = await makeVault();
    final jar = EncryptedCookieJar(vault: vault);
    final url = Uri.parse('https://h.example/api');
    await jar.saveFromResponse(url, [Cookie('s', 'v')]);
    await jar.deleteAll();
    expect(await jar.loadForRequest(url), isEmpty);
  });
}
