"""
Pushes what scene_scraper.py scrapes straight into Supabase: films and
each movie's earliest-available-date showtimes, for Scene Cinemas'
two Riyadh branches (Panorama Mall, Riyadh Gallery Mall). Mirrors
sync_cinehouse_to_supabase.py's approach - same tables, same
branch-is-hand-managed rule, same scripts/.env - just pointed at
scene_scraper.py, stamping rows with source='scene', and handling TWO
branches instead of one (see fetch_branch_ids() below).

Not literally "today" for this chain
-------------------------------------
scene_scraper.py's docstring explains why: Scene's own site never
offers today or tomorrow as a bookable date, so what gets synced here
is each movie's EARLIEST available date instead - usually a couple of
days out, moving forward as Scene opens more days for booking. The
`showtimes` rows still land in the same `show_time` column as every
other chain's literal-today rows; there's just no guarantee a given
sync actually contains anything happening today for Scene specifically.

branches is hand-managed, not touched by this script
------------------------------------------------------
Exactly like the other sync scripts: this only ever READS `branches`
(to find the branch_ids you assigned Panorama Mall / Riyadh Gallery
Mall) and never writes to it. For that to work, Scene's two rows need
source='scene' and their own source_code (the site's own cinema GUID -
see scene_scraper.py's RIYADH_BRANCHES). Run --propose-branches to see
the exact SQL for both rows - IMPORTANT: your `branches` table almost
certainly already has hand-entered "Panorama Mall" and "Riyadh Gallery
Mall" rows with no source/source_code set yet, so read the UPDATE
suggestion --propose-branches prints before running anything - a plain
INSERT next to those would create duplicates, exactly what happened
with Reel/Granada Mall earlier in this project.

CINEMA_NAME below must match your `cinemas` table exactly
------------------------------------------------------------
Set to "Scene" below - if your `cinemas` table calls this chain
something else, change CINEMA_NAME here first.

Needs the SAME scripts/.env as sync_to_supabase.py
-----------------------------------------------------
    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<service role key, from Project Settings > API>

Usage
-----
    pip install requests curl_cffi beautifulsoup4
    python3 sync_scene_to_supabase.py

    # Read-only: see the two Scene branches this needs, without
    # writing anything (run this first, before the first real sync):
    python3 sync_scene_to_supabase.py --propose-branches
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

import requests

from scene_scraper import RIYADH_BRANCHES, Movie, scrape_all

SCRIPT_DIR = Path(__file__).resolve().parent

CINEMA_NAME = "Scene"  # Must match your `cinemas` table exactly - see docstring above.
SOURCE = "scene"


def _load_env() -> tuple[str | None, str | None]:
    """Same scripts/.env as the other sync scripts - read by hand for
    the same reason (no python-dotenv dependency). A real env var
    already exported always wins over the file."""
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
    """Same reasoning as every other sync script: films.duration_min is
    NOT NULL in spirit, so skip a film with no runtime rather than
    write one nothing could ever be scheduled from."""
    return [m for m in movies if m.duration_minutes is not None]


def build_film_rows(movies: list[Movie]) -> list[dict]:
    return [
        {
            "source": SOURCE,
            "source_slug": m.slug,
            "title": m.title,
            "duration_min": m.duration_minutes,
            "poster_url": m.poster_url,
        }
        for m in movies
    ]


def fetch_branch_ids(supabase_url: str, service_role_key: str) -> dict[str, int]:
    """branches is hand-managed, static reference data - this only ever
    READS it, to find the branch_id for each Riyadh GUID
    (source='scene', source_code=<guid>), and never writes to the
    table. Returns {guid: branch_id} for whichever of the two already
    have source_code set - possibly empty, possibly missing one of the
    two."""
    codes = ",".join(RIYADH_BRANCHES.keys())
    rows = _select(
        supabase_url,
        service_role_key,
        "branches",
        f"source=eq.{SOURCE}&source_code=in.({codes})&select=branch_id,source_code",
    )
    return {row["source_code"]: row["branch_id"] for row in rows}


def fetch_branch_ids_by_name(supabase_url: str, service_role_key: str) -> dict[str, int]:
    """Fallback for a Scene row with no source_code filled in yet -
    same idea as the other chains' fallbacks, just for two expected
    names instead of one."""
    names = ",".join(RIYADH_BRANCHES.values())
    rows = _select(
        supabase_url,
        service_role_key,
        "branches",
        f"cinema_name=eq.{CINEMA_NAME}&branch_name=in.({names})&select=branch_id,branch_name",
    )
    name_to_id = {row["branch_name"]: row["branch_id"] for row in rows}
    return {guid: name_to_id[name] for guid, name in RIYADH_BRANCHES.items() if name in name_to_id}


def resolve_branch_ids(supabase_url: str, service_role_key: str) -> dict[str, int]:
    branch_ids = fetch_branch_ids(supabase_url, service_role_key)
    missing = [guid for guid in RIYADH_BRANCHES if guid not in branch_ids]
    if missing:
        by_name = fetch_branch_ids_by_name(supabase_url, service_role_key)
        matched_by_name = [RIYADH_BRANCHES[guid] for guid in missing if guid in by_name]
        branch_ids.update({guid: by_name[guid] for guid in missing if guid in by_name})
        if matched_by_name:
            print(
                f"  note: matched {', '.join(matched_by_name)} by name - "
                "run --propose-branches to fill in source_code too."
            )
    return branch_ids


def build_showtime_rows(
    movies: list[Movie], film_id_by_slug: dict[str, int], branch_ids: dict[str, int]
) -> tuple[list[dict], int]:
    rows = []
    skipped = 0
    for m in movies:
        film_id = film_id_by_slug.get(m.slug)
        for st in m.showtimes_today:
            branch_id = branch_ids.get(st.branch_code)
            if film_id is None or branch_id is None:
                skipped += 1
                continue
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

    branch_ids = resolve_branch_ids(supabase_url, service_role_key)
    missing_branches = [name for guid, name in RIYADH_BRANCHES.items() if guid not in branch_ids]
    if missing_branches:
        print(
            f"  note: no branch found yet for {', '.join(missing_branches)}. "
            "Run --propose-branches, read the SQL it prints, and run that in "
            "the Supabase SQL Editor first. Showtimes for that branch will be skipped until then."
        )

    showtime_rows, skipped = build_showtime_rows(movies, film_id_by_slug, branch_ids)
    saved_showtimes = _upsert(
        supabase_url, service_role_key, "showtimes", showtime_rows, on_conflict="branch_id,source_booking_id"
    )

    note = f" ({skipped} skipped — no matching film/branch)" if skipped else ""
    print(f"Upserted {len(saved_showtimes)} showtimes.{note}")


def print_proposed_branches() -> None:
    """Prints the SQL for Scene's two Riyadh branches.

    Like Reel's and CineHouse's, this checks for an existing
    hand-entered row for each name first and tells you to UPDATE
    instead of blindly inserting - your `branches` table almost
    certainly already has "Panorama Mall" and "Riyadh Gallery Mall"
    rows with NULL source/source_code (the same shape Reel's Granada
    Mall row had), and a plain insert next to those creates a duplicate
    row instead of updating the one you already have. If you don't have
    existing rows for these two, use the INSERT; if you do (likely),
    use the UPDATE.
    """
    print("-- Scene's two Riyadh locations (GUIDs are the site's own cinema ids,")
    print("-- from /Home/LoadCinemas - see scene_scraper.py's RIYADH_BRANCHES):")
    for guid, name in RIYADH_BRANCHES.items():
        print(f"--   {name}: {guid}")
    print("--")
    print(f"-- CINEMA_NAME below is '{CINEMA_NAME}' - if your `cinemas` table calls")
    print("-- this chain something else, edit CINEMA_NAME at the top of this file")
    print("-- (and the cinema_name literal below) to match before running this SQL.")
    print()
    print("-- If you ALREADY have Panorama Mall / Riyadh Gallery Mall rows for Scene")
    print("-- (branch_id shown in your `branches` table), run this instead of the")
    print("-- inserts below - one UPDATE per row:")
    print("--")
    for guid, name in RIYADH_BRANCHES.items():
        print(f"--   update branches set source = '{SOURCE}', source_code = '{guid}'")
        print(f"--   where cinema_name = '{CINEMA_NAME}' and branch_name = '{name}';")
    print()
    print("-- Otherwise, insert new rows (upsert on (source, source_code), safe to")
    print("-- run more than once):")
    print()
    for guid, name in RIYADH_BRANCHES.items():
        print(
            "insert into branches (cinema_name, branch_name, source, source_code) "
            "values ('{}', '{}', '{}', '{}')\n"
            "on conflict (source, source_code) do update set branch_name = excluded.branch_name;".format(
                CINEMA_NAME, name, SOURCE, guid
            )
        )
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
