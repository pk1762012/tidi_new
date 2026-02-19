import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

/// Replicates the CryptoJS.AES.encrypt(value, "ApiKeySecret") behavior
/// used in the RGX web app's checkValidApiAnSecret() function.
///
/// CryptoJS with a string passphrase uses OpenSSL's EVP_BytesToKey for
/// key derivation (MD5-based) and AES-256-CBC encryption.
/// Output format: Base64("Salted__" + 8-byte-salt + ciphertext)
class BrokerCryptoService {
  BrokerCryptoService._();
  static final BrokerCryptoService instance = BrokerCryptoService._();

  static const String _passphrase = 'ApiKeySecret';

  /// Encrypt a credential value using CryptoJS-compatible AES-256-CBC.
  /// Returns Base64 string identical to CryptoJS.AES.encrypt(value, "ApiKeySecret").toString()
  String encryptCredential(String plaintext) {
    final random = Random.secure();
    final salt = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      salt[i] = random.nextInt(256);
    }

    final keyIv = _evpBytesToKey(
      utf8.encode(_passphrase),
      salt,
      32, // key length for AES-256
      16, // IV length for CBC
    );

    final key = encrypt_lib.Key(Uint8List.fromList(keyIv[0]));
    final iv = encrypt_lib.IV(Uint8List.fromList(keyIv[1]));
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
    );

    final encrypted = encrypter.encryptBytes(utf8.encode(plaintext), iv: iv);

    // OpenSSL format: "Salted__" + salt + ciphertext
    final output = Uint8List(8 + 8 + encrypted.bytes.length);
    output.setAll(0, utf8.encode('Salted__'));
    output.setAll(8, salt);
    output.setAll(16, encrypted.bytes);

    return base64.encode(output);
  }

  /// EVP_BytesToKey: derives key and IV from passphrase + salt using MD5.
  /// This matches the OpenSSL / CryptoJS key derivation algorithm.
  List<List<int>> _evpBytesToKey(
    List<int> password,
    List<int> salt,
    int keyLen,
    int ivLen,
  ) {
    final totalLen = keyLen + ivLen;
    final derivedBytes = <int>[];
    List<int> block = [];

    while (derivedBytes.length < totalLen) {
      final data = <int>[];
      if (block.isNotEmpty) {
        data.addAll(block);
      }
      data.addAll(password);
      data.addAll(salt);

      block = md5.convert(data).bytes;
      derivedBytes.addAll(block);
    }

    return [
      derivedBytes.sublist(0, keyLen),
      derivedBytes.sublist(keyLen, keyLen + ivLen),
    ];
  }
}
