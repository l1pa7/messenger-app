package chat

import (
	"context"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/middleware"
	"github.com/l1pa7/messenger-app/backend/internal/models"
	"github.com/l1pa7/messenger-app/backend/internal/security"
	"github.com/redis/go-redis/v9"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Разрешать только наш домен в production
	CheckOrigin: func(r *http.Request) bool {
		// TODO: заменить на проверку r.Header.Get("Origin") == "https://ваш-домен.com"
		return true
	},
}

type Handler struct {
	db        *pgxpool.Pool
	redis     *redis.Client
	hub       *Hub
	msgEncKey []byte
	jwtSecret string
}

func NewHandler(db *pgxpool.Pool, rdb *redis.Client, hub *Hub, encKey []byte, jwtSecret string) *Handler {
	return &Handler{db: db, redis: rdb, hub: hub, msgEncKey: encKey, jwtSecret: jwtSecret}
}

// ServeWS — WebSocket endpoint.
// Токен принимается в ПЕРВОМ ФРЕЙМЕ, не в URL-параметре.
func (h *Handler) ServeWS(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	// Аутентификация через первый WS-фрейм (не URL)
	userID, err := security.ValidateWSAuth(conn, h.jwtSecret)
	if err != nil {
		conn.Close()
		return
	}

	client := NewClient(userID, conn, h.hub, h.db, h.msgEncKey)
	h.hub.Register(client)
	go client.WritePump()
	go client.ReadPump()
}

// GetMessages — история сообщений с расшифровкой (только для non-E2EE чатов).
// E2EE сообщения возвращаются как ciphertext — клиент расшифровывает сам.
func (h *Handler) GetMessages(c *gin.Context) {
	userID := middleware.GetUserID(c)
	chatID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chat id"})
		return
	}

	var isMember bool
	h.db.QueryRow(context.Background(),
		`SELECT EXISTS(SELECT 1 FROM chat_members WHERE chat_id=$1 AND user_id=$2)`,
		chatID, userID,
	).Scan(&isMember)
	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit > 100 {
		limit = 100
	}
	beforeID, _ := strconv.ParseInt(c.Query("before"), 10, 64)

	query := `
		SELECT m.id, m.chat_id, m.user_id, m.content_encrypted, m.type,
		       m.file_url, m.is_e2e, m.created_at,
		       u.username, u.avatar_url
		FROM messages m
		JOIN users u ON m.user_id = u.id
		WHERE m.chat_id = $1 AND m.deleted_at IS NULL`

	var args []interface{}
	args = append(args, chatID)

	if beforeID > 0 {
		query += " AND m.id < $2 ORDER BY m.created_at DESC LIMIT $3"
		args = append(args, beforeID, limit)
	} else {
		query += " ORDER BY m.created_at DESC LIMIT $2"
		args = append(args, limit)
	}

	rows, err := h.db.Query(context.Background(), query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var msg models.Message
		var author models.User
		if err := rows.Scan(
			&msg.ID, &msg.ChatID, &msg.UserID, &msg.Content,
			&msg.Type, &msg.FileURL, &msg.IsE2E, &msg.CreatedAt,
			&author.Username, &author.AvatarURL,
		); err != nil {
			continue
		}
		author.ID = msg.UserID
		msg.Author = &author

		// Расшифровать только non-E2EE сообщения
		// E2EE: клиент получает ciphertext и сам расшифровывает
		if !msg.IsE2E {
			plain, err := security.Decrypt(msg.Content, h.msgEncKey)
			if err == nil {
				msg.Content = string(plain)
			}
		}

		messages = append(messages, msg)
	}

	// Реверс: старое → новое
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	if messages == nil {
		messages = []models.Message{}
	}
	c.JSON(http.StatusOK, messages)
}

// GetChats — список диалогов текущего пользователя.
func (h *Handler) GetChats(c *gin.Context) {
	userID := middleware.GetUserID(c)

	rows, err := h.db.Query(context.Background(), `
		SELECT ch.id, ch.name, ch.is_group, ch.is_e2e, ch.avatar_url, ch.created_at,
		  COALESCE(m.id, 0),
		  COALESCE(m.content_encrypted, ''),
		  COALESCE(m.type, ''),
		  COALESCE(m.user_id, 0),
		  COALESCE(m.is_e2e, true),
		  m.created_at,
		  CASE WHEN ch.is_group THEN ch.name
		       ELSE (SELECT username FROM users WHERE id = (
		         SELECT user_id FROM chat_members
		         WHERE chat_id = ch.id AND user_id != $1 LIMIT 1))
		  END,
		  CASE WHEN ch.is_group THEN ch.avatar_url
		       ELSE (SELECT avatar_url FROM users WHERE id = (
		         SELECT user_id FROM chat_members
		         WHERE chat_id = ch.id AND user_id != $1 LIMIT 1))
		  END
		FROM chats ch
		JOIN chat_members cm ON ch.id = cm.chat_id
		LEFT JOIN LATERAL (
		  SELECT id, content_encrypted, type, user_id, is_e2e, created_at
		  FROM messages
		  WHERE chat_id = ch.id AND deleted_at IS NULL
		  ORDER BY created_at DESC LIMIT 1
		) m ON true
		WHERE cm.user_id = $1
		ORDER BY COALESCE(m.created_at, ch.created_at) DESC
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var chats []gin.H
	for rows.Next() {
		var (
			chatID, msgID, msgUserID                              int64
			chatName, avatarURL, displayName, dispAvatar          string
			isGroup, isE2E, msgIsE2E                              bool
			chatCreated, msgCreated                               interface{}
			msgContent, msgType                                   string
		)
		if err := rows.Scan(
			&chatID, &chatName, &isGroup, &isE2E, &avatarURL, &chatCreated,
			&msgID, &msgContent, &msgType, &msgUserID, &msgIsE2E, &msgCreated,
			&displayName, &dispAvatar,
		); err != nil {
			continue
		}

		// Для превью последнего сообщения:
		// non-E2EE — расшифровать, E2EE — показать заглушку
		lastMsgPreview := msgContent
		if msgIsE2E {
			lastMsgPreview = "🔒 Зашифровано"
		} else if msgContent != "" {
			plain, err := security.Decrypt(msgContent, h.msgEncKey)
			if err == nil {
				lastMsgPreview = string(plain)
			}
		}

		chats = append(chats, gin.H{
			"id":         chatID,
			"name":       displayName,
			"is_group":   isGroup,
			"is_e2e":     isE2E,
			"avatar_url": dispAvatar,
			"last_message": gin.H{
				"id":         msgID,
				"content":    lastMsgPreview,
				"type":       msgType,
				"user_id":    msgUserID,
				"created_at": msgCreated,
			},
		})
	}

	if chats == nil {
		chats = []gin.H{}
	}
	c.JSON(http.StatusOK, chats)
}

// CreateChat — создать диалог или группу.
func (h *Handler) CreateChat(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		Name      string  `json:"name"`
		IsGroup   bool    `json:"is_group"`
		IsE2E     bool    `json:"is_e2e"`
		MemberIDs []int64 `json:"member_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Проверить: direct-чат уже существует?
	if !req.IsGroup && len(req.MemberIDs) == 1 {
		targetID := req.MemberIDs[0]
		var existingID int64
		h.db.QueryRow(context.Background(), `
			SELECT cm1.chat_id FROM chat_members cm1
			JOIN chat_members cm2 ON cm1.chat_id = cm2.chat_id
			JOIN chats ch ON ch.id = cm1.chat_id
			WHERE cm1.user_id = $1 AND cm2.user_id = $2 AND ch.is_group = false
			LIMIT 1
		`, userID, targetID).Scan(&existingID)
		if existingID > 0 {
			c.JSON(http.StatusOK, gin.H{"id": existingID, "existing": true})
			return
		}
	}

	tx, err := h.db.Begin(context.Background())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "tx error"})
		return
	}
	defer tx.Rollback(context.Background())

	var chatID int64
	err = tx.QueryRow(context.Background(),
		`INSERT INTO chats (name, is_group, is_e2e, created_by) VALUES ($1,$2,$3,$4) RETURNING id`,
		req.Name, req.IsGroup, req.IsE2E, userID,
	).Scan(&chatID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "create chat"})
		return
	}

	tx.Exec(context.Background(),
		`INSERT INTO chat_members (chat_id, user_id, role) VALUES ($1,$2,'admin')`,
		chatID, userID)
	for _, mid := range req.MemberIDs {
		if mid != userID {
			tx.Exec(context.Background(),
				`INSERT INTO chat_members (chat_id, user_id) VALUES ($1,$2)`, chatID, mid)
		}
	}

	if err := tx.Commit(context.Background()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": chatID})
}

// SearchUsers — поиск пользователей по имени.
func (h *Handler) SearchUsers(c *gin.Context) {
	userID := middleware.GetUserID(c)
	q := c.Query("q")
	if q == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query required"})
		return
	}
	rows, err := h.db.Query(context.Background(),
		`SELECT id, username, avatar_url, bio FROM users
		 WHERE username ILIKE $1 AND id != $2 LIMIT 20`,
		"%"+q+"%", userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var u models.User
		if rows.Scan(&u.ID, &u.Username, &u.AvatarURL, &u.Bio) == nil {
			users = append(users, u)
		}
	}
	if users == nil {
		users = []models.User{}
	}
	c.JSON(http.StatusOK, users)
}
