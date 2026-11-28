package live

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type Repository struct{ db *sql.DB }

func NewRepository(db *sql.DB) *Repository { return &Repository{db: db} }

const nameExpr = `COALESCE(NULLIF(TRIM(CONCAT(COALESCE(p.first_name, ''), ' ', COALESCE(p.last_name, ''))), ''), 'ผู้สอน')`

// sessionSelect needs the viewer id twice (registered, mine).
const sessionSelect = `SELECT ls.id, ls.title, ` + nameExpr + `, ls.course_id, ls.scheduled_at,
	COALESCE(ls.duration_minutes, 60), COALESCE(ls.price, 0), ls.status,
	(SELECT COUNT(*) FROM live_attendees a WHERE a.live_session_id = ls.id),
	EXISTS (SELECT 1 FROM live_attendees a WHERE a.live_session_id = ls.id AND a.user_id = ?),
	ins.user_id = ?, COALESCE(ls.stream_url, ''), COALESCE(ls.replay_url, '')
	FROM live_sessions ls
	JOIN instructors ins ON ins.id = ls.instructor_id
	LEFT JOIN profiles p ON p.user_id = ins.user_id`

func scanSession(s interface{ Scan(...any) error }) (Session, error) {
	var out Session
	var course sql.NullInt64
	err := s.Scan(&out.ID, &out.Title, &out.Instructor, &course, &out.ScheduledAt,
		&out.DurationMinutes, &out.Price, &out.Status, &out.Attendees, &out.Registered,
		&out.Mine, &out.StreamURL, &out.ReplayURL)
	if course.Valid {
		out.CourseID = &course.Int64
	}
	return out, err
}

func (r *Repository) list(ctx context.Context, viewerID int64, where, order string, args ...any) ([]Session, error) {
	all := append([]any{viewerID, viewerID}, args...)
	rows, err := r.db.QueryContext(ctx, sessionSelect+" WHERE "+where+" ORDER BY "+order+" LIMIT 50", all...)
	if err != nil {
		return nil, fmt.Errorf("list live sessions: %w", err)
	}
	defer rows.Close()
	var out []Session
	for rows.Next() {
		s, err := scanSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *Repository) Upcoming(ctx context.Context, viewerID int64) ([]Session, error) {
	return r.list(ctx, viewerID, "ls.status IN ('upcoming', 'live')", "ls.scheduled_at ASC, ls.id ASC")
}

func (r *Repository) Past(ctx context.Context, viewerID int64) ([]Session, error) {
	return r.list(ctx, viewerID, "ls.status = 'ended'", "ls.scheduled_at DESC, ls.id DESC")
}

func (r *Repository) ByInstructor(ctx context.Context, userID int64) ([]Session, error) {
	return r.list(ctx, userID, "ins.user_id = ?", "ls.scheduled_at DESC, ls.id DESC", userID)
}

func (r *Repository) Get(ctx context.Context, viewerID, id int64) (Session, error) {
	s, err := scanSession(r.db.QueryRowContext(ctx, sessionSelect+" WHERE ls.id = ?", viewerID, viewerID, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Session{}, ErrNotFound
	}
	return s, err
}

func (r *Repository) Questions(ctx context.Context, viewerID, sessionID int64) ([]Question, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT q.id, q.question,
		COALESCE(NULLIF(TRIM(COALESCE(p.first_name, '')), ''), 'ผู้เรียน'),
		COALESCE(q.upvotes, 0),
		EXISTS (SELECT 1 FROM live_question_votes v WHERE v.question_id = q.id AND v.user_id = ?),
		COALESCE(q.answered, 0) = 1, q.user_id = ?, q.created_at
		FROM live_questions q LEFT JOIN profiles p ON p.user_id = q.user_id
		WHERE q.live_session_id = ?
		ORDER BY q.answered ASC, q.upvotes DESC, q.id ASC LIMIT 200`, viewerID, viewerID, sessionID)
	if err != nil {
		return nil, fmt.Errorf("list live questions: %w", err)
	}
	defer rows.Close()
	var out []Question
	for rows.Next() {
		var q Question
		if err := rows.Scan(&q.ID, &q.Question, &q.Author, &q.Upvotes, &q.VotedByMe, &q.Answered, &q.Mine, &q.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, rows.Err()
}

func (r *Repository) SetRegistered(ctx context.Context, userID, sessionID int64, on bool) error {
	var err error
	if on {
		_, err = r.db.ExecContext(ctx, `INSERT IGNORE INTO live_attendees (live_session_id, user_id) VALUES (?, ?)`, sessionID, userID)
	} else {
		_, err = r.db.ExecContext(ctx, `DELETE FROM live_attendees WHERE live_session_id = ? AND user_id = ?`, sessionID, userID)
	}
	return err
}

func (r *Repository) AddQuestion(ctx context.Context, userID, sessionID int64, text string) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO live_questions (live_session_id, user_id, question) VALUES (?, ?, ?)`,
		sessionID, userID, text)
	return err
}

// QuestionSession returns the session a question belongs to.
func (r *Repository) QuestionSession(ctx context.Context, questionID int64) (int64, error) {
	var id int64
	err := r.db.QueryRowContext(ctx, `SELECT live_session_id FROM live_questions WHERE id = ?`, questionID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNotFound
	}
	return id, err
}

// SetVote adds or removes one vote and keeps live_questions.upvotes equal
// to the number of vote rows, in one transaction.
func (r *Repository) SetVote(ctx context.Context, userID, questionID int64, on bool) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	var id int64
	if err := tx.QueryRowContext(ctx, `SELECT id FROM live_questions WHERE id = ? FOR UPDATE`, questionID).Scan(&id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	var res sql.Result
	if on {
		res, err = tx.ExecContext(ctx, `INSERT IGNORE INTO live_question_votes (question_id, user_id) VALUES (?, ?)`, questionID, userID)
	} else {
		res, err = tx.ExecContext(ctx, `DELETE FROM live_question_votes WHERE question_id = ? AND user_id = ?`, questionID, userID)
	}
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		if _, err := tx.ExecContext(ctx, `UPDATE live_questions
			SET upvotes = (SELECT COUNT(*) FROM live_question_votes WHERE question_id = ?) WHERE id = ?`,
			questionID, questionID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (r *Repository) MarkAnswered(ctx context.Context, questionID int64) error {
	_, err := r.db.ExecContext(ctx, `UPDATE live_questions SET answered = 1 WHERE id = ?`, questionID)
	return err
}

// InstructorID maps a user to their instructors row.
func (r *Repository) InstructorID(ctx context.Context, userID int64) (int64, error) {
	var id int64
	err := r.db.QueryRowContext(ctx, `SELECT id FROM instructors WHERE user_id = ?`, userID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNotInstructor
	}
	return id, err
}

func (r *Repository) CourseOwnedBy(ctx context.Context, courseID, instructorID int64) (bool, error) {
	var one int
	err := r.db.QueryRowContext(ctx, `SELECT 1 FROM courses WHERE id = ? AND instructor_id = ?`, courseID, instructorID).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (r *Repository) Create(ctx context.Context, instructorID int64, title string, at time.Time, minutes int, courseID *int64) (int64, error) {
	res, err := r.db.ExecContext(ctx, `INSERT INTO live_sessions (course_id, instructor_id, title, scheduled_at, duration_minutes)
		VALUES (?, ?, ?, ?, ?)`, courseID, instructorID, title, at.UTC(), minutes)
	if err != nil {
		return 0, fmt.Errorf("create live session: %w", err)
	}
	return res.LastInsertId()
}

// UpdateStatus moves the session only if it is still in fromStatus, so two
// concurrent changes cannot both succeed.
func (r *Repository) UpdateStatus(ctx context.Context, id int64, fromStatus string, c StatusChange) (bool, error) {
	res, err := r.db.ExecContext(ctx, `UPDATE live_sessions
		SET status = ?, stream_url = COALESCE(NULLIF(?, ''), stream_url), replay_url = COALESCE(NULLIF(?, ''), replay_url)
		WHERE id = ? AND status = ?`, c.Status, c.StreamURL, c.ReplayURL, id, fromStatus)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n == 1, nil
}
