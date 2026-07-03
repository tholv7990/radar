create or replace view signal_feed as
with latest as (
  select distinct on (entity_id) * from snapshots
  order by entity_id, captured_at desc
),
prior as (
  select distinct on (s.entity_id) s.* from snapshots s
  join latest l on l.entity_id = s.entity_id
  where s.captured_at <= l.captured_at - interval '7 days'
  order by s.entity_id, s.captured_at desc
),
calc as (
  select
    e.id, e.source, e.external_id, e.name, e.one_liner, e.url,
    e.language, e.topics, e.owner_type, e.created_at,
    l.captured_at, l.stars, l.forks, l.watchers, l.votes, l.comments,
    l.rating, l.pushed_at, l.archived, l.provisional_quality,
    p.id as prior_id,
    case when p.id is null then null
         when e.source='github' then (l.stars - p.stars)
         else ((coalesce(l.votes,0)+coalesce(l.comments,0))
             - (coalesce(p.votes,0)+coalesce(p.comments,0))) end as velocity,
    case when e.source='github' then (l.forks - p.forks)
         else (l.comments - p.comments) end as secondary_velocity,
    case when e.source='github' then l.stars else l.votes end as total_metric,
    w.state as watch_state
  from entities e
  join latest l on l.entity_id = e.id
  left join prior p on p.entity_id = e.id
  left join watchlist_state w on w.entity_id = e.id
)
select
  c.*,
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'mixed'
    when c.secondary_velocity > 0 then 'corroborated'
    when c.velocity > 50 and c.secondary_velocity = 0 then 'suspicious'
    else 'mixed'
  end as consistency,
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'fading'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.10 then 'emerging'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.03 then 'rising'
    else 'steady'
  end as momentum_stage,
  coalesce(c.velocity::numeric, c.provisional_quality::numeric) as rank_score
from calc c;
grant select on signal_feed to authenticated;
