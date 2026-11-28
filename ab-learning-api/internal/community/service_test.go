package community

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ablearning/api/internal/platform"
)

type memPost struct {
	Post
	owner int64
	likes map[int64]bool
	notes []Comment
}

type memRepo struct {
	posts  []*memPost
	nextID int64
}

func (m *memRepo) find(id int64) *memPost {
	for _, p := range m.posts {
		if p.ID == id {
			return p
		}
	}
	return nil
}

func (m *memRepo) view(p *memPost, viewer int64) Post {
	out := p.Post
	out.LikeCount = len(p.likes)
	out.CommentCount = len(p.notes)
	out.LikedByMe = p.likes[viewer]
	out.Mine = p.owner == viewer
	return out
}

func (m *memRepo) ListPosts(_ context.Context, viewer int64, limit, offset int) ([]Post, error) {
	var out []Post
	for i := len(m.posts) - 1; i >= 0; i-- {
		out = append(out, m.view(m.posts[i], viewer))
	}
	if offset >= len(out) {
		return nil, nil
	}
	out = out[offset:]
	if limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *memRepo) GetPost(_ context.Context, viewer, id int64) (Post, error) {
	p := m.find(id)
	if p == nil {
		return Post{}, ErrNotFound
	}
	return m.view(p, viewer), nil
}

func (m *memRepo) CreatePost(_ context.Context, user int64, content string) (int64, error) {
	m.nextID++
	m.posts = append(m.posts, &memPost{
		Post:  Post{ID: m.nextID, Author: "A.", Content: content, CreatedAt: time.Now()},
		owner: user, likes: map[int64]bool{},
	})
	return m.nextID, nil
}

func (m *memRepo) DeletePost(_ context.Context, user, id int64) error {
	for i, p := range m.posts {
		if p.ID == id {
			if p.owner != user {
				return ErrForbidden
			}
			m.posts = append(m.posts[:i], m.posts[i+1:]...)
			return nil
		}
	}
	return ErrNotFound
}

func (m *memRepo) SetLike(_ context.Context, user, id int64, liked bool) error {
	p := m.find(id)
	if p == nil {
		return ErrNotFound
	}
	if liked {
		p.likes[user] = true
	} else {
		delete(p.likes, user)
	}
	return nil
}

func (m *memRepo) ListComments(_ context.Context, viewer, id int64) ([]Comment, error) {
	p := m.find(id)
	var out []Comment
	for _, c := range p.notes {
		c.Mine = c.ID == viewer // test marker: comment id == author id
		out = append(out, c)
	}
	return out, nil
}

func (m *memRepo) AddComment(_ context.Context, user, id int64, content string) (int64, error) {
	p := m.find(id)
	if p == nil {
		return 0, ErrNotFound
	}
	p.notes = append(p.notes, Comment{ID: user, Content: content})
	return user, nil
}

func TestCreateValidatesAndTrims(t *testing.T) {
	svc := NewService(&memRepo{})
	ctx := context.Background()
	for _, bad := range []string{"", "   ", strings.Repeat("ก", MaxPost+1)} {
		if _, err := svc.Create(ctx, 1, bad); !errors.Is(err, ErrInvalid) {
			t.Errorf("content of %d runes: err = %v, want ErrInvalid", len([]rune(bad)), err)
		}
	}
	p, err := svc.Create(ctx, 1, "  สวัสดีทุกคน  ")
	if err != nil || p.Content != "สวัสดีทุกคน" || !p.Mine {
		t.Fatalf("create = %+v, %v", p, err)
	}
}

func TestLikeIsIdempotentAndPerUser(t *testing.T) {
	svc := NewService(&memRepo{})
	ctx := context.Background()
	p, _ := svc.Create(ctx, 1, "hello")
	for i := 0; i < 2; i++ {
		if _, err := svc.Like(ctx, 2, p.ID, true); err != nil {
			t.Fatal(err)
		}
	}
	got, _ := svc.Like(ctx, 3, p.ID, true)
	if got.LikeCount != 2 || !got.LikedByMe {
		t.Fatalf("after likes by users 2 (twice) and 3: %+v", got)
	}
	got, _ = svc.Like(ctx, 2, p.ID, false)
	if got.LikeCount != 1 {
		t.Fatalf("after unlike: count %d, want 1", got.LikeCount)
	}
	if _, err := svc.Like(ctx, 2, 999, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("like on missing post: %v", err)
	}
}

func TestOnlyTheAuthorDeletes(t *testing.T) {
	svc := NewService(&memRepo{})
	ctx := context.Background()
	p, _ := svc.Create(ctx, 1, "mine")
	if err := svc.Delete(ctx, 2, p.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("other user delete: %v", err)
	}
	if err := svc.Delete(ctx, 1, p.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Comments(ctx, 1, p.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("comments on deleted post: %v", err)
	}
}

func TestCommentsValidateAndReturnTheThread(t *testing.T) {
	svc := NewService(&memRepo{})
	ctx := context.Background()
	p, _ := svc.Create(ctx, 1, "question")
	if _, err := svc.Comment(ctx, 2, p.ID, " "); !errors.Is(err, ErrInvalid) {
		t.Fatalf("blank comment: %v", err)
	}
	thread, err := svc.Comment(ctx, 2, p.ID, "answer")
	if err != nil || len(thread) != 1 || thread[0].Content != "answer" {
		t.Fatalf("thread = %+v, %v", thread, err)
	}
	empty, _ := svc.Create(ctx, 1, "no replies")
	list, _ := svc.Comments(ctx, 1, empty.ID)
	if list == nil {
		t.Fatal("an empty thread must be [] not null")
	}
}

type fakeVerifier struct{}

func (fakeVerifier) Verify(tok string) (int64, string, error) {
	switch tok {
	case "u1":
		return 1, "LEARNER", nil
	case "u2":
		return 2, "LEARNER", nil
	}
	return 0, "", errors.New("bad token")
}

func TestHTTPStatusCodes(t *testing.T) {
	repo := &memRepo{}
	_, _ = repo.CreatePost(context.Background(), 1, "seed")
	mux := http.NewServeMux()
	NewHandler(NewService(repo)).RegisterRoutes(mux, platform.RequireAuth(fakeVerifier{}))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	do := func(method, path, token, body string) int {
		req, _ := http.NewRequest(method, srv.URL+path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	p := "/api/v1/community/posts"
	cases := []struct {
		name, method, path, token, body string
		want                            int
	}{
		{"anonymous feed", "GET", p, "", "", 401},
		{"feed", "GET", p, "u1", "", 200},
		{"empty post", "POST", p, "u1", `{"content":"  "}`, 400},
		{"post", "POST", p, "u1", `{"content":"hi"}`, 201},
		{"like", "POST", p + "/1/like", "u2", "", 200},
		{"unlike", "DELETE", p + "/1/like", "u2", "", 200},
		{"like missing", "POST", p + "/99/like", "u2", "", 404},
		{"bad id", "POST", p + "/x/like", "u2", "", 400},
		{"comment", "POST", p + "/1/comments", "u2", `{"content":"ok"}`, 201},
		{"comments", "GET", p + "/1/comments", "u1", "", 200},
		{"delete by other", "DELETE", p + "/1", "u2", "", 403},
		{"delete by author", "DELETE", p + "/1", "u1", "", 200},
	}
	for _, c := range cases {
		if got := do(c.method, c.path, c.token, c.body); got != c.want {
			t.Errorf("%s: status %d, want %d", c.name, got, c.want)
		}
	}
}
