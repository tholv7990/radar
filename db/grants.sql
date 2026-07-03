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

-- Supabase's default-privilege behavior may auto-grant `anon` SELECT on
-- newly created objects. The app gates access behind login, so `anon` must
-- never be able to read app data — revoke explicitly and idempotently
-- (revoking a privilege that isn't held is a harmless no-op).
revoke all on signal_feed, entities, snapshots, watchlist_state, deep_dive_cache from anon;
