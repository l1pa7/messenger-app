package chat

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/models"
	"github.com/l1pa7/messenger-app/backend/internal/security"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10
	maxMsgSize = 8192
)

type Client struct {
	UserID    int64
	conn      *websocket.Conn
	Send      chan []byte
	hub       *Hub
	db        *pgxpool.Pool
	msgEncKey []byte // server-side AES ключ (для non-E2EE хранения)
}

func NewClient(userID int64, conn *websocket.Conn, hub *Hub, db *pgxpool.Pool, encKey []byte) *Client {
	return &Client{
		UserID:    userID,
		conn:      conn,
		Send:      make(chan []byte, 256),
		hub:       hub,
		db:        db,
		msgEncKey: encKey,
	}
}

func (c *Client) ReadPump() {
	defer func() {
		c.hub.Unregister(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMsgSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WS] read error user %d: %v", c.UserID, err)
			}
			break
		}
		c.handleIncoming(raw)
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.Send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) handleIncoming(raw []byte) {
	var msg models.WSMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		return
	}
	switch msg.Type {
	case "message":
		c.handleMessage(msg.Payload)
	case "typing":
		c.handleTyping(msg.Payload)
	}
}

func (c *Client) handleMessage(payload interface{}) {
	data, _ := json.Marshal(payload)
	var p struct {
		ChatID  int64  `json:"chat_id"`
		Content string `json:"content"` // уже зашифрован клиентом (E2EE) или plaintext
		Type    string `json:"type"`
		IsE2E   bool   `json:"is_e2e"`
	}
	if err := json.Unmarshal(data, &p); err != nil || p.ChatID == 0 {
		return
	}

	// Проверить членство в чате
	var isMember bool
	c.db.QueryRow(context.Background(),
		`SELECT EXISTS(SELECT 1 FROM chat_members WHERE chat_id=$1 AND user_id=$2)`,
		p.ChatID, c.UserID,
	).Scan(&isMember)
	if !isMember {
		return
	}

	if p.Type == "" {
		p.Type = "text"
	}

	// Что хранить в БД:
	// - E2EE чат: клиент присылает уже зашифрованный ciphertext → сервер хранит as-is
	// - Обычный чат: сервер шифрует сам перед сохранением (AES-256-GCM)
	contentToStore := p.Content
	if !p.IsE2E {
		encrypted, err := security.Encrypt([]byte(p.Content), c.msgEncKey)
		if err != nil {
			log.Printf("[chat] encrypt error: %v", err)
			return
		}
		contentToStore = encrypted
	}

	var msg models.Message
	err := c.db.QueryRow(context.Background(),
		`INSERT INTO messages (chat_id, user_id, content_encrypted, type, is_e2e)
		 VALUES ($1,$2,$3,$4,$5)
		 RETURNING id, chat_id, user_id, content_encrypted, type, file_url, is_e2e, created_at`,
		p.ChatID, c.UserID, contentToStore, p.Type, p.IsE2E,
	).Scan(&msg.ID, &msg.ChatID, &msg.UserID, &msg.Content,
		&msg.Type, &msg.FileURL, &msg.IsE2E, &msg.CreatedAt)
	if err != nil {
		log.Printf("[chat] save message: %v", err)
		return
	}

	// Для E2EE: контент остаётся зашифрованным — клиент сам расшифрует
	// Для обычных: расшифровать перед отправкой через WS
	outContent := msg.Content
	if !p.IsE2E {
		plain, err := security.Decrypt(msg.Content, c.msgEncKey)
		if err == nil {
			outContent = string(plain)
		}
	}

	var author models.User
	c.db.QueryRow(context.Background(),
		`SELECT id, username, avatar_url FROM users WHERE id=$1`, c.UserID,
	).Scan(&author.ID, &author.Username, &author.AvatarURL)
	msg.Author = &author
	msg.Content = outContent

	wsMsg := &models.WSMessage{Type: "message", Payload: msg}
	c.hub.BroadcastToChat(p.ChatID, wsMsg, -1)
}

func (c *Client) handleTyping(payload interface{}) {
	data, _ := json.Marshal(payload)
	var p struct {
		ChatID int64 `json:"chat_id"`
	}
	if json.Unmarshal(data, &p) != nil || p.ChatID == 0 {
		return
	}
	c.hub.BroadcastToChat(p.ChatID, &models.WSMessage{
		Type: "typing",
		Payload: map[string]interface{}{
			"chat_id": p.ChatID,
			"user_id": c.UserID,
		},
	}, c.UserID)
}
