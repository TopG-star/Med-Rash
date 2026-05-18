create or replace function app.current_season_key_ghana(input_ts timestamptz default now())
returns text
language sql
stable
as $$
  select to_char(input_ts at time zone 'Africa/Accra', 'YYYY-MM');
$$;

create or replace view app.ranked_attempt_totals_all_time as
select
  a.user_id,
  u.nickname,
  sum(a.score)::bigint as total_score,
  count(*)::bigint as ranked_attempts,
  max(a.completed_at) as last_ranked_at
from app.attempts a
join app.users u on u.id = a.user_id
where a.mode = 'ranked'
  and a.completed_at is not null
group by a.user_id, u.nickname;

create or replace view app.ranked_attempt_totals_monthly as
select
  a.season_key,
  a.user_id,
  u.nickname,
  sum(a.score)::bigint as total_score,
  count(*)::bigint as ranked_attempts,
  max(a.completed_at) as last_ranked_at
from app.attempts a
join app.users u on u.id = a.user_id
where a.mode = 'ranked'
  and a.completed_at is not null
group by a.season_key, a.user_id, u.nickname;

create or replace function app.leaderboard_all_time(limit_count integer default 10)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  total_score bigint,
  ranked_attempts bigint,
  last_ranked_at timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      rank() over (order by total_score desc, last_ranked_at asc, nickname asc) as rank_position,
      *
    from app.ranked_attempt_totals_all_time
  )
  select rank_position, user_id, nickname, total_score, ranked_attempts, last_ranked_at
  from ranked
  order by rank_position, nickname
  limit greatest(limit_count, 1);
$$;

create or replace function app.leaderboard_monthly(
  season text default app.current_season_key_ghana(now()),
  limit_count integer default 10
)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  total_score bigint,
  ranked_attempts bigint,
  last_ranked_at timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      rank() over (order by total_score desc, last_ranked_at asc, nickname asc) as rank_position,
      *
    from app.ranked_attempt_totals_monthly
    where season_key = season
  )
  select rank_position, user_id, nickname, total_score, ranked_attempts, last_ranked_at
  from ranked
  order by rank_position, nickname
  limit greatest(limit_count, 1);
$$;

create or replace function app.my_rank_all_time(target_user uuid)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  total_score bigint,
  ranked_attempts bigint,
  last_ranked_at timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      rank() over (order by total_score desc, last_ranked_at asc, nickname asc) as rank_position,
      *
    from app.ranked_attempt_totals_all_time
  )
  select rank_position, user_id, nickname, total_score, ranked_attempts, last_ranked_at
  from ranked
  where user_id = target_user;
$$;

create or replace function app.my_rank_monthly(
  target_user uuid,
  season text default app.current_season_key_ghana(now())
)
returns table (
  rank_position bigint,
  user_id uuid,
  nickname text,
  total_score bigint,
  ranked_attempts bigint,
  last_ranked_at timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      rank() over (order by total_score desc, last_ranked_at asc, nickname asc) as rank_position,
      *
    from app.ranked_attempt_totals_monthly
    where season_key = season
  )
  select rank_position, user_id, nickname, total_score, ranked_attempts, last_ranked_at
  from ranked
  where user_id = target_user;
$$;

create or replace function app.session_kpis(target_session uuid)
returns table (
  session_id uuid,
  join_count bigint,
  completed_count bigint,
  completion_rate numeric,
  average_score numeric,
  median_time_seconds numeric
)
language sql
stable
as $$
  with session_attempts as (
    select *
    from app.attempts
    where session_id = target_session
  ),
  completed as (
    select *
    from session_attempts
    where completed_at is not null
  )
  select
    target_session as session_id,
    count(*)::bigint as join_count,
    count(completed.*)::bigint as completed_count,
    case when count(*) = 0 then 0 else round((count(completed.*)::numeric / count(*)::numeric) * 100, 2) end as completion_rate,
    round(avg(completed.score::numeric), 2) as average_score,
    round((percentile_cont(0.5) within group (order by completed.time_taken_ms) / 1000.0)::numeric, 2) as median_time_seconds
  from session_attempts
  left join completed on completed.id = session_attempts.id;
$$;

create or replace function app.knowledge_gaps(
  limit_count integer default 10,
  specialty_filter text default null,
  facility_filter text default null,
  session_filter uuid default null
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
  where (specialty_filter is null or u.specialty = specialty_filter)
    and (facility_filter is null or u.facility = facility_filter)
    and (session_filter is null or att.session_id = session_filter)
  group by q.id, quiz.title, q.prompt, q.tags
  having count(a.id) > 0
  order by incorrect_rate desc, incorrect_count desc, prompt asc
  limit greatest(limit_count, 1);
$$;

create or replace function app.facility_performance(limit_count integer default 20)
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
      a.id,
      a.mode,
      a.score,
      a.completed_at,
      a.user_id
    from app.attempts a
    join app.users u on u.id = a.user_id
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

create or replace function app.treatment_perception_trends(limit_count integer default 10)
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
    where 'treatment-perception' = any(q.tags)
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