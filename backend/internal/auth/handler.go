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
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	db        *pgxpool.Pool
	jwtSecret string
}

func NewHandler(db *pgxpool.Pool, jwtSecret string) *Handler {
	return &Handler{db: db, jwtSecret: jwtSecret}
}

func (h *Handler) Register(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required,min=3,max=50"`
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	var user models.User
	err = h.db.QueryRow(context.Background(),
		`INSERT INTO users (username, email, password_hash) VALUES ($1,$2,$3)
		 RETURNING id, username, email, avatar_url, bio, created_at, updated_at`,
		req.Username, req.Email, string(hash),
	).Scan(&user.ID, &user.Username, &user.Email, &user.AvatarURL, &user.Bio, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username or email already taken"})
		return
	}

	access, refresh, err := h.generateTokens(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate tokens"})
		return
	}

	h.saveRefreshToken(user.ID, refresh)

	c.JSON(http.StatusCreated, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

func (h *Handler) Login(c *gin.Context) {
	var req struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	err := h.db.QueryRow(context.Background(),
		`SELECT id, username, email, password_hash, avatar_url, bio, created_at, updated_at
		 FROM users WHERE email = $1`,
		req.Email,
	).Scan(&user.ID, &user.Username, &user.Email, &user.Password, &user.AvatarURL, &user.Bio, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	access, refresh, err := h.generateTokens(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate tokens"})
		return
	}

	h.saveRefreshToken(user.ID, refresh)
	user.Password = ""

	c.JSON(http.StatusOK, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

func (h *Handler) Me(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	err := h.db.QueryRow(context.Background(),
		`SELECT id, username, email, avatar_url, bio, created_at, updated_at FROM users WHERE id = $1`,
		userID,
	).Scan(&user.ID, &user.Username, &user.Email, &user.AvatarURL, &user.Bio, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

func (h *Handler) generateTokens(userID int64) (access, refresh string, err error) {
	// Access token: 15 minutes
	accessClaims := jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(15 * time.Minute).Unix(),
		"type":    "access",
	}
	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	access, err = accessToken.SignedString([]byte(h.jwtSecret))
	if err != nil {
		return "", "", fmt.Errorf("sign access token: %w", err)
	}

	// Refresh token: 30 days
	refresh = uuid.New().String()
	return access, refresh, nil
}

func (h *Handler) saveRefreshToken(userID int64, token string) {
	h.db.Exec(context.Background(),
		`INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
		userID, token, time.Now().Add(30*24*time.Hour),
	)
}
