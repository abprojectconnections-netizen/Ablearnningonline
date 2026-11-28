package live

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ablearning/api/internal/platform"
)

// fakeStore keeps one instructor (user 100) and enforces the same rules the
// SQL repository relies on.
type fakeStore struct {
	sessions map[int64]*Session
	owner    map[int64]int64 // session -> instructor user
	attend   map[[2]int64]bool
	qs       map[int64]*Question
	qSession map[int64]int64
	votes    map[[2]int64]bool
	next     int64
}

func newFake() *fakeStore {
	return &fakeStore{
		sessions: map[int64]*Session{}, owner: map[int64]int64{}, attend: map[[2]int64]bool{},
		qs: map[int64]*Question{}, qSession: map[int64]int64{}, votes: map[[2]int64]bool{},
	}
}

func (f *fakeStore) view(viewer int64, s Session) Session {
	n := 0
	for k := range f.attend {
		if k[0] == s.ID {
			n++
		}
	}
	s.Attendees = n
	s.Registered = f.attend[[2]int64{s.ID, viewer}]
	s.Mine = f.owner[s.ID] == viewer
	return s
}

func (f *fakeStore) all(viewer int64, keep func(Session) bool) []Session {
	var out []Session
	for _, s := range f.sessions {
		if keep(*s) {
			out = append(out, f.view(viewer, *s))
		}
	}
	return out
}

func (f *fakeStore) Upcoming(_ context.Context, v int64) ([]Session, error) {
	return f.all(v, func(s Session) bool { return s.Status == "upcoming" || s.Status == "live" }), nil
}
func (f *fakeStore) Past(_ context.Context, v int64) ([]Session, error) {
	return f.all(v, func(s Session) bool { return s.Status == "ended" }), nil
}
func (f *fakeStore) ByInstructor(_ context.Context, u int64) ([]Session, error) {
	return f.all(u, func(s Session) bool { return f.owner[s.ID] == u }), nil
}
func (f *fakeStore) Get(_ context.Context, v, id int64) (Session, error) {
	s, ok := f.sessions[id]
	if !ok {
		return Session{}, ErrNotFound
	}
	return f.view(v, *s), nil
}
func (f *fakeStore) Questions(_ context.Context, v, sid int64) ([]Question, error) {
	var out []Question
	for id, q := range f.qs {
		if f.qSession[id] == sid {
			c := *q
			c.VotedByMe = f.votes[[2]int64{id, v}]
			out = append(out, c)
		}
	}
	return out, nil
}
func (f *fakeStore) SetRegistered(_ context.Context, u, sid int64, on bool) error {
	if on {
		f.attend[[2]int64{sid, u}] = true
	} else {
		delete(f.attend, [2]int64{sid, u})
	}
	return nil
}
func (f *fakeStore) AddQuestion(_ context.Context, u, sid int64, text string) error {
	f.next++
	f.qs[f.next] = &Question{ID: f.next, Question: text}
	f.qSession[f.next] = sid
	return nil
}
func (f *fakeStore) QuestionSession(_ context.Context, qid int64) (int64, error) {
	sid, ok := f.qSession[qid]
	if !ok {
		return 0, ErrNotFound
	}
	return sid, nil
}
func (f *fakeStore) SetVote(_ context.Context, u, qid int64, on bool) error {
	k := [2]int64{qid, u}
	if on {
		f.votes[k] = true
	} else {
		delete(f.votes, k)
	}
	n := 0
	for vk := range f.votes {
		if vk[0] == qid {
			n++
		}
	}
	f.qs[qid].Upvotes = n
	return nil
}
func (f *fakeStore) MarkAnswered(_ context.Context, qid int64) error {
	f.qs[qid].Answered = true
	return nil
}
func (f *fakeStore) InstructorID(_ context.Context, u int64) (int64, error) {
	if u != 100 {
		return 0, ErrNotInstructor
	}
	return 7, nil
}
func (f *fakeStore) CourseOwnedBy(_ context.Context, courseID, _ int64) (bool, error) {
	return courseID == 1, nil
}
func (f *fakeStore) Create(_ context.Context, _ int64, title string, at time.Time, minutes int, courseID *int64) (int64, error) {
	f.next++
	f.sessions[f.next] = &Session{ID: f.next, Title: title, ScheduledAt: at, DurationMinutes: minutes, Status: "upcoming", CourseID: courseID}
	f.owner[f.next] = 100
	return f.next, nil
}
func (f *fakeStore) UpdateStatus(_ context.Context, id int64, from string, c StatusChange) (bool, error) {
	s := f.sessions[id]
	if s.Status != from {
		return false, nil
	}
	s.Status = c.Status
	if c.StreamURL != "" {
		s.StreamURL = c.StreamURL
	}
	if c.ReplayURL != "" {
		s.ReplayURL = c.ReplayURL
	}
	return true, nil
}

func future() string { return time.Now().Add(2 * time.Hour).UTC().Format(time.RFC3339) }

func TestScheduleValidation(t *testing.T) {
	svc := NewService(newFake())
	ctx := context.Background()
	bad := []NewSession{
		{Title: "", ScheduledAt: future()},
		{Title: "x", ScheduledAt: "tomorrow"},
		{Title: "x", ScheduledAt: time.Now().Add(-time.Hour).Format(time.RFC3339)},
		{Title: "x", ScheduledAt: future(), DurationMinutes: 5},
		{Title: "x", ScheduledAt: future(), DurationMinutes: 600},
	}
	for i, in := range bad {
		if _, err := svc.Schedule(ctx, 100, in); !errors.Is(err, ErrInvalid) {
			t.Errorf("case %d: err = %v, want ErrInvalid", i, err)
		}
	}
	other := int64(2)
	if _, err := svc.Schedule(ctx, 100, NewSession{Title: "x", ScheduledAt: future(), CourseID: &other}); !errors.Is(err, ErrNotOwner) {
		t.Errorf("someone else's course: %v", err)
	}
	if _, err := svc.Schedule(ctx, 5, NewSession{Title: "x", ScheduledAt: future()}); !errors.Is(err, ErrNotInstructor) {
		t.Errorf("non-instructor: %v", err)
	}
	d, err := svc.Schedule(ctx, 100, NewSession{Title: " Go Q&A ", ScheduledAt: future()})
	if err != nil || d.Title != "Go Q&A" || d.DurationMinutes != 60 || !d.Mine {
		t.Fatalf("schedule = %+v, %v", d, err)
	}
}

func TestLifecycleLinksAndQuestions(t *testing.T) {
	store := newFake()
	svc := NewService(store)
	ctx := context.Background()
	s, _ := svc.Schedule(ctx, 100, NewSession{Title: "Live", ScheduledAt: future()})

	if _, err := svc.Ask(ctx, 1, s.ID, "hi"); !errors.Is(err, ErrNotRegistered) {
		t.Fatalf("ask before register: %v", err)
	}
	if _, err := svc.Register(ctx, 1, s.ID, true); err != nil {
		t.Fatal(err)
	}
	d, _ := svc.Ask(ctx, 1, s.ID, "  How do goroutines work?  ")
	if len(d.Questions) != 1 || d.Questions[0].Question != "How do goroutines work?" {
		t.Fatalf("questions = %+v", d.Questions)
	}
	qid := d.Questions[0].ID

	if _, err := svc.ChangeStatus(ctx, 1, s.ID, StatusChange{Status: "live"}); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("learner changing status: %v", err)
	}
	if _, err := svc.ChangeStatus(ctx, 100, s.ID, StatusChange{Status: "ended"}); !errors.Is(err, ErrTransition) {
		t.Fatalf("upcoming -> ended: %v", err)
	}
	if _, err := svc.ChangeStatus(ctx, 100, s.ID, StatusChange{Status: "live", StreamURL: "javascript:alert(1)"}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("bad stream link: %v", err)
	}
	if _, err := svc.ChangeStatus(ctx, 100, s.ID, StatusChange{Status: "live", StreamURL: "https://meet.example/abc"}); err != nil {
		t.Fatal(err)
	}

	registered, _ := svc.Detail(ctx, 1, s.ID)
	outsider, _ := svc.Detail(ctx, 2, s.ID)
	if registered.StreamURL == "" || outsider.StreamURL != "" {
		t.Fatalf("stream link must reach registered learners only: %q / %q", registered.StreamURL, outsider.StreamURL)
	}

	if _, err := svc.Vote(ctx, 2, qid, true); !errors.Is(err, ErrNotRegistered) {
		t.Fatalf("outsider vote: %v", err)
	}
	_, _ = svc.Vote(ctx, 1, qid, true)
	d, _ = svc.Vote(ctx, 1, qid, true)
	if d.Questions[0].Upvotes != 1 || !d.Questions[0].VotedByMe {
		t.Fatalf("double vote must count once: %+v", d.Questions[0])
	}
	if _, err := svc.Answer(ctx, 1, qid); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("learner answering: %v", err)
	}
	d, _ = svc.Answer(ctx, 100, qid)
	if !d.Questions[0].Answered {
		t.Fatal("question not marked answered")
	}

	_, _ = svc.ChangeStatus(ctx, 100, s.ID, StatusChange{Status: "ended", ReplayURL: "https://video.example/replay"})
	if _, err := svc.Register(ctx, 3, s.ID, true); !errors.Is(err, ErrClosed) {
		t.Fatalf("register after end: %v", err)
	}
	if _, err := svc.Ask(ctx, 1, s.ID, "late"); !errors.Is(err, ErrClosed) {
		t.Fatalf("ask after end: %v", err)
	}
	past, _ := svc.List(ctx, 1, true)
	if len(past) != 1 || past[0].ReplayURL == "" || past[0].StreamURL != "" {
		t.Fatalf("past list for a registered learner = %+v", past)
	}
}

func TestPaidSessionsCannotBeJoinedYet(t *testing.T) {
	store := newFake()
	svc := NewService(store)
	s, _ := svc.Schedule(context.Background(), 100, NewSession{Title: "Paid", ScheduledAt: future()})
	store.sessions[s.ID].Price = 299
	if _, err := svc.Register(context.Background(), 1, s.ID, true); !errors.Is(err, ErrPaid) {
		t.Fatalf("paid register: %v", err)
	}
}

type fakeVerifier struct{}

func (fakeVerifier) Verify(tok string) (int64, string, error) {
	switch tok {
	case "learner":
		return 1, "LEARNER", nil
	case "teacher":
		return 100, "INSTRUCTOR", nil
	}
	return 0, "", errors.New("bad token")
}

func TestHTTPRoutesAndRoles(t *testing.T) {
	mux := http.NewServeMux()
	NewHandler(NewService(newFake())).RegisterRoutes(mux, platform.RequireAuth(fakeVerifier{}))
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
	create := `{"title":"Go live","scheduled_at":"` + future() + `"}`
	cases := []struct {
		name, method, path, token, body string
		want                            int
	}{
		{"anonymous list", "GET", "/api/v1/live", "", "", 401},
		{"learner cannot schedule", "POST", "/api/v1/instructor/live", "learner", create, 403},
		{"instructor schedules", "POST", "/api/v1/instructor/live", "teacher", create, 201},
		{"list", "GET", "/api/v1/live", "learner", "", 200},
		{"detail", "GET", "/api/v1/live/1", "learner", "", 200},
		{"missing", "GET", "/api/v1/live/99", "learner", "", 404},
		{"ask unregistered", "POST", "/api/v1/live/1/questions", "learner", `{"question":"q"}`, 403},
		{"register", "POST", "/api/v1/live/1/register", "learner", "", 200},
		{"ask", "POST", "/api/v1/live/1/questions", "learner", `{"question":"q"}`, 200},
		{"upvote", "POST", "/api/v1/live/questions/2/upvote", "learner", "", 200},
		{"bad transition", "PATCH", "/api/v1/instructor/live/1/status", "teacher", `{"status":"ended"}`, 409},
		{"go live", "PATCH", "/api/v1/instructor/live/1/status", "teacher", `{"status":"live"}`, 200},
		{"answered", "POST", "/api/v1/instructor/live/questions/2/answered", "teacher", "", 200},
		{"mine", "GET", "/api/v1/instructor/live", "teacher", "", 200},
	}
	for _, c := range cases {
		if got := do(c.method, c.path, c.token, c.body); got != c.want {
			t.Errorf("%s: status %d, want %d", c.name, got, c.want)
		}
	}
}
