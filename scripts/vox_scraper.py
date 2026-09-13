"""
VOX Cinemas (Saudi Arabia) "what's on" scraper.

What it does
------------
1. Fetches the now-showing list: https://ksa.voxcinemas.com/movies/whatson
   -> title, poster URL, slug, rating, language for every movie currently playing.
2. Visits each movie's own detail page (https://ksa.voxcinemas.com/movies/<slug>)
   -> adds running time (minutes), genre, release date, and *today's* showtimes
      per branch/screen type - Riyadh branches only (see _is_riyadh_branch;
      VOX has branches in Jeddah, Dammam, Tabuk, Hail, Jubail and AlUla too,
      but the app only serves Riyadh for now).
3. Writes everything to vox_movies.json next to this script (handy for
   eyeballing what got scraped). Getting it into Supabase is a separate
   step - see sync_to_supabase.py, which imports scrape_all() from here.

Why detail pages, not just the list page
-----------------------------------------
The listing page has title/poster/rating/language but NOT the runtime -
that only appears on each movie's own page ("Running Time: 175 min").
Showtimes also only live on the detail page, under <section id="showtimes">.

Branch identity
----------------
VOX's showtime links carry a booking id like "0034-221312". The part
before the dash ("0034") is VOX's own internal code for the *branch*
(Riyadh Park, in that example) - stable across every film and every
showing at that branch, as far as this scrape could tell. That's what
sync_to_supabase.py upserts branches on, since branch *names* alone
aren't a reliable key (VOX itself renders some without a city suffix
inconsistently). Flagging the assumption here in case a future scrape
shows a branch's code changing - it hasn't in testing, but this is one
site's undocumented convention, not a documented contract.

Scope / etiquette
-----------------
robots.txt for this site disallows crawling any URL with a query string
(`Disallow: *?*`) plus /booking/, /account/, /orders/ and the legal pages.
The showtimes section's "Tomorrow"/"Wed 16 Sep" date tabs are query-string
links (?d=YYYYMMDD), so this script only scrapes TODAY's showtimes (the
ones already present on the page with no query string) and does not
follow those date links. Everything else it touches (the listing page,
each /movies/<slug> page) is a plain path with no query string, so it's
allowed.

Usage
-----
    pip install curl_cffi beautifulsoup4
    python3 vox_scraper.py

Why curl_cffi instead of plain requests
----------------------------------------
This site sits behind Akamai's bot-detection, which fingerprints the TLS
handshake itself (not just headers/User-Agent). Plain `requests` (via
Python's built-in ssl/urllib3) produces a detectably different handshake
than a real browser, so Akamai silently stalls the response instead of
answering - it never errors, it just hangs until requests times out. This
happens with any interpreter (confirmed on both Xcode's Python and
Anaconda's Python, so it isn't an OpenSSL-vs-LibreSSL thing either) -
curl(1) and real browsers get through instantly because their handshake
looks "normal" to Akamai. curl_cffi wraps curl-impersonate, which
reproduces a real Chrome TLS fingerprint, so it gets through the same
way plain `curl` does. It's used as a drop-in replacement for `requests`
below (same .get/.text/.raise_for_status/.RequestException API).
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field, asdict
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from curl_cffi import requests
from bs4 import BeautifulSoup

BASE = "https://ksa.voxcinemas.com"
LISTING_URL = f"{BASE}/movies/whatson"

# Saudi Arabia is UTC+3 year-round (no DST) - used so `show_time` lands
# in Supabase as an unambiguous instant rather than a naive local time.
KSA_TZ = timezone(timedelta(hours=3))

HEADERS = {
    # A normal browser UA. Without this some sites (this one included,
    # in testing) can behave differently or block plain "python-requests".
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    )
}

# Be polite: pause between requests instead of hammering the site.
REQUEST_DELAY_SECONDS = 0.6

# The app only serves Riyadh for now. VOX's branch names are mostly
# "<Place> - <City>" (e.g. "Al Qasr Mall - Riyadh"), which the default
# check below handles on its own - but a couple of branches don't
# include a city in their name at all, so those are listed explicitly
# rather than guessed at:
#   - "The Esplanade" is a Riyadh branch (opened 2021, Riyadh) despite
#     the bare name.
#   - "Cinema Aljadidah" is in AlUla, not Riyadh, despite having no
#     city suffix either.
_RIYADH_BRANCH_NAME_OVERRIDES = {
    "The Esplanade": True,
    "Cinema Aljadidah": False,
}


def _is_riyadh_branch(branch_name: str) -> bool:
    if branch_name in _RIYADH_BRANCH_NAME_OVERRIDES:
        return _RIYADH_BRANCH_NAME_OVERRIDES[branch_name]
    return "riyadh" in branch_name.lower()

_TIME_RE = re.compile(r"(\d{1,2}):(\d{2})\s*(am|pm)", re.IGNORECASE)


def _parse_showtime(time_text: str, scrape_date: date) -> Optional[datetime]:
    """'11:45pm' + today -> an aware datetime. Cinemas list post-midnight
    showings ("1:15am") under the same day's tab, so anything before 6am
    is treated as rolling into the next calendar day rather than as
    already-passed today."""
    match = _TIME_RE.search(time_text)
    if not match:
        return None
    hour, minute, meridiem = int(match.group(1)), int(match.group(2)), match.group(3).lower()
    if meridiem == "pm" and hour != 12:
        hour += 12
    if meridiem == "am" and hour == 12:
        hour = 0
    day = scrape_date + timedelta(days=1) if hour < 6 else scrape_date
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=KSA_TZ)


@dataclass
class Showtime:
    branch: str
    branch_code: str
    screen_type: str
    time: str
    sold_out: bool
    booking_id: str
    show_time_iso: Optional[str] = None


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
    subtitles: Optional[str] = None
    detail_url: str = ""
    showtimes_today: list[Showtime] = field(default_factory=list)


def fetch(url: str) -> BeautifulSoup:
    # impersonate="chrome124" makes curl_cffi present a real Chrome TLS
    # fingerprint (see the module docstring for why that's necessary here).
    resp = requests.get(url, headers=HEADERS, timeout=20, impersonate="chrome124")
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "html.parser")


def parse_listing(soup: BeautifulSoup) -> list[Movie]:
    """Parse https://ksa.voxcinemas.com/movies/whatson into Movie stubs
    (no runtime/showtimes yet - those need the detail page)."""
    movies: list[Movie] = []
    for card in soup.select("article.movie-summary"):
        slug = card.get("data-slug")
        title = card.get("data-title") or card.select_one("h3 a").get_text(strip=True)
        img = card.select_one("img.poster")
        poster_url = img.get("src") if img else None
        # A couple of not-yet-released titles use a generic placeholder
        # image instead of a real poster - keep the field but it's worth
        # knowing which ones these are before they hit the app.
        rating_el = card.select_one(".classification")
        rating = rating_el.get_text(strip=True) if rating_el else None
        lang_el = card.select_one(".language")
        language = (
            lang_el.get_text(strip=True).replace("Language:", "").strip()
            if lang_el
            else None
        )
        movies.append(
            Movie(
                title=title,
                slug=slug,
                poster_url=poster_url,
                rating=rating,
                language=language,
                detail_url=f"{BASE}/movies/{slug}",
            )
        )
    return movies


_RUNTIME_RE = re.compile(r"(\d+)\s*min", re.IGNORECASE)


def parse_detail(soup: BeautifulSoup, movie: Movie, scrape_date: date) -> None:
    """Fill in runtime/genre/release date and today's showtimes on `movie`
    in place, from its own detail page."""
    aside = soup.select_one("aside")
    if aside:
        for p in aside.select("p"):
            label_el = p.select_one("strong")
            if not label_el:
                continue
            label = label_el.get_text(strip=True).rstrip(":").lower()
            value = p.get_text(strip=True)
            # strip the leading "Label:" the <strong> contributes
            value = value[len(label_el.get_text(strip=True)):].strip()
            if label == "genre":
                movie.genre = value
            elif label == "running time":
                match = _RUNTIME_RE.search(value)
                movie.duration_minutes = int(match.group(1)) if match else None
            elif label == "release date":
                movie.release_date = value
            elif label == "subtitle(s)":
                movie.subtitles = value
            # "starring" and "language" are also here; language we already
            # have from the listing page, and starring isn't part of the
            # three fields we need right now.

    showtimes_section = soup.select_one("#showtimes")
    if not showtimes_section:
        return
    dates_div = showtimes_section.select_one(".dates")
    if not dates_div:
        return

    # The branch names (h3.highlight) and their <ol class="showtimes">
    # block alternate as siblings under div.dates - walk them in order.
    current_branch: Optional[str] = None
    for el in dates_div.find_all(["h3", "ol"], recursive=False):
        if el.name == "h3":
            current_branch = el.get_text(strip=True)
            continue
        if el.name == "ol" and current_branch:
            if not _is_riyadh_branch(current_branch):
                continue  # not a Riyadh branch - the app only serves Riyadh for now
            for screen_li in el.find_all("li", recursive=False):
                strong = screen_li.find("strong")
                if not strong:
                    continue
                # Some screen types (e.g. "Private Cinema") embed a tooltip
                # <a>i</a> inside the <strong> - only take the direct text.
                screen_type = strong.find(string=True, recursive=False)
                screen_type = screen_type.strip() if screen_type else strong.get_text(strip=True)
                inner_ol = screen_li.find("ol")
                if not inner_ol:
                    continue
                for time_li in inner_ol.find_all("li", recursive=False):
                    booking_id = time_li.get("data-id", "")
                    branch_code = booking_id.split("-", 1)[0] if "-" in booking_id else booking_id
                    link = time_li.find("a", class_="showtime")
                    sold_out_span = time_li.find("span", class_="showtime")
                    if link is not None:
                        time_text = link.get_text(strip=True)
                        sold_out = False
                    elif sold_out_span is not None:
                        time_text = sold_out_span.get_text(strip=True)
                        sold_out = True
                    else:
                        continue
                    parsed = _parse_showtime(time_text, scrape_date)
                    movie.showtimes_today.append(
                        Showtime(
                            branch=current_branch,
                            branch_code=branch_code,
                            screen_type=screen_type,
                            time=time_text,
                            sold_out=sold_out,
                            booking_id=booking_id,
                            show_time_iso=parsed.isoformat() if parsed else None,
                        )
                    )


def scrape_all() -> list[Movie]:
    scrape_date = datetime.now(KSA_TZ).date()
    print(f"Fetching listing: {LISTING_URL}")
    listing_soup = fetch(LISTING_URL)
    movies = parse_listing(listing_soup)
    print(f"Found {len(movies)} movies on the what's-on page.")

    for i, movie in enumerate(movies, start=1):
        print(f"  [{i}/{len(movies)}] {movie.title} -> {movie.detail_url}")
        try:
            detail_soup = fetch(movie.detail_url)
            parse_detail(detail_soup, movie, scrape_date)
        except requests.RequestException as exc:
            print(f"    ! failed to fetch detail page: {exc}")
        time.sleep(REQUEST_DELAY_SECONDS)

    return movies


def main() -> None:
    movies = scrape_all()
    out_path = "vox_movies.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(m) for m in movies], f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(movies)} movies to {out_path}")

    missing_runtime = [m.title for m in movies if m.duration_minutes is None]
    if missing_runtime:
        print(f"Note: no runtime found for {len(missing_runtime)} title(s): {missing_runtime}")


if __name__ == "__main__":
    main()
