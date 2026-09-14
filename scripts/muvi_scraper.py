"""
Muvi Cinemas (Saudi Arabia) "now showing" scraper.

What it does
------------
1. Fetches the film list from Muvi's own JSON API (Riyadh only, cityId=2):
       GET {API_BASE}/film-finder/filters/films?cityId=2&date=<now>&timeDuration=ALL_DAY
   -> title, poster URL, slug, runtime (minutes), rating and language for
      every film Muvi lists - both showing now and coming soon, same as
      vox_scraper.py keeps both and lets duration/showtimes tell them apart.
2. For each film, fetches that film's own per-branch sessions for today:
       GET {API_BASE}/films/<id>/cinemas?cityId=2&showMore=false&date=<now>
   -> which Riyadh branch, which experience (screen type - Standard,
      IMAX, Muvi Suites, ScreenX, ...) and what time, for every showing
      of that film today.
3. Writes everything to muvi_movies.json next to this script, same as
   vox_scraper.py does with vox_movies.json. Getting it into Supabase is
   a separate step - see sync_muvi_to_supabase.py, which imports
   scrape_all() from here, mirroring how sync_to_supabase.py uses VOX's.

Why a JSON API instead of parsing HTML
-----------------------------------------
Unlike VOX (an HTML page scraped with BeautifulSoup - see vox_scraper.py),
Muvi's site is a Next.js app that gets its own listings from a public
JSON API at api-gateway.prod.muvicinemas.com. The browser calls it
straight from the page with nothing beyond a required `Accept-Language:
EN` header - no cookies, no token, no signed request. That's what this
scraper calls too, instead of rendering the page and picking classes out
of HTML. Found by watching the network panel while browsing
muvicinemas.com/en/movie-finder and a film's own /en/movies/<slug> page;
confirmed by calling both endpoints directly (outside the page) and
getting the same data back.

Branch identity
----------------
Muvi's API gives every cinema (branch) a plain numeric `id`, present
both in the standalone /cinemas list and on every session under a film -
e.g. Hayat Mall is cinema id 26. That's what sync_muvi_to_supabase.py
upserts branches on (as `source_code`) - the same idea as VOX's
dash-prefixed booking code, but sturdier: it's the API's own primary key
for the branch, not a substring pulled out of a booking id.

City scope
----------
cityId=2 is Riyadh (confirmed via GET {API_BASE}/cities, which lists
{"id": 2, "name": "Riyadh", "cinemaCount": 9, ...}) - the app only
serves Riyadh for now, same as VOX, so every request below is pinned to
cityId=2 and nothing here has to filter branches by name the way
vox_scraper.py's _is_riyadh_branch does.

Poster vs backdrop
-------------------
Each film carries two image fields: `image` (portrait - used here as
the poster, matching what the app's FilmPosterCard expects) and
`coverUrl` (a wide landscape banner). Worth double-checking against the
real app once some Muvi posters show up on the Cinemas tab - if they
render as a wide banner instead of a portrait poster, the two are
swapped here.

"sold out" is a guess
-----------------------
Each session carries `isDisabled: bool` with no further explanation
seen anywhere in the API. Treated here as the closest match to VOX's
sold-out flag (a session that's listed but not bookable), but nothing
confirms it isn't used for something else (a showing pulled last
minute, a private/rental screening, etc.) - flagging the assumption
the same way vox_scraper.py flags its own about branch codes.

Scope / etiquette
-----------------
This calls Muvi's own JSON API directly, at the same pace and the same
endpoints its own website calls when a person browses it - nothing
scraped here isn't already public on muvicinemas.com. A small delay is
added between each film's per-branch request anyway, so a full run
doesn't hit the API back-to-back for two dozen films in a burst.

Usage
-----
    pip install requests
    python3 muvi_scraper.py

Why plain requests, not curl_cffi
-----------------------------------
VOX's site sits behind Akamai bot-detection that fingerprints the TLS
handshake itself, which is why vox_scraper.py needs curl_cffi instead of
plain requests (see that file's docstring). Nothing seen while poking at
Muvi's API suggests the same protection - its responses carry no
Akamai/Cloudflare markers, and a plain fetch() to it from a browser
needed nothing but the Accept-Language header. That said, this has only
been exercised through a real browser's fetch(), not yet as a real run
of this exact script hitting the API cold from a fresh machine - if it
hangs the way the VOX scraper used to before curl_cffi, swap the
`requests.get` call in `fetch_json()` for curl_cffi's (already installed
for vox_scraper.py) the same way that file does. Treat that as a real
possibility to check on the first run, not a remote one.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Optional

import requests

API_BASE = "https://api-gateway.prod.muvicinemas.com/api/v1"
CITY_ID = 2  # Riyadh - see the "City scope" note above.

HEADERS = {
    # A normal browser UA, same reasoning as vox_scraper.py's.
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    # Required - the API answers 400 "accept-language must be a valid
    # enum value" without it. Case-sensitive: lowercase ("en") also 400s;
    # only the upper-case two-letter form works.
    "Accept-Language": "EN",
}

# Be polite: pause between each film's showtimes request instead of
# hammering the API - same idea as vox_scraper.py's REQUEST_DELAY_SECONDS.
REQUEST_DELAY_SECONDS = 0.6


@dataclass
class Showtime:
    branch: str
    branch_code: str  # Muvi's own numeric cinema id, as a string - see docstring.
    screen_type: str
    show_time_iso: str  # Muvi's API already returns UTC ISO timestamps - no parsing needed.
    sold_out: bool
    booking_id: str  # Muvi's own session id - stable per showing, for upsert/dedup.


@dataclass
class Movie:
    title: str
    slug: str
    poster_url: Optional[str]
    rating: Optional[str]
    language: Optional[str]
    genre: Optional[str] = None
    duration_minutes: Optional[int] = None
    release_date: Optional[str] = None
    detail_url: str = ""
    # Muvi's own numeric film id - needed to fetch this film's showtimes,
    # not part of vox_scraper.py's Movie since VOX only ever needs the
    # slug. Kept on the row (harmless) rather than threaded through as a
    # separate parallel list.
    source_film_id: Optional[int] = None
    showtimes_today: list[Showtime] = field(default_factory=list)


def fetch_json(url: str) -> dict:
    resp = requests.get(url, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    return resp.json()


def _now_iso() -> str:
    """Muvi's API takes any timestamp that falls on the day it cares
    about - a precise "now" and the rounder timestamps the site's own
    frontend sends were both tried against the live API and returned
    identical results, so there's no need to align this to a particular
    hour the way vox_scraper.py aligns showtimes to KSA midnight."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_listing(payload: dict) -> list[Movie]:
    """Parse the film-finder/filters/films response into Movie stubs
    (no showtimes yet - those need a second, per-film request)."""
    movies: list[Movie] = []
    for f in payload.get("films", []):
        genres = f.get("genres") or []
        slug = f["uniqueName"]
        movies.append(
            Movie(
                title=f["title"],
                slug=slug,
                poster_url=f.get("image"),
                rating=(f.get("rate") or {}).get("title"),
                language=(f.get("movieLang") or "").strip() or None,
                genre=" / ".join(g["name"] for g in genres) if genres else None,
                duration_minutes=f.get("runtime"),
                release_date=f.get("releaseDate"),
                detail_url=f"https://www.muvicinemas.com/en/movies/{slug}",
                source_film_id=f.get("id"),
            )
        )
    return movies


def fetch_showtimes_for_film(film_id: int) -> list[Showtime]:
    """Every Riyadh branch's sessions for [film_id], today."""
    payload = fetch_json(
        f"{API_BASE}/films/{film_id}/cinemas?cityId={CITY_ID}&showMore=false&date={_now_iso()}"
    )
    showtimes: list[Showtime] = []
    for cinema in payload.get("cinemas", []):
        branch_name = cinema.get("name", "")
        branch_code = str(cinema.get("id", ""))
        for experience in cinema.get("experiences", []):
            screen_type = experience.get("name") or experience.get("uniqueName") or "Standard"
            for session in experience.get("sessions", []):
                show_time_iso = session.get("showtime")
                booking_id = session.get("id")
                if not show_time_iso or booking_id is None:
                    continue
                showtimes.append(
                    Showtime(
                        branch=branch_name,
                        branch_code=branch_code,
                        screen_type=screen_type,
                        show_time_iso=show_time_iso,
                        sold_out=bool(session.get("isDisabled")),
                        booking_id=str(booking_id),
                    )
                )
    return showtimes


def scrape_all() -> list[Movie]:
    listing_url = f"{API_BASE}/film-finder/filters/films?cityId={CITY_ID}&date={_now_iso()}&timeDuration=ALL_DAY"
    print(f"Fetching listing: {listing_url}")
    movies = parse_listing(fetch_json(listing_url))
    print(f"Found {len(movies)} movies.")

    for i, movie in enumerate(movies, start=1):
        print(f"  [{i}/{len(movies)}] {movie.title} -> {movie.detail_url}")
        if movie.source_film_id is None:
            print("    ! no film id from the listing - can't fetch showtimes")
            continue
        try:
            movie.showtimes_today = fetch_showtimes_for_film(movie.source_film_id)
        except requests.RequestException as exc:
            print(f"    ! failed to fetch showtimes: {exc}")
        time.sleep(REQUEST_DELAY_SECONDS)

    return movies


def main() -> None:
    movies = scrape_all()
    out_path = "muvi_movies.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(m) for m in movies], f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(movies)} movies to {out_path}")

    missing_runtime = [m.title for m in movies if m.duration_minutes is None]
    if missing_runtime:
        print(f"Note: no runtime found for {len(missing_runtime)} title(s): {missing_runtime}")


if __name__ == "__main__":
    main()
