package security

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

// WSAuthFrame — первый фрейм, который клиент должен отправить после подключения.
// Токен передаётся ВНУТРИ WebSocket, не в URL — URL логируется везде,
// WebSocket-тело — нет.
type WSAuthFrame struct {
	Type  string `json:"type"`  // должен быть "auth"
	Token string `json:"token"` // Bearer JWT
}

// ValidateWSAuth читает первый фрейм, проверяет JWT и возвращает userID.
// Если что-то не так — закрывает соединение с кодом 4001.
func ValidateWSAuth(conn *websocket.Conn, jwtSecret string) (int64, error) {
	// Клиент должен прислать auth-фрейм в течение 10 секунд
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))

	_, raw, err := conn.ReadMessage()
	if err != nil {
		return 0, err
	}

	var frame WSAuthFrame
	if err := json.Unmarshal(raw, &frame); err != nil || frame.Type != "auth" {
		conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(4001, "first frame must be {type:auth,token:...}"))
		return 0, err
	}

	tokenStr := strings.TrimPrefix(frame.Token, "Bearer ")
	tok, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(jwtSecret), nil
	})
	if err != nil || !tok.Valid {
		conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(4001, "invalid token"))
		return 0, jwt.ErrSignatureInvalid
	}

	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return 0, jwt.ErrTokenMalformed
	}

	userID, ok := claims["user_id"].(float64)
	if !ok {
		return 0, jwt.ErrTokenMalformed
	}

	// Сброс дедлайна после успешной аутентификации
	conn.SetReadDeadline(time.Time{})

	return int64(userID), nil
}

// NoTokenInURL — мидлвара, которая отклоняет WS-запросы с токеном в URL.
func NoTokenInURL(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("token") != "" {
			http.Error(w, "token in URL is forbidden", http.StatusBadRequest)
			return
		}
		next.ServeHTTP(w, r)
	})
}
