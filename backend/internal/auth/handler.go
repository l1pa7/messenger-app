package auth

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/middleware"
	"github.com/l1pa7/messenger-app/backend/internal/models"
	"github.com/l1pa7/messenger-app/backend/internal/security"
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	db        *pgxpool.Pool
	jwtSecret string
}

func NewHandler(db *pgxpool.Pool, jwtSecret string) *Handler {
	return &Handler{db: db, jwtSecret: jwtSecret}
}

// Register — регистрация нового пользователя.
func (h *Handler) Register(c *gin.Context) {
	var req struct {
		Username  string `json:"username"   binding:"required,min=3,max=50"`
		Email     string `json:"email"      binding:"required,email"`
		Password  string `json:"password"   binding:"required,min=8"`
		PublicKey string `json:"public_key" binding:"required"` // X25519, base64
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// bcrypt cost=12 — достаточно дорого против brute-force, но не замедляет UX
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	tx, err := h.db.Begin(context.Background())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	defer tx.Rollback(context.Background())

	var user models.User
	err = tx.QueryRow(context.Background(),
		`INSERT INTO users (username, email, password_hash)
		 VALUES ($1,$2,$3)
		 RETURNING id, username, email, avatar_url, bio, created_at`,
		req.Username, req.Email, string(hash),
	).Scan(&user.ID, &user.Username, &user.Email,
		&user.AvatarURL, &user.Bio, &user.CreatedAt)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username or email already taken"})
		return
	}

	// Сохранить публичный X25519 ключ пользователя
	_, err = tx.Exec(context.Background(),
		`INSERT INTO user_keys (user_id, public_key_b64) VALUES ($1,$2)`,
		user.ID, req.PublicKey,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save key"})
		return
	}

	if err := tx.Commit(context.Background()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	access, refresh, err := h.issueTokens(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	security.SaveRefreshToken(h.db, user.ID, refresh)

	c.JSON(http.StatusCreated, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

// Login — вход с email + пароль.
func (h *Handler) Login(c *gin.Context) {
	var req struct {
		Email    string `json:"email"    binding:"required,email"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	err := h.db.QueryRow(context.Background(),
		`SELECT id, username, email, password_hash, avatar_url, bio, created_at
		 FROM users WHERE email = $1`,
		req.Email,
	).Scan(&user.ID, &user.Username, &user.Email, &user.Password,
		&user.AvatarURL, &user.Bio, &user.CreatedAt)
	if err != nil {
		// Одинаковый ответ при неверном email И пароле — защита от user enumeration
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	access, refresh, err := h.issueTokens(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	security.SaveRefreshToken(h.db, user.ID, refresh)
	user.Password = ""

	c.JSON(http.StatusOK, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

// Refresh — обновление access token (с ротацией refresh token).
func (h *Handler) Refresh(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Найти токен по хешу
	hash := security.HashToken(req.RefreshToken)
	var userID int64
	err := h.db.QueryRow(context.Background(),
		`SELECT user_id FROM refresh_tokens
		 WHERE token_hash = $1 AND expires_at > NOW()`,
		hash,
	).Scan(&userID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}

	access, newRefresh, err := h.issueTokens(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	// Rotate: старый удаляем, новый сохраняем
	if err := security.RotateRefreshToken(h.db, req.RefreshToken, newRefresh, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rotation failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"access_token":  access,
		"refresh_token": newRefresh,
	})
}

// Logout — инвалидировать все сессии.
func (h *Handler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	security.InvalidateAllTokens(h.db, userID)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// Me — текущий пользователь.
func (h *Handler) Me(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var user models.User
	err := h.db.QueryRow(context.Background(),
		`SELECT id, username, email, avatar_url, bio, created_at FROM users WHERE id = $1`,
		userID,
	).Scan(&user.ID, &user.Username, &user.Email,
		&user.AvatarURL, &user.Bio, &user.CreatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	c.JSON(http.StatusOK, user)
}

// GetPublicKey — получить X25519 public key пользователя для E2EE.
func (h *Handler) GetPublicKey(c *gin.Context) {
	var userID int64
	fmt.Sscanf(c.Param("id"), "%d", &userID)

	var pubKey string
	err := h.db.QueryRow(context.Background(),
		`SELECT public_key_b64 FROM user_keys WHERE user_id = $1`, userID,
	).Scan(&pubKey)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "key not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"user_id": userID, "public_key": pubKey})
}

// UpdatePublicKey — ротация ключа (если устройство потеряно).
func (h *Handler) UpdatePublicKey(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		PublicKey string `json:"public_key" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_, err := h.db.Exec(context.Background(),
		`INSERT INTO user_keys (user_id, public_key_b64, key_version, updated_at)
		 VALUES ($1,$2,1,NOW())
		 ON CONFLICT (user_id) DO UPDATE
		 SET public_key_b64 = $2,
		     key_version    = user_keys.key_version + 1,
		     updated_at     = NOW()`,
		userID, req.PublicKey,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update key"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *Handler) issueTokens(userID int64) (access, refresh string, err error) {
	claims := jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(15 * time.Minute).Unix(),
		"iat":     time.Now().Unix(),
		"type":    "access",
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	access, err = tok.SignedString([]byte(h.jwtSecret))
	if err != nil {
		return "", "", fmt.Errorf("sign token: %w", err)
	}
	refresh = uuid.New().String() // хранится только хеш, не сам токен
	return
}
