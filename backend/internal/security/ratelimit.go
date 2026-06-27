package security

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// limiterEntry хранит состояние лимита для одного IP.
type limiterEntry struct {
	tokens   float64
	lastSeen time.Time
	mu       sync.Mutex
}

// RateLimiter — token bucket rate limiter в памяти.
// Не требует Redis для базового использования.
type RateLimiter struct {
	mu       sync.Mutex
	entries  map[string]*limiterEntry
	rps      float64 // токенов в секунду
	burst    float64 // максимальный запас токенов
	cleanupInterval time.Duration
}

func NewRateLimiter(rps float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		entries: make(map[string]*limiterEntry),
		rps:     rps,
		burst:   float64(burst),
		cleanupInterval: 5 * time.Minute,
	}
	go rl.cleanup()
	return rl
}

func (rl *RateLimiter) Allow(ip string) bool {
	rl.mu.Lock()
	e, ok := rl.entries[ip]
	if !ok {
		e = &limiterEntry{tokens: rl.burst, lastSeen: time.Now()}
		rl.entries[ip] = e
	}
	rl.mu.Unlock()

	e.mu.Lock()
	defer e.mu.Unlock()

	now := time.Now()
	elapsed := now.Sub(e.lastSeen).Seconds()
	e.lastSeen = now

	// Пополнить токены за прошедшее время
	e.tokens = min(rl.burst, e.tokens+elapsed*rl.rps)

	if e.tokens < 1 {
		return false // лимит исчерпан
	}
	e.tokens-- // тратим 1 токен на запрос
	return true
}

// Middleware возвращает gin-мидлвару для ограничения частоты запросов.
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !rl.Allow(ip) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "Слишком много запросов, подождите",
			})
			return
		}
		c.Next()
	}
}

// cleanup периодически удаляет устаревшие записи.
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(rl.cleanupInterval)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		for ip, e := range rl.entries {
			e.mu.Lock()
			if time.Since(e.lastSeen) > 10*time.Minute {
				delete(rl.entries, ip)
			}
			e.mu.Unlock()
		}
		rl.mu.Unlock()
	}
}

func min(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
