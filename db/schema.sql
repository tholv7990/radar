create table if not exists entities (
  id            bigint generated always as identity primary key,
  source        text not null check (source in ('github','producthunt')),
  external_id   text not null,
  name          text not null,
  one_liner     text,
  url           text,
  language      text,
  topics        text[],
  owner_type    text,
  created_at    timestamptz,
  default_branch text,
  first_seen_at timestamptz default now(),
  unique (source, external_id)
);

create table if not exists snapshots (
  id            bigint generated always as identity primary key,
  entity_id     bigint not null references entities(id),
  captured_at   timestamptz not null default now(),
  stars int, forks int, watchers int, open_issues int,
  pushed_at timestamptz, license text, archived bool,
  votes int, comments int, rating numeric, reviews_count int,
  provisional_quality int,
  raw_json      jsonb not null
);
create index if not exists snapshots_entity_time on snapshots (entity_id, captured_at desc);

create table if not exists watchlist_state (
  entity_id  bigint primary key references entities(id),
  state      text not null check (state in ('seen','watching','dismissed')),
  note       text,
  updated_at timestamptz default now()
);

create table if not exists deep_dive_cache (
  entity_id     bigint primary key references entities(id),
  status        text not null default 'running' check (status in ('running','done','error')),
  error_note    text,
  computed_at   timestamptz default now(),
  quality_score int,
  momentum_stage text,
  veto_flags    jsonb,
  reasons       jsonb,
  full_result   jsonb
);
