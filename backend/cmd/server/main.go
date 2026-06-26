package main

import (
	"fmt"
	"log"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/l1pa7/messenger-app/backend/internal/auth"
	"github.com/l1pa7/messenger-app/backend/internal/chat"
	"github.com/l1pa7/messenger-app/backend/internal/config"
	"github.com/l1pa7/messenger-app/backend/internal/database"
	"github.com/l1pa7/messenger-app/backend/internal/middleware"
	"github.com/redis/go-redis/v9"
)

func main() {
	_ = godotenv.Load()

	cfg := config.Load()

	// Database
	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("DB connect: %v", err)
	}
	defer db.Close()

	if err := database.Migrate(db); err != nil {
		log.Fatalf("Migrate: %v", err)
	}
	log.Println("✅ Database ready")

	// Redis
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort),
		Password: cfg.RedisPassword,
	})
	log.Println("✅ Redis ready")

	// WebSocket Hub
	hub := chat.NewHub(db, rdb)

	// Router
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())
	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		AllowCredentials: true,
	}))

	// Auth routes (public)
	authHandler := auth.NewHandler(db, cfg.JWTSecret)
	authGroup := r.Group("/api/auth")
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login", authHandler.Login)
	}

	// Protected routes
	authMiddleware := middleware.AuthRequired(cfg.JWTSecret)
	chatHandler := chat.NewHandler(db, rdb, hub)

	api := r.Group("/api", authMiddleware)
	{
		api.GET("/me", authHandler.Me)

		api.GET("/chats", chatHandler.GetChats)
		api.POST("/chats", chatHandler.CreateChat)
		api.GET("/chats/:id/messages", chatHandler.GetMessages)

		api.GET("/users/search", chatHandler.SearchUsers)
	}

	// WebSocket endpoint
	r.GET("/ws", authMiddleware, chatHandler.ServeWS)

	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })

	addr := fmt.Sprintf(":%s", cfg.ServerPort)
	log.Printf("🚀 Server running on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Server: %v", err)
	}
}
