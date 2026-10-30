import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Ed25519 public key for datasets signed with `tool/sign_dataset.sh`.
/// The private key lives in `pass` under `radar-local/dataset-signing-key`.
const datasetPublicKey = 'uApNcYk1FjR6cK/CtnGjGn93qOsDyaaYkqb5j2wuywk=';

/// Verifies a base64 Ed25519 signature over the exact dataset bytes.
Future<bool> verifyDatasetSignature(List<int> data, String signature) async {
  try {
    final bytes = base64.decode(signature.trim());
    if (bytes.length != 64) return false;
    return await Ed25519().verify(
      data,
      signature: Signature(
        bytes,
        publicKey: SimplePublicKey(
          base64.decode(datasetPublicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  } on FormatException {
    return false;
  }
}
