package live

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/ablearning/api/internal/database"
)

// Runs only when TEST_DB_DSN points at a disposable database.
func TestLiveAgainstMySQL(t *testing.T) {
	dsn := os.Getenv("TEST_DB_DSN")
	if dsn == "" {
		t.Skip("TEST_DB_DSN not set; skipping MySQL live test")
	}
	if err := database.Migrate(dsn, "../../db/migrations"); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	db, err := database.Open(dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err := database.SeedDev(db); err != nil {
		t.Fatalf("seed: %v", err)
	}

	var teacher int64
	if err := db.QueryRow(`SELECT u.id FROM users u JOIN instructors i ON i.user_id = u.id ORDER BY u.id LIMIT 1`).Scan(&teacher); err != nil {
		t.Fatalf("no instructor in the dev seed: %v", err)
	}
	mkUser := func(tag string) int64 {
		res, err := db.Exec(`INSERT INTO users (role_id, email, password_hash, status)
			SELECT id, ?, 'x', 'active' FROM roles WHERE code = 'learner'`,
			fmt.Sprintf("live-%s-%d@example.test", tag, time.Now().UnixNano()))
		if err != nil {
			t.Fatal(err)
		}
		id, _ := res.LastInsertId()
		return id
	}
	learner, outsider := mkUser("learner"), mkUser("outsider")
	voters := make([]int64, 6)
	for i := range voters {
		voters[i] = mkUser(fmt.Sprintf("v%d", i))
	}

	svc := NewService(NewRepository(db))
	ctx := context.Background()
	at := time.Now().Add(3 * time.Hour).UTC().Truncate(time.Second)
	created, err := svc.Schedule(ctx, teacher, NewSession{Title: "Go concurrency Q&A", ScheduledAt: at.Format(time.RFC3339), DurationMinutes: 45})
	if err != nil {
		t.Fatalf("schedule: %v", err)
	}
	if !created.ScheduledAt.Equal(at) || created.DurationMinutes != 45 || created.Status != "upcoming" {
		t.Fatalf("created = %+v", created.Session)
	}
	if _, err := svc.Schedule(ctx, learner, NewSession{Title: "x", ScheduledAt: at.Format(time.RFC3339)}); !errors.Is(err, ErrNotInstructor) {
		t.Fatalf("learner scheduling: %v", err)
	}

	for _, u := range append([]int64{learner}, voters...) {
		if _, err := svc.Register(ctx, u, created.ID, true); err != nil {
			t.Fatalf("register %d: %v", u, err)
		}
	}
	// Registering twice is harmless.
	d, _ := svc.Register(ctx, learner, created.ID, true)
	if d.Attendees != 7 || !d.Registered {
		t.Fatalf("attendees = %d registered=%v, want 7/true", d.Attendees, d.Registered)
	}

	d, err = svc.Ask(ctx, learner, created.ID, "channel หรือ mutex ดีกว่า?")
	if err != nil {
		t.Fatal(err)
	}
	qid := d.Questions[0].ID

	// Every voter upvotes twice at once: the counter must equal the voters.
	var wg sync.WaitGroup
	for _, v := range voters {
		for k := 0; k < 2; k++ {
			wg.Add(1)
			go func(v int64) {
				defer wg.Done()
				if _, err := svc.Vote(ctx, v, qid, true); err != nil {
					t.Errorf("vote by %d: %v", v, err)
				}
			}(v)
		}
	}
	wg.Wait()
	d, _ = svc.Vote(ctx, voters[0], qid, false)
	if d.Questions[0].Upvotes != len(voters)-1 {
		t.Fatalf("upvotes = %d, want %d", d.Questions[0].Upvotes, len(voters)-1)
	}
	if _, err := svc.Vote(ctx, outsider, qid, true); !errors.Is(err, ErrNotRegistered) {
		t.Fatalf("outsider vote: %v", err)
	}

	if _, err := svc.ChangeStatus(ctx, teacher, created.ID, StatusChange{Status: "live", StreamURL: "https://meet.example/go"}); err != nil {
		t.Fatalf("go live: %v", err)
	}
	mine, _ := svc.Detail(ctx, learner, created.ID)
	theirs, _ := svc.Detail(ctx, outsider, created.ID)
	if mine.StreamURL != "https://meet.example/go" || theirs.StreamURL != "" {
		t.Fatalf("stream link: registered %q, outsider %q", mine.StreamURL, theirs.StreamURL)
	}
	if _, err := svc.ChangeStatus(ctx, teacher, created.ID, StatusChange{Status: "cancelled"}); !errors.Is(err, ErrTransition) {
		t.Fatalf("live -> cancelled must be refused: %v", err)
	}
	if _, err := svc.Answer(ctx, teacher, qid); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ChangeStatus(ctx, teacher, created.ID, StatusChange{Status: "ended", ReplayURL: "https://video.example/go"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Register(ctx, outsider, created.ID, true); !errors.Is(err, ErrClosed) {
		t.Fatalf("register after end: %v", err)
	}
	past, _ := svc.List(ctx, learner, true)
	found := false
	for _, s := range past {
		if s.ID == created.ID {
			found = true
			if s.ReplayURL != "https://video.example/go" || s.StreamURL != "" {
				t.Fatalf("past session links = %+v", s)
			}
		}
	}
	if !found {
		t.Fatal("ended session missing from the past list")
	}
	list, _ := svc.Mine(ctx, teacher)
	if len(list) == 0 || list[0].ID != created.ID {
		t.Fatalf("instructor list = %+v", list)
	}
}
