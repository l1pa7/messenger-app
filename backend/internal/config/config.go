package config

import (
	"os"
)

type Config struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string

	RedisHost     string
	RedisPort     string
	RedisPassword string

	MinioEndpoint string
	MinioUser     string
	MinioPassword string
	MinioBucket   string

	JWTSecret  string
	ServerPort string
}

func Load() *Config {
	return &Config{
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "messenger"),
		DBPassword: getEnv("DB_PASSWORD", "secret"),
		DBName:     getEnv("DB_NAME", "messenger"),

		RedisHost:     getEnv("REDIS_HOST", "localhost"),
		RedisPort:     getEnv("REDIS_PORT", "6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", "redispass"),

		MinioEndpoint: getEnv("MINIO_ENDPOINT", "localhost:9000"),
		MinioUser:     getEnv("MINIO_USER", "minioadmin"),
		MinioPassword: getEnv("MINIO_PASSWORD", "minioadmin"),
		MinioBucket:   getEnv("MINIO_BUCKET", "messenger-files"),

		JWTSecret:  getEnv("JWT_SECRET", "changeme"),
		ServerPort: getEnv("SERVER_PORT", "8080"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
