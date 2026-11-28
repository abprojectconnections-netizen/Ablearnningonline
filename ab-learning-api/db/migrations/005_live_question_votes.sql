-- One upvote per learner per live question; live_questions.upvotes counts these rows.
CREATE TABLE live_question_votes (
  question_id BIGINT UNSIGNED NOT NULL,
  user_id     BIGINT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (question_id, user_id),
  FOREIGN KEY (question_id) REFERENCES live_questions(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_live_sessions_status_time ON live_sessions (status, scheduled_at);
