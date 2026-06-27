package security

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// HashToken хеширует refresh-токен перед хранением в БД.
// Даже если БД утечёт — токены непригодны для использования.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// RotateRefreshToken:
// 1. Проверяет что старый токен существует и не истёк.
// 2. Удаляет его (одноразовое использование).
// 3. Сохраняет хеш нового токена.
// Защита от replay-атак: украденный refresh-токен можно использовать только 1 раз.
func RotateRefreshToken(db *pgxpool.Pool, oldToken, newToken string, userID int64) error {
	oldHash := HashToken(oldToken)
	newHash := HashToken(newToken)

	tx, err := db.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())

	// Удалить старый токен (и проверить что он принадлежит пользователю)
	tag, err := tx.Exec(context.Background(),
		`DELETE FROM refresh_tokens
		 WHERE token_hash = $1 AND user_id = $2 AND expires_at > NOW()`,
		oldHash, userID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		return err
	}

	// Записать новый
	_, err = tx.Exec(context.Background(),
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)`,
		userID, newHash, time.Now().Add(30*24*time.Hour),
	)
	if err != nil {
		return err
	}

	return tx.Commit(context.Background())
}

// SaveRefreshToken сохраняет хеш нового refresh-токена.
func SaveRefreshToken(db *pgxpool.Pool, userID int64, token string) error {
	hash := HashToken(token)
	_, err := db.Exec(context.Background(),
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)
		 ON CONFLICT DO NOTHING`,
		userID, hash, time.Now().Add(30*24*time.Hour),
	)
	return err
}

// InvalidateAllTokens выкидывает все сессии пользователя (logout everywhere).
func InvalidateAllTokens(db *pgxpool.Pool, userID int64) error {
	_, err := db.Exec(context.Background(),
		`DELETE FROM refresh_tokens WHERE user_id = $1`, userID,
	)
	return err
}
