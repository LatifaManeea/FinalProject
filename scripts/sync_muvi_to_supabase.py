"""
Pushes what muvi_scraper.py scrapes straight into Supabase: films and
today's showtimes, for the Muvi chain. Mirrors sync_to_supabase.py's
approach for VOX - same tables, same branch-is-hand-managed rule, same
scripts/.env - just pointed at muvi_scraper.py and stamping rows with
source='muvi' instead of 'vox'.

branches is hand-managed, not touched by this script
------------------------------------------------------
Exactly like sync_to_supabase.py: this script only ever READS `branches`
(to match a scraped Muvi cinema id to the branch_id you assigned that
branch) and never writes to it. For that matching to work, every Riyadh
Muvi branch's row needs source='muvi' and source_code set to Muvi's own
numeric id for it (e.g. "26" for Hayat Mall - see fetch_branch_ids()'s
docstring and muvi_scraper.py's "Branch identity" note). A branch with
no matching row, or a wrong source_code, just has its showtimes silently
skipped.

The placeholder "Panorama Mall" row schema.sql seeded for Muvi is not a
real Muvi branch name (Muvi's own API lists no Riyadh cinema by that
name) - it was always a stand-in for a chain that wasn't scraped yet.
Run --propose-branches once, read the printed SQL and its note about
that row, and clean it up by hand before relying on the Muvi section.

Needs the SAME scripts/.env as sync_to_supabase.py
-----------------------------------------------------
    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<service role key, from Project Settings > API>

See sync_to_supabase.py's docstring for exactly why this must be its own
file, separate from the app's root .env, and never bundled into the app.
Nothing about that changes here - both scrapers' sync scripts share the
one scripts/.env.

Usage
-----
    pip install requests
    python3 sync_muvi_to_supabase.py

    # Read-only: see what Muvi branches exist today without writing
    # anything (run this first, before the first real sync):
    python3 sync_muvi_to_supabase.py --propose-branches
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import requests

from muvi_scraper import API_BASE, CITY_ID, Movie, fetch_json, scrape_all

SCRIPT_DIR = Path(__file__).resolve().parent

CINEMA_NAME = "Muvi"
SOURCE = "muvi"


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
    """Same reasoning as sync_to_supabase.py's: films.duration_min is
    NOT NULL in spirit (the ad/break schedule is computed from it), so
    skip writing a film with no runtime rather than one nothing could
    ever be scheduled from. In practice Muvi's API has returned a
    runtime for every title seen so far, including COMING_SOON ones -
    this is here for the day that stops being true."""
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
    """branches is hand-managed, static reference data - the daily sync
    only ever READS it here, to match each Muvi cinema id to the
    branch_id you assigned it, and never writes to the table. A scraped
    branch code with no matching row here has its showtimes silently
    skipped - see the "skipped" count sync() prints."""
    rows = _select(supabase_url, service_role_key, "branches", "source=eq.muvi&select=branch_id,source_code")
    return {row["source_code"]: row["branch_id"] for row in rows if row.get("source_code")}


def normalise_branch_name(name: str) -> str:
    """A branch name reduced to something two sources can agree on.

    Unlike VOX ("Riyadh Park - Riyadh" vs stored "Riyadh Park"), Muvi's
    own names carry no city suffix to strip - "Hayat Mall", "Park
    Avenue", and so on are already exactly what should be stored. One
    real Muvi branch even has its own " - " in the name ("muvi Boutique
    - Tala Mall"), which is exactly why this does NOT split on " - "
    the way vox_scraper.py's normaliser does - doing that here would
    wrongly chop a real branch name in half. Just casefold and collapse
    whitespace."""
    return " ".join(name.split()).casefold()


def fetch_branch_ids_by_name(supabase_url: str, service_role_key: str) -> dict[str, int]:
    """Fallback lookup for branches that have no source_code yet - same
    idea as sync_to_supabase.py's version. Matching on source_code is
    the right way round once it's filled in; until then this is what
    lets a first sync find branches by name instead of skipping every
    showtime silently."""
    rows = _select(
        supabase_url, service_role_key, "branches", "cinema_name=eq.Muvi&select=branch_id,branch_name"
    )

    by_name: dict[str, int] = {}
    ambiguous: set[str] = set()

    for row in rows:
        key = normalise_branch_name(row["branch_name"])
        if key in by_name:
            ambiguous.add(key)
        by_name[key] = row["branch_id"]

    for key in ambiguous:
        print(f"  ! two branches both normalise to {key!r} — matching neither by name.")
        del by_name[key]

    return by_name


def build_showtime_rows(
    movies: list[Movie],
    film_id_by_slug: dict[str, int],
    branch_id_by_code: dict[str, int],
    branch_id_by_name: dict[str, int] | None = None,
) -> tuple[list[dict], int]:
    by_name = branch_id_by_name or {}
    rows = []
    skipped = 0
    for m in movies:
        film_id = film_id_by_slug.get(m.slug)
        if film_id is None:
            skipped += len(m.showtimes_today)
            continue
        for st in m.showtimes_today:
            branch_id = branch_id_by_code.get(st.branch_code)
            if branch_id is None:
                branch_id = by_name.get(normalise_branch_name(st.branch))
            if branch_id is None:
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

    branch_id_by_code = fetch_branch_ids(supabase_url, service_role_key)
    branch_id_by_name = fetch_branch_ids_by_name(supabase_url, service_role_key)
    print(
        f"Matched against {len(branch_id_by_code)} branch(es) by source_code, "
        f"{len(branch_id_by_name)} available by name as a fallback."
    )
    if not branch_id_by_code and branch_id_by_name:
        print(
            "  note: no Muvi branch has source/source_code set, so matching is "
            "by name this run. Run --propose-branches to fill those in."
        )
    if not branch_id_by_code and not branch_id_by_name:
        print(
            "  note: no Muvi branches exist in `branches` at all yet (or only "
            "the old placeholder does). Run --propose-branches, read the SQL "
            "it prints, and run that in the Supabase SQL Editor first."
        )

    showtime_rows, skipped = build_showtime_rows(
        movies, film_id_by_slug, branch_id_by_code, branch_id_by_name
    )
    saved_showtimes = _upsert(
        supabase_url, service_role_key, "showtimes", showtime_rows, on_conflict="branch_id,source_booking_id"
    )
    note = f" ({skipped} skipped — no matching film/branch)" if skipped else ""
    print(f"Upserted {len(saved_showtimes)} showtimes.{note}")


def fetch_all_riyadh_branches() -> list[dict]:
    """Every Muvi cinema in Riyadh, straight from Muvi's own /cinemas
    endpoint - not derived from today's scrape the way VOX's
    build_branch_rows() has to be. This is deliberately its own request
    rather than reusing scrape_all(): a branch showing nothing today
    would be invisible to a showtimes-derived list, but /cinemas lists
    every Riyadh Muvi location regardless of what's playing there."""
    payload = fetch_json(f"{API_BASE}/cinemas?cityId={CITY_ID}")
    return [
        {"cinema_name": CINEMA_NAME, "branch_name": c["name"], "source": SOURCE, "source_code": str(c["id"])}
        for c in payload.get("cinema", [])
    ]


def print_proposed_branches() -> None:
    """Prints the Riyadh Muvi branches Muvi's own site lists, as SQL to
    read before running.

    Unlike VOX, where the branches already existed by hand and only
    needed source/source_code filled in (an UPDATE), Muvi's only
    existing row is the "Panorama Mall" placeholder from schema.sql -
    not a real Muvi branch name, and not something to match against.
    So this prints INSERTs instead, upserting on the same
    (source, source_code) unique index schema.sql already created for
    exactly this purpose - safe to run more than once.
    """
    rows = fetch_all_riyadh_branches()

    if not rows:
        print("No Riyadh Muvi branches found — nothing to propose.")
        return

    print(f"-- {len(rows)} Riyadh Muvi branch(es), from Muvi's own /cinemas endpoint.")
    print("--")
    print("-- Run this once in the Supabase SQL Editor. It's an upsert (ON")
    print("-- CONFLICT on the same (source, source_code) index VOX's rows use),")
    print("-- so running it again later (if Muvi opens/renames a branch) is safe.")
    print()
    for r in rows:
        name = r["branch_name"].replace("'", "''")
        print(
            "insert into branches (cinema_name, branch_name, source, source_code) "
            "values ('{}', '{}', '{}', '{}')\n"
            "on conflict (source, source_code) do update set branch_name = excluded.branch_name;".format(
                r["cinema_name"], name, r["source"], r["source_code"]
            )
        )
    print()
    print("-- The 'Panorama Mall' row schema.sql hand-seeded for Muvi is not a")
    print("-- real branch name (Muvi's own site lists no such Riyadh cinema) and")
    print("-- would otherwise sit alongside the real ones above and confuse the")
    print("-- branch picker. Recommended cleanup, once the inserts above have run:")
    print("--")
    print("--   delete from branches where cinema_name = 'Muvi' and source is null;")
    print()
    print("-- Verify: every Muvi branch should now have a source and a code.")
    print("-- select branch_id, branch_name, source, source_code")
    print("-- from branches where cinema_name = 'Muvi' order by branch_name;")


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
