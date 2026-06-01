-- 010_reports_filters.sql
-- Phase: Reports MECE fix. Wire `quiz_filter`, `starts_at_filter`, and
-- `ends_at_filter` through the three intelligence RPCs so the Reports page
-- form actually constrains what its panels and CSV exports return.
--
-- Before this migration:
--   * knowledge_gaps honored specialty / facility / session only.
--   * facility_performance honored nothing besides created_by.
--   * treatment_perception_trends honored nothing besides created_by.
--   Result: the Reports UI offered a Quiz dropdown + date pickers that the
--   server silently ignored on the intelligence panels — admins saw global
--   data even though their filter showed "applied".
--
-- Backward compatibility: the new parameters all default to NULL so any
-- existing caller that does not pass them keeps working unchanged. We
-- drop the prior signatures first to avoid PostgREST overload ambiguity.

drop function if exists app.knowledge_gaps(integer, text, text, uuid, uuid);
drop function if exists app.facility_performance(integer, uuid);
drop function if exists app.treatment_perception_trends(integer, uuid);

create or replace function app.knowledge_gaps(
  limit_count integer default 10,
  specialty_filter text default null,
  facility_filter text default null,
  session_filter uuid default null,
  created_by_filter uuid default null,
  quiz_filter uuid default null,
  starts_at_filter timestamptz default null,
  ends_at_filter timestamptz default null
)
returns table (
  question_id uuid,
  quiz_title text,
  prompt text,
  tags text[],
  attempts_count bigint,
  incorrect_count bigint,
  incorrect_rate numeric
)
language sql
stable
as $$
  select
    q.id as question_id,
    quiz.title as quiz_title,
    q.prompt,
    q.tags,
    count(a.id)::bigint as attempts_count,
    count(*) filter (where a.is_correct = false)::bigint as incorrect_count,
    round(
      (count(*) filter (where a.is_correct = false)::numeric / nullif(count(a.id)::numeric, 0)) * 100,
      2
    ) as incorrect_rate
  from app.answers a
  join app.questions q on q.id = a.question_id
  join app.quizzes quiz on quiz.id = q.quiz_id
  join app.attempts att on att.id = a.attempt_id
  join app.users u on u.id = att.user_id
  left join app.sessions s on s.id = att.session_id
  where (specialty_filter is null or u.specialty = specialty_filter)
    and (facility_filter is null or u.facility = facility_filter)
    and (session_filter is null or att.session_id = session_filter)
    and (created_by_filter is null or s.created_by = created_by_filter)
    and (quiz_filter is null or att.quiz_id = quiz_filter)
    and (starts_at_filter is null or att.started_at >= starts_at_filter)
    and (ends_at_filter is null or att.started_at <= ends_at_filter)
  group by q.id, quiz.title, q.prompt, q.tags
  having count(a.id) > 0
  order by incorrect_rate desc, incorrect_count desc, prompt asc
  limit greatest(limit_count, 1);
$$;

create or replace function app.facility_performance(
  limit_count integer default 20,
  created_by_filter uuid default null,
  quiz_filter uuid default null,
  session_filter uuid default null,
  specialty_filter text default null,
  facility_filter text default null,
  starts_at_filter timestamptz default null,
  ends_at_filter timestamptz default null
)
returns table (
  facility text,
  average_score numeric,
  completed_attempts bigint,
  ranked_participants bigint,
  completion_rate numeric
)
language sql
stable
as $$
  with facility_attempts as (
    select
      u.facility,
      u.specialty,
      a.id,
      a.mode,
      a.score,
      a.started_at,
      a.completed_at,
      a.user_id,
      a.quiz_id,
      a.session_id,
      s.created_by
    from app.attempts a
    join app.users u on u.id = a.user_id
    left join app.sessions s on s.id = a.session_id
    where (created_by_filter is null or s.created_by = created_by_filter)
      and (quiz_filter is null or a.quiz_id = quiz_filter)
      and (session_filter is null or a.session_id = session_filter)
      and (specialty_filter is null or u.specialty = specialty_filter)
      and (facility_filter is null or u.facility = facility_filter)
      and (starts_at_filter is null or a.started_at >= starts_at_filter)
      and (ends_at_filter is null or a.started_at <= ends_at_filter)
  )
  select
    facility,
    round(avg(score::numeric) filter (where completed_at is not null), 2) as average_score,
    count(*) filter (where completed_at is not null)::bigint as completed_attempts,
    count(distinct user_id) filter (where mode = 'ranked' and completed_at is not null)::bigint as ranked_participants,
    round(
      (count(*) filter (where completed_at is not null)::numeric / nullif(count(*)::numeric, 0)) * 100,
      2
    ) as completion_rate
  from facility_attempts
  group by facility
  order by average_score asc nulls last, completed_attempts desc, facility asc
  limit greatest(limit_count, 1);
$$;

create or replace function app.treatment_perception_trends(
  limit_count integer default 10,
  created_by_filter uuid default null,
  quiz_filter uuid default null,
  session_filter uuid default null,
  specialty_filter text default null,
  facility_filter text default null,
  starts_at_filter timestamptz default null,
  ends_at_filter timestamptz default null
)
returns table (
  clinical_area text,
  prompt text,
  most_selected_wrong_option text,
  wrong_selection_count bigint,
  incorrect_rate numeric
)
language sql
stable
as $$
  with tagged_answers as (
    select
      q.clinical_area,
      q.prompt,
      a.selected_option_text,
      a.is_correct
    from app.answers a
    join app.questions q on q.id = a.question_id
    join app.attempts att on att.id = a.attempt_id
    join app.users u on u.id = att.user_id
    left join app.sessions s on s.id = att.session_id
    where 'treatment-perception' = any(q.tags)
      and (created_by_filter is null or s.created_by = created_by_filter)
      and (quiz_filter is null or att.quiz_id = quiz_filter)
      and (session_filter is null or att.session_id = session_filter)
      and (specialty_filter is null or u.specialty = specialty_filter)
      and (facility_filter is null or u.facility = facility_filter)
      and (starts_at_filter is null or att.started_at >= starts_at_filter)
      and (ends_at_filter is null or att.started_at <= ends_at_filter)
  ),
  summarized as (
    select
      clinical_area,
      prompt,
      selected_option_text,
      count(*) filter (where is_correct = false) as wrong_selection_count,
      count(*) as total_count
    from tagged_answers
    group by clinical_area, prompt, selected_option_text
  ),
  ranked as (
    select
      clinical_area,
      prompt,
      selected_option_text,
      wrong_selection_count,
      round((wrong_selection_count::numeric / nullif(sum(total_count) over (partition by prompt), 0)) * 100, 2) as incorrect_rate,
      row_number() over (
        partition by prompt
        order by wrong_selection_count desc, selected_option_text asc
      ) as option_rank
    from summarized
    where wrong_selection_count > 0
  )
  select
    clinical_area,
    prompt,
    selected_option_text as most_selected_wrong_option,
    wrong_selection_count::bigint,
    incorrect_rate
  from ranked
  where option_rank = 1
  order by incorrect_rate desc, wrong_selection_count desc, prompt asc
  limit greatest(limit_count, 1);
$$;

notify pgrst, 'reload schema';
