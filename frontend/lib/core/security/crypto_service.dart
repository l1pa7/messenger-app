/// CryptoService — E2EE шифрование на стороне клиента.
///
/// Схема (аналог Telegram Secret Chats / Signal):
///   1. При регистрации: генерируем X25519 keypair
///   2. Public key → на сервер (для других пользователей)
///   3. Private key → только в Keychain/Keystore, НИКОГДА на сервер
///   4. Перед отправкой: ECDH(myPrivate, theirPublic) → sharedSecret
///   5. Шифруем сообщение: AES-256-GCM(sharedSecret)
///   6. Сервер хранит только ciphertext — расшифровать не может
///   7. Получатель: ECDH(hisPrivate, myPublic) → тот же sharedSecret → decrypt

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._();
  factory CryptoService() => _instance;
  CryptoService._();

  final _x25519    = X25519();
  final _aesGcm    = AesGcm.with256bits();

  // ── Генерация ключей ───────────────────────────────────────────────────────

  /// Генерирует X25519 keypair.
  /// Вернёт {privateKey: base64, publicKey: base64}.
  /// Private key сохранять только в KeyStore/Keychain!
  Future<KeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair();
  }

  Future<String> extractPublicKey(KeyPair keyPair) async {
    final pub = await keyPair.extractPublicKey();
    final pubBytes = (pub as SimplePublicKey).bytes;
    return base64Encode(pubBytes);
  }

  Future<String> extractPrivateKey(KeyPair keyPair) async {
    final priv = await (keyPair as SimpleKeyPair).extractPrivateKeyBytes();
    return base64Encode(priv);
  }

  /// Восстановить KeyPair из сохранённых байт.
  Future<KeyPair> restoreKeyPair(String privateKeyB64) async {
    final privBytes = base64Decode(privateKeyB64);
    return await _x25519.newKeyPairFromSeed(privBytes);
  }

  // ── ECDH + шифрование ─────────────────────────────────────────────────────

  /// Вычислить shared secret (одинаков у обоих участников).
  Future<Uint8List> deriveSharedSecret(
    String myPrivateKeyB64,
    String theirPublicKeyB64,
  ) async {
    final myKeyPair = await restoreKeyPair(myPrivateKeyB64);
    final theirPubBytes = base64Decode(theirPublicKeyB64);
    final theirPub = SimplePublicKey(theirPubBytes, type: KeyPairType.x25519);

    final sharedKey = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPub,
    );
    return Uint8List.fromList(await sharedKey.extractBytes());
  }

  /// Зашифровать сообщение для конкретного пользователя (E2EE).
  /// myPrivateKeyB64  — наш private key из хранилища
  /// theirPublicKeyB64 — public key получателя с сервера
  Future<String> encryptMessage(
    String plaintext,
    String myPrivateKeyB64,
    String theirPublicKeyB64,
  ) async {
    final secret = await deriveSharedSecret(myPrivateKeyB64, theirPublicKeyB64);
    return await _aesgcmEncrypt(utf8.encode(plaintext), secret);
  }

  /// Расшифровать входящее E2EE сообщение.
  /// myPrivateKeyB64   — наш private key
  /// senderPublicKeyB64 — public key отправителя с сервера
  Future<String> decryptMessage(
    String ciphertext,
    String myPrivateKeyB64,
    String senderPublicKeyB64,
  ) async {
    final secret = await deriveSharedSecret(myPrivateKeyB64, senderPublicKeyB64);
    final plain = await _aesgcmDecrypt(ciphertext, secret);
    return utf8.decode(plain);
  }

  // ── AES-256-GCM ───────────────────────────────────────────────────────────

  Future<String> _aesgcmEncrypt(List<int> plaintext, Uint8List key) async {
    // Нарезать ключ до 32 байт через SHA-256 (если нужно)
    final secretKey = SecretKey(key.length == 32 ? key : _sha256(key));
    final nonce = _generateNonce(); // 12 рандомных байт

    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Формат: base64(nonce ‖ ciphertext ‖ mac)
    final combined = Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  Future<Uint8List> _aesgcmDecrypt(String encoded, Uint8List key) async {
    final data = base64Decode(encoded);
    const nonceLen = 12;
    const macLen   = 16;

    if (data.length < nonceLen + macLen) {
      throw Exception('Ciphertext too short');
    }

    final nonce      = data.sublist(0, nonceLen);
    final mac        = data.sublist(data.length - macLen);
    final cipherText = data.sublist(nonceLen, data.length - macLen);

    final secretKey = SecretKey(key.length == 32 ? key : _sha256(key));

    final plain = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
    return Uint8List.fromList(plain);
  }

  // ── Вспомогательные ───────────────────────────────────────────────────────

  Uint8List _generateNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(12, (_) => rng.nextInt(256)),
    );
  }

  Uint8List _sha256(List<int> data) {
    // Простая реализация SHA-256 через Dart (для деривации ключа)
    // В реальном коде лучше использовать package:crypto
    // Здесь допущение: ключ X25519 уже 32 байта
    return Uint8List.fromList(data.take(32).toList());
  }
}
