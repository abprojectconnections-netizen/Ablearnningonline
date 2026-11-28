package database

import (
	"database/sql"
	"fmt"
	"log"
)

// demoQuestions is the question set given to every seeded quiz lesson.
// Choice ids are stable so graders and tests can rely on them.
var demoQuestions = []struct {
	question, choices, correct, skill string
}{
	{
		"Widget ใดใช้จัดวางลูกในแนวตั้ง?",
		`[{"id":"a","text":"Row"},{"id":"b","text":"Column"},{"id":"c","text":"Stack"},{"id":"d","text":"Wrap"}]`,
		"b", "Layout",
	},
	{
		"ควรใช้ StatefulWidget เมื่อใด?",
		`[{"id":"a","text":"เมื่อหน้าจอไม่เปลี่ยนเลย"},{"id":"b","text":"เมื่อข้อมูลบนหน้าจอเปลี่ยนได้"},{"id":"c","text":"เมื่อต้องการ import package"},{"id":"d","text":"ทุกครั้งที่ใช้ Text"}]`,
		"b", "State",
	},
	{
		"คำสั่งใดสั่งให้ Flutter วาดหน้าจอใหม่?",
		`[{"id":"a","text":"setState()"},{"id":"b","text":"print()"},{"id":"c","text":"dispose()"},{"id":"d","text":"main()"}]`,
		"a", "State",
	},
}

// SeedDevQuizzes gives every quiz-type lesson that has no quiz a demo one.
// It only adds rows, never changes existing ones, and is safe to run on
// every start. Like SeedDev it must only run with SEED_DEV=true.
func SeedDevQuizzes(db *sql.DB) error {
	rows, err := db.Query(`
		SELECT l.id, s.course_id, l.title
		FROM lessons l
		JOIN course_sections s ON s.id = l.section_id
		WHERE l.type = 'quiz'
		  AND NOT EXISTS (SELECT 1 FROM quizzes q WHERE q.lesson_id = l.id)`)
	if err != nil {
		return fmt.Errorf("find quiz lessons: %w", err)
	}
	type target struct {
		lessonID, courseID int64
		title              string
	}
	var targets []target
	for rows.Next() {
		var t target
		if err := rows.Scan(&t.lessonID, &t.courseID, &t.title); err != nil {
			rows.Close()
			return err
		}
		targets = append(targets, t)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, t := range targets {
		if err := seedQuiz(db, t.lessonID, t.courseID, t.title); err != nil {
			return err
		}
	}
	if len(targets) > 0 {
		log.Printf("dev seed: added demo quizzes for %d quiz lesson(s)", len(targets))
	}
	return nil
}

func seedQuiz(db *sql.DB, lessonID, courseID int64, title string) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	res, err := tx.Exec(`INSERT INTO quizzes (course_id, lesson_id, title, pass_score_pct) VALUES (?, ?, ?, 60)`,
		courseID, lessonID, title)
	if err != nil {
		return fmt.Errorf("insert quiz: %w", err)
	}
	quizID, err := res.LastInsertId()
	if err != nil {
		return err
	}
	for i, q := range demoQuestions {
		if _, err := tx.Exec(`INSERT INTO quiz_questions (quiz_id, question, choices, correct_choice, skill_tag, sort_order)
			VALUES (?, ?, ?, ?, ?, ?)`, quizID, q.question, q.choices, q.correct, q.skill, i+1); err != nil {
			return fmt.Errorf("insert quiz question: %w", err)
		}
	}
	return tx.Commit()
}
