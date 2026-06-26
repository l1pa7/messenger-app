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
			id           BIGSERIAL PRIMARY KEY,
			username     VARCHAR(50)  UNIQUE NOT NULL,
			email        VARCHAR(255) UNIQUE NOT NULL,
			password_hash TEXT        NOT NULL,
			avatar_url   TEXT         DEFAULT '',
			bio          TEXT         DEFAULT '',
			created_at   TIMESTAMPTZ  DEFAULT NOW(),
			updated_at   TIMESTAMPTZ  DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS chats (
			id         BIGSERIAL PRIMARY KEY,
			name       VARCHAR(100) DEFAULT '',
			is_group   BOOLEAN      DEFAULT false,
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
		`CREATE TABLE IF NOT EXISTS messages (
			id          BIGSERIAL PRIMARY KEY,
			chat_id     BIGINT REFERENCES chats(id)    ON DELETE CASCADE,
			user_id     BIGINT REFERENCES users(id)    ON DELETE SET NULL,
			content     TEXT        NOT NULL DEFAULT '',
			type        VARCHAR(20) NOT NULL DEFAULT 'text',
			file_url    TEXT        DEFAULT '',
			reply_to_id BIGINT      REFERENCES messages(id) ON DELETE SET NULL,
			created_at  TIMESTAMPTZ DEFAULT NOW(),
			updated_at  TIMESTAMPTZ DEFAULT NOW(),
			deleted_at  TIMESTAMPTZ
		)`,
		`CREATE TABLE IF NOT EXISTS read_receipts (
			chat_id    BIGINT REFERENCES chats(id) ON DELETE CASCADE,
			user_id    BIGINT REFERENCES users(id) ON DELETE CASCADE,
			message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
			read_at    TIMESTAMPTZ DEFAULT NOW(),
			PRIMARY KEY (chat_id, user_id)
		)`,
		`CREATE TABLE IF NOT EXISTS refresh_tokens (
			id         BIGSERIAL PRIMARY KEY,
			user_id    BIGINT REFERENCES users(id) ON DELETE CASCADE,
			token      TEXT UNIQUE NOT NULL,
			expires_at TIMESTAMPTZ NOT NULL,
			created_at TIMESTAMPTZ DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)`,
		`CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON chat_members(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id)`,
	}

	for _, query := range migrations {
		if _, err := pool.Exec(context.Background(), query); err != nil {
			return fmt.Errorf("migration failed: %w\nQuery: %s", err, query)
		}
	}
	return nil
}
