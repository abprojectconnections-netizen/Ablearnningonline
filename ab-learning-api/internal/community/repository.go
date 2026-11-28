package community

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

type SQLRepository struct{ db *sql.DB }

func NewRepository(db *sql.DB) *SQLRepository { return &SQLRepository{db: db} }

// authorName renders "Somchai K." from the profile, or a neutral fallback.
const authorName = `COALESCE(NULLIF(TRIM(CONCAT(COALESCE(p.first_name, ''), ' ',
	IF(COALESCE(p.last_name, '') = '', '', CONCAT(LEFT(p.last_name, 1), '.')))), ''), 'ผู้เรียน')`

const postSelect = `SELECT cp.id, ` + authorName + `, cp.content, cp.like_count, cp.comment_count,
	EXISTS (SELECT 1 FROM likes l WHERE l.post_id = cp.id AND l.user_id = ?),
	cp.user_id = ?, cp.created_at
	FROM community_posts cp LEFT JOIN profiles p ON p.user_id = cp.user_id`

func scanPost(s interface{ Scan(...any) error }) (Post, error) {
	var p Post
	err := s.Scan(&p.ID, &p.Author, &p.Content, &p.LikeCount, &p.CommentCount, &p.LikedByMe, &p.Mine, &p.CreatedAt)
	return p, err
}

func (r *SQLRepository) ListPosts(ctx context.Context, viewerID int64, limit, offset int) ([]Post, error) {
	rows, err := r.db.QueryContext(ctx, postSelect+` ORDER BY cp.created_at DESC, cp.id DESC LIMIT ? OFFSET ?`,
		viewerID, viewerID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list posts: %w", err)
	}
	defer rows.Close()
	var out []Post
	for rows.Next() {
		p, err := scanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (r *SQLRepository) GetPost(ctx context.Context, viewerID, postID int64) (Post, error) {
	p, err := scanPost(r.db.QueryRowContext(ctx, postSelect+` WHERE cp.id = ?`, viewerID, viewerID, postID))
	if errors.Is(err, sql.ErrNoRows) {
		return Post{}, ErrNotFound
	}
	return p, err
}

func (r *SQLRepository) CreatePost(ctx context.Context, userID int64, content string) (int64, error) {
	res, err := r.db.ExecContext(ctx,
		`INSERT INTO community_posts (user_id, content) VALUES (?, ?)`, userID, content)
	if err != nil {
		return 0, fmt.Errorf("create post: %w", err)
	}
	return res.LastInsertId()
}

func (r *SQLRepository) DeletePost(ctx context.Context, userID, postID int64) error {
	var owner int64
	err := r.db.QueryRowContext(ctx, `SELECT user_id FROM community_posts WHERE id = ?`, postID).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if owner != userID {
		return ErrForbidden
	}
	// likes and comments go with it (ON DELETE CASCADE).
	_, err = r.db.ExecContext(ctx, `DELETE FROM community_posts WHERE id = ? AND user_id = ?`, postID, userID)
	return err
}

func (r *SQLRepository) SetLike(ctx context.Context, userID, postID int64, liked bool) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Lock the post so concurrent likes serialise on its counter.
	var id int64
	err = tx.QueryRowContext(ctx, `SELECT id FROM community_posts WHERE id = ? FOR UPDATE`, postID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}

	var res sql.Result
	var delta string
	if liked {
		res, err = tx.ExecContext(ctx, `INSERT IGNORE INTO likes (post_id, user_id) VALUES (?, ?)`, postID, userID)
		delta = "like_count + 1"
	} else {
		res, err = tx.ExecContext(ctx, `DELETE FROM likes WHERE post_id = ? AND user_id = ?`, postID, userID)
		delta = "GREATEST(like_count, 1) - 1"
	}
	if err != nil {
		return fmt.Errorf("set like: %w", err)
	}
	if n, _ := res.RowsAffected(); n > 0 {
		if _, err := tx.ExecContext(ctx, `UPDATE community_posts SET like_count = `+delta+` WHERE id = ?`, postID); err != nil {
			return fmt.Errorf("update like count: %w", err)
		}
	}
	return tx.Commit()
}

func (r *SQLRepository) ListComments(ctx context.Context, viewerID, postID int64) ([]Comment, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT c.id, `+authorName+`, c.content, c.user_id = ?, c.created_at
		FROM comments c LEFT JOIN profiles p ON p.user_id = c.user_id
		WHERE c.post_id = ? ORDER BY c.created_at ASC, c.id ASC LIMIT 200`, viewerID, postID)
	if err != nil {
		return nil, fmt.Errorf("list comments: %w", err)
	}
	defer rows.Close()
	var out []Comment
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.Author, &c.Content, &c.Mine, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *SQLRepository) AddComment(ctx context.Context, userID, postID int64, content string) (int64, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback() }()
	upd, err := tx.ExecContext(ctx, `UPDATE community_posts SET comment_count = comment_count + 1 WHERE id = ?`, postID)
	if err != nil {
		return 0, fmt.Errorf("update comment count: %w", err)
	}
	if n, _ := upd.RowsAffected(); n == 0 {
		return 0, ErrNotFound
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO comments (post_id, user_id, content) VALUES (?, ?, ?)`, postID, userID, content)
	if err != nil {
		return 0, fmt.Errorf("add comment: %w", err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	return id, tx.Commit()
}
