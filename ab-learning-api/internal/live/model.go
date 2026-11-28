// Package live runs scheduled live classes: learners browse, register and
// ask or upvote questions; the instructor schedules a session, moves it
// through upcoming → live → ended (or cancelled) and marks questions answered.
//
// No video service is wired yet: stream_url and replay_url are links the
// instructor supplies, shown only to registered learners.
package live

import (
	"errors"
	"net/url"
	"strings"
	"time"
)

var (
	ErrNotFound      = errors.New("live session not found")
	ErrInvalid       = errors.New("invalid request")
	ErrClosed        = errors.New("this session has ended or was cancelled")
	ErrPaid          = errors.New("paid live sessions need checkout, which is not available yet")
	ErrNotRegistered = errors.New("register for this session first")
	ErrNotInstructor = errors.New("only instructors can do this")
	ErrNotOwner      = errors.New("only the session's instructor can do this")
	ErrTransition    = errors.New("that status change is not allowed")
)

const (
	MaxQuestion     = 500
	MaxTitle        = 200
	QuestionsPerMin = 10
)

type Session struct {
	ID              int64     `json:"id"`
	Title           string    `json:"title"`
	Instructor      string    `json:"instructor"`
	CourseID        *int64    `json:"course_id,omitempty"`
	ScheduledAt     time.Time `json:"scheduled_at"`
	DurationMinutes int       `json:"duration_minutes"`
	Price           float64   `json:"price"`
	Status          string    `json:"status"`
	Attendees       int       `json:"attendees"`
	Registered      bool      `json:"registered"`
	Mine            bool      `json:"mine"`
	StreamURL       string    `json:"stream_url,omitempty"`
	ReplayURL       string    `json:"replay_url,omitempty"`
}

type Question struct {
	ID        int64     `json:"id"`
	Question  string    `json:"question"`
	Author    string    `json:"author"`
	Upvotes   int       `json:"upvotes"`
	VotedByMe bool      `json:"voted_by_me"`
	Answered  bool      `json:"answered"`
	Mine      bool      `json:"mine"`
	CreatedAt time.Time `json:"created_at"`
}

type Detail struct {
	Session
	Questions []Question `json:"questions"`
}

type NewSession struct {
	Title           string `json:"title"`
	ScheduledAt     string `json:"scheduled_at"`
	DurationMinutes int    `json:"duration_minutes"`
	CourseID        *int64 `json:"course_id"`
}

type StatusChange struct {
	Status    string `json:"status"`
	StreamURL string `json:"stream_url"`
	ReplayURL string `json:"replay_url"`
}

// allowed lists every legal status change.
var allowed = map[string][]string{
	"upcoming": {"live", "cancelled"},
	"live":     {"ended"},
}

func canMove(from, to string) bool {
	for _, s := range allowed[from] {
		if s == to {
			return true
		}
	}
	return false
}

// validLink accepts an empty value or an absolute http(s) URL.
func validLink(raw string) bool {
	if raw == "" {
		return true
	}
	u, err := url.Parse(raw)
	return err == nil && (u.Scheme == "https" || u.Scheme == "http") && u.Host != "" && len(raw) <= 500
}

func cleanText(s string, max int) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" || len([]rune(s)) > max {
		return "", ErrInvalid
	}
	return s, nil
}
