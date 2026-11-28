package quiz

import (
	"context"
	"os"
	"strconv"
	"testing"

	"github.com/ablearning/api/internal/database"
)

// Runs only when TEST_DB_DSN points at a disposable database.
func TestLessonQuizAgainstMySQL(t *testing.T) {
	dsn := os.Getenv("TEST_DB_DSN")
	if dsn == "" {
		t.Skip("TEST_DB_DSN not set; skipping MySQL quiz test")
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
	// Twice: the second run must add nothing.
	for i := 0; i < 2; i++ {
		if err := database.SeedDevQuizzes(db); err != nil {
			t.Fatalf("seed quizzes (run %d): %v", i+1, err)
		}
	}

	var lessonID int64
	if err := db.QueryRow(`SELECT id FROM lessons WHERE type = 'quiz' ORDER BY id LIMIT 1`).Scan(&lessonID); err != nil {
		t.Fatalf("no quiz lesson in the dev seed: %v", err)
	}
	var quizzes int
	_ = db.QueryRow(`SELECT COUNT(*) FROM quizzes WHERE lesson_id = ?`, lessonID).Scan(&quizzes)
	if quizzes != 1 {
		t.Fatalf("quiz lesson has %d quizzes, want exactly 1", quizzes)
	}

	svc := NewService(NewRepository(db), nil)
	ctx := context.Background()
	quiz, err := svc.GetLessonQuiz(ctx, lessonID)
	if err != nil {
		t.Fatalf("get lesson quiz: %v", err)
	}
	if len(quiz.Questions) != 3 || len(quiz.Questions[0].Choices) != 4 {
		t.Fatalf("unexpected quiz shape: %+v", quiz)
	}

	var userID int64
	if err := db.QueryRow(`SELECT id FROM users WHERE email = 'learner@ablearning.co'`).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	// Two right (b, b), one wrong (b instead of a): 2/3 passes a 60% bar.
	answers := map[string]string{}
	for _, q := range quiz.Questions {
		answers[strconv.FormatInt(q.ID, 10)] = "b"
	}
	res, err := svc.Submit(ctx, userID, quiz.ID, answers)
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	if res.Score != 2 || res.Total != 3 || !res.Passed {
		t.Fatalf("result = %d/%d passed=%v, want 2/3 passed", res.Score, res.Total, res.Passed)
	}
}
