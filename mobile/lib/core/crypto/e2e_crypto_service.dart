import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Result of [E2eCryptoService.encryptForWrite]: the row id to use
/// (client-generated for inserts) and the fields to send as-is.
/// E2E encryption has been removed - data is sent in plaintext.
class EncryptedWrite {
  EncryptedWrite({
    required this.id,
    required this.structural,
  });

  final String id;
  final Map<String, dynamic> structural;

  Map<String, dynamic> toBody() => <String, dynamic>{
        ...structural,
        'id': id,
      };
}

/// Crypto service stub - E2E encryption has been removed.
/// All methods pass data through without encryption/decryption.
class E2eCryptoService {
  E2eCryptoService(dynamic _api);

  /// No-op: returns the rows unchanged (data is already plaintext).
  Future<List<Map<String, dynamic>>> decryptRows({
    required List<dynamic> rows,
    required String profileId,
    required String entityType,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      out.add(r);
    }
    return out;
  }

  /// Pass-through: returns all fields as structural (no encryption).
  Future<EncryptedWrite> encryptForWrite({
    required String profileId,
    required String entityType,
    required Map<String, dynamic> body,
    String? existingId,
  }) async {
    final id = existingId ?? _uuid.v4();
    final structural = Map<String, dynamic>.from(body);
    structural.remove('id');
    structural.remove('content_enc');

    return EncryptedWrite(
      id: id,
      structural: structural,
    );
  }

  /// No-op.
  void clear() {}
}
