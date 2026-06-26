package models

import "time"

type User struct {
	ID        int64     `json:"id" db:"id"`
	Username  string    `json:"username" db:"username"`
	Email     string    `json:"email,omitempty" db:"email"`
	Password  string    `json:"-" db:"password_hash"`
	AvatarURL string    `json:"avatar_url" db:"avatar_url"`
	Bio       string    `json:"bio" db:"bio"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

type Chat struct {
	ID        int64     `json:"id" db:"id"`
	Name      string    `json:"name" db:"name"`
	IsGroup   bool      `json:"is_group" db:"is_group"`
	AvatarURL string    `json:"avatar_url" db:"avatar_url"`
	CreatedBy int64     `json:"created_by" db:"created_by"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`

	// Computed fields
	LastMessage *Message `json:"last_message,omitempty"`
	UnreadCount int      `json:"unread_count"`
	Members     []User   `json:"members,omitempty"`
}

type ChatMember struct {
	ChatID   int64     `json:"chat_id" db:"chat_id"`
	UserID   int64     `json:"user_id" db:"user_id"`
	Role     string    `json:"role" db:"role"` // "admin" | "member"
	JoinedAt time.Time `json:"joined_at" db:"joined_at"`
}

type Message struct {
	ID        int64     `json:"id" db:"id"`
	ChatID    int64     `json:"chat_id" db:"chat_id"`
	UserID    int64     `json:"user_id" db:"user_id"`
	Content   string    `json:"content" db:"content"`
	Type      string    `json:"type" db:"type"` // "text" | "image" | "file"
	FileURL   string    `json:"file_url,omitempty" db:"file_url"`
	ReplyToID *int64    `json:"reply_to_id,omitempty" db:"reply_to_id"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
	DeletedAt *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`

	// Computed
	Author *User    `json:"author,omitempty"`
	ReplyTo *Message `json:"reply_to,omitempty"`
}

// WebSocket message types
type WSMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

type WSMessagePayload struct {
	ChatID  int64  `json:"chat_id"`
	Content string `json:"content"`
	Type    string `json:"type"`
}

type WSTypingPayload struct {
	ChatID int64 `json:"chat_id"`
	UserID int64 `json:"user_id"`
}
