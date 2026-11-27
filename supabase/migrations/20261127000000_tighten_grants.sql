-- Second lock behind row-level security: signed-out visitors get no table access at all, and signed-in
-- drivers keep only the four operations the app uses (TRUNCATE, for one, would skip row-level security).
revoke all on table public.entries, public.profiles from anon;
revoke truncate, references, trigger on table public.entries, public.profiles from authenticated;
-- Tables added later start the same way.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated;
