-- =====================================================================
-- Mark which safe windows Gemini actually knew, and which it estimated.
--
-- Run this ONCE in the Supabase SQL Editor (your project > SQL Editor >
-- New query > paste this > Run). Safe on a live project: it adds one
-- column with a default and touches nothing else.
--
-- Why it's needed: the app asks Gemini twice. First strictly — "if you
-- are not confident about this specific film, return nothing rather
-- than guessing". Almost every film in `films` is unreleased or brand
-- new, so that first pass declines and the breaks table stayed empty.
-- The second pass asks for windows based on how films of this kind are
-- usually paced, which does answer — but that answer is a reasoned
-- guess, not knowledge of this film's actual scenes.
--
-- Both kinds are worth showing. Presenting them identically is not:
-- someone deciding whether to walk out during a twist should know
-- which of the two they're looking at. Hence one boolean.
--
-- Existing rows default to false (not estimated), which is correct —
-- anything already stored came from the strict pass.
-- =====================================================================

alter table breaks
  add column if not exists is_estimated boolean not null default false;

-- Verify:
--
--   select f.title, b.start_min, b.end_min, b.is_estimated
--   from breaks b join films f on f.film_id = b.film_id
--   order by f.title, b.start_min;
