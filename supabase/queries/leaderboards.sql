-- Top 10 all-time leaderboard.
select *
from app.leaderboard_all_time(10);

-- Top 10 leaderboard for the current Ghana month.
select *
from app.leaderboard_monthly(app.current_season_key_ghana(now()), 10);

-- Current user's all-time rank example.
select *
from app.my_rank_all_time('11111111-1111-1111-1111-111111111111');

-- Current user's monthly rank example.
select *
from app.my_rank_monthly(
  '11111111-1111-1111-1111-111111111111',
  app.current_season_key_ghana(now())
);

-- Session-level participation and completion KPI example.
select *
from app.session_kpis('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');