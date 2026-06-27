package security

import "github.com/gin-gonic/gin"

// SecurityHeaders добавляет заголовки защиты, аналогичные best-practice OWASP.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Запрет встройки в iframe — защита от clickjacking
		c.Header("X-Frame-Options", "DENY")
		// Браузер не угадывает MIME — защита от MIME sniffing
		c.Header("X-Content-Type-Options", "nosniff")
		// Строгий HTTPS на 2 года с subdomains
		c.Header("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
		// Ограничить referrer — не светить URL в логах сторонних сервисов
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		// Отключить все лишние браузерные фичи
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		// Content-Security-Policy: только свой домен
		c.Header("Content-Security-Policy",
			"default-src 'self'; "+
				"connect-src 'self' wss:; "+
				"img-src 'self' data: blob:; "+
				"style-src 'self' 'unsafe-inline'; "+
				"script-src 'self'")
		// Убрать "X-Powered-By" и прочую утечку технологий
		c.Header("X-Powered-By", "")
		c.Header("Server", "")
		c.Next()
	}
}
