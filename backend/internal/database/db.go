package database

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/config"
)

func Connect(cfg *config.Config) (*pgxpool.Pool, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBName,
	)
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return nil, fmt.Errorf("connect to postgres: %w", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		return nil, fmt.Errorf("ping postgres: %w", err)
	}
	return pool, nil
}

func Migrate(pool *pgxpool.Pool) error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id            BIGSERIAL PRIMARY KEY,
			username      VARCHAR(50)  UNIQUE NOT NULL,
			email         VARCHAR(255) UNIQUE NOT NULL,
			password_hash TEXT         NOT NULL,
			avatar_url    TEXT         DEFAULT '',
			bio           TEXT         DEFAULT '',
			created_at    TIMESTAMPTZ  DEFAULT NOW(),
			updated_at    TIMESTAMPTZ  DEFAULT NOW()
		)`,

		// Публичные X25519 ключи пользователей для E2EE.
		// Приватные ключи НИКОГДА не приходят на сервер.
		`CREATE TABLE IF NOT EXISTS user_keys (
			user_id        BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			public_key_b64 TEXT    NOT NULL,         -- X25519 public key, base64
			key_version    INT     DEFAULT 1,         -- инкрементируется при ротации
			created_at     TIMESTAMPTZ DEFAULT NOW(),
			updated_at     TIMESTAMPTZ DEFAULT NOW()
		)`,

		`CREATE TABLE IF NOT EXISTS chats (
			id         BIGSERIAL PRIMARY KEY,
			name       VARCHAR(100) DEFAULT '',
			is_group   BOOLEAN      DEFAULT false,
			is_e2e     BOOLEAN      DEFAULT true,      -- E2EE включён по умолчанию
			avatar_url TEXT         DEFAULT '',
			created_by BIGINT       REFERENCES users(id) ON DELETE SET NULL,
			created_at TIMESTAMPTZ  DEFAULT NOW()
		)`,

		`CREATE TABLE IF NOT EXISTS chat_members (
			chat_id   BIGINT REFERENCES chats(id)  ON DELETE CASCADE,
			user_id   BIGINT REFERENCES users(id)  ON DELETE CASCADE,
			role      VARCHAR(20) DEFAULT 'member',
			joined_at TIMESTAMPTZ DEFAULT NOW(),
			PRIMARY KEY (chat_id, user_id)
		)`,

		// content_encrypted — ciphertext AES-256-GCM, base64.
		// Для E2EE чатов: сервер НЕ МОЖЕТ расшифровать, ключ только у участников.
		// Для обычных чатов: шифруется server-side ключом из env.
		`CREATE TABLE IF NOT EXISTS messages (
			id                BIGSERIAL PRIMARY KEY,
			chat_id           BIGINT REFERENCES chats(id)    ON DELETE CASCADE,
			user_id           BIGINT REFERENCES users(id)    ON DELETE SET NULL,
			content_encrypted TEXT        NOT NULL,          -- всегда зашифровано
			type              VARCHAR(20) NOT NULL DEFAULT 'text',
			file_url          TEXT        DEFAULT '',
			reply_to_id       BIGINT      REFERENCES messages(id) ON DELETE SET NULL,
			is_e2e            BOOLEAN     DEFAULT true,
			created_at        TIMESTAMPTZ DEFAULT NOW(),
			updated_at        TIMESTAMPTZ DEFAULT NOW(),
			deleted_at        TIMESTAMPTZ
		)`,

		// Refresh-токены хранятся как SHA-256 хеши — не plaintext.
		// Утечка БД не даёт злоумышленнику использовать чужие сессии.
		`CREATE TABLE IF NOT EXISTS refresh_tokens (
			id         BIGSERIAL PRIMARY KEY,
			user_id    BIGINT REFERENCES users(id) ON DELETE CASCADE,
			token_hash TEXT UNIQUE NOT NULL,         -- SHA-256(token), не сам токен
			expires_at TIMESTAMPTZ NOT NULL,
			created_at TIMESTAMPTZ DEFAULT NOW()
		)`,

		`CREATE TABLE IF NOT EXISTS read_receipts (
			chat_id    BIGINT REFERENCES chats(id) ON DELETE CASCADE,
			user_id    BIGINT REFERENCES users(id) ON DELETE CASCADE,
			message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
			read_at    TIMESTAMPTZ DEFAULT NOW(),
			PRIMARY KEY (chat_id, user_id)
		)`,

		// Индексы для производительности
		`CREATE INDEX IF NOT EXISTS idx_messages_chat_id    ON messages(chat_id)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_chat_members_user   ON chat_members(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_refresh_user        ON refresh_tokens(user_id)`,
	}

	for _, q := range migrations {
		if _, err := pool.Exec(context.Background(), q); err != nil {
			return fmt.Errorf("migration failed:\n%s\nerr: %w", q[:min(80, len(q))], err)
		}
	}
	return nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
