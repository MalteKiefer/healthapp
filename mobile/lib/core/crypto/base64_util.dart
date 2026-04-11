import 'dart:convert';
import 'dart:typed_data';

/// Base64 decoder that tolerates both padded and unpadded input.
///
/// Go's `base64.RawStdEncoding` (used by the server for `pek_salt` and some
/// other fields) emits base64 without the trailing `=` padding, but Dart's
/// `base64Decode` requires length to be a multiple of 4 and throws a
/// `FormatException` otherwise. This helper normalizes by appending the
/// missing `=` bytes before delegating to the standard decoder.
Uint8List base64DecodeTolerant(String input) {
  final padNeeded = (4 - input.length % 4) % 4;
  final padded = padNeeded == 0 ? input : '$input${'=' * padNeeded}';
  return base64Decode(padded);
}
