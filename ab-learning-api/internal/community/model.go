// Package community is the learners' feed: posts, likes and comments.
// Counters on community_posts change in the same transaction as the rows
// they count, so they never drift.
package community

import (
	"context"
	"errors"
	"strings"
	"time"
)

var (
	ErrNotFound  = errors.New("post not found")
	ErrInvalid   = errors.New("invalid content")
	ErrForbidden = errors.New("only the author can delete this post")
)

const (
	MaxPost      = 2000
	MaxComment   = 1000
	DefaultLimit = 20
	MaxLimit     = 50
)

type Post struct {
	ID           int64     `json:"id"`
	Author       string    `json:"author"`
	Content      string    `json:"content"`
	LikeCount    int       `json:"like_count"`
	CommentCount int       `json:"comment_count"`
	LikedByMe    bool      `json:"liked_by_me"`
	Mine         bool      `json:"mine"`
	CreatedAt    time.Time `json:"created_at"`
}

type Comment struct {
	ID        int64     `json:"id"`
	Author    string    `json:"author"`
	Content   string    `json:"content"`
	Mine      bool      `json:"mine"`
	CreatedAt time.Time `json:"created_at"`
}

type Page struct {
	Items  []Post `json:"items"`
	Limit  int    `json:"limit"`
	Offset int    `json:"offset"`
}

type Repository interface {
	ListPosts(ctx context.Context, viewerID int64, limit, offset int) ([]Post, error)
	GetPost(ctx context.Context, viewerID, postID int64) (Post, error)
	CreatePost(ctx context.Context, userID int64, content string) (int64, error)
	// DeletePost removes the post when userID wrote it; ErrForbidden otherwise.
	DeletePost(ctx context.Context, userID, postID int64) error
	// SetLike likes or unlikes; repeating the same call changes nothing.
	SetLike(ctx context.Context, userID, postID int64, liked bool) error
	ListComments(ctx context.Context, viewerID, postID int64) ([]Comment, error)
	AddComment(ctx context.Context, userID, postID int64, content string) (int64, error)
}

func clean(s string, max int) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" || len([]rune(s)) > max {
		return "", ErrInvalid
	}
	return s, nil
}

func clampPaging(limit, offset int) (int, int) {
	if limit <= 0 {
		limit = DefaultLimit
	}
	if limit > MaxLimit {
		limit = MaxLimit
	}
	if offset < 0 {
		offset = 0
	}
	return limit, offset
}
