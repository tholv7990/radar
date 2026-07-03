-- Explicit privilege grants for the app-facing `authenticated` role.
-- RLS policies (db/rls.sql) control WHICH rows are visible/writable.
-- GRANTs control WHETHER the role can touch the table/view AT ALL. Supabase's
-- default-privilege behavior for new tables is not something we should rely
-- on implicitly, so we grant explicitly and idempotently (GRANT is safe to
-- re-run, it does not error if the privilege already exists).
grant usage on schema public to authenticated;
grant select on entities, snapshots, watchlist_state, deep_dive_cache to authenticated;
grant insert, update, delete on watchlist_state to authenticated;
grant select on signal_feed to authenticated;
