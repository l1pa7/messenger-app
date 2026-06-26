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
	"github.com/redis/go-redis/v9"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type Handler struct {
	db    *pgxpool.Pool
	redis *redis.Client
	hub   *Hub
}

func NewHandler(db *pgxpool.Pool, rdb *redis.Client, hub *Hub) *Handler {
	return &Handler{db: db, redis: rdb, hub: hub}
}

// ServeWS upgrades HTTP to WebSocket
func (h *Handler) ServeWS(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	userID := middleware.GetUserID(c)
	client := NewClient(userID, conn, h.hub, h.db)
	h.hub.Register(client)

	go client.WritePump()
	go client.ReadPump()
}

// GetChats returns all chats for current user
func (h *Handler) GetChats(c *gin.Context) {
	userID := middleware.GetUserID(c)

	rows, err := h.db.Query(context.Background(), `
		SELECT DISTINCT ON (ch.id) ch.id, ch.name, ch.is_group, ch.avatar_url, ch.created_at,
		  m.id, m.content, m.type, m.user_id, m.created_at,
		  CASE WHEN ch.is_group THEN ch.name
		       ELSE (SELECT username FROM users WHERE id = (
		         SELECT user_id FROM chat_members WHERE chat_id = ch.id AND user_id != $1 LIMIT 1
		       ))
		  END as display_name,
		  CASE WHEN ch.is_group THEN ch.avatar_url
		       ELSE (SELECT avatar_url FROM users WHERE id = (
		         SELECT user_id FROM chat_members WHERE chat_id = ch.id AND user_id != $1 LIMIT 1
		       ))
		  END as display_avatar
		FROM chats ch
		JOIN chat_members cm ON ch.id = cm.chat_id
		LEFT JOIN messages m ON m.id = (
		  SELECT id FROM messages WHERE chat_id = ch.id AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1
		)
		WHERE cm.user_id = $1
		ORDER BY ch.id, COALESCE(m.created_at, ch.created_at) DESC
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var chats []gin.H
	for rows.Next() {
		var (
			chatID, msgID, msgUserID                  int64
			chatName, avatarURL, displayName, dispAvatar string
			isGroup                                   bool
			chatCreated, msgCreated                   interface{}
			msgContent, msgType                       string
		)
		if err := rows.Scan(&chatID, &chatName, &isGroup, &avatarURL, &chatCreated,
			&msgID, &msgContent, &msgType, &msgUserID, &msgCreated,
			&displayName, &dispAvatar); err != nil {
			continue
		}
		chats = append(chats, gin.H{
			"id":         chatID,
			"name":       displayName,
			"is_group":   isGroup,
			"avatar_url": dispAvatar,
			"last_message": gin.H{
				"id":         msgID,
				"content":    msgContent,
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

// GetMessages returns paginated messages for a chat
func (h *Handler) GetMessages(c *gin.Context) {
	userID := middleware.GetUserID(c)
	chatID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chat id"})
		return
	}

	// Check membership
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

	var rows interface{ Next() bool; Scan(...interface{}) error; Close() }
	if beforeID > 0 {
		rows, err = h.db.Query(context.Background(), `
			SELECT m.id, m.chat_id, m.user_id, m.content, m.type, m.file_url, m.created_at,
			  u.username, u.avatar_url
			FROM messages m JOIN users u ON m.user_id = u.id
			WHERE m.chat_id = $1 AND m.deleted_at IS NULL AND m.id < $2
			ORDER BY m.created_at DESC LIMIT $3
		`, chatID, beforeID, limit)
	} else {
		rows, err = h.db.Query(context.Background(), `
			SELECT m.id, m.chat_id, m.user_id, m.content, m.type, m.file_url, m.created_at,
			  u.username, u.avatar_url
			FROM messages m JOIN users u ON m.user_id = u.id
			WHERE m.chat_id = $1 AND m.deleted_at IS NULL
			ORDER BY m.created_at DESC LIMIT $2
		`, chatID, limit)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var msg models.Message
		var author models.User
		if err := rows.Scan(&msg.ID, &msg.ChatID, &msg.UserID, &msg.Content, &msg.Type,
			&msg.FileURL, &msg.CreatedAt, &author.Username, &author.AvatarURL); err != nil {
			continue
		}
		author.ID = msg.UserID
		msg.Author = &author
		messages = append(messages, msg)
	}

	// Reverse so oldest is first
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	if messages == nil {
		messages = []models.Message{}
	}
	c.JSON(http.StatusOK, messages)
}

// CreateChat creates a direct or group chat
func (h *Handler) CreateChat(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		Name      string  `json:"name"`
		IsGroup   bool    `json:"is_group"`
		MemberIDs []int64 `json:"member_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// For direct chat: check if already exists
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "begin tx"})
		return
	}
	defer tx.Rollback(context.Background())

	var chatID int64
	err = tx.QueryRow(context.Background(),
		`INSERT INTO chats (name, is_group, created_by) VALUES ($1,$2,$3) RETURNING id`,
		req.Name, req.IsGroup, userID,
	).Scan(&chatID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "create chat"})
		return
	}

	// Add creator
	tx.Exec(context.Background(),
		`INSERT INTO chat_members (chat_id, user_id, role) VALUES ($1,$2,'admin')`,
		chatID, userID,
	)
	// Add members
	for _, mid := range req.MemberIDs {
		if mid != userID {
			tx.Exec(context.Background(),
				`INSERT INTO chat_members (chat_id, user_id) VALUES ($1,$2)`,
				chatID, mid,
			)
		}
	}

	if err := tx.Commit(context.Background()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit tx"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": chatID})
}

// SearchUsers searches users by username
func (h *Handler) SearchUsers(c *gin.Context) {
	userID := middleware.GetUserID(c)
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query required"})
		return
	}

	rows, err := h.db.Query(context.Background(),
		`SELECT id, username, avatar_url, bio FROM users
		 WHERE username ILIKE $1 AND id != $2 LIMIT 20`,
		"%"+query+"%", userID,
	)
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
