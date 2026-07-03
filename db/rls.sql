alter table entities        enable row level security;
alter table snapshots       enable row level security;
alter table watchlist_state enable row level security;
alter table deep_dive_cache enable row level security;

create policy read_entities  on entities        for select to authenticated using (true);
create policy read_snapshots on snapshots       for select to authenticated using (true);
create policy read_watch     on watchlist_state for select to authenticated using (true);
create policy read_cache     on deep_dive_cache for select to authenticated using (true);

create policy write_watch_ins on watchlist_state for insert to authenticated with check (true);
create policy write_watch_upd on watchlist_state for update to authenticated using (true) with check (true);
create policy write_watch_del on watchlist_state for delete to authenticated using (true);
-- NOTE: the collector connects as the table owner and bypasses RLS entirely.
