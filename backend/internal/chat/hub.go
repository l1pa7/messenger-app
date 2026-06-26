package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/l1pa7/messenger-app/backend/internal/models"
	"github.com/redis/go-redis/v9"
)

type Hub struct {
	mu      sync.RWMutex
	clients map[int64]*Client

	db    *pgxpool.Pool
	redis *redis.Client
}

func NewHub(db *pgxpool.Pool, rdb *redis.Client) *Hub {
	return &Hub{
		clients: make(map[int64]*Client),
		db:      db,
		redis:   rdb,
	}
}

func (h *Hub) Register(client *Client) {
	h.mu.Lock()
	h.clients[client.UserID] = client
	h.mu.Unlock()
	h.redis.Set(context.Background(), onlineKey(client.UserID), "1", 0)
	h.broadcastOnlineStatus(client.UserID, true)
	log.Printf("[Hub] user %d connected (%d total)", client.UserID, len(h.clients))
}

func (h *Hub) Unregister(client *Client) {
	h.mu.Lock()
	delete(h.clients, client.UserID)
	h.mu.Unlock()
	h.redis.Del(context.Background(), onlineKey(client.UserID))
	h.broadcastOnlineStatus(client.UserID, false)
	log.Printf("[Hub] user %d disconnected", client.UserID)
}

func (h *Hub) SendToUser(userID int64, msg *models.WSMessage) {
	h.mu.RLock()
	client, ok := h.clients[userID]
	h.mu.RUnlock()
	if !ok {
		return
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	select {
	case client.Send <- data:
	default:
		// Client buffer full — disconnect
		h.mu.Lock()
		delete(h.clients, userID)
		h.mu.Unlock()
		close(client.Send)
	}
}

func (h *Hub) BroadcastToChat(chatID int64, msg *models.WSMessage, excludeUserID int64) {
	for _, uid := range h.getChatMemberIDs(chatID) {
		if uid != excludeUserID {
			h.SendToUser(uid, msg)
		}
	}
}

func (h *Hub) IsOnline(userID int64) bool {
	val, err := h.redis.Get(context.Background(), onlineKey(userID)).Result()
	return err == nil && val == "1"
}

func (h *Hub) broadcastOnlineStatus(userID int64, online bool) {
	msg := &models.WSMessage{
		Type: "online",
		Payload: map[string]interface{}{
			"user_id": userID,
			"online":  online,
		},
	}
	rows, err := h.db.Query(context.Background(),
		`SELECT DISTINCT cm2.user_id FROM chat_members cm1
		 JOIN chat_members cm2 ON cm1.chat_id = cm2.chat_id
		 WHERE cm1.user_id = $1 AND cm2.user_id != $1`, userID)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var uid int64
		if rows.Scan(&uid) == nil {
			h.SendToUser(uid, msg)
		}
	}
}

func (h *Hub) getChatMemberIDs(chatID int64) []int64 {
	rows, err := h.db.Query(context.Background(),
		`SELECT user_id FROM chat_members WHERE chat_id = $1`, chatID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	return ids
}

func onlineKey(userID int64) string {
	return fmt.Sprintf("online:%d", userID)
}
