package community

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/ablearning/api/internal/database"
)

// Runs only when TEST_DB_DSN points at a disposable database.
func TestCommunityAgainstMySQL(t *testing.T) {
	dsn := os.Getenv("TEST_DB_DSN")
	if dsn == "" {
		t.Skip("TEST_DB_DSN not set; skipping MySQL community test")
	}
	if err := database.Migrate(dsn, "../../db/migrations"); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	db, err := database.Open(dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mkUser := func(tag string) int64 {
		res, err := db.Exec(`INSERT INTO users (role_id, email, password_hash, status)
			SELECT id, ?, 'x', 'active' FROM roles WHERE code = 'learner'`,
			fmt.Sprintf("community-%s-%d@example.test", tag, time.Now().UnixNano()))
		if err != nil {
			t.Fatal(err)
		}
		id, _ := res.LastInsertId()
		if _, err := db.Exec(`INSERT INTO profiles (user_id, first_name, last_name) VALUES (?, 'สมชาย', 'ใจดี')`, id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	author := mkUser("author")
	likers := make([]int64, 8)
	for i := range likers {
		likers[i] = mkUser(fmt.Sprintf("l%d", i))
	}

	svc := NewService(NewRepository(db))
	ctx := context.Background()
	post, err := svc.Create(ctx, author, "  แชร์โน้ต SQL  ")
	if err != nil {
		t.Fatal(err)
	}
	if post.Content != "แชร์โน้ต SQL" || post.Author != "สมชาย ใ." || !post.Mine {
		t.Fatalf("created post = %+v", post)
	}

	// Each liker likes twice at the same time: the counter must end at 8.
	var wg sync.WaitGroup
	for _, u := range likers {
		for k := 0; k < 2; k++ {
			wg.Add(1)
			go func(u int64) {
				defer wg.Done()
				if _, err := svc.Like(ctx, u, post.ID, true); err != nil {
					t.Errorf("like by %d: %v", u, err)
				}
			}(u)
		}
	}
	wg.Wait()
	got, _ := svc.Like(ctx, likers[0], post.ID, false)
	if got.LikeCount != 7 || got.LikedByMe {
		t.Fatalf("after 8 likers and one unlike: %+v, want count 7", got)
	}
	var rows int
	_ = db.QueryRow(`SELECT COUNT(*) FROM likes WHERE post_id = ?`, post.ID).Scan(&rows)
	if rows != 7 {
		t.Fatalf("likes rows = %d, want 7 (counter and rows must agree)", rows)
	}

	if _, err := svc.Comment(ctx, likers[1], post.ID, "ขอบคุณครับ"); err != nil {
		t.Fatal(err)
	}
	thread, _ := svc.Comment(ctx, author, post.ID, "ยินดีครับ")
	if len(thread) != 2 || !thread[1].Mine || thread[0].Mine {
		t.Fatalf("thread as author = %+v", thread)
	}
	feed, _ := svc.Feed(ctx, author, 50, 0)
	found := false
	for _, p := range feed.Items {
		if p.ID == post.ID {
			found = true
			if p.CommentCount != 2 || p.LikeCount != 7 {
				t.Fatalf("feed counters = %+v", p)
			}
		}
	}
	if !found {
		t.Fatal("new post missing from the feed")
	}

	if err := svc.Delete(ctx, likers[2], post.ID); err != ErrForbidden {
		t.Fatalf("delete by non-author: %v", err)
	}
	if err := svc.Delete(ctx, author, post.ID); err != nil {
		t.Fatal(err)
	}
	_ = db.QueryRow(`SELECT COUNT(*) FROM comments WHERE post_id = ?`, post.ID).Scan(&rows)
	if rows != 0 {
		t.Fatalf("comments left after delete: %d", rows)
	}
}
