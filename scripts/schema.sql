-- =====================================================================
-- Ticked — schema redo: no more TMDB, real scraped data instead.
--
-- Run this ONCE in the Supabase SQL Editor (your project > SQL Editor >
-- New query > paste all of this > Run).
--
-- THIS DROPS AND RECREATES cinemas, branches, films, breaks, and
-- movies_seen. Any rows currently in those five tables are gone after
-- this runs. profiles is untouched. (Confirmed OK to do this — it's
-- test/demo data from building the app so far.)
--
-- Why cinemas/branches are being redone too, not just films/breaks/
-- movies_seen: VOX branch names as VOX's own site prints them
-- ("Riyadh Park - Riyadh") don't exactly match whatever branch_name
-- values already exist by hand, and there's no reliable way to match
-- old rows to scraped ones by name alone. Cleaner to start the VOX
-- branches fresh, entirely scraper-owned, than risk silently
-- duplicating branches. Muvi/Scene/Empire/Cinema House branches are
-- reseeded exactly as they were (hand-entered placeholders) since
-- those chains aren't being scraped yet.
--
-- What changes, conceptually:
--   - Every film's identity used to be TMDB's tmdb_id. Nothing calls
--     TMDB anymore (cinema sites are scraped directly instead), so
--     films now get a plain auto-incrementing film_id, plus
--     (source, source_slug) e.g. ('vox', 'the-odyssey') so a re-scrape
--     of the same film upserts instead of duplicating.
--   - branches gets the same idea: (source, source_code) e.g.
--     ('vox', '0034') is VOX's own internal branch code (see
--     vox_scraper.py's docstring for where that number comes from).
--   - New showtimes table: which branch shows which film, on which
--     screen, at what time. Written ONLY by the scraper's service-role
--     key (see sync_to_supabase.py) — regular signed-in users can read
--     it but not write it, same as any other reference data.
-- =====================================================================

-- ---- drop in FK-safe order (children before parents) ---------------------

drop table if exists showtimes;
drop table if exists movies_seen;
drop table if exists breaks;
drop table if exists films;
drop table if exists branches;
drop table if exists cinemas;

-- ---- cinemas --------------------------------------------------------------
-- Unchanged shape from before — the ad-block minutes are researched by
-- hand per chain, not something scraping gives us.

create table cinemas (
  cinema_name       text primary key,
  short_ad_minutes  integer not null,  -- films under 2 hours
  long_ad_minutes   integer not null   -- films 2 hours and over
);

insert into cinemas (cinema_name, short_ad_minutes, long_ad_minutes) values
  ('VOX',          14, 11),
  ('Muvi',         18, 15),
  ('Scene',        12, 9),
  ('Empire',       20, 16),
  ('Cinema House', 16, 13);

alter table cinemas enable row level security;

create policy "cinemas are readable by any signed-in user"
  on cinemas for select
  to authenticated
  using (true);

-- No write policy for `authenticated` — this is reference data, edited
-- by hand (service role / dashboard) only.

-- ---- branches ---------------------------------------------------------

create table branches (
  branch_id     bigint generated always as identity primary key,
  cinema_name   text not null references cinemas(cinema_name),
  branch_name   text not null,
  lat           double precision,
  lon           double precision,
  -- Populated only for chains that are actually scraped (VOX today).
  -- NULL for the hand-seeded placeholder branches below.
  source        text,
  source_code   text
);

-- Non-VOX chains: reseeded exactly as before. VOX's own branches are
-- deliberately NOT seeded here — sync_to_supabase.py's first run
-- populates every real VOX branch it finds, with real names and codes.
insert into branches (cinema_name, branch_name, lat, lon) values
  ('Muvi',         'Panorama Mall',  24.6889, 46.6857),
  ('Scene',        'Localizer Mall', 24.8149, 46.6577),
  ('Empire',       'Hayat Mall',     24.6963, 46.6845),
  ('Cinema House', 'Granada Mall',   24.7605, 46.7998);

-- Lets the scraper upsert a branch by VOX's own code instead of
-- matching on branch_name text. A plain (non-partial) unique index is
-- fine here: Postgres never treats two NULLs as equal, so the
-- hand-seeded rows above (source/source_code both NULL) don't collide
-- with each other or with real ('vox', '00xx') rows.
create unique index branches_source_code_key on branches (source, source_code);

alter table branches enable row level security;

create policy "branches are readable by any signed-in user"
  on branches for select
  to authenticated
  using (true);

-- No insert/update policy for `authenticated` — VOX branches are
-- written only by the scraper's service-role key.

-- ---- films --------------------------------------------------------------

create table films (
  film_id           bigint generated always as identity primary key,
  source            text not null,   -- 'vox' today; another cinema site's slug later
  source_slug       text not null,   -- that site's own slug/id for this film
  title             text not null,
  duration_min      integer,         -- null until the site itself lists a runtime
  poster_url        text,
  credits_start_min integer,
  breaks_checked_at timestamptz,
  scraped_at        timestamptz not null default now(),
  unique (source, source_slug)
);

alter table films enable row level security;

create policy "films are readable by any signed-in user"
  on films for select
  to authenticated
  using (true);

create policy "films are writable by any signed-in user"
  on films for insert
  to authenticated
  with check (true);

create policy "films are updatable by any signed-in user"
  on films for update
  to authenticated
  using (true)
  with check (true);

-- ---- breaks (the shared Gemini cache) ------------------------------------
-- Unaffected by dropping TMDB — Gemini is asked for title/year/duration,
-- never a tmdb id — this table just now keys on film_id instead.

create table breaks (
  film_id   bigint not null references films(film_id) on delete cascade,
  start_min integer not null,
  end_min   integer not null,
  primary key (film_id, start_min)
);

alter table breaks enable row level security;

create policy "breaks are readable by any signed-in user"
  on breaks for select
  to authenticated
  using (true);

create policy "breaks are writable by any signed-in user"
  on breaks for insert
  to authenticated
  with check (true);

create policy "breaks are deletable by any signed-in user"
  on breaks for delete
  to authenticated
  using (true);

-- ---- movies_seen (per-user attendance history) ---------------------------

create table movies_seen (
  movie_seen_id bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  branch_id     bigint not null references branches(branch_id),
  film_id       bigint not null references films(film_id),
  ticket_time   timestamptz not null
);

alter table movies_seen enable row level security;

create policy "users read their own history"
  on movies_seen for select
  to authenticated
  using (auth.uid() = user_id);

create policy "users insert their own history"
  on movies_seen for insert
  to authenticated
  with check (auth.uid() = user_id);

-- ---- showtimes (new) -------------------------------------------------------
-- "This branch shows this movie at this time" — the actual feature
-- this redo was for.

create table showtimes (
  showtime_id       bigint generated always as identity primary key,
  film_id           bigint not null references films(film_id) on delete cascade,
  branch_id         bigint not null references branches(branch_id) on delete cascade,
  screen_type       text not null,       -- VOX's own names: "IMAX", "MAX", "VIP", ...
  show_time         timestamptz not null,
  sold_out          boolean not null default false,
  source_booking_id text,                -- VOX's own per-showing id, for upsert/dedup
  scraped_at        timestamptz not null default now(),
  unique (branch_id, source_booking_id)
);

create index showtimes_film_id_idx on showtimes (film_id);

alter table showtimes enable row level security;

create policy "showtimes are readable by any signed-in user"
  on showtimes for select
  to authenticated
  using (true);

-- Deliberately no insert/update policy for `authenticated` — showtimes
-- are written only by the daily scraper via the service role key
-- (which bypasses RLS entirely). Regular app users only ever read.
