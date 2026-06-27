/// KeyStore — безопасное хранилище приватных ключей.
///
/// iOS:   Keychain (hardware-backed на устройствах с Secure Enclave)
/// Android: EncryptedSharedPreferences / Android Keystore
/// Desktop: OS credential manager
///
/// Приватный X25519 ключ НИКОГДА не покидает устройство.
/// На сервер уходит только публичный ключ.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'crypto_service.dart';

class KeyStore {
  static final KeyStore _i = KeyStore._();
  factory KeyStore() => _i;
  KeyStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const _privateKeyKey   = 'e2e_private_key';
  static const _publicKeyKey    = 'e2e_public_key';
  static const _keyVersionKey   = 'e2e_key_version';

  // ── Инициализация ключей при первом запуске / регистрации ─────────────────

  /// Генерирует новую пару ключей и сохраняет приватный в Keychain.
  /// Возвращает публичный ключ (base64) для загрузки на сервер.
  Future<String> generateAndSave() async {
    final crypto  = CryptoService();
    final keyPair = await crypto.generateKeyPair();

    final privateB64 = await crypto.extractPrivateKey(keyPair);
    final publicB64  = await crypto.extractPublicKey(keyPair);

    await _storage.write(key: _privateKeyKey, value: privateB64);
    await _storage.write(key: _publicKeyKey,  value: publicB64);
    await _storage.write(key: _keyVersionKey, value: '1');

    return publicB64; // только это идёт на сервер
  }

  /// Проверить, есть ли сохранённые ключи.
  Future<bool> hasKeys() async {
    final priv = await _storage.read(key: _privateKeyKey);
    return priv != null && priv.isNotEmpty;
  }

  /// Получить сохранённый приватный ключ (base64).
  Future<String?> getPrivateKey() async {
    return _storage.read(key: _privateKeyKey);
  }

  /// Получить сохранённый публичный ключ (base64).
  Future<String?> getPublicKey() async {
    return _storage.read(key: _publicKeyKey);
  }

  /// Ротация ключей (например, при компрометации устройства).
  /// Генерирует новую пару и возвращает новый публичный ключ для сервера.
  Future<String> rotateKeys() async {
    final versionStr = await _storage.read(key: _keyVersionKey) ?? '1';
    final version    = (int.tryParse(versionStr) ?? 1) + 1;

    final crypto    = CryptoService();
    final keyPair   = await crypto.generateKeyPair();
    final privB64   = await crypto.extractPrivateKey(keyPair);
    final pubB64    = await crypto.extractPublicKey(keyPair);

    await _storage.write(key: _privateKeyKey,  value: privB64);
    await _storage.write(key: _publicKeyKey,   value: pubB64);
    await _storage.write(key: _keyVersionKey,  value: '$version');

    return pubB64;
  }

  /// Удалить все ключи (logout / смена аккаунта).
  Future<void> clearKeys() async {
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _publicKeyKey);
    await _storage.delete(key: _keyVersionKey);
  }

  // ── Кеш публичных ключей собеседников ────────────────────────────────────
  // Хранится локально, чтобы не запрашивать сервер каждый раз.

  Future<void> cacheContactKey(int userId, String publicKeyB64) async {
    await _storage.write(
      key: 'contact_key_$userId',
      value: publicKeyB64,
    );
  }

  Future<String?> getCachedContactKey(int userId) async {
    return _storage.read(key: 'contact_key_$userId');
  }
}
