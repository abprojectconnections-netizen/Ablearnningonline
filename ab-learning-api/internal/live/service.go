package live

import (
	"context"
	"time"
)

// Store is what the service needs from the database; *Repository is the
// MySQL implementation.
type Store interface {
	Upcoming(ctx context.Context, viewerID int64) ([]Session, error)
	Past(ctx context.Context, viewerID int64) ([]Session, error)
	ByInstructor(ctx context.Context, userID int64) ([]Session, error)
	Get(ctx context.Context, viewerID, id int64) (Session, error)
	Questions(ctx context.Context, viewerID, sessionID int64) ([]Question, error)
	SetRegistered(ctx context.Context, userID, sessionID int64, on bool) error
	AddQuestion(ctx context.Context, userID, sessionID int64, text string) error
	QuestionSession(ctx context.Context, questionID int64) (int64, error)
	SetVote(ctx context.Context, userID, questionID int64, on bool) error
	MarkAnswered(ctx context.Context, questionID int64) error
	InstructorID(ctx context.Context, userID int64) (int64, error)
	CourseOwnedBy(ctx context.Context, courseID, instructorID int64) (bool, error)
	Create(ctx context.Context, instructorID int64, title string, at time.Time, minutes int, courseID *int64) (int64, error)
	UpdateStatus(ctx context.Context, id int64, fromStatus string, c StatusChange) (bool, error)
}

type Service struct {
	store Store
	now   func() time.Time
}

func NewService(store Store) *Service { return &Service{store: store, now: time.Now} }

// redact hides links from people who have not registered (the instructor
// always sees them).
func redact(s Session) Session {
	if !s.Registered && !s.Mine {
		s.StreamURL, s.ReplayURL = "", ""
	}
	if s.Status != "live" && !s.Mine {
		s.StreamURL = ""
	}
	return s
}

func redactAll(in []Session) []Session {
	out := make([]Session, 0, len(in))
	for _, s := range in {
		out = append(out, redact(s))
	}
	return out
}

func (s *Service) List(ctx context.Context, viewerID int64, past bool) ([]Session, error) {
	var items []Session
	var err error
	if past {
		items, err = s.store.Past(ctx, viewerID)
	} else {
		items, err = s.store.Upcoming(ctx, viewerID)
	}
	if err != nil {
		return nil, err
	}
	return redactAll(items), nil
}

func (s *Service) Detail(ctx context.Context, viewerID, id int64) (Detail, error) {
	session, err := s.store.Get(ctx, viewerID, id)
	if err != nil {
		return Detail{}, err
	}
	questions, err := s.store.Questions(ctx, viewerID, id)
	if err != nil {
		return Detail{}, err
	}
	if questions == nil {
		questions = []Question{}
	}
	return Detail{Session: redact(session), Questions: questions}, nil
}

func (s *Service) Register(ctx context.Context, userID, id int64, on bool) (Detail, error) {
	session, err := s.store.Get(ctx, userID, id)
	if err != nil {
		return Detail{}, err
	}
	if on {
		if session.Status == "ended" || session.Status == "cancelled" {
			return Detail{}, ErrClosed
		}
		if session.Price > 0 {
			return Detail{}, ErrPaid
		}
	}
	if err := s.store.SetRegistered(ctx, userID, id, on); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, userID, id)
}

func (s *Service) Ask(ctx context.Context, userID, id int64, text string) (Detail, error) {
	text, err := cleanText(text, MaxQuestion)
	if err != nil {
		return Detail{}, err
	}
	session, err := s.store.Get(ctx, userID, id)
	if err != nil {
		return Detail{}, err
	}
	if session.Status == "ended" || session.Status == "cancelled" {
		return Detail{}, ErrClosed
	}
	if !session.Registered && !session.Mine {
		return Detail{}, ErrNotRegistered
	}
	if err := s.store.AddQuestion(ctx, userID, id, text); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, userID, id)
}

func (s *Service) Vote(ctx context.Context, userID, questionID int64, on bool) (Detail, error) {
	sessionID, err := s.store.QuestionSession(ctx, questionID)
	if err != nil {
		return Detail{}, err
	}
	session, err := s.store.Get(ctx, userID, sessionID)
	if err != nil {
		return Detail{}, err
	}
	if !session.Registered && !session.Mine {
		return Detail{}, ErrNotRegistered
	}
	if err := s.store.SetVote(ctx, userID, questionID, on); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, userID, sessionID)
}

// ---- instructor ----

func (s *Service) Mine(ctx context.Context, userID int64) ([]Session, error) {
	if _, err := s.store.InstructorID(ctx, userID); err != nil {
		return nil, err
	}
	items, err := s.store.ByInstructor(ctx, userID)
	if items == nil && err == nil {
		items = []Session{}
	}
	return items, err
}

func (s *Service) Schedule(ctx context.Context, userID int64, in NewSession) (Detail, error) {
	instructorID, err := s.store.InstructorID(ctx, userID)
	if err != nil {
		return Detail{}, err
	}
	title, err := cleanText(in.Title, MaxTitle)
	if err != nil {
		return Detail{}, err
	}
	at, err := time.Parse(time.RFC3339, in.ScheduledAt)
	if err != nil || !at.After(s.now()) {
		return Detail{}, ErrInvalid
	}
	minutes := in.DurationMinutes
	if minutes == 0 {
		minutes = 60
	}
	if minutes < 15 || minutes > 480 {
		return Detail{}, ErrInvalid
	}
	if in.CourseID != nil {
		ok, err := s.store.CourseOwnedBy(ctx, *in.CourseID, instructorID)
		if err != nil {
			return Detail{}, err
		}
		if !ok {
			return Detail{}, ErrNotOwner
		}
	}
	id, err := s.store.Create(ctx, instructorID, title, at, minutes, in.CourseID)
	if err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, userID, id)
}

func (s *Service) ChangeStatus(ctx context.Context, userID, id int64, c StatusChange) (Detail, error) {
	session, err := s.store.Get(ctx, userID, id)
	if err != nil {
		return Detail{}, err
	}
	if !session.Mine {
		return Detail{}, ErrNotOwner
	}
	if !canMove(session.Status, c.Status) {
		return Detail{}, ErrTransition
	}
	if !validLink(c.StreamURL) || !validLink(c.ReplayURL) {
		return Detail{}, ErrInvalid
	}
	moved, err := s.store.UpdateStatus(ctx, id, session.Status, c)
	if err != nil {
		return Detail{}, err
	}
	if !moved {
		return Detail{}, ErrTransition // someone changed it first
	}
	return s.Detail(ctx, userID, id)
}

func (s *Service) Answer(ctx context.Context, userID, questionID int64) (Detail, error) {
	sessionID, err := s.store.QuestionSession(ctx, questionID)
	if err != nil {
		return Detail{}, err
	}
	session, err := s.store.Get(ctx, userID, sessionID)
	if err != nil {
		return Detail{}, err
	}
	if !session.Mine {
		return Detail{}, ErrNotOwner
	}
	if err := s.store.MarkAnswered(ctx, questionID); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, userID, sessionID)
}
