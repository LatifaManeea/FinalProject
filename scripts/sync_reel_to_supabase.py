"""
Pushes what reel_scraper.py scrapes straight into Supabase: films and
today's showtimes, for the Reel chain (Granada Mall, its only Saudi
location). Mirrors sync_muvi_to_supabase.py's approach for Muvi - same
tables, same branch-is-hand-managed rule, same scripts/.env - just
pointed at reel_scraper.py and stamping rows with source='reel'.

branches is hand-managed, not touched by this script
------------------------------------------------------
Exactly like the VOX/Muvi sync scripts: this only ever READS `branches`
(to find the branch_id you assigned Granada Mall) and never writes to
it. For that to work, Reel's row needs source='reel' and
source_code='0010' (Reel's own cinema id for Granada Mall - see
reel_scraper.py's "One branch only" note). Run --propose-branches to
see the exact SQL for that one row.

CINEMA_NAME below must match your `cinemas` table exactly
------------------------------------------------------------
schema.sql originally seeded a placeholder Reel branch called "Hayat
Mall" - that was never a real Reel location (Hayat Mall is a Muvi
branch); Reel's actual, only Saudi cinema is Granada Mall. CINEMA_NAME
is set to "Reel" below to match the schema.sql seed's cinema_name - if
you've since renamed that row (the way "Cinema House" became
"CINEHOUSE"), change CINEMA_NAME to match before running
--propose-branches, the same way each chain's row has to say exactly
what your `cinemas` table says.

Needs the SAME scripts/.env as sync_to_supabase.py
-----------------------------------------------------
    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<service role key, from Project Settings > API>

Usage
-----
    pip install requests
    python3 sync_reel_to_supabase.py

    # Read-only: see the one Reel branch this needs, without writing
    # anything (run this first, before the first real sync):
    python3 sync_reel_to_supabase.py --propose-branches
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

import requests

from reel_scraper import GRANADA_MALL_CINEMA_ID, GRANADA_MALL_NAME, Movie, scrape_all

SCRIPT_DIR = Path(__file__).resolve().parent

CINEMA_NAME = "Reel"  # Must match your `cinemas` table exactly - see docstring above.
SOURCE = "reel"


def _load_env() -> tuple[str | None, str | None]:
    """Same scripts/.env as sync_to_supabase.py - read by hand for the
    same reason (no python-dotenv dependency). A real env var already
    exported always wins over the file."""
    env_path = SCRIPT_DIR / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    return os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY")


def _headers(service_role_key: str, prefer: str) -> dict:
    return {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
        "Prefer": prefer,
    }


def _upsert(supabase_url: str, service_role_key: str, table: str, rows: list[dict], on_conflict: str) -> list[dict]:
    if not rows:
        return []
    url = f"{supabase_url}/rest/v1/{table}?on_conflict={on_conflict}"
    resp = requests.post(
        url,
        headers=_headers(service_role_key, "resolution=merge-duplicates,return=representation"),
        json=rows,
        timeout=30,
    )
    if resp.status_code >= 300:
        raise RuntimeError(f"Upsert into {table} failed ({resp.status_code}): {resp.text}")
    return resp.json()


def _select(supabase_url: str, service_role_key: str, table: str, query: str) -> list[dict]:
    url = f"{supabase_url}/rest/v1/{table}?{query}"
    resp = requests.get(url, headers=_headers(service_role_key, "return=representation"), timeout=30)
    if resp.status_code >= 300:
        raise RuntimeError(f"Select from {table} failed ({resp.status_code}): {resp.text}")
    return resp.json()


def scrapeable_movies(movies: list[Movie]) -> list[Movie]:
    """Same reasoning as the VOX/Muvi sync scripts: films.duration_min
    is NOT NULL in spirit, so skip a film with no runtime rather than
    write one nothing could ever be scheduled from."""
    return [m for m in movies if m.duration_minutes is not None]


def build_film_rows(movies: list[Movie]) -> list[dict]:
    return [
        {
            "source": SOURCE,
            "source_slug": m.slug,  # the film's own Reel ID, e.g. "HO00005631" - see reel_scraper.py's Movie.slug note.
            "title": m.title,
            "duration_min": m.duration_minutes,
            "poster_url": m.poster_url,
        }
        for m in movies
    ]


def fetch_branch_id(supabase_url: str, service_role_key: str) -> Optional[int]:
    """branches is hand-managed, static reference data - this only
    ever READS it, to find the branch_id you assigned Granada Mall
    (source='reel', source_code='0010'), and never writes to the
    table. Returns None (and every showtime is skipped) until that row
    exists - see fetch_branch_id()'s caller for the printed note."""
    rows = _select(
        supabase_url,
        service_role_key,
        "branches",
        f"source=eq.{SOURCE}&source_code=eq.{GRANADA_MALL_CINEMA_ID}&select=branch_id",
    )
    return rows[0]["branch_id"] if rows else None


def fetch_branch_id_by_name(supabase_url: str, service_role_key: str) -> Optional[int]:
    """Fallback for a Reel row with no source_code filled in yet - same
    idea as the VOX/Muvi fallbacks, just for a single expected name
    instead of a whole map."""
    rows = _select(
        supabase_url,
        service_role_key,
        "branches",
        f"cinema_name=eq.{CINEMA_NAME}&branch_name=eq.{GRANADA_MALL_NAME}&select=branch_id",
    )
    return rows[0]["branch_id"] if rows else None


def build_showtime_rows(movies: list[Movie], film_id_by_slug: dict[str, int], branch_id: int) -> tuple[list[dict], int]:
    rows = []
    skipped = 0
    for m in movies:
        film_id = film_id_by_slug.get(m.slug)
        if film_id is None:
            skipped += len(m.showtimes_today)
            continue
        for st in m.showtimes_today:
            rows.append(
                {
                    "film_id": film_id,
                    "branch_id": branch_id,
                    "screen_type": st.screen_type,
                    "show_time": st.show_time_iso,
                    "sold_out": st.sold_out,
                    "source_booking_id": st.booking_id,
                }
            )
    return rows, skipped


def sync(movies: list[Movie], supabase_url: str, service_role_key: str) -> None:
    all_movies = movies
    movies = scrapeable_movies(movies)
    skipped_no_duration = len(all_movies) - len(movies)
    if skipped_no_duration:
        print(f"Skipping {skipped_no_duration} title(s) with no runtime listed yet (not synced).")

    saved_films = _upsert(supabase_url, service_role_key, "films", build_film_rows(movies), on_conflict="source,source_slug")
    film_id_by_slug = {row["source_slug"]: row["film_id"] for row in saved_films}
    print(f"Upserted {len(saved_films)} films.")

    branch_id = fetch_branch_id(supabase_url, service_role_key)
    if branch_id is None:
        branch_id = fetch_branch_id_by_name(supabase_url, service_role_key)
        if branch_id is not None:
            print(f"  note: matched {GRANADA_MALL_NAME} by name - run --propose-branches to fill in its source_code too.")

    if branch_id is None:
        print(
            f"  note: no branch found for {CINEMA_NAME}/{GRANADA_MALL_NAME} yet. "
            "Run --propose-branches, read the SQL it prints, and run that in "
            "the Supabase SQL Editor first. All showtimes below will be skipped until then."
        )
        skipped = sum(len(m.showtimes_today) for m in movies)
        saved_showtimes: list[dict] = []
    else:
        showtime_rows, skipped = build_showtime_rows(movies, film_id_by_slug, branch_id)
        saved_showtimes = _upsert(
            supabase_url, service_role_key, "showtimes", showtime_rows, on_conflict="branch_id,source_booking_id"
        )

    note = f" ({skipped} skipped — no matching film/branch)" if skipped else ""
    print(f"Upserted {len(saved_showtimes)} showtimes.{note}")


def print_proposed_branches() -> None:
    """Prints the SQL for Reel's one Saudi branch (Granada Mall).

    schema.sql's placeholder Reel row ("Hayat Mall") is not a real Reel
    location - Hayat Mall is a Muvi branch. This is an upsert on
    (source, source_code), same pattern as Muvi's, safe to run more than
    once.
    """
    print(f"-- Reel's only Saudi location: {GRANADA_MALL_NAME} (cinema id {GRANADA_MALL_CINEMA_ID}).")
    print("--")
    print(f"-- CINEMA_NAME below is '{CINEMA_NAME}' - if your `cinemas` table calls")
    print("-- this chain something else, edit CINEMA_NAME at the top of this file")
    print("-- (and the cinema_name literal below) to match before running this SQL.")
    print()
    print(
        "insert into branches (cinema_name, branch_name, source, source_code) "
        "values ('{}', '{}', '{}', '{}')\n"
        "on conflict (source, source_code) do update set branch_name = excluded.branch_name;".format(
            CINEMA_NAME, GRANADA_MALL_NAME, SOURCE, GRANADA_MALL_CINEMA_ID
        )
    )
    print()
    print("-- If schema.sql's placeholder 'Hayat Mall' row for Reel still exists")
    print("-- (wrong name for this chain), remove it once the row above is in:")
    print("--")
    print(f"--   delete from branches where cinema_name = '{CINEMA_NAME}' and branch_name = 'Hayat Mall';")
    print()
    print("-- Verify:")
    print(f"-- select branch_id, branch_name, source, source_code from branches where cinema_name = '{CINEMA_NAME}';")


def main() -> None:
    if "--propose-branches" in sys.argv:
        print_proposed_branches()
        return

    supabase_url, service_role_key = _load_env()
    if not supabase_url or not service_role_key:
        print(
            "Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.\n"
            "Create scripts/.env with those two values first — see the "
            "docstring at the top of sync_to_supabase.py for where to get "
            "the key and why it must NOT go in the app's root .env.",
            file=sys.stderr,
        )
        sys.exit(1)

    movies = scrape_all()
    sync(movies, supabase_url, service_role_key)


if __name__ == "__main__":
    main()
