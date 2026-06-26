package chat

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/models"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10
	maxMsgSize = 4096
)

type Client struct {
	UserID int64
	conn   *websocket.Conn
	Send   chan []byte
	hub    *Hub
	db     *pgxpool.Pool
}

func NewClient(userID int64, conn *websocket.Conn, hub *Hub, db *pgxpool.Pool) *Client {
	return &Client{
		UserID: userID,
		conn:   conn,
		Send:   make(chan []byte, 256),
		hub:    hub,
		db:     db,
	}
}

// ReadPump reads messages from WebSocket connection
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
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[WS] read error user %d: %v", c.UserID, err)
			}
			break
		}
		c.handleMessage(raw)
	}
}

// WritePump writes messages to WebSocket connection
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

func (c *Client) handleMessage(raw []byte) {
	var msg models.WSMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		return
	}

	switch msg.Type {
	case "message":
		c.handleChatMessage(msg.Payload)
	case "typing":
		c.handleTyping(msg.Payload)
	}
}

func (c *Client) handleChatMessage(payload interface{}) {
	data, _ := json.Marshal(payload)
	var p models.WSMessagePayload
	if err := json.Unmarshal(data, &p); err != nil {
		return
	}

	// Check membership
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

	// Save message to DB
	var msg models.Message
	err := c.db.QueryRow(context.Background(),
		`INSERT INTO messages (chat_id, user_id, content, type)
		 VALUES ($1,$2,$3,$4)
		 RETURNING id, chat_id, user_id, content, type, file_url, created_at`,
		p.ChatID, c.UserID, p.Content, p.Type,
	).Scan(&msg.ID, &msg.ChatID, &msg.UserID, &msg.Content, &msg.Type, &msg.FileURL, &msg.CreatedAt)
	if err != nil {
		log.Printf("[WS] failed to save message: %v", err)
		return
	}

	// Fetch author info
	var author models.User
	c.db.QueryRow(context.Background(),
		`SELECT id, username, avatar_url FROM users WHERE id = $1`, c.UserID,
	).Scan(&author.ID, &author.Username, &author.AvatarURL)
	msg.Author = &author

	// Send to all chat members (including sender for confirmation)
	wsMsg := &models.WSMessage{
		Type:    "message",
		Payload: msg,
	}
	c.hub.BroadcastToChat(p.ChatID, wsMsg, -1)
}

func (c *Client) handleTyping(payload interface{}) {
	data, _ := json.Marshal(payload)
	var p models.WSTypingPayload
	if err := json.Unmarshal(data, &p); err != nil {
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
