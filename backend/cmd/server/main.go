package main

import (
	"fmt"
	"log"
	"strings"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/l1pa7/messenger-app/backend/internal/auth"
	"github.com/l1pa7/messenger-app/backend/internal/chat"
	"github.com/l1pa7/messenger-app/backend/internal/config"
	"github.com/l1pa7/messenger-app/backend/internal/database"
	"github.com/l1pa7/messenger-app/backend/internal/middleware"
	"github.com/l1pa7/messenger-app/backend/internal/security"
	"github.com/redis/go-redis/v9"
)

func main() {
	_ = godotenv.Load()
	cfg := config.Load()

	// ── База данных ──────────────────────────────────────────────────────────
	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("DB: %v", err)
	}
	defer db.Close()
	if err := database.Migrate(db); err != nil {
		log.Fatalf("Migrate: %v", err)
	}
	log.Println("✅ PostgreSQL ready")

	// ── Redis ────────────────────────────────────────────────────────────────
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort),
		Password: cfg.RedisPassword,
	})
	log.Println("✅ Redis ready")

	// ── Ключ шифрования сообщений (server-side AES-256) ─────────────────────
	// Хранится только в env, не в БД.
	// Минимум 32 символа: openssl rand -hex 32
	msgKey := []byte(cfg.MessageEncKey)
	if len(msgKey) < 16 {
		log.Fatal("❌ MESSAGE_ENC_KEY must be at least 16 chars (32+ recommended)")
	}

	// ── WebSocket Hub ────────────────────────────────────────────────────────
	hub := chat.NewHub(db, rdb)

	// ── Rate limiters ────────────────────────────────────────────────────────
	// Аутентификация: 5 попыток/мин (защита от брутфорса)
	authLimiter := security.NewRateLimiter(5.0/60.0, 5)
	// API: 60 запросов/мин на IP
	apiLimiter := security.NewRateLimiter(60.0/60.0, 60)
	// WS: 10 подключений/мин на IP
	wsLimiter := security.NewRateLimiter(10.0/60.0, 10)

	// ── Router ───────────────────────────────────────────────────────────────
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Security headers на всех маршрутах
	r.Use(security.SecurityHeaders())

	// CORS — только свой домен (не AllowAllOrigins!)
	allowedOrigins := strings.Split(cfg.AllowedOrigins, ",")
	r.Use(cors.New(cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		AllowCredentials: true,
	}))

	// ── Auth (публичные) ─────────────────────────────────────────────────────
	authHandler := auth.NewHandler(db, cfg.JWTSecret)
	authGroup := r.Group("/api/auth")
	authGroup.Use(authLimiter.Middleware()) // строгий rate limit
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login",    authHandler.Login)
		authGroup.POST("/refresh",  authHandler.Refresh)
	}

	// ── Защищённые маршруты ──────────────────────────────────────────────────
	authMw := middleware.AuthRequired(cfg.JWTSecret)
	chatHandler := chat.NewHandler(db, rdb, hub, msgKey, cfg.JWTSecret)

	api := r.Group("/api", authMw, apiLimiter.Middleware())
	{
		api.POST("/auth/logout", authHandler.Logout)
		api.GET("/me",           authHandler.Me)

		// Ключи E2EE
		api.GET("/users/:id/key",  authHandler.GetPublicKey)
		api.PUT("/keys",           authHandler.UpdatePublicKey)

		// Чаты
		api.GET("/chats",               chatHandler.GetChats)
		api.POST("/chats",              chatHandler.CreateChat)
		api.GET("/chats/:id/messages",  chatHandler.GetMessages)

		// Поиск
		api.GET("/users/search", chatHandler.SearchUsers)
	}

	// ── WebSocket ────────────────────────────────────────────────────────────
	// НЕТ токена в URL — аутентификация через первый фрейм
	r.GET("/ws", wsLimiter.Middleware(), chatHandler.ServeWS)

	// ── Health check ─────────────────────────────────────────────────────────
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	addr := fmt.Sprintf(":%s", cfg.ServerPort)
	log.Printf("🚀 Server listening on %s", addr)
	log.Printf("🔒 E2EE: X25519 + AES-256-GCM")
	log.Printf("🛡️  Rate limits: auth=5/min, api=60/min, ws=10/min")
	if err := r.Run(addr); err != nil {
		log.Fatalf("Server: %v", err)
	}
}
