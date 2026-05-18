-- Migration 003: Add product column to quizzes and position column to questions.
-- product: first-class field for the pharmaceutical product associated with the quiz.
-- position: deterministic ordering of questions within a quiz.

alter table app.quizzes
  add column if not exists product text not null default '';

alter table app.questions
  add column if not exists position integer not null default 0;

create index if not exists questions_quiz_position_idx
  on app.questions (quiz_id, position);

comment on column app.quizzes.product is 'Pharmaceutical product associated with this quiz (e.g. Tavanic, Clexane).';
comment on column app.questions.position is 'Zero-based display order of the question within its quiz.';
