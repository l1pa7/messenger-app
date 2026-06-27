// Package security реализует шифрование для мессенджера.
//
// Слои защиты:
//   1. Transport  — TLS/HTTPS (Caddy)
//   2. At-rest    — AES-256-GCM: сообщения шифруются до сохранения в PostgreSQL
//   3. E2EE       — X25519 + AES-256-GCM: сервер хранит только шифротекст,
//                   расшифровать может только получатель на своём устройстве

package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"
)

// ─── AES-256-GCM (server-side encryption) ────────────────────────────────────

// Encrypt шифрует plaintext ключом key.
// Возвращает base64(nonce‖ciphertext‖tag) — безопасно хранить в БД.
func Encrypt(plaintext []byte, key []byte) (string, error) {
	k := deriveKey(key) // всегда ровно 32 байта
	block, err := aes.NewCipher(k[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	// Seal добавляет GCM-tag (16 байт) в конец — защита целостности
	sealed := gcm.Seal(nonce, nonce, plaintext, nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt расшифровывает строку, полученную от Encrypt.
func Decrypt(encoded string, key []byte) ([]byte, error) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, err
	}
	k := deriveKey(key)
	block, err := aes.NewCipher(k[:])
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	ns := gcm.NonceSize()
	if len(data) < ns {
		return nil, errors.New("ciphertext too short")
	}
	return gcm.Open(nil, data[:ns], data[ns:], nil)
}

// deriveKey приводит ключ произвольной длины к 32 байтам через SHA-256.
func deriveKey(key []byte) [32]byte {
	return sha256.Sum256(key)
}

// ─── X25519 + AES-256-GCM (E2EE) ────────────────────────────────────────────
// Схема:
//   • При регистрации клиент генерирует X25519 keypair.
//   • Публичный ключ хранится на сервере.
//   • Приватный ключ НИКОГДА не покидает устройство (Keychain / Keystore).
//   • Перед отправкой клиент делает ECDH, получает shared secret,
//     шифрует сообщение AES-256-GCM. Сервер видит только шифротекст.

// GenerateX25519KeyPair генерирует новую пару X25519 ключей.
// Приватный ключ → сохранить в flutter_secure_storage (никуда не слать).
// Публичный ключ → загрузить на сервер для других пользователей.
func GenerateX25519KeyPair() (privateKeyB64, publicKeyB64 string, err error) {
	curve := ecdh.X25519()
	priv, err := curve.GenerateKey(rand.Reader)
	if err != nil {
		return "", "", err
	}
	privateKeyB64 = base64.StdEncoding.EncodeToString(priv.Bytes())
	publicKeyB64 = base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())
	return
}

// DeriveSharedSecret вычисляет shared secret из своего private + чужого public.
// Результат одинаков у обоих участников → основа для симметричного шифра.
func DeriveSharedSecret(myPrivateB64, theirPublicB64 string) ([]byte, error) {
	curve := ecdh.X25519()

	privBytes, err := base64.StdEncoding.DecodeString(myPrivateB64)
	if err != nil {
		return nil, err
	}
	priv, err := curve.NewPrivateKey(privBytes)
	if err != nil {
		return nil, err
	}

	pubBytes, err := base64.StdEncoding.DecodeString(theirPublicB64)
	if err != nil {
		return nil, err
	}
	pub, err := curve.NewPublicKey(pubBytes)
	if err != nil {
		return nil, err
	}

	secret, err := priv.ECDH(pub)
	if err != nil {
		return nil, err
	}
	return secret, nil
}

// E2EEncrypt шифрует сообщение для конкретного получателя.
// myPrivate   — base64 X25519 private key отправителя
// theirPublic — base64 X25519 public key получателя (с сервера)
func E2EEncrypt(plaintext []byte, myPrivate, theirPublic string) (string, error) {
	secret, err := DeriveSharedSecret(myPrivate, theirPublic)
	if err != nil {
		return "", err
	}
	return Encrypt(plaintext, secret)
}

// E2EDecrypt расшифровывает входящее сообщение.
// myPrivate    — base64 X25519 private key получателя
// senderPublic — base64 X25519 public key отправителя (с сервера)
func E2EDecrypt(encoded string, myPrivate, senderPublic string) ([]byte, error) {
	secret, err := DeriveSharedSecret(myPrivate, senderPublic)
	if err != nil {
		return nil, err
	}
	return Decrypt(encoded, secret)
}

// SecureRandom возвращает n криптографически случайных байт.
func SecureRandom(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := io.ReadFull(rand.Reader, b)
	return b, err
}
