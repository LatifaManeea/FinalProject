# scripts/

Non-Flutter helper scripts. Not part of the app build.

## The pipeline

```
vox_scraper.py          scrapes ksa.voxcinemas.com -> Movie objects
        |
sync_to_supabase.py      upserts films + showtimes (branches is hand-managed - see below)
        |
   Supabase              the app reads films/showtimes via lib/services/database.dart
```

### 1. `schema.sql` — run this first, once

Paste into your Supabase project's SQL Editor and run it. Drops and
recreates `cinemas`, `branches`, `films`, `breaks`, `movies_seen`, and
adds a new `showtimes` table. See the comment block at the top of the
file for exactly what changes and why (short version: nothing is keyed
on TMDB's tmdb_id anymore, since nothing calls TMDB anymore).

### 2. `vox_scraper.py` — the scraper

Scrapes VOX's "what's on" page + each movie's own page: title, poster
URL, running time, genre, and today's showtimes per branch/screen —
Riyadh branches only (the app only serves Riyadh for now; see
`_is_riyadh_branch` in the file). Respects the site's `robots.txt`
(see the docstring in the file).

Uses `curl_cffi` instead of plain `requests` to actually fetch pages —
this site sits behind Akamai's bot protection, which fingerprints the
TLS handshake itself (not just headers), and plain `requests`/`urllib3`
gets silently stalled by it no matter which Python/OpenSSL build you
use. `curl_cffi` presents a real Chrome TLS fingerprint instead, the
same way plain `curl` does. See the "Why curl_cffi" note at the top of
`vox_scraper.py` for the full story.

```
pip install curl_cffi beautifulsoup4
python3 vox_scraper.py
```

Also writes `vox_movies.json` next to itself — handy for eyeballing a
scrape, not used by the app or by sync_to_supabase.py for anything
(that script re-scrapes fresh each run). `vox_movies.json` and
`vox_sync.log` are local/generated — gitignored, not something to commit.

### 3. `sync_to_supabase.py` — pushes it into Supabase

Imports `scrape_all()` from vox_scraper.py, then upserts:
- **films**, keyed on `(source, source_slug)` — e.g. `('vox', 'the-odyssey')`
- **showtimes**, keyed on `(branch_id, source_booking_id)`

so re-running it daily updates existing rows instead of duplicating
them. Needs `scripts/.env` (see below) — **not** the app's root `.env`.

**`branches` is hand-managed, not touched by this script at all** — it's
static reference data you fill in and keep accurate yourself in
Supabase. The script only *reads* it, to match a scraped VOX branch
code to the `branch_id` you assigned that branch (via `fetch_branch_ids()`
in the file). For that to work, every Riyadh branch's row needs
`source = 'vox'` and `source_code` set to VOX's own code for it — the
number in its booking ids (e.g. `"0034"` for Riyadh Park). If a row's
`source_code` is missing or wrong, that branch's showtimes are just
silently skipped rather than erroring — worth checking there first if
a branch's showtimes aren't showing up. VOX's current Riyadh branches,
for reference:

| source_code | branch_name |
|---|---|
| 0034 | Riyadh Park - Riyadh |
| 0041 | Al Qasr Mall - Riyadh |
| 0042 | The Roof - Riyadh |
| 0043 | Kingdom Centre - Riyadh |
| 0048 | Roshn Front - Riyadh |
| 0050 | Atyaf Mall - Riyadh |
| 0052 | Sahara Mall - Riyadh |
| 0058 | The Spot, Sheikh Jaber - Riyadh |
| 0059 | The Esplanade |
| 0101 | Via Riyadh |
| 0106 | Century Corner - Riyadh |

```
pip install curl_cffi requests beautifulsoup4
python3 sync_to_supabase.py
```

### 4. `setup_daily_scrape.sh` — run once to automate step 3

Registers a macOS launchd job (the modern cron) that runs
`sync_to_supabase.py` every day at 08:00. Requires `scripts/.env` to
already exist.

```
chmod +x setup_daily_scrape.sh   # already executable if you got this via git
./setup_daily_scrape.sh
```

See the comments at the top of the script to change the time, check it
ran, or remove it later.

## scripts/.env — separate from the app's root .env, on purpose

Create `scripts/.env` (gitignored — the project's `.env` rule in
`.gitignore` matches at any folder depth, confirmed not assumed):

```
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service role key, from Project Settings > API>
```

**Why not just add these to the app's existing root `.env`?** That file
is listed under `pubspec.yaml`'s `assets:`, which means its entire
contents get bundled into the compiled app and ship to every phone that
installs it. That's fine for `SUPABASE_URL` and the publishable/anon
key the app itself uses (they're meant to be public — Postgres RLS is
what actually protects the data). The **service role key** is
different: it bypasses row-level security completely, so anyone who
extracted it from an app binary would have full read/write access to
every table. It must only ever live somewhere that never gets bundled
— `scripts/.env`, read only by scripts that run on your Mac.

## Where things stand

- `films`/`showtimes` are real Supabase tables now, kept current by
  the daily scrape. `branches` is real too, but hand-managed — the
  scrape only reads it, never writes to it.
- `FakeRepository`'s mock films (in `lib/data/fake_repository.dart`)
  are a separate, hand-picked snapshot for UI development without
  hitting Supabase at all — they don't read from these tables and
  don't need to be kept in sync with them.
- Next cinema chain to scrape: same idea, new scraper file
  (`muvi_scraper.py`, etc.), same `sync_to_supabase.py`-style upsert
  with that chain's own `source` value.
