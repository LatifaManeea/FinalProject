-- =====================================================================
-- Split "the movie" from "a cinema's listing of it".
--
-- Run this ONCE in the Supabase SQL Editor (your project > SQL Editor >
-- New query > paste all of this > Run). It runs in one transaction: if
-- any step fails, nothing changes.
--
-- The problem this solves: `films` has one row per cinema per film. Once
-- a second cinema is scraped, The Odyssey is two rows — two film_ids —
-- and breaks were keyed on film_id, so Gemini would be asked twice about
-- the same film and could give two different answers. Someone at VOX and
-- someone at Muvi would see different safe windows for the same scene.
--
-- Breaks belong to the MOVIE, not to a cinema's listing of it. So:
--
--   movies  one row per actual film. Owns the Gemini answers:
--           credits_start_min, breaks_checked_at.
--   films   unchanged in meaning: one row per cinema listing, owned by
--           the scraper. Gains movie_id, pointing at its movie.
--   breaks  keyed on movie_id instead of film_id.
--
-- movies_seen and showtimes still point at films, and that's correct:
-- you attend a screening at a particular cinema's listing.
--
-- MATCHING (step 2, later): today every film gets its own movie, because
-- only VOX is scraped and there is nothing to match. When a second
-- scraper lands, its sync should set movie_id to the existing movie for
-- films it recognises (normalised title + runtime within a few minutes).
-- When unsure, leave it null and a new movie is created — a wrong merge
-- would show one film's breaks on a different film.
-- =====================================================================

begin;

-- ---- movies -----------------------------------------------------------

create table movies (
  movie_id          bigint generated always as identity primary key,
  -- For reading the table by eye; the scraped titles live on films.
  title             text not null,
  -- Moved here from films. Filled in by the app from Gemini's answer.
  credits_start_min integer,
  breaks_checked_at timestamptz
);

alter table movies enable row level security;

create policy "movies are readable by any signed-in user"
  on movies for select
  to authenticated
  using (true);

-- The app writes the two Gemini columns, same as it did on films. No
-- insert policy: movies are only ever created by the trigger below,
-- which runs as whoever inserts the film — the scraper's service role.
create policy "movies are updatable by any signed-in user"
  on movies for update
  to authenticated
  using (true)
  with check (true);

-- ---- films.movie_id, one movie per existing film ------------------------

alter table films add column movie_id bigint references movies(movie_id);

do $$
declare
  f record;
  new_id bigint;
begin
  for f in select film_id, title, credits_start_min, breaks_checked_at from films loop
    insert into movies (title, credits_start_min, breaks_checked_at)
    values (f.title, f.credits_start_min, f.breaks_checked_at)
    returning movie_id into new_id;

    update films set movie_id = new_id where film_id = f.film_id;
  end loop;
end $$;

alter table films alter column movie_id set not null;

-- ---- keep the scraper working, unchanged ----------------------------------
--
-- sync_to_supabase.py upserts films without knowing movies exist. This
-- gives each new film its movie automatically.
--
-- The lookup first is not optional. The scraper UPSERTS, and a BEFORE
-- INSERT trigger fires even when the row turns out to already exist and
-- the upsert becomes an update. Creating a movie unconditionally would
-- leave an orphaned movie behind on every film, on every daily run. So
-- an existing (source, source_slug) keeps the movie it already has.

create or replace function films_assign_movie() returns trigger
language plpgsql as $$
begin
  if new.movie_id is null then
    select movie_id into new.movie_id
    from films
    where source = new.source and source_slug = new.source_slug;

    if new.movie_id is null then
      insert into movies (title) values (new.title)
      returning movie_id into new.movie_id;
    end if;
  end if;

  return new;
end $$;

create trigger films_assign_movie
  before insert on films
  for each row execute function films_assign_movie();

-- ---- breaks: film_id -> movie_id ------------------------------------------

alter table breaks add column movie_id bigint references movies(movie_id) on delete cascade;

update breaks b
set movie_id = f.movie_id
from films f
where f.film_id = b.film_id;

-- Dropping film_id also drops the old (film_id, start_min) primary key
-- and the foreign key to films, which both involve that column.
alter table breaks drop column film_id;
alter table breaks alter column movie_id set not null;
alter table breaks add primary key (movie_id, start_min);

-- ---- the two Gemini columns now live on movies ----------------------------

alter table films drop column credits_start_min;
alter table films drop column breaks_checked_at;

commit;

-- Tell the API about the new shape straight away, instead of answering
-- "column not found" until its cache catches up.
notify pgrst, 'reload schema';

-- Verify: every film has a movie, and there are as many movies as films.
--
--   select count(*) as films, count(distinct movie_id) as movies,
--          count(*) filter (where movie_id is null) as unlinked
--   from films;
